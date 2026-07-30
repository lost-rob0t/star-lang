# Security, licensing, and SBOM inventory

This file records the source, license, and software bill of materials (SBOM)
policy for `star-lang`.

## License

- **Source license:** GNU Affero General Public License v3.0 only
  (`AGPL-3.0-only`). See `LICENSE`.
- All first-party `star-*` and `starlang-*` systems are `AGPL-3.0-only`.

## SBOM inventory

| Component | Origin | License | Notes |
| --- | --- | --- | --- |
| star-actor-protocol | first-party | AGPL-3.0-only | Actor message protocol. |
| star-sento-compat | first-party | AGPL-3.0-only | Sento / CL-GServer compatibility shim. |
| star-mailbox | first-party | AGPL-3.0-only | Per-actor mailbox. |
| star-supervisor | first-party | AGPL-3.0-only | Supervision trees. |
| star-journal | first-party | AGPL-3.0-only | Durable write-ahead journal. |
| star-lease | first-party | AGPL-3.0-only | Time-bound leases. |
| star-capability | first-party | AGPL-3.0-only | Capability tokens. |
| star-artifact | first-party | AGPL-3.0-only | Artifact storage. |
| star-adapter-sdk | first-party | AGPL-3.0-only | Adapter port SDK. |
| star-http-port | first-party | AGPL-3.0-only | HTTP adapter port. |
| star-process-port | first-party | AGPL-3.0-only | External-process adapter port. |
| star-canonical-json | first-party | AGPL-3.0-only | Canonical JSON. |
| star-xlsx | first-party | AGPL-3.0-only | XLSX handling. |
| starlang-compiler | first-party | AGPL-3.0-only | StarLang compiler. |
| starlang-runtime | first-party | AGPL-3.0-only | Durable actor runtime. |
| SBCL | upstream (sbcl.org) | public domain / MIT-style | Primary Common Lisp implementation. |
| ASDF | bundled with implementations | MIT-style | Build system. |
| Quicklisp | quicklisp.org | MIT-style | Dependency manager. |
| Roswell | roswell.github.io | MIT-style | Implementation and system installer. |
| Nixpkgs | upstream (nixos.org) | MIT | Reproducible package inputs. |

## Source inventory policy

- First-party sources are the `star-*` and `starlang-*` systems in this
  repository.
- Third-party dependencies must be pinned and reproducibly fetched.
- No private datasets, credentials, or evidence are ever committed.

## Vulnerability handling

- Report security issues privately to the maintainers before public disclosure.
- Affected releases receive a patch release and an updated SBOM entry.
- This repository contains no live data acquisition; runtime-only security
  boundaries apply.
