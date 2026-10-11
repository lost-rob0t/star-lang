# Domain services and Actor2Actor integration slice

Status: local implementation candidate, not a released wire profile or broker-parity claim.
Base: `e9ec1d883627d186aafe0b3647bdc29baea03543`. Owners:
StarLang #150/#159 (Actor2Actor), #198 / draft PR #199 (access payloads),
StarIntel Server #315 / draft PR #295 (host and DB runtime), StarRouter #5 (transport).

## Existing authority and provenance

This slice reuses `star-actor-protocol` and the implementation from
`agentic15/w05-actor2actor` at `3f476ce`, correcting its terminal-unknown behavior
against draft access PR #199 at `b75fba66da3a9ffec3559c66b373475cf63991e3`.
It adds no schema release, independent envelope, Target type, database, lease store,
registry, queue or DSL. Actor manifests and `starlang-runtime/src/runtime-directory.lisp`
remain discovery authority. Existing dispatcher owns execution and idempotency state.

The existing lifecycle constructors retain `star-version=1`, kind, message-id,
message-type, actor, sender, correlation-id, causation-id, attempt, idempotency-key,
dataset, reply-to, sent-at, deadline and payload. `star.actor2actor/1` is a semantic
profile over them. `star.access/1` uses all existing `star.documents.*@1` and
`star.targets.*@1` identities, not a new CRUD enum. PR #199 owns payload shape;
this slice intentionally does not manufacture a JSON Schema or handwritten
per-language copies while the canonical generator work is incomplete.

Actor service URIs remain the existing `star://domain:address:actor-name` runtime
form. Resource URIs in the draft access spec (`star://authority/document/id`) are
separate; do not send one through the other's parser. ActorRef incarnation,
partition owner epoch, document revision and Target fence are distinct authorities.

## Executable APIs

`staractorprotocol:validate-domain-service-definition` checks:

- domain-id, bounded services, max-services and max-in-flight;
- every service belongs to that domain;
- unique logical service identity (no competing registrations).

`validate-actor-service-description` checks the directory projection:

- actor-ref: existing ActorRef with domain, node, logical path, generation,
  protocol revision and capability-set hash;
- profiles: unique bounded names including `star.actor2actor/1`;
- operations: exact versioned operation strings; capabilities: names, not grants;
- readiness: ready, draining or unavailable;
- max-in-flight and max-message-bytes: positive policy limits;
- delivery-classes: volatile and/or durable (advertisement requires separate proof);
- scope: optional logical database-id/dataset-id, never connection credentials.

Unknown/duplicate keys and malformed declarations fail closed.
`actor-service-enrollment-decision` returns register/refresh/replace or
unauthorized/expired/identity-mismatch/stale-generation/generation-conflict.
Same-generation refresh cannot change protocol revision or capability-set hash.
The directory owner must authenticate enrollment, validate the advertised manifest,
serialize compare-and-register, retain generation high-water marks across restart,
and authorize replacements. A missing in-memory entry does not prove a fresh identity.
No heartbeat or registration grants partition write authority.

`actor-service-admission-decision` checks authorization, lease observation,
readiness, operation, delivery class, size and capacity. It returns a decision;
it does not reserve capacity. The existing actor serializes admission/counter update
and releases credit on every terminal/error path. Global domain capacity must also
be enforced by the host. Discovery must be filtered by authenticated scope.

`validate-correlated-lifecycle-outcome` checks command kind and matching original
message-id/causation-id, correlation-id, actor and exact dataset before settlement.
`actor2actor-completion-decision` adds incarnation, attempt, first-terminal,
cancel-arbitration and completion-time deadline guards. Authenticated runtime
observations are arguments, not trusted JSON flags. This is not Target lease checking;
the existing Target runtime still checks its own lease/fence at effect commit.

## Lifecycle, uncertainty and retries

Reuse the original Actor2Actor task/stream projection and existing dispatcher.
Accepted -> running -> completed/failed/cancelled/rejected/deadline-exceeded.
First terminal wins. Cancellation request alone is not a cancelled task. A late
accepted acknowledgement cannot regress running. Explicit status arguments cannot
promote an accepted envelope to completed. Controls undergo payload validation.

`star.outcome-unknown` is an invocation observation. It leaves execution status
unchanged and remains reconcilable; later authoritative result can complete it.
Do not automatically retry a potentially committed mutation. Reconcile using the
original idempotency identity, with current authorization, durable outcome and the
same semantic request digest. Neither a local task object nor an ACK is a durable
idempotency record. The current dispatcher scope key alone lacks authenticated
principal/tenant/database scope; access adapters must use PR #199's scoped identity.

Clock authority must derive deadline-expired at admission and completion using the
existing canonical timestamp rules. Stream frames carry task/correlation/sequence;
the frame constructor is not proof of bounded buffering, ordering, resume retention
or backpressure. The bus/host adapter must enforce those at its real boundary.

## Queue and fanout semantics

Competing-consumer queues distribute work only after authoritative ownership is
resolved. A consumer queue does not own a partition. Fanout emits one stable event
identity to independently bounded subscription cursors. Redelivery preserves that
identity. At-least-once delivery requires consumer deduplication; no exactly-once
external effect claim is made. Slow subscribers cannot consume unbounded memory:
apply credit/size limits, explicit gap/expiry and bounded replay or rejection.

Durable mutation means recoverably coupled authoritative commit + outcome + outbox.
Durable inbox acceptance may precede execution but must be labeled accepted.
Commit receipt, publication acceptance and broker settlement are separate evidence.
A service without persistence/recovery proof advertises volatile only.

## RabbitMQ to ZeroMQ parity inventory

Code inspected: StarIntel Server local `a04b5b3b6295b95ef4db6b258656475a4e7b1281`,
`source/rabbit.lisp`, `source/consumers/{rabbit-settlement,retry-policy,owner-fixes}.lisp`,
`source/producers/producers.lisp`; requirements from current #315 and PR #199.
This is source inspection, not broker testing, and not proof the inspected local
server checkout is the current upstream default.

| Concern | Rabbit source/required behavior | ZeroMQ parity obligation |
|---|---|---|
| Persistence | durable exchange/queue declarations, delivery-mode 2 visible | durable inbox/outbox and restart recovery; socket buffers are not storage |
| Publish result | publisher confirms/routability required by access spec; not found in inspected source paths | explicit persisted publication receipt and no-route handling; send success insufficient |
| Settlement | manual ACK/NACK on receiving connection/channel | explicit correlated receipt with credit restoration and retry classification |
| Backpressure | bounded prefetch in consumer source | HWM plus application bounded admission, byte limits and explicit overload |
| Retry/DLQ | retry-policy/dead-letter source exists | bounded retry schedule/poison quarantine; no reconnect replay of unknown effects |
| Fanout | topic exchange and per-consumer bindings | independent subscriptions/checkpoints, gap reporting, bounded replay |
| Principal | broker login alone insufficient | authenticated ingress + scoped authority references; ZMQ routing identity not principal |
| Failover | neither queue nor heartbeat is storage ownership | fenced commit and recovered dedup/outbox before readiness |
| Replies | recoverable outcomes required despite lost reply queue | request/correlation matching, out-of-order multiplexing and durable reconciliation |

SC01/SR01 currently acknowledge transport without a canonical request correlation or
persistence proof. They cannot be presented as the full Actor2Actor binding. Do not
invent an EventType mapping or silently encode the new profile as document bytes.
A negotiated canonical lifecycle framing/generator and server transport adapter are
remaining implementation gates; direct local ASDF service calls can reuse this API.

## Star server integration requirements

Server hosts these definitions under its actual init/shutdown lifecycle, using its
existing Sento actor/registry and PR #295 trusted named DB-operation boundary.
No standalone-only success claim. Start in unavailable, verify adapters/policy,
register exact generation, publish readiness; on stop drain admissions, settle or
persist pending work, remove only the matching generation, then close resources.
Partial startup unwinds only resources it created. Reload/restart must fence old
completions. Do not advertise durable or write operations merely because declared.

Required host tests include real Sento ask/reply; duplicate startup; partial startup
failure; graceful drain and forced crash; stale unregister/late reply after restart;
unauthorized/wrong-tenant call before adapter effect; real commit/outcome/outbox crash
points. Server worker owns this integration; these pure protocol tests do not prove it.

## Evidence and outstanding gates

Executed locally with existing SBCL 2.2.9 (no installation):

- RED: unknown observation regression failed against original issue159 implementation.
- GREEN: `asdf:test-system :star-actor-protocol`, including Actor2Actor, domain/service,
  enrollment, bounded admission, correlation, completion and portable boundary suites.
- GREEN: `asdf:test-system :starlang-runtime`, including ownership, stale completion,
  wire dispatcher and failure settlement suites on the changed protocol dependency.

Not run here: real Rabbit/ZMQ sockets, live broker confirms, restart persistence,
Sento server integration, cross-language profile generation, JVM parity, full Nix.
Nix is absent. Existing full runtime tests passing do not mean new pure guards have
been wired into every adapter. No socket restriction bypass, publication or deploy.

Remaining conformance: simultaneous cancellation/completion at the real actor;
duplicate identity + changed digest; durable retry after each crash interval;
expired/stale enrollment under concurrent replacement; overload/HWM recovery;
out-of-order replies; stream gaps/resume; authorization revocation during recovery;
partition ownership change during commit; fanout slow-consumer isolation. These are
required real-boundary gates, not satisfied by inventory or pure helper tests.

## Shared wire extraction follow-on

A subsequent inspection found the existing lifecycle encoder/strict decoder in
`star-zmq/src/wire.lisp`. It is now extracted without duplicating semantics into
`star-actor-wire`, depending only on protocol, canonical JSON, Babel and Yason.
The old `star-zmq-actors:encode-envelope/decode-envelope/wire-error` symbols are
imports of the same shared definitions, preserving peer API compatibility.
No libzmq loading or socket creation is required to load/test the shared codec.

Thus the earlier missing-codec assessment is narrowed: the lifecycle codec exists;
production access payload manifest generation and full host transport execution
remain separate gates. There is no new JSON wrapper or protocol version.

Exact adapter API:

- `negotiate-actor2actor-profile(peer-profiles)` selects `star.actor2actor/1` or
  signals `unsupported-peer-protocol`. This uses advertised descriptor capability,
  not a new probe/handshake. A stale/unauthenticated advertisement is not authority.
- `encode-binding-message(binding, peer-profiles, manifest, envelope)` returns
  canonical UTF-8 body octets and binding-local headers. Binding is `:zmq` or
  `:rabbit`. ZMQ has one payload frame; ROUTER routing identity is a separate frame.
- `decode-binding-message(binding, peer-profiles, manifest, body, headers)` returns
  the existing lifecycle plist. Rabbit requires message-id, correlation-id,
  content-type=application/json and profile metadata to match the body/context.
  Header names here are adapter plist keys, not a second public envelope.

Rabbit adapter maps message-id/correlation-id/content-type to AMQP properties and
profile to its transport metadata. Other trusted AMQP properties (reply destination,
TTL, persistence, mandatory/confirm policy) stay in the broker adapter and cannot
change lifecycle identity. ZMQ passes bytes unchanged and cannot claim persisted
acceptance from `send`. Neither binding API sends, settles or retries anything.
The host uses authenticated generation-bound routes and bounded pending requests;
the authority callback decodes before dispatch and validates correlated results.

Six canonical lifecycle JSON fixtures are under `fixtures/actor2actor/lifecycle-v1`.
The fixture operation is test-only, not a handwritten document schema. Native
bindings consume bytes through an injected canonical authority encoder/decoder;
they must not recreate document or task semantics. SC01-only descriptors fail
before an effectful send, with no fallback to a fixed EventType.

Verification added: 74 actual codec/binding/fixture assertions, full canonical JSON,
protocol and surrounding runtime suites, ASDF load of the existing ZMQ actor system,
and its original codec-only tests all passed. No socket/peer/broker test was run.
The codec tests cover malformed/duplicate JSON, UTF-8, size/depth, forbidden field,
version/attempt errors, false/null loss, identical transport bytes, mismatched
Rabbit identities and explicit legacy-peer rejection. Nix gate wiring now includes
`star-actor-wire`, but Nix remains unavailable and was not executed.

Independent review follow-on: task and stream constructors now own snapshots of
caller identity strings and envelopes. Terminal results must match the task actor,
correlation and projected terminal status; mutation through the original inputs
cannot replace retained evidence. Outcome correlation also rejects a different
dataset. Invalid status names are selected from the existing closed set rather
than interned into the keyword package. These remain local boundary guards, not
authorization or persistence authorities.

## Exact document JSON across the lifecycle boundary

`star-actor-protocol` now owns `portable-json-number` with a bounded validated
JSON numeric lexeme. `make-portable-json-number` copies its input; snapshots copy
and revalidate tokens. The canonical writer emits these as JSON numbers, not
strings. The bounded wire parser uses Yason only for strings and never coerces
number tokens through binary floating point. Existing integer values remain
arbitrary-precision Lisp integers. Numeric token length is limited to 128 characters;
oversized values fail explicitly rather than round. Huge exponent magnitudes do
not allocate a power of ten or require a representable host float/Decimal.

Opaque JSON representation is explicit: nonempty objects are string-key alists,
empty objects use `+portable-json-empty-object+`, arrays are vectors (including
empty vectors), JSON false uses `+portable-json-false+`, and JSON null uses
`+portable-json-null+`. Omitted fields stay absent. Typed manifest booleans/lists
retain their established NIL/list representation; only opaque ANY/MAP values use
these distinctions. Reserved object keys remain data and cannot change prototypes.

`star-actor-wire:decode-json-value` and `encode-json-value` are the exact JSON
bridge. The server can pass `starintel:stringify-json` output through UTF-8 and
`decode-json-value`, or invert that path, without StarLang depending on star-cl.
These functions validate JSON/fidelity, not the StarIntel document schema; the
pinned generated document validator remains mandatory at the application boundary.
There is no authority-to-SDK dependency, alternate document schema or number stringification.

`decode-command-message(binding, profiles, manifest, bytes, headers)` adds one
shared command-only admission API. Foreign invocation adapters must use it before
sending; reply, event and control envelopes are rejected rather than dispatched
as commands. The general decoder remains available to receive valid outcomes.

The exact person fixture and generated lifecycle request/reply cover non-BMP text,
NUL, absent/null/false, empty arrays/objects, reserved keys, integers beyond int64,
long decimal tokens, negative zero and symbolic extreme exponents. The Python test
executes the real Lisp codec/snapshot in a subprocess, then checks the returned
document with the pinned authority versioned reader and semantic validator.
Malformed/duplicate input and non-command requests fail before encoding or dispatch.
The smoke CLI also supports actual-codec callbacks for Python/JS adapters; it does
not open sockets and its fixture manifest is not the production access-profile generator.

Exact-value review hardening: integer-form JSON `-0` also uses the owned numeric
token, preserving its sign through scalar, array, document, snapshot and Actor2Actor
frame paths. Optional typed booleans use the explicit false sentinel for present
false, NIL for present null, and no entry for absence. This is an additive portable
value representation: ordinary nonoptional boolean decoding still returns NIL for
false; optional consumers must not treat every non-NIL value as true. Both canonical
validation and encoding understand the explicit false value. Nested present-false,
present-null and missing-field cases are exercised against the actual codec.
