# StarLang language support contract

StarLang is intentionally polyglot.

## Permanent invariants

- Common Lisp is a permanent first-class compiler and runtime backend.
- Kotlin/JVM is an additive peer runtime backend, not a Common Lisp replacement.
- The StarLang specification, normalized IR, wire contracts, canonical fixtures,
  and conformance tests define semantics across implementations.
- Runtime parity never authorizes deletion or demotion of another supported backend.
- Removing or demoting a supported backend requires a new explicit operator-approved decision.

## Current support matrix

| Language | Compiler/runtime role |
| --- | --- |
| Common Lisp | first-class compiler + runtime |
| Kotlin | peer JVM runtime + generated executable target |
| Java | JVM consumer ABI / generated boundary |
| Python | generated portable boundary / external actor integration |
| TypeScript | generated portable boundary / external actor integration |
| Nim | generated boundary + native/edge adapter option |
| Go | generated portable boundary |
| Rust | generated portable boundary |
| Emacs Lisp | generated portable boundary |
| Prolog | generated portable boundary + logic integration |

A generated boundary does not automatically claim a full native runtime.
Additional full runtimes may be added only by passing the same conformance suite.

## CI expectation

Repository policy and reviews must reject changes that describe Common Lisp as
temporary, fallback-only, legacy-only, retired, or scheduled for deletion as a
consequence of Kotlin/JVM parity work.
