# Kotlin/JVM runtime expansion

Authority: #162 plus the operator reversal of STAR-LANG-014.

Kotlin/JVM is an additive peer runtime. This work does **not** migrate StarLang away from Common Lisp.

## Language ownership

| Layer | Common Lisp | Kotlin/JVM |
| --- | --- | --- |
| closed .star parser, spans, macro expansion | first-class, retained | consumes normalized IR |
| normalized IR + canonical manifest | first-class compiler authority | consumes shared contracts |
| executable runtime binding | first-class CL runtime | peer Kotlin runtime |
| mailbox + local actor lifecycle | retained + conformance target | peer implementation |
| wire lifecycle dispatcher | retained + conformance target | peer implementation |
| supervisor | retained + conformance target | peer implementation |
| journal/replay | retained + conformance target | peer implementation |
| leases/capabilities/artifacts | retained + conformance target | peer implementation |
| JVM consumer API | n/a | Kotlin public API + Java ABI |

Portable generated/boundary support remains available for Common Lisp, Python,
TypeScript, Nim, Java, Kotlin, Go, Rust, Emacs Lisp, and Prolog.

## Parity rule

A JVM subsystem is accepted only after shared fixtures execute against both the
real Common Lisp and real Kotlin/JVM boundaries and produce equivalent normalized
observable behavior.

Parity is **not a cutover trigger**. The Common Lisp implementation remains
supported after the Kotlin implementation reaches parity.

No agent may:

- describe Common Lisp as temporary, legacy, fallback-only, or scheduled for retirement;
- delete or demote Common Lisp runtime/compiler capability as part of JVM work;
- silently change a default runtime merely because a peer backend reaches parity;
- remove an existing generated/boundary language target without explicit operator approval.

## Initial parity surface

The first JVM slice mirrors local runtime semantics already owned by
`star-mailbox` and `starlang-runtime`:

- bounded offer/poll FIFO behavior;
- full/closed delivery results;
- deterministic actor registration order;
- per-runtime ownership;
- state-preserving restart with new generation and fresh mailbox;
- stale actor-reference rejection;
- asynchronous tell plus deterministic single-step dispatch;
- deterministic ask semantics;
- input/output validation hooks;
- explicit state replacement rather than mutation-based implicit commit;
- stale completion fencing when lifecycle changes during a handler.

## Native-language rule

Nim may be used for standalone native/edge adapters when a JVM is unavailable or
materially wrong for a deployment. Those adapters speak frozen StarLang
message/effect contracts.

C is limited to thin FFI for native libraries unless a separate operator-approved
runtime decision expands its role.
