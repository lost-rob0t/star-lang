"""StarIntel 0.10.1 identity-association admission atop generated document schemas.

This is a cross-field consumer admission check, not a schema generator or an
identity resolver. Call it only after validating against canonical JSON Schema.
"""

from collections.abc import Mapping
from decimal import Decimal, InvalidOperation

IDENTITY_EQUIVALENCE_PREDICATES = frozenset({
    "same-as", "sameAs", "same_as", "org.starintel/core@1/same-as",
    "owl:sameAs", "http://www.w3.org/2002/07/owl#sameAs",
    "https://www.w3.org/2002/07/owl#sameAs",
    "schema:sameAs", "http://schema.org/sameAs", "https://schema.org/sameAs",
})
NONVERIFIED_STATUSES = frozenset({"candidate", "disputed", "rejected"})


def _nonblank(value):
    return isinstance(value, str) and bool(value.strip())


def _confidence(value, label):
    if not isinstance(value, str):
        raise ValueError(f"{label} requires decimal-string confidence")
    try:
        number = Decimal(value)
    except InvalidOperation as exc:
        raise ValueError(f"{label} requires decimal-string confidence") from exc
    if (not number.is_finite() or number < 0 or number > 1
            or number.as_tuple().exponent < -4):
        raise ValueError(f"{label} requires confidence in [0, 1] at scale <= 4")


def _require_basis(document, label, refs_field, score_field="confidence"):
    if not _nonblank(document.get("confidenceBasis")):
        raise ValueError(f"{label} requires nonblank confidenceBasis")
    if not isinstance(document.get(refs_field), list) or not document[refs_field]:
        raise ValueError(f"{label} requires nonempty {refs_field} references")
    if not isinstance(document.get("provenance"), Mapping) or not document["provenance"]:
        raise ValueError(f"{label} requires provenance")
    _confidence(document.get(score_field), label)


def _require_attestation(document, label):
    if not _nonblank(document.get("verifiedBy")):
        raise ValueError(f"{label} requires verifiedBy")
    timestamp = document.get("verifiedAt")
    if isinstance(timestamp, bool) or not isinstance(timestamp, int) or timestamp < 0:
        raise ValueError(f"{label} requires unix-time verifiedAt")


def _reject_false_attestation(document):
    if document.get("verificationStatus") != "verified" and (
            "verifiedAt" in document or "verifiedBy" in document):
        raise ValueError("nonverified identity assertion cannot carry attestation")


def _id_set(document, name):
    values = document.get(name, [])
    if not isinstance(values, list):
        raise ValueError(f"{name} must be an array")
    if any(not _nonblank(value) or value != value.strip() for value in values):
        raise ValueError(f"{name} must contain nonblank normalized IDs")
    if len(values) != len(set(values)):
        raise ValueError(f"{name} must not contain duplicate IDs")
    if document.get("id") in values:
        raise ValueError(f"{name} must not contain the entity's own ID")
    return set(values)


def validate_relation_assertion(document):
    """Validate a Relation's resolution semantics, without modifying it."""
    if not isinstance(document, Mapping):
        raise TypeError("document must be a mapping")
    if document.get("dtype") != "relation":
        return document
    if document.get("schemaVersion") != "0.10.1":
        raise ValueError("relation semantics require schemaVersion 0.10.1")

    status = document.get("verificationStatus")
    predicate = document.get("predicate")
    if not _nonblank(predicate) or predicate != predicate.strip():
        raise ValueError("relation predicate must be a nonblank normalized string")
    inverse_predicate = document.get("inversePredicate")
    if inverse_predicate is not None and (
            not _nonblank(inverse_predicate)
            or inverse_predicate != inverse_predicate.strip()):
        raise ValueError("relation inversePredicate must be a nonblank normalized string")
    equivalence = predicate in IDENTITY_EQUIVALENCE_PREDICATES
    inverse_equivalence = inverse_predicate in IDENTITY_EQUIVALENCE_PREDICATES
    if inverse_predicate is not None and equivalence != inverse_equivalence:
        raise ValueError("identity equivalence requires consistent predicate and inversePredicate")
    _reject_false_attestation(document)
    if equivalence and status != "verified":
        raise ValueError("identity equivalence requires explicit verified status")
    if status in NONVERIFIED_STATUSES:
        _require_basis(document, status, "evidence")
    elif equivalence:
        _require_basis(document, "verified identity", "evidence")
        _require_attestation(document, "verified identity")
        source = document.get("source")
        destination = document.get("destination")
        if (isinstance(source, Mapping) and isinstance(destination, Mapping)
                and source.get("id") is not None
                and source.get("id") == destination.get("id")):
            raise ValueError("verified identity cannot be a self-equivalence")
    return document


def _require_link_attestations(document, verified_relations):
    """Require separately attested Relation proof for *each* Entity.sameAsIds link.

    Global Entity attestation is insufficient: appending an unreviewed ID to a
    previously verified entity must never silently promote that new link.
    These supplied Relation documents are still untrusted until the consumer
    dereferences and authorizes the reviewer/evidence at the admission edge.
    """
    target_ids = _id_set(document, "sameAsIds")
    if not target_ids:
        return
    attested_ids = set()
    own_id = document["id"]
    for assertion in verified_relations:
        if not isinstance(assertion, Mapping):
            raise ValueError("supporting assertions must be Relation mappings")
        if assertion.get("dtype") != "relation":
            raise ValueError("supporting assertions must be Relation documents")
        if assertion.get("predicate") not in IDENTITY_EQUIVALENCE_PREDICATES:
            continue
        validate_relation_assertion(assertion)
        source = assertion.get("source")
        target = assertion.get("destination")
        if not isinstance(source, Mapping) or not isinstance(target, Mapping):
            raise ValueError("supporting Relation requires typed endpoints")
        if source.get("schema") != "org.starintel/core@1/entity" or target.get("schema") != "org.starintel/core@1/entity":
            raise ValueError("Entity identity proof must reference Entity on both ends")
        pair = {source.get("id"), target.get("id")}
        if own_id in pair and len(pair) == 2:
            attested_ids.update(pair - {own_id})
    unproven = target_ids - attested_ids
    if unproven:
        raise ValueError(f"sameAsIds lack per-link verified Relation evidence: {sorted(unproven)!r}")


def validate_entity_association(document, verified_relations=()):
    """Reject promotion of Entity duplicateCandidateIds into sameAsIds.

    Entity's string ID arrays cannot encode per-link support; candidate proof
    stays in reified Relation records, not in either Entity ID array.
    """
    if not isinstance(document, Mapping):
        raise TypeError("document must be a mapping")
    if document.get("dtype") != "entity":
        return document
    if document.get("schemaVersion") != "0.10.1":
        raise ValueError("entity semantics require schemaVersion 0.10.1")
    _reject_false_attestation(document)

    same_as = _id_set(document, "sameAsIds")
    candidates = _id_set(document, "duplicateCandidateIds")
    if same_as & candidates:
        raise ValueError("candidate IDs must not overlap verified sameAsIds")
    if same_as:
        if document.get("verificationStatus") != "verified":
            raise ValueError("sameAsIds require explicit verified status")
        _require_basis(document, "verified Entity identity", "sources")
        _require_attestation(document, "verified Entity identity")
        _require_link_attestations(document, verified_relations)
    return document


def validate_graph_association(document, verified_relations=()):
    """Post-schema admission for either Relation or Entity; pure on success."""
    if not isinstance(document, Mapping):
        raise TypeError("document must be a mapping")
    if document.get("dtype") == "relation":
        return validate_relation_assertion(document)
    if document.get("dtype") == "entity":
        return validate_entity_association(document, verified_relations=verified_relations)
    return document
