# StarLang production readiness

Status: **final-system migration complete on this branch; stable release still gated**

StarLang's production product path is owned by final `star-*` and `starlang-*`
systems. The retired `starlang-prototype.asd` system and `prototype/` source tree
must not return.

This document separates two different claims:

1. **final-system authority** — compiler/runtime/CLI/package code no longer depends
   on prototype authority;
2. **stable production release** — all research-conformance, runtime, adapter,
   packaging, security, and reproducibility gates pass on the same release commit.

The first claim is enforced structurally. The second remains blocked until every
release gate below is green.

## Permanent final-authority gate

Run:

```sh
bash ci/check-final-authority.sh
```

The gate fails if:

- `starlang-prototype.asd` exists;
- `prototype/` exists;
- active ASDF, CI, Nix, or shell configuration references prototype authority;
- the final `starlang-loader` is missing from the independently load-checked
  target systems;
- final compiler program IR / semantic validation ownership disappears;
- final Sento program binding disappears; or
- the CLI delegates to retired prototype code.

This is intentionally a one-way structural rule. There is no compatibility
ledger whose state can be edited to make retirement appear complete.

## Final compiler path

`starlang-compiler` owns the closed source-to-IR path:

```text
UTF-8 source bytes
  -> read-star-syntax
  -> exact locked import resolution
  -> expand-star-syntax
  -> validate-star-core
  -> compile-star-core
  -> runtime-neutral normalized IR
```

Production invariants include:

- `.star` source never reaches Common Lisp `READ`/`EVAL`;
- parser/source work is explicitly bounded;
- syntax occurrences retain source identity/spans;
- imported specifications are exact-versioned and digest locked;
- semantic validation happens before runtime binding;
- normalized IR contains data, not Sento/cl-gserver objects or raw host handles;
- portable manifests are emitted through final compiler/serialization systems.

`star-sento-compat` owns concrete Sento translation after lowering. Backend names
and objects do not become compiler IR authority.

## Final product path

The installed `starlang` command enters `starlang-cli` directly and loads final
systems only. Stable commands are:

```text
starlang version
starlang check FILE
starlang compile FILE [--manifest FILE]
starlang run FILE [--eval FORM]... [--load FILE]... [--package PKG] [--manifest FILE]
starlang load FILE [--allow-network] [--cache DIR] [--manifest FILE]
starlang load-url URL --name NAME --version VERSION --digest SHA256 [options]
```

`load` and `load-url` are now final `starlang-loader` operations. Network
resolution is opt-in. Product code must not fall back to a prototype loader.

Exit status is stable: 0 success, 1 runtime/diagnostic failure, 2 usage error.

## Final actor/runtime path

A stable production release must keep one final semantic authority for:

- actor definition/materialization, lifecycle, identity, and generation;
- bounded mailboxes and serialized actor-state transitions;
- tell and split-phase ask/reply semantics;
- command/reply/error/cancel lifecycle;
- deterministic dispatch and external adapter dispatch;
- runtime directory / actor discovery;
- supervision and restart policy;
- journal/replay/idempotency and lease/fencing semantics;
- concrete Sento/cl-gserver integration behind `star-sento-compat`;
- deterministic drain/shutdown without leaked actors, workers, or processes.

Mocks may prove external-effect port behavior. They do not count as actor-semantic
evidence. Shipped Sento behavior requires real Sento integration evidence.

## Research-conformance release blocker

Prototype retirement is not permission to call the language fully conformant.
`RESEARCH-CONFORMANCE-000-009.md` remains authoritative for the approved research
boundary, and issue #6 remains the integration gate.

In particular, a stable release must not be claimed until the remaining
conformance work — including the binary64 `float`/canonical-number contract,
canonical relation positions, complete digest/import policy, generated binding
coverage, and permanent research-conformance CI guards — is complete.

## Reproducible release contract

A production release requires all applicable checks to pass on the **same commit**:

```sh
bash ci/check-final-authority.sh
nix flake check -L
```

And, through CI/ASDF/package checks:

- every system in `ci/target-systems.txt` loads independently in a fresh process;
- final compiler, loader, CLI, runtime, journal, lease, mailbox, supervisor,
  protocol, canonical JSON, and adapter suites pass;
- real Sento integration and the final-only two-process remoting smoke pass;
- shipped external logic adapters pass their pinned integration suites;
- canonical fixtures and generated bindings reproduce exactly;
- the installed `starlang` package executes the same final-only path tested by CI;
- dependency/version locks, license inventory, and SBOM are current;
- no implementation authority is hidden in fixtures/examples/compatibility code;
- no secret, credential, private dataset, or private evidence is present.

A green subset is not a release. A failed or skipped required check keeps the
release blocked.

## Release policy

StarLang remains a `0.x` contract while research conformance and the remaining
service-grade runtime/embedding gates are still active. Moving to a stable
release line requires:

1. issue #6 / research 000–009 conformance closed with permanent executable gates;
2. final runtime and embedding acceptance profiles satisfied;
3. exact-head ASDF, CI, Nix, native interoperability, and package checks green;
4. release artifacts generated from that exact commit; and
5. ownership/status documentation updated to match executable reality.

Production ergonomics — formatter/LSP/editor UX, profiling, tracing, benchmarks,
deprecation helpers, and migration guides — matter after semantic and release
authority is proven. Tooling polish must not hide a red semantic gate.
