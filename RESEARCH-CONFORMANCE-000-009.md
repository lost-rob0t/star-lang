# Star-Lang research 000–009 implementation ledger

This file tracks whether `lost-rob0t/star-lang` actually implements the approved
Star-Lang research sequence. Research approval does not imply implementation
completion.

## Status

**BLOCKED — not yet fully conformant.**

The repository may not claim complete conformance until every blocking item
below is implemented, tested, and enforced by CI.

## Research mapping

| Research | Required implementation property | Current status |
| --- | --- | --- |
| 000 | Closed parser, bounded source processing, checked data-only IR, no host `READ`/`EVAL` for `.star` source | Compiler foundation implemented: all `.star` entry points share the octet parser, every occurrence carries a syntax object and UTF-8 byte span, parser limits are explicit, and the loader has a static no-`READ` regression gate. |
| 001 | Common Lisp executable baseline with deterministic fixture and explicit prototype limits | Implemented as historical baseline; must not override later approved constraints. |
| 002–005 | Alternate implementations denied; Common Lisp selected | Conformant: no Racket, Scheme, or Guile implementation is retained. |
| 006 | Exact locked specification libraries, HTTPS-only remote resolution, additive schema extension, `source/predicate/destination` relations, keyed domain servers | **Blocked**: the canonical `.star` loader now requires HTTPS and full SHA-256 locks, but retained specification-domain/compiler compatibility checks still accept prefix-only digests, and the Star-CL relation schema/runtime still uses `target`. |
| 007 | Deterministic runtime-neutral normalized IR; cl-gserver names only in adapter manifests | Compiler boundary implemented as read → locked import resolution → expand → validate → compile, with deterministic IR/source-map tests and adapter binding kept after lowering. |
| 008 | Closed core surface, semantic validation, camelCase fields, portable camelCase wire envelope | **Blocked**: parsing now preserves exact source spelling, but kebab-case fields are still accepted, fixtures remain kebab-case, and wire keys use snake_case. |
| 009 | Deterministic canonical JSON, generated Python/TypeScript bindings, finite binary64 `float`, exact string `decimal` | **Blocked**: no `float` type exists in compiler/JSON/bindings; geo remains `decimal`; canonical JSON emits snake_case envelope and manifest keys. |

## Blocking implementation work

### Source boundary

- [x] Route every `.star` load through the closed Star-Lang parser, never Common Lisp `READ`.
- [x] Preserve identifier spelling through parsing; do not lowercase field identifiers.
- [x] Add source-size, nesting-depth, node-count, token-length, string-length, collection-length, numeric-literal-length, and numeric-magnitude limits before unbounded allocation or recursion.
- [x] Replace list-identity-only positions with per-occurrence syntax objects carrying complete source spans.
- [x] Keep source parse conditions structured and noninteractive.

### Specification resolution

- [ ] Reject plain HTTP imports; allow pinned HTTPS and local files only.
- [ ] Require full `sha256:<64 hexadecimal digits>` digests everywhere.
- [x] Keep network resolution outside semantic compilation and runtime execution.
- [ ] Freeze and test the resolved local lock graph consumed by compilation.

### Field and relation contracts

- [ ] Enforce lower camelCase for every document field, message field, manifest field, and serialized wire key.
- [ ] Reject hyphenated and snake_case field declarations with a structured compiler condition.
- [ ] Migrate all `.star` fixtures, tests, constructor overlays, and runtime field lookups.
- [ ] Use canonical relation positions `source`, `predicate`, and `destination`; remove the generic relation `target` field.

### Numeric and serialization model

- [ ] Add `float` as finite IEEE-754 binary64.
- [ ] Encode floats as deterministic shortest-round-trip JSON numbers.
- [ ] Reject NaN and infinities; canonicalize negative zero to JSON `0`.
- [ ] Keep exact `decimal` values as canonical strings.
- [ ] Migrate latitude, longitude, altitude, and accuracy to `float`.
- [ ] Emit lower camelCase canonical JSON keys.
- [ ] Map `float` to Python `float` and TypeScript `number`; keep `decimal` mapped to strings.

### Compiler architecture and CI

- [x] Consolidate the retained prototype paths into one authoritative read → expand → validate → compile pipeline.
- [x] Verify normalized IR contains no syntax objects, cl-gserver objects, or runtime handles.
- [ ] Add a permanent `research-000-009` conformance suite to CI.
- [ ] Make fixture drift, snake_case wire keys, unsupported float behavior, insecure imports, and relation `target` fail CI.
- [ ] Remove transitional claims only after the conformance suite and full test matrix pass.

## Related implementation issues

- `#4` — lower camelCase field identifiers
- `#5` — float scalar support for geo and approximate measurements
- `#6` — remaining research 000–009 integration and final conformance gates

## Completion rule

Complete conformance requires all blocking items above, the full SBCL suite,
`nix flake check`, generated JSON validation, generated Python compilation, and
a clean static conformance audit. Do not mark this ledger complete based only on
research approval or passing legacy prototype tests.
