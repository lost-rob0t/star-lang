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
