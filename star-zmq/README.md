# star-zmq — local transport and external actor sessions

Tracks star-lang#111, draft PR #112, and lost-rob0t/starintel-server#193.

**Draft integration. No server federation plugin, Sento mailbox bridge, compiler
lowering, host authorization, CURVE/ZAP, seeding, durable delivery or infra
activation is implemented here.** Remote TCP remains deliberately rejected.
IPC callers must use an owned private runtime directory. A routing identity or
claimed actor name is not authentication.

## Implemented layers

| Layer | Ownership and behavior |
| --- | --- |
| `star-zmq` | CFFI binding to libzmq's C API, one host-owned context, checked socket-owner threads, bounded ROUTER/DEALER frames, finite I/O/HWM, mandatory routing, polling and explicit cleanup. |
| `star-zmq-actors` | Strict lifecycle-envelope codec and single-owner external process sessions. Protocol validation and canonical encoding delegate to existing StarLang authorities. Child lifecycle delegates to `star-process-port`. |
| Nim library | Single-threaded local DEALER binding, with bounded optional linger; compile with `--threads:off`. |
| `star-zmq-actor` | Persistent example executable supporting readiness, echo, structured unsupported-message errors and orderly stop. Not an alternate StarLang runtime or production supervisor. |
| Python library | Local PyZMQ byte transport with the same framing/ownership limits. No separate Python actor runtime or schema authority. |

The one-shot `star-zmq-peer` remains a byte-interoperability fixture. The new
persistent executable is separate. Existing StarLang/Sento mailboxes, registry,
journal, supervision policy and compiler ownership are unchanged. This optional
package does not move semantics out of or add authority to `prototype/`.

## Encoding and framing

Use existing version-1 lifecycle envelopes as lowerCamelCase **UTF-8 JSON**.
`star-actor-protocol` owns message validation and `star-canonical-json` owns
serialization. The byte binding itself does not deserialize. The optional
session codec validates before sending or accepting an envelope.

```
DEALER sends:  [envelope-utf8]
ROUTER sees:  [routing-id, envelope-utf8]
ROUTER sends: [routing-id, envelope-utf8]
DEALER sees:  [envelope-utf8]
```

No REQ/REP empty delimiter is present. Routing IDs are opaque 1..255-byte values,
not permission grants. Exactly one application frame is allowed. The local
session codec bounds payloads to 1 MiB, JSON nesting to 32 and value count to
16,384. It rejects duplicate keys (including escaped equivalents), invalid UTF-8,
trailing input, malformed numbers, unknown envelope fields and lossy conversion
of portable payload values. Peer-controlled strings are never interned as Lisp
symbols. The canonical serializer remains the final value authority; do not use
arbitrary `json.dumps` output as signature material.

A DEALER has one explicit endpoint, avoiding address-blind round-robin across
multiple peers. This is not a cross-host P2P service. IPC and literal loopback TCP
are allowed; `inproc` is available only at the byte layer, not for child sessions.
Extra parts, truncated frames and partial multipart failures close the socket.

## Managed external sessions

`open-peer` binds the ROUTER, launches the supplied executable without a shell,
and requires a readiness envelope whose route, actor and supervisor-supplied
generation match. It drains both child output pipes using fixed buffers without
retaining potentially sensitive output. One request is in flight per session.
`peer-request` checks reply actor, sender, correlation, causation, dataset and
message type. Wrong-thread callers are rejected without taking ownership.

A successful byte send means **queued**, not admitted, journaled or executed.
Timeout, crash, malformed reply or stale route closes the session. Execution
outcome can be unknown. Commands are never automatically replayed; the existing
journal/idempotency authority must decide whether a subsequent attempt is safe.
Socket polling tolerates interrupted system calls without resetting the overall
monotonic timeout budget. `close-peer` reuses process-port termination/reaping and
bounds output-drainer cleanup.

The example handles `star.zmq/echo@1` with `{ "text": "..." }` and
`star.zmq/stop@1` with `{}`. Readiness is `star.zmq/ready@1` with an integer
`generation`. It has a 60-second idle receive limit and a 100,000-request lifetime
bound. These are example limits, not a configurable production restart policy.
Lifecycle `deadline` fields are explicitly rejected before sending because this
example does not implement deadline execution semantics. Transport `timeout-ms`
is supported. Cancellation, durable acknowledgment and automatic restart are
not claimed.

## Lisp usage

Load `star-zmq-actors` through ASDF with the sibling `star-actor-protocol`,
`star-canonical-json` and `star-process-port` systems available. This example
assumes `executable` is the absolute path to the compiled Nim actor and `endpoint`
is an IPC endpoint in an owned private directory:

```lisp
(let* ((manifest '(:messages
                  ((:name "star.zmq/ready@1"
                    :fields ((:name "generation" :type "integer" :required t)))
                   (:name "star.zmq/echo@1"
                    :fields ((:name "text" :type "string" :required t))))))
       (context (star-zmq:make-context))
       (peer nil))
  (unwind-protect
       (progn
         (setf peer (star-zmq-actors:open-peer
                     context executable endpoint "example" "nim.echo"
                     manifest :generation 1 :timeout-ms 5000))
         (star-zmq-actors:peer-request
          peer
          (staractorprotocol:make-command-envelope
           :message-id "example/1" :message-type "star.zmq/echo@1"
           :actor "nim.echo" :sender "caller" :reply-to "caller"
           :correlation-id "example/1" :idempotency-key "example/1"
           :payload '(("text" . "hello")))))
    (when peer (star-zmq-actors:close-peer peer))
    (star-zmq:close-context context)))
```

An embedding host must reuse its one context and call each session from its
owner thread. Do not call these synchronous functions from arbitrary pooled
Sento callbacks. The real owner-loop/mailbox integration is still required.

## Build outputs and checks

From the repository root:

```sh
nix build ./star-zmq#star-zmq-actor ./star-zmq#star-zmq-peer
nix build ./star-zmq#star-zmq-cl ./star-zmq#star-zmq-nim ./star-zmq#star-zmq-python
nix flake check ./star-zmq --no-update-lock-file --print-build-logs
```

`apps.actor` runs the example with arguments `endpoint identity actor generation`.
`star-zmq-cl` and `star-zmq-nim` package source libraries, not runtime images.
The optional CL session system's sibling StarLang dependencies must be supplied
by the embedding repository; they are not copied into this standalone flake.

The flake checks actual CL/CFFI-to-Nim byte interoperability, the Nim actor's
IPC/TCP behavior and rejection paths, and the Python transport/package. The
complete CL session suite additionally runs in GitHub's native job with the
sibling systems, followed by their protocol/canonical-JSON/process-port suites.
The standalone flake does not substitute for that gate or the root StarLang
checks. Linux x86_64 and aarch64 outputs are declared; this pass verified x86_64
only. No Windows, macOS or Android native-build claim is made.

Native session test entrypoint (dependencies as installed in the workflow):

```sh
nim c --threads:off --out:/tmp/star-zmq-actor star-zmq/nim/actor.nim
export STAR_ZMQ_ACTOR=/tmp/star-zmq-actor
export STAR_ZMQ_FAULT_PEER="$PWD/star-zmq/tests/adversarial_peer.py"
chmod +x "$STAR_ZMQ_FAULT_PEER"
python star-zmq/tests/actor_conformance.py
sbcl --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:initialize-source-registry `(:source-registry (:tree ,(uiop:getcwd)) :inherit-configuration))' \
  --eval '(asdf:test-system "star-zmq-actors")'
```

Set `STAR_ZMQ_LIBRARY` for Lisp shared-library discovery when needed. Nim accepts
`-d:StarZmqLibrary=/absolute/library/path` at compilation. Missing native test
executables fail the gate rather than silently skipping execution.

## Verification and merge limits

At commit `229ff08f072e3c70c119faaf2bd7af0e8fe995e9`, both jobs of workflow run
35165580045 passed: native CL/CFFI and Nim compilation; persistent CL/Nim session
and real subprocess fault tests; independent Nim IPC/TCP conformance; surrounding
protocol, canonical JSON and process-port tests; Python framing; standalone locked
Nix checks and named package builds. Later changes require their own head checks.

The real-process suite covers missing readiness, stale generations, wrong routes,
wrong correlation, crashed/hung workers, malformed replies, and output flooding
on both pipes. These are transport/session checks, **not real Sento mailbox or
compiled StarLang end-to-end evidence**. No independent server preflight voters
are claimed. The requested integration remains incomplete and the PR stays draft.

Remaining: real Sento owner-loop integration and compiler/runtime port lowering;
Lisp federation plugin lifecycle; authenticated CURVE/ZAP identities and
revocation; host read/write policies intersected with existing tenant/dataset/key
quotas; bounded discovery without automatic trust promotion; journal/checkpoint
and provenance integration; canonical private biz configuration and infra wiring.
No firewall is opened, service enabled, configuration migrated, or deployment
performed by this package.

## References

- https://libzmq.readthedocs.io/en/latest/zmq_poll.html
- https://libzmq.readthedocs.io/en/latest/zmq_socket.html
- https://libzmq.readthedocs.io/en/latest/zmq_recv.html
- https://nim-lang.org/docs/manual.html#foreign-function-interface
- ../star-actor-protocol/src/message-lifecycle.lisp
- ../star-canonical-json/src/starlang-wire-json.lisp
- ../star-process-port/src/process.lisp
