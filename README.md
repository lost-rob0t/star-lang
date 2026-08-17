# star-lang

Common Lisp-only **StarLang** compiler and durable actor runtime.

`star-lang` hosts the reusable Common Lisp systems that power the StarIntel
actor platform. The approved research and design evidence lives in
[`lost-rob0t/starintel-auto-research`][research]; `starintel-server` consumes
released runtime systems from this repository.

[research]: https://github.com/lost-rob0t/starintel-auto-research

## Coding-agent contract

BEGIN STARLANG AGENT INSTRUCTIONS
- `main` is canonical; every change is reviewed through a pull request.
- Common Lisp is the sole runtime and compiler implementation language.
- The StarLang research/design repository is semantic design authority.
- Executable ASDF, Nix, CI, and runtime state outranks stale status prose.
- Add no new authoritative behavior under `prototype/`.
- Migration means move, delegate, or delete behavior; never duplicate it.
- Use test-driven development and run focused, surrounding, and full gates.
- Actor-semantic tests must execute the real runtime boundary they claim to verify.
- Mocks may replace external-effect ports, never actor semantics evidence.
- Keep the final-system dependency graph acyclic.
- Commit no secrets, credentials, private datasets, or private evidence.
- Complete the applicable ASDF, CI, and `nix flake check -L` gates before declaring completion.
- Update ownership and migration documentation whenever executable ownership moves.
END STARLANG AGENT INSTRUCTIONS

## Research conformance

The implementation is being hardened against the approved Star-Lang research
sequence `STAR-LANG-RESEARCH-000` through `STAR-LANG-RESEARCH-009`.

**Current status: not yet fully conformant.** The authoritative implementation
ledger is [`RESEARCH-CONFORMANCE-000-009.md`](RESEARCH-CONFORMANCE-000-009.md),
and completion is blocked by [issue #6][conformance-issue]. Research approval
does not imply that the current implementation already satisfies every rule.

[conformance-issue]: https://github.com/lost-rob0t/star-lang/issues/6

The required boundary is:

- Common Lisp is the sole parser, compiler, semantic-engine, dispatcher, and
  runtime implementation language.
- `.star` source must be parsed by the closed Star-Lang parser and never by the
  Common Lisp reader.
- specification imports must be exact-versioned, full SHA-256 locked, locally
  compiled, and HTTPS-only when remote resolution is explicitly enabled.
- normalized IR must remain data-only and runtime-neutral; cl-gserver operations
  may appear only in adapter manifests.
- document, message, manifest, and serialized wire field names must use lower
  camelCase and preserve source spelling.
- canonical JSON must use lower camelCase keys, deterministic key ordering,
  finite binary64 JSON numbers for `float`, and canonical strings for exact
  `decimal`.
- generated Python and TypeScript bindings consume the same portable manifest;
  they do not implement StarLang.

The compiler front end is one explicit pipeline:

```text
UTF-8 source bytes
  → read-star-syntax
  → locked import resolution
  → expand-star-syntax
  → validate-star-core
  → compile-star-core
  → normalized runtime-neutral IR
```

The expansion phase supports bounded, declarative format-1 macros in declaration
context. Macro definitions are collected before expansion, imported macros retain
their locked library identity, generated identifiers receive deterministic fresh
scopes, and expansion records definition/use-site provenance without invoking the
Common Lisp reader or evaluator. Parsed identifiers remain exact, uninterned
strings. `star-syntax-to-datum` is an explicit lossy compatibility operation: it
discards occurrence identity, spans, scopes, origins, and introduction metadata.

A permanent conformance suite must guard these rules before this section can be
changed to claim full compliance.

## Scope

This repository is the **runtime home** for the following Common Lisp systems.
It is not the design source and contains no live Franklin County data
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
| `star-verification` | Immutable verification certificate, claim vocabulary, and evidence-scope contract. |
| `star-adapter-sdk` | SDK for building inbound and outbound adapter ports. |
| `star-http-port` | HTTP adapter port built on the adapter SDK. |
| `star-process-port` | External-process adapter port. |
| `star-canonical-json` | Canonical JSON serialization for deterministic interchange. |
| `star-xlsx` | XLSX reading and writing for structured ingest. |
| `starlang-compiler` | The StarLang parser, IR, and compiler. |
| `starlang-runtime` | The durable actor runtime that executes compiled StarLang. |

`star-verification` is authoritative only for the generic
`star.verify.certificate/1` data contract and its closed vocabularies. It does
not validate documents, match actor manifests, execute lifecycle transitions,
model-check topologies, persist artifacts, or serialize canonical JSON. Those
behaviors remain with their existing or later dependency-correct authorities.

## Implementation language

Common Lisp is the **sole** approved implementation language, per
[STAR-LANG-INDEX-001][impl-index] in the research repository. Alternate parser,
compiler, dispatcher, and runtime implementations are denied. Generated Python
and TypeScript bindings may consume versioned JSON contracts at system
boundaries but do not implement StarLang.

[impl-index]: https://github.com/lost-rob0t/starintel-auto-research/blob/main/roam/indexes/star-lang/STAR-LANG-INDEX-001-implementation.org

## Transitional architecture

`prototype/` is migration debt, not a license for new runtime development. The
installed CLI and broad compatibility suite still compose through
`starlang-prototype`, while final `star-*` and `starlang-*` systems own the
semantics already extracted from it.

The target systems must not duplicate or shadow prototype source files. A file
moves only when its package ownership and dependencies can be represented by an
acyclic final-system boundary. Until then, the working code remains owned by
`starlang-prototype`.

`ci/target-systems.txt` is the checked list of final systems. SBCL CI and Nix
load each entry in a fresh process so incomplete package definitions and ASDF
dependency errors cannot hide behind the prototype system.

### Migration map

| Prototype components | Intended final boundary |
| --- | --- |
| `core-surface-prototype`, `actor-wire-prototype`, message lifecycle files | `star-actor-protocol` and runtime-facing protocol packages |
| `canonical-json-prototype` | `star-canonical-json` |
| `compiler-ir-prototype`, `spec-domain-prototype`, `binding-generator-prototype` | `starlang-compiler` |
| dispatcher, runtime directory, loader, document, constructor, and API files | `starlang-runtime` |
| transport and dispatcher transport adapter files | `star-adapter-sdk`, then concrete port systems |
| `cl-gserver-runtime-facade-prototype` | `star-sento-compat` |
| runtime and remoting journal files | `star-journal` |
| remoting lease file | `star-lease` |
| domain server and remoting files | `starlang-runtime` plus the relevant adapter-port systems |

Mailbox, supervision, capability, artifact, HTTP, process, and XLSX ownership is
filled as those APIs are extracted. Their target systems are load-checked now;
that does not make placeholder packages authoritative over `prototype/`.

### Current actor-runtime migration state

- `star-actor-protocol`, `star-mailbox`, and `starlang-runtime` own the final
  deterministic actor contract and execution path.
- `star-sento-compat` owns concrete local Sento construction, spawn, tell,
  asynchronous ask/reply translation, lookup, liveness, stop, and shutdown.
- Real Sento integration tests hard-load the backend only in the test system;
  the production compatibility system keeps a soft backend dependency.
- Prototype domain-remoting code is a transitional composition wrapper over
  final compatibility entry points. It no longer owns direct backend calls.
- `starlang-prototype` remains in the product load graph, and
  `prototype/run-star.lisp` remains the installed CLI. The overall prototype
  migration is therefore not complete.
- Split-phase nested actor ask, final supervision policy, and later durable
  distributed-runtime extraction remain separate follow-up work.

## Validation

ASDF owns the complete prototype test contract. The secondary
`starlang-prototype/tests` system runs the baseline and every
`prototype/*-tests.lisp` script in deterministic filename order, using a fresh
SBCL process for each script.

```sh
sbcl --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:load-system :starlang-prototype)' \
  --eval '(asdf:test-system :starlang-prototype)' \
  --eval '(sb-ext:quit)'
```

```sh
nix flake check -L
```

A failing child test process causes `asdf:test-system`, SBCL CI, and the Nix
check to fail.

## Nix

The flake packages the complete StarLang source tree, loads the authoritative
prototype and declared target systems, runs the prototype ASDF test operation,
and exposes runnable development commands.

```sh
nix build
nix run
nix run .#tests
nix develop
nix flake check -L
```

The installed package provides:

- `bin/starlang`: starts SBCL with `starlang-prototype` loaded.
- `bin/starlang-test`: runs `(asdf:test-system :starlang-prototype)`.
- `share/common-lisp/source/star-lang`: ASDF-visible StarLang sources.

## Layout

```text
prototype/               Authoritative StarLang implementation and test scripts
fixtures/                .star and .sexp test fixtures
ci/target-systems.txt    Final systems loaded independently by CI and Nix
<system>/                Incrementally populated target ASDF system directories
starlang-prototype.asd   Transitional implementation and test ASDF systems
flake.nix                Package, apps, checks, and development shell
.github/workflows/       SBCL and Nix CI
```

## Tooling entry points

- **ASDF** loads `(asdf:load-system :starlang-prototype)` and tests
  `(asdf:test-system :starlang-prototype)`.
- **SBCL** is the primary Common Lisp implementation.
- **Roswell** is available in the development shell when provided by Nixpkgs.
- **Nix** builds, runs, and checks StarLang reproducibly.

## Licensing and SBOM

- Source license: **GNU Affero General Public License v3.0 only**
  (`AGPL-3.0-only`).
- Upstream contributions and fork policy: see `CONTRIBUTING.md`.
- Source, license, and SBOM inventory: see `SECURITY.md`.

## Status

`prototype/` remains in the product and CLI composition paths, but ownership is
component-specific. Final systems are authoritative for the actor protocol,
mailbox, deterministic runtime, and concrete Sento adapter described above;
remaining prototype components stay migration debt until moved without
duplication, dependency cycles, or lost coverage. Research 000–009 compliance
remains an active hardening gate tracked in the implementation ledger.
