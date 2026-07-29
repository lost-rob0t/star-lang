# star-lang

Common Lisp-only **StarLang** compiler and durable actor runtime.

`star-lang` hosts the reusable Common Lisp systems that power the StarIntel
actor platform. The research and design evidence lives in
[`lost-rob0t/starintel-auto-research`][research]; `starintel-server` later
consumes released runtime systems from this repository.

[research]: https://github.com/lost-rob0t/starintel-auto-research

## Scope

This repository is the **runtime home** for the following Common Lisp systems.
It is *not* the design source and contains *no* live Franklin County data
acquisition implementation.

| System | Purpose |
| --- | --- |
| `star-actor-protocol` | Actor message and protocol definitions. |
| `star-sento-compat` | Compatibility shim for the Sento / CL-GServer actor model. |
| `star-mailbox` | Per-actor mailbox and single-message dispatch. |
| `star-supervisor` | Supervision trees, restart strategies, and child lifecycle. |
| `star-journal` | Durable write-ahead journal for recovery and replay. |
| `star-lease` | Time-bound leases for actors and resources. |
| `star-capability` | Capability tokens and authorization surface. |
| `star-artifact` | Artifact storage and provenance attachment. |
| `star-adapter-sdk` | SDK for building inbound and outbound adapter ports. |
| `star-http-port` | HTTP adapter port built on the adapter SDK. |
| `star-process-port` | External-process adapter port. |
| `star-canonical-json` | Canonical JSON serialization for deterministic interchange. |
| `star-xlsx` | XLSX reading and writing for structured ingest. |
| `starlang-compiler` | The StarLang parser, IR, and compiler. |
| `starlang-runtime` | The durable actor runtime that executes compiled StarLang. |

## Implementation language

Common Lisp is the **sole** approved implementation language, per
[STAR-LANG-INDEX-001][impl-index] in the research repository. Every alternate
parser, compiler, dispatcher, and runtime implementation is denied. Generated
Python and TypeScript bindings may consume versioned JSON contracts at system
boundaries but do not implement StarLang.

[impl-index]: https://github.com/lost-rob0t/starintel-auto-research/blob/main/roam/indexes/star-lang/STAR-LANG-INDEX-001-implementation.org

## Layout

```
prototype/               65 Common Lisp source files (~15K LOC) — the real StarLang implementation
  *.lisp                 parser, compiler, dispatcher, runtime, remoting, journal, etc.
  tests.lisp             baseline test + benchmark entry point
  *-tests.lisp           individual test suites (run via sbcl --script)
fixtures/                .star and .sexp fixture files for tests
<system>/                placeholder ASDF system directories (to be filled from prototype/)
  <system>.asd           ASDF system definition
  src/                   implementation sources
  tests/                 FiveAM-style tests
starlang-prototype.asd   transitional ASDF system that loads the full prototype
.github/workflows/ci.yml SBCL-first CI running all 24 test suites
flake.nix                Nix flake entry point
```

## Tooling entry points

- **ASDF** is the build system. Each system is loadable via `(asdf:load-system :star-actor-protocol)`.
- **SBCL** is the primary implementation. CI runs SBCL first; other conforming
  implementations (ECL, ABCL) may be added later as a non-blocking matrix.
- **Roswell** installs SBCL and loads systems reproducibly. See `docs/roswell.md`.
- **Nix** provides a reproducible offline cache via `flake.nix` (`nix develop`).

## Licensing and SBOM

- Source license: **GPL-3.0** (see `LICENSE`).
- Upstream contributions and fork policy: see `CONTRIBUTING.md`.
- Source, license, and SBOM inventory: see `SECURITY.md`.

## Status

The real StarLang prototype implementation (65 Common Lisp files, ~15K LOC) now
lives in `prototype/`. All 24 test suites pass under SBCL. The code is organized
as a transitional `starlang-prototype` ASDF system; the 15 target `star-*` and
`starlang-*` systems are scaffolded placeholders that will be filled
incrementally by splitting the prototype code along its natural boundaries.
