# Kotlin/JVM runtime migration

Authority: STAR-LANG-014 in `lost-rob0t/starintel-auto-research`.

## Language ownership

| Layer | Current owner | Target |
| --- | --- | --- |
| closed .star parser, spans, macro expansion | Common Lisp | unchanged in this migration |
| normalized IR + canonical manifest | Common Lisp | unchanged in this migration |
| IR -> executable runtime binding | Common Lisp compiler | deterministic Kotlin source |
| mailbox + local actor lifecycle | Common Lisp oracle + Kotlin candidate | Kotlin/JVM |
| wire lifecycle dispatcher | Common Lisp | Kotlin/JVM |
| supervisor | Common Lisp | Kotlin/JVM |
| journal/replay | Common Lisp | Kotlin/JVM |
| leases/capabilities/artifacts | Common Lisp | Kotlin/JVM |
| JVM consumer API | none | Kotlin public API with Java ABI |
| native/edge adapters | effect-specific | Nim where justified |
| native ABI glue | effect-specific | C only when unavoidable |

## Cutover rule

A subsystem moves only after the same fixture executes against both the current
Common Lisp owner and the real Kotlin boundary and produces equivalent normalized
behavior. After cutover, the superseded Common Lisp semantic implementation is
removed or reduced to a forwarding compatibility boundary.

No new runtime semantic feature should be implemented only in the Common Lisp
runtime while its Kotlin port is active.

## Initial parity surface

The first JVM slice mirrors the final local runtime semantics that are already
owned by `star-mailbox` and `starlang-runtime`:

- bounded offer/poll FIFO behavior;
- full/closed delivery results;
- deterministic actor registration order;
- per-runtime ownership;
- state-preserving restart with new generation and fresh mailbox;
- stale actor-reference rejection;
- asynchronous tell plus deterministic single-step dispatch;
- ask measured in deterministic dispatch steps, not wall clock;
- input/output validation hooks;
- explicit state replacement rather than mutation-based implicit commit;
- stale completion fencing when lifecycle changes during a handler.

The Kotlin state model uses immutable portable values so retained aliases cannot
mutate committed actor state after the transition.

## Native-language rule

Nim can be used for standalone adapters when a JVM is unavailable or
materially wrong for the deployment. Those adapters speak frozen StarLang
message/effect contracts and never implement actor state machines.

C is limited to thin FFI for existing native libraries. It must not own parser,
compiler, mailbox, dispatcher, supervision, lifecycle, journal, replay, or
capability semantics.
