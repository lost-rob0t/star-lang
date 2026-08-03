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
