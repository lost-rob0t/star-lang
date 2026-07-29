# Contributing to star-lang

This repository is the **Common Lisp-only** runtime home for StarLang. Before
contributing, read the design and language decision recorded in the research
repository:

- [STAR-LANG-INDEX-001: Common Lisp Implementation][impl-index]
- [STAR-LANG-001: Final Common Lisp Architecture][arch-001]

[impl-index]: https://github.com/lost-rob0t/starintel-auto-research/blob/main/roam/indexes/star-lang/STAR-LANG-INDEX-001-implementation.org
[arch-001]: https://github.com/lost-rob0t/starintel-auto-research/blob/main/roam/design/star-lang/STAR-LANG-001-common-lisp-host-portable-manifest.org

## Implementation language

Common Lisp is the sole approved implementation language for parser, compiler,
dispatcher, and runtime code. Alternate languages are **denied**. Generated
Python or TypeScript may exist only as boundary bindings that consume versioned
JSON contracts and must not implement StarLang semantics.

## Upstream contribution and fork policy

- This is the canonical upstream for the `star-*` and `starlang-*` systems.
- Forks are welcome for experimentation; releases are cut only from `main`.
- Do not vendor modified copies of these systems into other repositories.
  Consumers depend on released versions or pinned Git SHAs.
- Cross-research design discussion belongs in `starintel-auto-research`, not
  here. This repository holds runtime implementation only.
- Contributions must keep CI green (SBCL-first matrix in
  `.github/workflows/ci.yml`) and not regress the Common Lisp-only boundary.

## Commits and changes

- Make minimal, reviewable changes.
- Keep I/O, parsing, storage, routing, and domain logic separated.
- Preserve structured errors; do not swallow conditions silently.
- Add regression tests for bug fixes under the affected system's `tests/`.
- Never commit secrets, credentials, private datasets, or local evidence.

## Review and release

- `main` is protected; all changes flow through pull requests.
- Releases follow the changelog policy in `CHANGELOG.md`.
- Each release produces a Git tag of the form `vX.Y.Z` and updates the SBOM
  inventory in `SECURITY.md`.
