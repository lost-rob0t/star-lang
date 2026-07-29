# Security, licensing, and SBOM inventory

This file records the source, license, and software bill of materials (SBOM)
policy for `star-lang`.

## License

- **Source license:** GNU General Public License v3.0 (GPL-3.0). See `LICENSE`.
- All first-party `star-*` and `starlang-*` systems are GPL-3.0.

## SBOM inventory

| Component | Origin | License | Notes |
| --- | --- | --- | --- |
| star-actor-protocol | first-party | GPL-3.0 | Actor message protocol. |
| star-sento-compat | first-party | GPL-3.0 | Sento / CL-GServer compatibility shim. |
| star-mailbox | first-party | GPL-3.0 | Per-actor mailbox. |
| star-supervisor | first-party | GPL-3.0 | Supervision trees. |
| star-journal | first-party | GPL-3.0 | Durable write-ahead journal. |
| star-lease | first-party | GPL-3.0 | Time-bound leases. |
| star-capability | first-party | GPL-3.0 | Capability tokens. |
| star-artifact | first-party | GPL-3.0 | Artifact storage. |
| star-adapter-sdk | first-party | GPL-3.0 | Adapter port SDK. |
| star-http-port | first-party | GPL-3.0 | HTTP adapter port. |
| star-process-port | first-party | GPL-3.0 | External-process adapter port. |
| star-canonical-json | first-party | GPL-3.0 | Canonical JSON. |
| star-xlsx | first-party | GPL-3.0 | XLSX handling. |
| starlang-compiler | first-party | GPL-3.0 | StarLang compiler. |
| starlang-runtime | first-party | GPL-3.0 | Durable actor runtime. |
| SBCL | upstream (sbcl.org) | public domain / MIT-style | Primary Common Lisp implementation. |
| ASDF | bundled with implementations | MIT-style | Build system. |
| Quicklisp | quicklisp.org | MIT-style | Dependency manager (offline-cache strategy). |
| Roswell | roswell.github.io | MIT-style | Implementation and system installer. |

## Source inventory policy

- First-party sources are the `star-*` and `starlang-*` systems in this
  repository.
- Third-party dependencies are pinned in a lockfile and fetched through an
  offline cache. Reproducible offline build is a release gate.
- No private datasets, credentials, or evidence are ever committed.

## Vulnerability handling

- Report security issues privately to the maintainers before public disclosure.
- Affected releases receive a patch release (`vX.Y.Z+1`) and an updated SBOM
  entry.
- This repository contains no live data acquisition; runtime-only security
  boundaries apply.
