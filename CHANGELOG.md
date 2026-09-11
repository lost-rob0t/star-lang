# Changelog

All notable changes to `star-lang` are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Branch, release, and changelog policy

- `main` is the release branch. All changes flow through pull requests.
- Feature work lives on short-lived `feature/*` or `agent/*` branches.
- Fixes live on `fix/*` branches.
- Releases are cut by tagging `main` with `vX.Y.Z`.
- `X` (major): incompatible public contract changes.
- `Y` (minor): additive, backward-compatible runtime or system changes.
- `Z` (patch): bug fixes and reproducibility improvements.
- Every release updates this file and `SECURITY.md`.
- Pre-release work may be tagged `vX.Y.Z-rc.N`.

## [Unreleased]

### Added

- Added a flake-locked real Sento actor-system integration suite covering a
  multi-actor topology, asynchronous ask/reply, lookup/liveness, blocking
  teardown, mapped failures, and concurrent serialized state mutation.
- Added matching `AGENTS.md` and README execution contracts with CI consistency
  and direct-backend-boundary guards.
- Added final actor compilation to `starlang-compiler`: a real `.star` actor
  declaration is read by the closed parser, validated, and lowered into
  runtime-neutral actor IR without loading `starlang-prototype`.
  `compile-actor-source`/`compile-actor-file` expose the explicit
  read -> expand -> validate -> lower pipeline for single-actor units.
- Added the optional actor `:metadata` contract: a list of
  `(lowerCamelCaseIdentifier scalar)` pairs carried into actor IR and the
  portable manifest with lower camelCase JSON keys.
- Added the closed parser keyword vocabulary for actor declarations
  (`:runtime`, `:service-uri`, `:accepts`, `:produces`, `:handler`,
  `:protocol`, `:endpoint`, `:restart`, `:mailbox`, `:capabilities`,
  `:metadata`), making actors real `.star` source for the first time.
- Added a fresh-SBCL acceptance proof that loads only `starlang-compiler`,
  compiles the actor fixture deterministically, rejects name/service-URI
  mismatches and malformed declarations, and asserts the prototype packages
  never load.
- Added `ci/with-nix-sbcl.sh` for local verification with the flake-pinned
  SBCL and a correctly ordered source registry (guards against the
  `~/common-lisp` shadowing hazard).

### Changed

- Moved the closed StarLang compiler core (parser, syntax model, expansion
  boundary, grammar validation, specification lowering) from
  `prototype/core-surface-prototype.lisp` into
  `starlang-compiler/src/core-surface.lisp` (package
  `star-lang.compiler.core`); the prototype file is now a compatibility
  re-export shell.
- Moved actor lowering and portable manifest emission
  (`compile-actor`, `portable-actor`, `portable-declaration`,
  `portable-field`, `declarations-of-kind`, `emit-portable-manifest`) from
  `prototype/actor-wire-prototype.lisp` into `starlang-compiler`; the
  prototype file retains only cl-gserver binding composition and wire
  forwarders.
- `starlang-compiler` now depends on `star-actor-protocol` for canonical
  `star://domain:address:actor-name` service URIs; the dependency graph
  stays acyclic.

### Fixed

- Fixed a `sbcl --script prototype/run-star.lisp` crash
  (`SB-EXT:PACKAGE-DOES-NOT-EXIST` for `:STAR-LANG.COMPILER.CORE`) on
  machines with a stale star-lang checkout under an inherited ASDF source
  registry (e.g. `~/common-lisp`): the core-surface compatibility shell now
  registers the repository tree as a directory pathname `:tree` entry placed
  before `:inherit-configuration`, so this checkout always wins over
  inherited configuration and the fallback `load-asd`/`load-system` resolves
  the real `starlang-compiler`. Added
  `prototype/core-surface-load-tests.lisp`, which forces a hostile decoy
  registry and asserts this checkout's `starlang-compiler` 0.1.0 wins.
- Fixed two latent `starlang-compiler` resolver-effects tests that used a
  parallel `let` whose effect lambda captured the global binding instead of
  the intended local one (per CLHS, `let` init-forms are outside the scope
  of that `let`'s bindings); they now use `let*`.
- `starlang-compiler` test suites now fail loudly: `run!` results are
  checked and failures raise, so ASDF/Nix/CI gates can no longer pass
  silently on fiveam failures.

- Added bounded declarative format-1 macros with deterministic pattern matching,
  tail repetition, fresh introduction scopes, cycle/ambiguity detection, and
  resource limits.
- Added macro expansion traces, definition/use-site origin spans, stable expanded
  source rendering, and digest-qualified dependencies for locked imported macros.
- Added macro conformance tests covering hygiene, use-site identity, imported
  expansion, repetition, deterministic output, validation, and failure limits.
- Added an ASCII lower camelCase field grammar with structured
  `invalid-field-name` diagnostics and exact offending-token spans.
- Added a permanent camelCase conformance suite covering source spelling,
  negative field forms, normalized IR versioning, and canonical manifest keys.
- Added an explicit `org.star-lang/normalized-ir@2` schema discriminator and
  adapter rejection of legacy IR after the field-contract migration.
- Added first-class syntax objects for every parsed occurrence, complete UTF-8
  byte/character source spans, persistent import-origin chains treated as
  immutable, and stable source maps.
- Added explicit configurable parser resource limits and structured diagnostics
  across read, expand, validate, and compile phases.
- Added a compiler-foundation conformance suite covering closed-reader syntax,
  UTF-8 offsets, limits, provenance, deterministic IR, and the no-`READ` loader
  regression gate.
- Added a real Nix package that loads and checks `starlang-prototype`, installs
  the full source tree, and exposes `starlang` and `starlang-test` executables.
- Added flake apps, a development shell, a formatter, and `nix flake check`.
- Added a dedicated Nix GitHub Actions workflow.

### Changed

- Moved claimed concrete Sento operations behind `star-sento-compat`, made ask
  explicitly future-based, and reduced prototype remoting code to compatibility
  composition over the final boundary.

- Replaced the macro-rejecting expansion boundary with an explicit
  read → collect locked macro environment → bounded expand → validate → compile
  pipeline. Version 1 macros are declaration-context only and cannot perform
  intentional capture or execute host Common Lisp code.
- Migrated document and message fields, portable manifests, canonical JSON,
  lifecycle envelopes, generated Python/TypeScript bindings, fixtures, and
  runtime field lookups to lower camelCase. Kebab-case declaration and type
  names remain unchanged.
- Bumped runtime-neutral normalized IR to version 2 so the camelCase field
  contract is not silently introduced under the version 1 contract.
- Consolidated all `.star` loading on the closed octet parser and the explicit
  read → locked imports → expand → validate → compile pipeline; removed the
  loader's Common Lisp reader implementation.
- Preserved source identifier spelling and kept source-controlled identifiers
  out of Common Lisp packages.
- Relicensed all first-party StarLang systems from GPL-3.0 to
  GNU Affero General Public License v3.0 only (`AGPL-3.0-only`).
- Replaced the placeholder Nix derivation that swallowed ASDF failures and
  installed an empty output.

### Decisions

- License: `AGPL-3.0-only`.
- Visibility: public.
- ASDF naming: `star-<name>` and `starlang-<name>`, lowercase, hyphen-separated.
- Primary implementation: SBCL.
