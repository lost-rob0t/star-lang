# star-zmq — local transport foundation, not completed federation

Tracks star-lang#111 and lost-rob0t/starintel-server#193.

**Draft. No server plugin, Sento bridge, compiler lowering, host authorization,
CURVE/ZAP, seeding, durable delivery or infra deployment is implemented here.**
The binding deliberately rejects non-loopback TCP until the authenticated port
exists. An IPC path is not authentication: callers must place sockets inside a
private runtime directory with appropriate permissions.

## What this slice implements

- Common Lisp `star-zmq` ASDF system, using CFFI against the stable libzmq C ABI.
  One managed context per Lisp process, checked socket owner thread, bounded
  ROUTER/DEALER frames, finite timeout/HWM, mandatory routing, explicit cleanup.
- Nim single-threaded local DEALER binding and a one-shot external echo peer.
  The peer is a byte-level interoperability fixture, not an alternate StarLang
  runtime or a completed supervised actor. Compile it with `--threads:off`.
- Python local DEALER binding using PyZMQ 27 and the same framing rules.
- Native ASDF tests, a Lisp-launched Nim process round trip, Python transport
  tests, and a standalone pinned Nix flake. Linux x86_64/aarch64 outputs are
  declared; no Windows, macOS, Android or other native build has been verified.

The standalone flake is intentionally optional. Root StarLang packaging and
actor/compiler/runtime ownership are unchanged. This does not move any semantics
from prototype/ or replace star-actor-protocol, star-mailbox, starlang-runtime,
star-sento-compat, or the existing canonical JSON authority.

## Encoding decision and framing

Use existing StarLang version-1 lifecycle envelopes as lowerCamelCase **UTF-8
JSON**. The message contract is owned by `star-actor-protocol`, not this binding.
The future adapter must use the existing canonical serializer/generated schema
bindings, validate types and tenant/capability permissions, then dispatch.
Exact decimal strings remain strings. Do not stringify arbitrary exact integers
or invent tagged representations outside their declared schema. Do not hash
arbitrary `json.dumps` output as if it were the canonical signature encoding.

Transport frames are byte vectors/strings and intentionally do not deserialize:

```
DEALER sends:   [validated-envelope-utf8]
ROUTER sees:   [routing-id, validated-envelope-utf8]
ROUTER sends:  [routing-id, validated-envelope-utf8]
DEALER sees:   [validated-envelope-utf8]
```

There is no REQ/REP empty delimiter. Exactly one application frame is allowed.
Routing IDs are opaque, 1..255 bytes; they are not hostnames, actor identities,
tenants, authentication, or permission grants. A direct peer uses one DEALER per
peer and a ROUTER listener; a central broker is not a protocol requirement.
Connecting one addressed DEALER to multiple peers is forbidden in this binding
because libzmq would round-robin messages without understanding actor targets.

Default payload bound: 1 MiB. CL/Python permit an explicit 1..16 MiB bound; Nim's
first fixture is fixed at 1 MiB. The ROUTER identity frame has a separate 255-byte
bound. Native receive checks the actual returned length before copying. Extra
parts, truncated frames and partial multipart failures close the socket; they
are not drained in an unbounded loop or silently joined to another message.

A successful send means **queued to libzmq**, not received, authorized, admitted
to an actor mailbox, journaled, executed or committed. Timeouts do not prove an
effect did not run. No automatic retry or exactly-once claim is made. The eventual
adapter must preserve the existing lifecycle acknowledgments, correlation,
deadlines, idempotency, cancellation and generation fencing.

## Build and test

From repository root:

```sh
nix build ./star-zmq#star-zmq-peer
nix build ./star-zmq#star-zmq-cl ./star-zmq#star-zmq-nim ./star-zmq#star-zmq-python
nix flake check ./star-zmq -L
```

`star-zmq-cl` and `star-zmq-nim` are source-library packages, not compiled runtime
images. `checks.native-interop` compiles Nim and executes the real CFFI path with
a Lisp-launched child. It is separate from Python framing evidence.

Without Nix, install libzmq, SBCL, CFFI, Bordeaux Threads, Nim and PyZMQ 27:

```sh
nim c --threads:off --out:/tmp/star-zmq-peer star-zmq/nim/peer.nim
STAR_ZMQ_PEER=/tmp/star-zmq-peer sbcl --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:load-asd (truename "star-zmq/star-zmq.asd"))' \
  --eval '(asdf:test-system "star-zmq")'
python -m unittest discover -s star-zmq/tests -p 'test_*.py' -v
```

Set `STAR_ZMQ_LIBRARY` for the Lisp libzmq shared-library path when discovery is
not available; Nim supports `-d:StarZmqLibrary=/absolute/library/path` at compile
time. No credentials are passed in argv or copied into this source tree.

## Verification status at authoring

Python client: 12 real libzmq tests passed locally, including binary/UTF-8 byte
preservation, empty payload, two explicit identities, unknown routing, loopback
TCP, wrong-thread rejection, timeouts, oversized send/receive and extra parts.

**Not run here:** SBCL/CFFI, Nim compilation/execution, Nix evaluation/build/check,
full StarLang gates, real actor semantics, or server/federation/infra integration.
The editor environment does not have SBCL, Nim or Nix. A syntax balance check is
not Lisp compilation. This PR must remain draft until native checks and review
are complete. Server AGENTS.md also requires independent issue voters before
production server mutation; none are claimed by this transport slice.

## Remaining integration contract

The complete server request is tracked in server#193. It needs a Sento-compatible
owner loop and registered StarLang port; Lisp plugin lifecycle and supervised Nim
actor; CURVE+ZAP key-to-authority authentication and revocation; default-deny
read/write host lists intersected with tenant/dataset/key quotas; bounded seeds
that discover peers without promoting trust; provenance and replay/checkpoint
integration; and private biz init plus infra wiring. No firewall is opened and
no service is enabled by this package.

## References

- https://libzmq.readthedocs.io/en/latest/zmq_socket.html
- https://libzmq.readthedocs.io/en/latest/zmq_recv.html
- https://libzmq.readthedocs.io/en/latest/zmq_setsockopt.html
- https://nim-lang.org/docs/manual.html#foreign-function-interface
- ../star-actor-protocol/src/message-lifecycle.lisp
- ../star-actor-protocol/src/portable-wire.lisp
