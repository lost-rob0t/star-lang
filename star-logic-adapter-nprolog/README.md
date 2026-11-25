# star-logic-adapter-nprolog

Final Common Lisp ownership for the N-Prolog worker boundary.

This slice implements only worker ownership and process trust for the
`n-prolog` logic backend kind: exact executable identity, plain-REPL process
launch, a bounded startup-banner handshake, one canary exchange, health, and
orderly shutdown/reaping. It deliberately does **not** implement query
operations, fact mutation, portable value transport, proofs, cancellation
escalation, or worker pooling/reset.

## Engine identity and provenance

N-Prolog here means `sasagawa888/nprolog` exclusively (an ARITY/PROLOG
compatible interpreter/compiler; modified BSD). An unrelated historical
system shares the name; the upstream is recorded in descriptor metadata
(`:engine-upstream`).

`make-nprolog-backend` requires an explicit executable path. It never
discovers `npl` through ambient `PATH`. The path is resolved to its exact
file, the version is obtained by launching that exact executable with `-v`,
and `backendBuildId` is the SHA-256 digest of the resolved executable bytes.
Under Nix the exact store executable is also retained in descriptor
metadata.

Before every session open, the adapter rechecks path, version pair, and
executable digest. Any mismatch fails closed before a worker is spawned.

## Process boundary

The editable N-Prolog REPL is an ncurses line editor; only `-r` provides the
plain stdin/stdout REPL loop. Workers therefore launch with exactly
`("-r")` — no `-c`/`-s` startup files, no ambient configuration. Startup
opens with the bounded `N-Prolog Ver X.Y [..M cells]` banner line, which
must match the backend's `-v` version pair exactly. One canary goal
(`true.`) must be answered with a standalone `yes` verdict before a session
is open. Observed N-Prolog 5.20 output includes ANSI reset sequences even in
plain REPL mode; bounded reads strip ANSI escapes before matching.

Shutdown writes `halt.` and requires exit status 0 within the bounded wait;
otherwise the worker is killed, reaped, and the shutdown fails.

## Descriptor honesty

Like the SWI adapter foundation, semantic profiles and capabilities are
empty: lifecycle/build conformance is not semantic query conformance. The
backend stays out of `auto` selection until later slices prove actual
query semantics. The adapter also publishes no trusted package identity:
`open-logic-session` rejects any `package-id`/`package-digest` expectation.

## Deliberate non-goals (this slice)

- no `solve`/`solutions`/`exists?`/`assert!`/`retract!`/`explain` operations
- no portable-value encoding or wire protocol (a StarLang-owned line
  protocol is the next slice, mirroring the MQI slice's trust posture)
- no tabling, constraints, proofs, cancellation escalation, pooling/reset

## Tests

- `star-logic-adapter-nprolog-tests` — pure and fake-boundary fiveam tests.
- `star-logic-adapter-nprolog-integration-tests` — real worker tests against
  the Nix-pinned engine; they require `STARLANG_NPROLOG_EXECUTABLE` in the
  environment and fail loudly when it is absent.
