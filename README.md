# star-lang

Common Lisp-only **StarLang** compiler and durable actor runtime.

`star-lang` hosts the reusable compiler, runtime, actor, protocol, logic, and
adapter systems used by StarIntel. The approved research/design evidence lives
in [`lost-rob0t/starintel-auto-research`][research]; product consumers depend on
released final systems from this repository.

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

## Authority model

The production tree is final-only:

- `starlang-compiler` owns the closed parser, expansion, validation, and
  runtime-neutral normalized IR;
- `starlang-loader` owns locked local/remote specification loading;
- `starlang-runtime` owns portable actor/runtime semantics;
- `starlang-cli` owns the installed command surface;
- `star-*` systems own protocol, mailbox, supervision, durability, adapters,
  canonical serialization, logic, verification, and other reusable boundaries;
- `star-sento-compat` translates supported runtime operations to Sento/cl-gserver.

`starlang-prototype.asd` and `prototype/` are retired. The permanent structural
gate is:

```sh
bash ci/check-final-authority.sh
```

It is a regression if active product/build code reintroduces prototype authority.

## Research conformance

StarLang is being hardened against approved research
`STAR-LANG-RESEARCH-000` through `STAR-LANG-RESEARCH-009`.

**Prototype retirement does not mean full research conformance.**
[`RESEARCH-CONFORMANCE-000-009.md`](RESEARCH-CONFORMANCE-000-009.md) is the
implementation ledger and issue #6 is the integration gate. Remaining stable
release work includes the complete binary64 `float` contract, canonical relation
positions, import/digest hardening, generated-binding coverage, and permanent
research-conformance CI guards.

The compiler front end is one explicit pipeline:

```text
UTF-8 source bytes
  -> read-star-syntax
  -> exact locked import resolution
  -> expand-star-syntax
  -> validate-star-core
  -> compile-star-core
  -> runtime-neutral normalized IR
```

Core invariants:

- Common Lisp is the only compiler/runtime implementation language;
- `.star` source never passes through Common Lisp `READ`/`EVAL`;
- parser/source work is bounded and diagnostics retain source identity/spans;
- specification imports are explicit, exact-versioned, and SHA-256 locked;
- normalized IR is data-only and runtime-neutral;
- Sento/cl-gserver objects exist only behind final runtime/adapter boundaries;
- document/message/manifest/wire field names preserve approved lower-camelCase
  spelling;
- canonical JSON is deterministic;
- generated bindings consume portable manifests and do not implement StarLang.

## Final systems

`ci/target-systems.txt` is the machine-checked list of independently loadable
final systems. It currently includes:

| System | Purpose |
| --- | --- |
| `star-actor-protocol` | Actor message/wire protocol contracts. |
| `star-sento-compat` | Concrete Sento/cl-gserver translation boundary. |
| `star-mailbox` | Bounded mailbox and serialized dispatch primitives. |
| `star-supervisor` | Supervision/restart policy. |
| `star-journal` | Durable runtime journal/replay primitives. |
| `star-lease` | Lease/fencing primitives. |
| `star-capability` | Capability/authorization values. |
| `star-artifact` | Artifact/provenance storage contracts. |
| `star-verification` | Verification certificate and claim vocabulary. |
| `star-adapter-sdk` | Common adapter-port contracts. |
| `star-http-port` | HTTP adapter port. |
| `star-scrape` | Scraping adapter primitives. |
| `star-process-port` | External-process adapter boundary. |
| `star-canonical-json` | Deterministic canonical JSON/wire serialization. |
| `star-logic-protocol` | Engine-neutral logic protocol. |
| `star-logic-ir` | Engine-neutral logic IR. |
| `star-logic-testing` | Logic adapter conformance fixtures. |
| `star-logic-adapter-swi` | SWI-Prolog adapter behind the final logic protocol. |
| `star-xlsx` | XLSX structured-data support. |
| `starlang-compiler` | Closed parser, semantics, IR, manifests. |
| `starlang-loader` | Locked specification/program loading. |
| `starlang-runtime` | Durable actor runtime. |
| `starlang-cli` | Installed StarLang CLI. |

Local native ZMQ interoperability lives in the standalone `star-zmq` subflake
and is exercised by its own native/Nix workflow. It is not a second StarLang
compiler/runtime implementation.

## CLI

The installed `starlang` command loads final systems only:

```text
starlang version
starlang check FILE
starlang compile FILE [--manifest FILE]
starlang run FILE [--eval FORM]... [--load FILE]... [--package PKG] [--manifest FILE]
starlang load FILE [--allow-network] [--cache DIR] [--manifest FILE]
starlang load-url URL --name NAME --version VERSION --digest SHA256 [options]
```

`load` and `load-url` use final `starlang-loader`. Network resolution is opt-in.
Host-side `--load` / `--eval` on `run` are explicit trusted CLI operations; Star
source itself is never sent to the Common Lisp reader.

Exit status:

- `0` success;
- `1` runtime or diagnostic failure;
- `2` usage error.

## Validation

From a development environment:

```sh
bash ci/check-final-authority.sh
nix flake check -L
```

The Nix package also exposes:

```sh
nix build
nix run -- version
nix run -- check fixtures/actor-compiler/enrichment-worker.star
nix run .#tests
nix develop
```

The release matrix additionally exercises independent ASDF loads/tests, final
CLI commands, real Sento integration, a final-only two-process Sento remoting
smoke, SWI adapter conformance, canonical fixtures, generated artifacts, and
native interoperability workflows.

A green subset is not release evidence. Required checks must pass on the same
commit that produces release artifacts.

## Nix package

`flake.nix` builds a final-only `star-lang` package containing:

- `bin/starlang` — final CLI entrypoint;
- `bin/starlang-test` — packaged final-system test entrypoint;
- `share/common-lisp/source/star-lang` — ASDF-visible sources.

The build independently loads every system in `ci/target-systems.txt` and asserts
that package `STAR-LANG.PROTOTYPE` is absent. The check phase executes the final
compiler/runtime/loader/CLI/adapter matrix and permanent final-authority gate.

## Runtime evidence rule

Actor semantics must be tested through the real actor/runtime boundary being
claimed. Fake ports are acceptable for external effects, but they are not proof
of actor semantics.

For shipped Sento behavior the repository therefore carries both focused real
Sento integration tests and a real two-process remoting smoke. Runtime-specific
Sento binding happens after compiler lowering; portable IR does not contain raw
Sento references.

## Layout

```text
ci/                         Structural/release gates and target-system list
fixtures/                    StarLang and interchange fixtures
nix/                         Pinned Nix integration modules
star-*/                      Final reusable runtime/protocol/adapter systems
starlang-compiler/           Final compiler
starlang-loader/             Final loader
starlang-runtime/            Final actor runtime
starlang-cli/                Final installed CLI
star-zmq/                    Standalone local native ZMQ interoperability subflake
.prolog/kb/                  Machine-checkable repository/authority facts
.github/workflows/           CI, Nix, native, logic, and release gates
flake.nix                    Main package/check/dev-shell definition
```

There is deliberately no `prototype/` product tree.

## Production readiness

The final-authority migration is structural, but the project remains on a
`0.x` contract until the stable-release gates in
[`docs/PRODUCTION-READINESS.md`](docs/PRODUCTION-READINESS.md) are all green.
The research-conformance ledger, final runtime/embedding acceptance, ASDF/CI/Nix
matrix, native interoperability, license/SBOM inventory, and release artifacts
must agree on one exact commit before a stable production release is declared.

## Licensing and SBOM

- Source license: **GNU Affero General Public License v3.0 only**
  (`AGPL-3.0-only`).
- Contribution/fork policy: [`CONTRIBUTING.md`](CONTRIBUTING.md).
- Source/license/SBOM inventory: [`SECURITY.md`](SECURITY.md).
