# Explicit versioned readers and archival migration

`../0.10.1/core.star` and its generated artifacts remain the only normative
current writer contract. This directory defines historical **read profiles** and
a bounded reference migration, not an alternative schema for new records.

## Supported version and profile inventory

| Profile | Reader | Migration |
| --- | --- | --- |
| `nested-0.9.0-cb258634` | Full original nested-envelope JSON schema, pinned from `lost-rob0t/starintel-gpt-auto-dig` commit `cb258634bf413b9f3620c229dfd821270e8d5377` | The 28 dtypes in the current source-locked workflow mappings, restricted to documents valid under this original schema |
| `canonical-0.10.1` | Generated schema plus decimal and operation/workflow semantic checks | Validated identity, no restamping or accumulated provenance |

Dispatch requires exactly one explicit wire version: `schema_version: "0.9.0"`
for the historical nested profile, or `schemaVersion: "0.10.1"` for the current
profile. Both markers, absent versions, all other versions, and unrecognized
dtypes fail closed. Historical readers return the historical representation;
they do not silently migrate or normalize it. Writer support does not imply
historical-reader support in an SDK.

The repository contains distinct historical artifacts that must not be conflated:

- The full pinned JSON schema has 51 dtype alternatives.
- The same source commit's executable `starintel_doc/spec.py` payload contracts,
  already recorded in `../0.10.1/legacy-workflow-oracle.json`, have additional
  fields. For example `alert.rule_id` and `alert.acknowledgement_actions` are
  executable-contract fields but are rejected by the pinned JSON schema.
- Existing SDK adapters advertise some nested `0.10.1` inputs. No independent
  historical full schema establishing that wire profile is pinned here.
- Common Lisp `c3d18ac` standalone `starintel-v090` and JavaScript `456b692`
  explicit legacy schema match the 51-type historical JSON schema semantically.
  Nim `bdd5ac1`'s explicit `v090` schema is an older 50-type snapshot, missing
  `operation`. Identical wire version strings do not establish snapshot parity.
- Nim's explicitly legacy flat object declares `LEGACY_DOC_VERSION = "0.7.3"`.
  This is a real old API, but no complete independently pinned 0.7.3 schema is
  established by this slice; the registry does not invent a reader for it.
- Python's historical schema lock records wire version `0.9.0` and package
  release `0.9.1`. Package versions are not additional document wire versions.

The executable-only extended dialect and nested `0.10.1` are **unsupported by
this reference**; do not infer that changing a version marker makes them valid.
Adding either requires its own complete source-locked profile, fixtures and
reader dispatch policy. Other old versions and migrations for the remaining
historical dtypes are unsupported. No arbitrary downgrade or reverse projection
of edited canonical records is provided.

## Contract `starintel-migration/1`

1. Read immutable UTF-8 JSON bytes. Reject duplicate keys, non-finite numbers,
   unsupported profiles, invalid old fields, and missing required source data.
   Parse numbers exactly, without passing through binary floating point.
2. Validate the complete input under the pinned old schema. A malformed old
   field cannot be hidden in an extension to make migration succeed.
3. Map only the source-locked payload fields. Convert exact numeric values to
   native decimal strings, structured snake-case fields to declared native
   fields, and explicitly typed dynamic maps to key/value entry arrays.
   Preserve null versus absence and false versus null. Never invent references,
   identities, timestamps, status, or required data.
4. Map envelope identity, dataset, dtype and explicit target version. Other
   historical envelope metadata is retained in the original; this bounded
   implementation does not claim native equivalence for policy, evidence,
   timestamps, provenance, or source references. The report says so field by
   field. Applications requiring their native semantics must gate on retained
   report entries rather than treat migration as full semantic conversion.
5. Optional payload fields without a lossless native representation remain in
   the original with an explicit report entry. Required native fields that
   cannot be produced are an error. Validate the canonical result with the
   generated schema, exact decimal constraints, and semantic checks.
6. Place the exact original UTF-8 JSON, source profile, SHA-256, field report,
   and target semantic-content SHA-256 under the reserved
   `extensions.starintelVersionedMigration` key. Existing historical extensions,
   unknown opaque keys, number lexemes, whitespace, and field omission remain
   available in that exact original. They are never overwritten or discarded.
7. Migrating a current valid document is an identity operation. Restoring the
   original is allowed only for unedited canonical migration output whose
   provenance, target hash, original hash and original validation pass. The
   complete target and receipt are also regenerated from the source and compared
   for consistency, so recomputed hashes cannot bless an unrelated target or
   a forged report. This is
   exact archival recovery, not a claim to infer a historical representation
   from arbitrary new data. Hashes detect accidental corruption; they are not
   signatures or a trust/authentication mechanism.

The registry pins old and current schema artifacts. Updating an old schema in
place would change its profile: add a new profile instead. The reference neither
reads nor rewrites a corpus, connects to a server, nor writes output files. It
uses standard input/output only. The caller chooses any staging destination.
Dry-run performs every validation/mapping check but emits only its report.
Document-processing errors exit 2, write a JSON error on stderr and write
nothing on stdout. Corrupt registry artifacts fail before processing starts.

## Commands and evidence

Requires the existing Python `jsonschema` dependency (no new installation).
Date-time checking is explicit and does not depend on optional packages.
Documents exercising the generated URI field additionally require the existing
`jsonschema` URI format checker; if unavailable, the reader rejects that field
with an explicit checker-unavailable error rather than silently accepting it:

```sh
python specs/starintel/compatibility/versioned_reader.py read < old.json
python specs/starintel/compatibility/versioned_reader.py migrate --dry-run < old.json
python specs/starintel/compatibility/versioned_reader.py migrate < old.json > staged-new.json
python specs/starintel/compatibility/versioned_reader.py restore < staged-new.json > recovered-old.json
python tools/test-starintel-versioned-reader.py
```

`read` returns the original bytes after validation. `migrate` returns current
canonical JSON. `restore` returns the exact old bytes, including whitespace and
numeric lexemes. Parsing/mapping serialization sorts object keys for a stable
semantic digest; opaque numeric values are emitted exactly as JSON numbers.
Receipt hashing and equality normalize numeric *values* symbolically, so an SDK
may write `1000` for `1e3`, `1` for `1.0`, or `0` for `-0` without breaking
archival restoration. Strings, booleans and genuinely different numeric values
remain distinct; the exact original number spelling stays in `sourceUtf8`.

`historical-reader-fixtures.json` and `canonical-migration-fixtures.json` contain
28 paired migrations, each validated against the actual full historical schema.
They deliberately omit executable-oracle-only fields. The latter uses the
existing cross-language conformance fixture shape (`name`, `valid`, `document`)
so real SDK process boundaries can validate and roundtrip migration output.
Decimal precision, invalid source input, missing required data, duplicate keys,
unknown versions, exact old-reader recovery, tamper rejection and idempotence
are exercised by `tools/test-starintel-versioned-reader.py`.

## Ownership and language matrix

The language-neutral contract, pinned historical registry and fixtures are owned
here in StarLang. `versioned_reader.py` is a bounded executable reference, not a
replacement for the existing Python, Common Lisp, TypeScript/JavaScript or Nim
SDK APIs. SDK migration helpers retain their current scope until explicitly
adapted to this contract. Java, Kotlin, Go, Rust, Emacs Lisp and Prolog support is
not removed or inferred from these tests. Cross-language canonical acceptance
and byte-preserving archival recovery must be measured separately; passing the
former alone does not prove an old SDK reader exists.

### Exact symbolic numeric wire values

The authority-owned `raw_json_numbers.py` preserves valid JSON number lexemes
whose exponents exceed the host Decimal domain. It compares sign, significant
coefficient and decimal order without expanding powers of ten. Native integer
classification and range checks remain exact, including huge positive/negative
exponents, mathematically integral exponent notation, signed zero and long
coefficient/exponent tokens. Parsing does not change Python's global integer
string limits. Malformed numeric tokens and non-finite values still reject.
The helper's bytes are pinned by the compatibility registry; there is no
StarLang-to-SDK import or dependency.

Canonical opaque numbers remain JSON numbers, never quoted strings. Native
Star decimal fields still use the generated plain-decimal-string contract.
Historical-to-native plain decimal conversion uses a fixed 10,000-place
expansion budget, enlarged only for already-present coefficient digits. An
oversized optional conversion is explicitly reported as
`native-decimal-expansion-limit` and retained in the exact original instead of
allocating an exponent-sized string. Required conversions fail. Zero with an oversized
exponent is represented as plain `0` or `-0`, with its exact original lexeme
still recoverable. This staging bound does not restrict canonical reader
acceptance of schema-valid symbolic numeric wire values.
