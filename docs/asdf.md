# StarLang as a Common Lisp library

StarLang final systems use ordinary ASDF discovery and load semantics.

From a checkout in the ASDF source registry:

```lisp
(require :asdf)
(asdf:load-system "star-lang")
```

`star-lang` is a side-effect-free convenience system over the final compiler and runtime. Loading it does not load the transitional prototype, start an actor system, initialize SWI-Prolog, spawn a logic worker, read provider credentials, or activate Prolog-RLM.

Individual final systems remain directly loadable, for example:

```lisp
(asdf:load-system "starlang-compiler")
(asdf:load-system "starlang-runtime")
(asdf:load-system "star-logic-protocol")
(asdf:load-system "star-logic-ir")
```

Tests use normal ASDF operations:

```lisp
(asdf:test-system "star-lang")
```

The aggregate test operation delegates to compiler, runtime, logic-protocol and logic-IR tests.

## Optional Prolog-RLM integration

Prolog-RLM is intentionally **not** a dependency of `star-lang`. The planned optional `star-prolog-rlm` final system is tracked by P0 issues #113 and #114 and must remain explicitly loaded.

Until the native logic boundary in #113 is complete, StarLang must not expose an RLM integration that silently falls back to a parallel raw-text or per-query process API merely to make the optional system appear finished.

The required end state is:

```lisp
(asdf:load-system "star-lang")       ; core only
(asdf:load-system "star-prolog-rlm") ; explicit optional integration
```

Loading core must continue to work when Prolog-RLM is not installed. Loading the optional system must use a reproducibly packaged upstream `prolog-rlm` and must not make upstream Prolog-RLM depend on StarLang.

Standalone Prolog-RLM CLI, library, Agent Zero, PrologAgent, and OpenCode-oriented workflows remain independent compatibility surfaces.
