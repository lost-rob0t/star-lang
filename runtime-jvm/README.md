# StarLang runtime-jvm

This module is the Kotlin/JVM peer runtime backend. It is additive to, not a replacement for, the permanent Common Lisp runtime.

The semantic core is deliberately synchronous and deterministic. Concurrency,
coroutines, transports, Android services, and native helpers belong outside the
core and may schedule effects only around this state machine.

Current first-slice coverage:

- portable immutable runtime values;
- bounded FIFO mailbox with accepted/full/closed outcomes;
- actor definitions and instances;
- per-runtime name/URI ownership;
- generation-fenced actor references;
- stop/start/restart/shutdown;
- deterministic tell/ask/dispatch/run-until-idle;
- input/output validation hooks;
- state commit only after the dispatch incarnation is still current;
- stale-completion rejection when a handler stops/restarts/unregisters/shuts down
  its actor through the real runtime;
- Java-callable factories and runtime methods.

Not ported yet: runtime directory/star URI authority, lifecycle wire dispatcher,
supervision, journal/replay, leases, capabilities, artifacts/verification,
adapter SDK, HTTP/process ports, remoting, distributed scheduling, or the CLI
execution cutover. The Common Lisp implementations remain permanent peer conformance targets. JVM parity adds another supported runtime; it does not authorize a Common Lisp cutover or retirement.

Toolchain pin:

- Kotlin 2.4.20
- Gradle 9.7.1
- JVM target/toolchain 17

Run:

    gradle -p runtime-jvm check
