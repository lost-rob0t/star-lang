# Complete StarIntel 0.10.1 compatibility bundle

This opt-in bundle preserves the existing release-only sync mode. It packages
the authority reader and its complete dependency closure; it does not create
another schema, migration engine or SDK historical-reader implementation.

## Identity and layout

The generated `0.10.1/bundle-lock.json` hashes 28 files: the existing 18-file
release closure (including its release lock) and 10 compatibility files. The
bundle lock is not self-hashed. A consumer lock also hashes the bundle lock,
so a complete consumer vendors 29 files. The existing release-lock bytes,
generated schema/bindings and registry provenance remain unchanged.

Preserve `0.10.1/` and `compatibility/` as siblings. The reader imports numeric
and semantic helpers through these relative paths. The checker rejects a
flattened or remapped layout even if individual bytes are valid.

The immutable transport commit in a consumer lock identifies where bytes were
retrieved. The registry's existing `canonicalCommit` is source provenance.
Do not overwrite one with the other.

## Generate and verify in StarLang

```sh
python3 tools/finalize-starintel-release.py --bundle
python3 tools/finalize-starintel-release.py --check --bundle
python3 tools/test-starintel-consumer.py
python3 tools/test-starintel-versioned-reader.py
```

The generator does not change wire semantics or compiler outputs. If the
canonical source changes, first use the established Lisp release generator.
CI checks the committed bundle against the finalizer. The separate read-only
generation workflow uploads the actual generated lock and records its source
commit and Git blob identity; it has no automatic push or release step.

Initial lock provenance: workflow run
https://github.com/lost-rob0t/star-lang/actions/runs/38021301836 at source
`ee28e47395a846a73a94bf6d0bc34e050cfea3aa`; generated Git blob
`c579f5c4adc6bd991ffc14edb94e8120a39872ba`. The bytes retrieved from the
successful job log exactly matched GitHub's created blob identity. The same
lock was uploaded as artifact `starintel-0101-generated-bundle`.

## Consume from an immutable pin

Copy the maintained consumer tool to the downstream repository. From its root:

```sh
python3 tools/sync-starintel-consumer.py --bundle --release 0.10.1 --commit FULL_40_CHARACTER_COMMIT
python3 tools/sync-starintel-consumer.py --bundle --release 0.10.1
python3 tools/sync-starintel-consumer.py --bundle --release 0.10.1 --offline
```

Default bundle destination: `schemas/starintel/`. The existing default
release-only destination remains `schemas/starintel-0.10.1/`.
`--destination` may select another safe relative root. The authority generator
and reader support only 0.10.1 here; other release selections fail explicitly.

The online or local-Git check verifies exact upstream identity. The offline
check verifies local closure without network access; it does not independently
authenticate a locally rewritten lock. Hashes are integrity checks, not signatures.

Use a dedicated bundle directory: checks and sync reject unlisted files, including
Python import shadows and bytecode caches. Invoke the reader with `-B` (or set
`PYTHONDONTWRITEBYTECODE=1`) so normal execution does not add bytecode to that
closed directory. Existing cache files must be removed before verification.

Run the complete consumer check before loading the reader or generated code:

```sh
python3 tools/sync-starintel-consumer.py --bundle --offline &&
python3 -B schemas/starintel/compatibility/versioned_reader.py read < old.json
```

## Failure and activation boundary

Sync verifies the complete upstream release, bundle and registry hashes before
writing. It validates all destination paths, rejects symlink targets and
duplicate source mappings, and writes the consumer lock last.

This is not transactional activation, rollback or an adversarial concurrent
filesystem-race defense. An interrupted sync can leave partial files, while the
old lock remains. A mandatory check rejects that state; do not consume it.
Sync to a separate staging checkout and verify before choosing it for runtime
use. Automated promotion/resume and production corpus changes are not provided.

## Matrix and bounded property tests

`compatibility/capabilities.json` records reference-reader support and explicit
exclusions. Tests verify the 51-dtype pinned historical schema inventory,
all 28 paired migration fixtures after relocation, canonical identity, CLI
read/dry-run/migrate/exact-byte restore, and 64 deterministic seeded archival
cases using exact numeric lexemes, whitespace, booleans and nulls. Malformed
duplicate-key mutations must reject.

Bundle tests also reject missing/tampered files, wrong release/format, floating
refs, traversal, duplicate mappings, incompatible layout and interrupted writes.
These bounded property tests are not coverage-guided fuzzing. Cross-SDK reader
parity, arbitrary downgrade, nested historical 0.10.1, the executable-only
legacy dialect and unpinned 0.7.3 are not established by this bundle.
