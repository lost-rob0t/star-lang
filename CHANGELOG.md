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

- Added a real Nix package that loads and checks `starlang-prototype`, installs
  the full source tree, and exposes `starlang` and `starlang-test` executables.
- Added flake apps, a development shell, a formatter, and `nix flake check`.
- Added a dedicated Nix GitHub Actions workflow.

### Changed

- Relicensed all first-party StarLang systems from GPL-3.0 to
  GNU Affero General Public License v3.0 only (`AGPL-3.0-only`).
- Replaced the placeholder Nix derivation that swallowed ASDF failures and
  installed an empty output.

### Decisions

- License: `AGPL-3.0-only`.
- Visibility: public.
- ASDF naming: `star-<name>` and `starlang-<name>`, lowercase, hyphen-separated.
- Primary implementation: SBCL.
