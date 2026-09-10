# StarLang production readiness

Status: **not production-ready**

StarLang becomes a production language when the product path is owned entirely by final `star-*` and `starlang-*` systems. Passing tests in `starlang-prototype` is necessary during migration, but it is not evidence that the migration is complete.

## Hard release gate

`ci/prototype-migration.tsv` is the machine-readable authority ledger for every implementation component still loaded by `starlang-prototype.asd`.

```sh
bash ci/check-prototype-migration.sh
bash ci/check-prototype-migration.sh --require-final
```

The first command is the normal structural CI gate. It fails when a prototype component is added, removed, or renamed without updating the ledger, when an invalid state is used, or when a component points at a final owner that is not independently load-checked.

The second command is the production release gate. It fails until every remaining prototype component is `compat`, meaning it contains compatibility composition/forwarding only and no authoritative language or runtime behavior.

Do not change a ledger row to `compat` merely to satisfy the gate. The implementation must move first, its final-system tests must pass independently, and the prototype file must become a thin compatibility layer or leave the authoritative ASDF system.

## P0: finish the compiler

The final `starlang-compiler` must own the complete source-to-IR path without loading `starlang-prototype`:

```text
UTF-8 bytes
  -> read-star-syntax
  -> exact locked import resolution
  -> expand-star-syntax
  -> validate-star-core
  -> compile-star-core
  -> runtime-neutral normalized IR
```

Extraction order:

1. syntax objects, source spans, structured diagnostics, and parser resource limits from `core-surface-prototype`;
2. the closed `.star` parser and the no-Common-Lisp-reader invariant;
3. bounded hygienic macro expansion from `macro-expander-prototype`;
4. semantic validation and normalized IR from `core-semantics-prototype` and `compiler-ir-prototype`;
5. specification/domain compilation and full SHA-256/HTTPS import policy;
6. loader resolution and effect adapters;
7. generated portable manifests and Python/TypeScript bindings;
8. public compile/check APIs and CLI entry points.

The resolver effect protocol is the first loader-boundary item moved to the final compiler. Network and digest implementations remain adapters; compiler policy must not gain ambient shell/network authority.

Before a stable release, the research-conformance blocker must be closed with executable regression coverage for field casing, canonical numbers/JSON, complete digests, source spelling/spans, parser bounds, secure imports, and runtime-neutral IR.

## P0: finish the actor runtime

`starlang-runtime` and the final actor systems must own one semantic path for:

- actor definition materialization, registration, lifecycle, and generation;
- bounded mailboxes and serialized state transitions;
- tell and split-phase ask/reply without deadlocking nested actor exchanges;
- command/reply/error/cancel wire lifecycle;
- deterministic dispatch and external adapter dispatch;
- runtime directory and remote registration/dispatch;
- supervision and restart policy;
- journal, replay, idempotency, leases, and fencing;
- concrete Sento/cl-gserver integration behind `star-sento-compat`;
- deterministic shutdown with no leaked actor systems, processes, or workers.

A fake operation port can prove argument forwarding. It does not count as evidence for actor semantics. Actor-semantic integration tests must execute through the real actor system/runtime boundary being claimed.

## P0: make the product path final-only

The installed `starlang` command must stop loading `starlang-prototype` as the product runtime. The stable command/API surface should provide explicit compile/check/run behavior, deterministic exit status, structured diagnostics, and version reporting while loading only final systems.

Nix, ASDF, CI, and packaged artifacts must exercise that same path. A compatibility test suite may continue to load `starlang-prototype` until the directory is deleted, but production execution may not depend on it.

## P0: reproducible release contract

A production release requires all of the following at the same commit:

- `bash ci/check-prototype-migration.sh --require-final` passes;
- final compiler and runtime test systems pass in fresh SBCL processes;
- real Sento integration passes when that backend is shipped;
- real external logic adapters pass their pinned integration suites when shipped;
- `nix flake check -L` passes from a clean checkout;
- frozen canonical fixtures and generated bindings are reproducible;
- dependency/version locks, license inventory, and SBOM are current;
- no implementation authority is hidden in example, fixture, or compatibility code;
- the README no longer describes `prototype/` as authoritative.

Only then should the language move from a `0.x`/transitional contract to a stable production release policy.

## P1 after the semantic core is stable

Production ergonomics matter, but they come after language/runtime authority is settled: formatter, Emacs major mode/LSP-quality diagnostics, package/library UX, profiling, tracing, benchmark suites, compatibility policy, deprecation tooling, and release migration docs.

The rule is simple: do not make tooling polish hide an unfinished compiler/runtime port.
