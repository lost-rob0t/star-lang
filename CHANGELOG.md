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

- Provisioned the `lost-rob0t/star-lang` repository as the Common Lisp-only
  StarLang compiler and durable actor runtime home.
- Scaffolded placeholder ASDF systems for all fifteen `star-*` and
  `starlang-*` subsystems defined in the provisioning decision.
- Added SBCL-first CI matrix, Nix flake entry point, Roswell notes, GPL-3.0
  license, contribution policy, and SBOM inventory.

### Decisions

- License: GPL-3.0.
- Visibility: public.
- ASDF naming: `star-<name>` and `starlang-<name>`, lowercase, hyphen-separated.
- Primary implementation: SBCL.
