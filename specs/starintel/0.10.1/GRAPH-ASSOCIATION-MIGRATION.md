# StarIntel 0.10.1 graph-association admission

This semantic rule is additive to `specs/starintel/0.10.1/core.star` and
its source-generated contracts. The generated schema validates field types;
it cannot prove cross-document identity equivalence.

## Tentative links

A candidate or disputed person/entity association is a reified `Relation`
with a non-equivalence predicate, explicit `verificationStatus`, confidence,
a human-readable confidence basis, evidence references and provenance.
A score of `1.0000` is not verification. Do not emit `owl:sameAs`, merge
Person records, or promote `duplicateCandidateIds` into `sameAsIds`.

## Inverse predicate admission

When `Relation.inversePredicate` is present, it must be nonblank and
lexically normalized. Identity-equivalence predicates are symmetric:
`inversePredicate` and `predicate` must either both express identity
equivalence or neither may. A candidate `related-to` assertion with
`inversePredicate: owl:sameAs` is not an innocuous nonidentity link;
it fails admission. A verified `same-as` assertion with a nonidentity
inverse also fails. Omit `inversePredicate` when it is not independently
known. Do not infer verification from an inverse field.

## Reference-ID self-equivalence

Identity-equivalence admission compares the two `StarReference.id` values,
not the entire `{schema, id}` maps. Re-labeling one endpoint as another
document schema cannot establish a second identity with the same document ID.
A verified `same-as` Relation linking one ID to itself must be rejected even
when its reference schema strings differ. Consumers must quarantine such
historical links rather than manufacture a new ID or reviewer attestation.

## Inherited Document validity windows

`Document.validFrom` and `Document.validUntil` are inherited UnixTime
fields in all 0.10.1 graph types (Person, Org, NetworkDevice, Address,
Observation, Entity and Relation). The generated JSON Schema independently
validates their nonnegative integer wire types; semantic admission rejects
both endpoints when `validFrom > validUntil`. Equal endpoints are accepted,
and omitting either endpoint retains an open interval. Do not reinterpret
`observedAt`, `validAt`, `endedAt`, or collection timestamps as a substitute
for these document-level fields.

During migration, quarantine old records with reversed common validity
windows and retain the original source timestamps, evidence, provenance,
and verification state for operator review. Do not silently swap endpoints,
fill absent endpoints from inferred observations, or promote tentative links.
IR14/StarIntel Server and Pro Actors should run the common-window admission
after generated-schema validation and before persistence, for every 0.10.1
document type; 0.9.x records remain historical input only. This is a
semantic-only change: the canonical `core.star` fields and source-generated
JSON Schema, language bindings, and release locks remain byte-identical.

## Source-content validity windows

Entity and other 0.10.1 domain documents declare optional
`contentValidFrom` / `contentValidUntil` RFC3339 date-times in canonical
`core.star`. They are distinct from inherited document-level UnixTime
`validFrom` / `validUntil` and must **not** be substituted for each other.
After official generated-schema validation, semantic admission compares
actual UTC instants (including timezone offsets and arbitrary fractional
seconds) and rejects a reversed pair. Identical instants across offsets are
valid; a missing or `null` endpoint remains open. The rule does not infer
an absent endpoint or change candidate, disputed, or verified status.

For historical records with reversed source-content windows, quarantine
those records and retain both original strings, evidence, and provenance
for operator review. Never silently swap timestamps or rewrite asserted
identity links. IR14 / StarIntel Server and Pro Actors should apply this
post-schema check before persistence; downstreams should not substitute
lexicographic timestamp comparisons. It is a semantic-only hardening of
fields already declared in `core.star`: no generated wire artifact or release
lock changes. The regression corpus now exercises these fields using the
existing generated 0.10.1 `Entity` definition.

## Verified links

An asserted identity-equivalence `Relation` requires explicit verified
status, a reviewer and timestamp, nonempty evidence, provenance, confidence
and basis. Nonverified claims must not carry verification attestation.
An Entity `sameAsIds` entry additionally requires a matching, separately
attested `Relation` for that *exact pair of Entity IDs*. Entity-wide
`verificationStatus: verified` alone never verifies newly appended links.
Missing proof fails closed.

Run `python3 tools/test-starintel-graph-associations.py` after the generated
JSON Schema is present. The tests first validate against the complete
source-generated `#/$defs/Relation` and `#/$defs/Entity`, then apply the
semantic admission rules. No source-generated artifacts should be edited.

## Migration

Preserve historical weak matches as candidate Relation documents with original
evidence and provenance. Quarantine unreviewed strong links rather than
inventing reviewer attestations. Preserve stable IDs and source bytes. 0.9.x is
a historical input format only; `0.10.1` is authority.

## Consumer boundary

Before persistence: generated schema validation, graph semantics, resolve
all evidence and counterpart references, authorize reviewers, enforce current
resolution state, then persist. A supplied Relation is not itself proof of
reviewer authorization. Server and Pro Actors own those runtime checks.
SL01 owns compiler scalar enforcement. SL02 owns generated artifacts,
release locks and JSON-LD projections; candidate links must not project to
`owl:sameAs`. No database indexes change in Star Language.
