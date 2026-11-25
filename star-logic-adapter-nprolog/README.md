# star-logic-adapter-nprolog

Final Common Lisp ownership for the N-Prolog worker boundary.

This slice implements worker ownership and the trusted socket-bridge
transport for the `n-prolog` logic backend kind: exact executable and bridge
identity, plain-REPL process launch with the digest-pinned bridge file, a
bounded startup-banner handshake, one canary exchange, a lock-step request/
response wire over a loopback socket, health, and orderly shutdown/reaping.
It deliberately does **not** implement query operations, fact mutation,
portable value transport, proofs, cancellation escalation, or worker
pooling/reset — descriptor semantic profiles and capabilities stay empty
until later slices prove query semantics.

## Engine identity and provenance

N-Prolog here means `sasagawa888/nprolog` exclusively (an ARITY/PROLOG
compatible interpreter/compiler; modified BSD). An unrelated historical
system shares the name; the upstream is recorded in descriptor metadata
(`:engine-upstream`).

`make-nprolog-backend` requires an explicit executable path. It never
discovers `npl` through ambient `PATH`. The path is resolved to its exact
file, the version is obtained by launching that exact executable with `-v`,
and `backendBuildId` is the SHA-256 digest of the resolved executable bytes.
Before every session open, the adapter rechecks path, version pair, and both
digests (executable and bridge). Any mismatch fails closed before a worker
is spawned.

## Trusted bridge package identity

The bridge file `prolog/star-logic-bridge.pl` is the only in-engine code
this adapter owns. Its bytes are SHA-256 digest-pinned at backend
construction and revalidated before every launch; sessions may pin the
package explicitly (`star-logic-bridge` + digest) or open with the implicit
bridge identity, and any other expectation fails closed. The bridge binds a
loopback port chosen by the adapter (kernel-probed, with one retry for the
probe-to-bind race) and speaks `star-logic-nprolog-bridge-1`.

## Process and wire boundary

The editable N-Prolog REPL is an ncurses line editor; only `-r` provides the
plain stdin/stdout REPL loop. Workers therefore launch with exactly
`("-r" "-c" "./star-logic-bridge.pl")` in the bridge directory — the
`./`-prefixed consult name resolves against the child's working directory,
ahead of any `NPROLOG_HOME`/`HOME` fallback. Startup opens with the bounded
`N-Prolog Ver X.Y [..M cells]` banner line (matched against the backend's
`-v` version pair), one canary goal (`true.`), then the adapter drives the
bridge-start goal and completes the wire handshake (`hello` →
`star-logic-nprolog-bridge-1`).

Wire contract, verified against upstream `builtin.c`/`superset.c` (npl
5.20):

- `send_socket/2` writes exactly 256 bytes: payload, one NUL from `strcpy`,
  then uninitialized stack padding. Frames are NUL-terminated; receivers
  discard everything after the first NUL, and request payloads are bounded
  at 255 UTF-8 bytes (an over-long atom would overflow the upstream buffer,
  so the codec fails closed first).
- `recv_socket/2` is one raw `read(2)`, so coalesced frames would lose data:
  the protocol is strict lock-step — one request, one reply, no pipelining.
- `create_server_socket/2` binds `INADDR_ANY` and blocks in `accept()`, and
  never reports the bound port; the adapter probes a free loopback port,
  passes it into the bridge goal, and connects within a bounded deadline.
  The bind exposure window is the documented cost of this transport until
  upstream grows a loopback-only or port-reporting socket primitive.

Shutdown closes the bridge with a `quit` frame (which unblocks the engine's
bridge loop and returns it to the REPL), then writes `halt.` and requires
exit status 0 within the bounded wait; otherwise the worker is killed,
reaped, and the shutdown fails.

## Descriptor honesty

Lifecycle/build/transport conformance is not semantic query conformance.
Semantic profiles and capabilities stay empty: the backend stays out of
`auto` selection until later slices prove actual query semantics over this
bridge.

## Deliberate non-goals (this slice)

- no `solve`/`solutions`/`exists?`/`assert!`/`retract!`/`explain` operations
- no portable-value encoding: the wire carries protocol atoms only
- no `compile_file/1` accelerator, no `-n` network mode
  (roadmap: STARLANG-NPL-000)
- no tabling, constraints, proofs, cancellation escalation, pooling/reset

## Batch load validation

`nprolog-batch-validate` runs the exact pinned executable with `-s ./<name>`
in the file's parent directory. Upstream `-s` always exits 0 — even on
consult failures, syntax errors, and missing files — and a clean consult
prints nothing at all. Validation is therefore fail-closed on output:
valid iff exit status 0 and stdout is empty after ANSI stripping; any
diagnostic, nonzero exit, timeout, or output over the capture bound is
invalid, with the bounded ANSI-stripped diagnostic in the report. The
report carries the sha256 of the exact validated bytes. Files without a
dotted name are refused before launch (upstream consult appends `.pl` to
dot-free names, silently targeting a different file).

## Tests

- `star-logic-adapter-nprolog-tests` — pure and fake-boundary fiveam tests.
- `star-logic-adapter-nprolog-integration-tests` — real worker tests against
  the Nix-pinned engine; they require `STARLANG_NPROLOG_EXECUTABLE` in the
  environment and fail loudly when it is absent.
