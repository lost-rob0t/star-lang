# star-process-port

`star-process-port` is the final Common Lisp host boundary for external process
lifecycle. It owns OS process launch/stop/reap mechanics; it does **not** own
actor supervision policy, provider behavior, `.star` shell syntax, or portable
process objects.

## Exact command boundary

`launch-process` and `run-process` take an executable string and a proper list
of argv strings. The list is passed to `uiop:launch-program` as tokens; the port
does not build a shell command string or interpolate argv. A caller may choose
a shell as its executable, but that is an explicit caller decision.

`launch-process` is the low-level API for long-lived protocol adapters. It
returns separate stdin/stdout/stderr streams and the caller must eventually use
`wait-process` or `dispose-process`. Each launch has an immutable process-local
instance ID plus a caller-supplied non-negative generation. Generation is
metadata only: supervision/restart policy remains outside this port.

## Bounded one-shot lifecycle

`run-process` is the bounded one-shot API. It concurrently drains stdout and
stderr, retaining at most `stdout-limit` and `stderr-limit` characters while
discarding excess data so full child pipes cannot turn the retention limit into
a deadlock. Its result records whether each retained stream was truncated.

A relative `timeout` is treated as a monotonic deadline budget. A
`process-cancellation-token` can be cancelled from another thread. Deadline or
cancellation uses the same deterministic cleanup path: graceful termination,
bounded grace wait, urgent termination if needed, then reap before returning.
`process-result-outcome` is one of `:exited`, `:signaled`, `:timeout`, or
`:cancelled`; exit code and signal are retained when the host reports them.
`ensure-process-success` converts unsuccessful results into typed
`process-exit-error`, `process-timeout-error`, or `process-cancelled-error`
conditions.

After the owned root process is reaped, stdout/stderr collection receives one
shared `terminate-timeout` cleanup budget. A descendant outside this port's
ownership may inherit a pipe writer and therefore suppress EOF after the root
has exited. Such a descendant does not extend `run-process` indefinitely: any
capture thread still blocked when the shared cleanup budget expires is stopped,
the corresponding result stream is marked truncated, and the owned process
streams are closed. This is output-resource fencing only; it does not make the
port a process-tree supervisor or define descendant restart policy.

## Provenance and secrets

`process-provenance` / `process-result-provenance` contain only instance ID,
generation, and executable. They intentionally exclude argv, environment,
working directory, stdin/stdout/stderr, and host process objects. Launch and
lifecycle condition reports also avoid rendering argv or captured output.
Captured stdout/stderr remain explicit result data and should be treated by the
calling adapter according to that adapter's data-handling policy.

## Tests

```lisp
(asdf:test-system :star-process-port)
```

The test system uses a repository-local shell fixture through an explicitly
selected shell executable. Set `STARLANG_TEST_SHELL` when `/bin/sh` is not the
appropriate test shell. It also exercises inherited stdout/stderr descriptors:
a descendant may keep pipe writers open after the owned root exits, but normal
completion, timeout, and cancellation must still return without retaining live
capture threads.
