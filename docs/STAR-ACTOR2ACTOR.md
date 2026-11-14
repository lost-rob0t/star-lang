# Star Actor2Actor Protocol

Status: design for #150. Database-specific A2A integration is tracked by #149.

StarLang already has the pieces of an actor protocol in `star-actor-protocol`: canonical Star service URIs, ActorRef identity and generation, command/event/reply/ack/error/cancel lifecycle envelopes, correlation/causation identifiers, portable manifests, and payload validation.

This design makes that existing authority the canonical **Actor2Actor protocol** instead of introducing another envelope.

## Protocol identity

Semantic profile:

```text
star.actor2actor/1
```

The protocol is transport-neutral.

Bindings may include:

- in-process StarLang runtime;
- Sento;
- ZMQ;
- HTTP+JSON;
- upstream Agent2Agent (A2A);
- a future StarMesh/libp2p binding;
- runtime providers such as AWS Lambda.

## Addressing

Canonical actor addresses remain:

```text
star://domain:address:actor-name
```

Actor references additionally carry incarnation/generation information so an old reference cannot silently address a replacement actor.

## Message lifecycle

Do not replace the existing lifecycle envelope.

Canonical semantic kinds are built from the existing constructors:

- command;
- event;
- reply;
- ack;
- error;
- cancel.

Actor2Actor adds a transport-neutral task/stream view over that lifecycle.

Required identity:

- message id;
- correlation id;
- causation id;
- actor reference;
- sender reference;
- operation/task id;
- delivery attempt;
- deadline;
- idempotency scope;
- trace context.

Principal/tenant authority is attached by the authenticated runtime boundary. A caller-provided payload cannot grant itself authority.

## Core operations

### Describe

Return the portable actor manifest:

- accepted message types;
- produced message types;
- capabilities;
- protocol revision;
- runtime readiness;
- supported Actor2Actor transport bindings.

### Send

Deliver a command/event.

### Ask

Command plus typed reply/error terminal outcome.

### Status

Return current canonical task state without changing execution.

### Cancel

Use the existing Star cancel envelope. Cancellation cannot overwrite an already-established terminal state and a late completion cannot overwrite cancellation.

### Stream

Expose ordered typed events/results.

Requirements:

- monotonically ordered sequence within one stream;
- bounded buffering;
- explicit resume/checkpoint token;
- cancellation;
- deadline;
- terminal event;
- no unbounded producer when a consumer is slow.

## Terminal states

Canonical Star task states should cover at least:

```text
accepted
running
completed
failed
cancelled
rejected
deadlineExceeded
outcomeUnknown
```

First terminal state wins.

A transport adapter may map these to its native representation, but cannot change their meaning.

## Upstream A2A binding

Upstream Agent2Agent is a **binding** of Star Actor2Actor, not StarLang's internal authority.

Mapping:

| Star Actor2Actor | Upstream A2A |
| --- | --- |
| portable actor manifest | Agent Card |
| command / ask | message/send |
| task status | tasks/get |
| cancel envelope | tasks/cancel |
| stream | message/stream |
| typed result/artifact | Message / Artifact |
| Star terminal state | A2A task state/error mapping |

The binding must preserve functional behavior across supported A2A transports.

StarLang actor semantics are not allowed to depend on whether the peer uses JSON-RPC, REST, gRPC, SSE, local Sento, ZMQ, or a future P2P binding.

## Database actors

Database actors use the same protocol.

```text
remote actor
    |
 upstream A2A
    |
A2A binding
    |
Star Actor2Actor
    |
database actor
    |
database adapter
```

The remote actor sends a typed named operation plus bindings. It never sends a database credential or raw backend program.

## Runtime provider interaction

A provider may transport/execute an Actor2Actor invocation remotely while retaining the same actor semantics.

Example AWS Lambda:

```text
Star dispatcher
   |
Actor2Actor invocation
   |
Lambda provider
   |
StarLang custom runtime
   |
native actor
   |
reply/error
```

Provider retries and instance reuse do not change idempotency, state ownership, deadline, or terminal-state rules.

## Security invariants

- capability checks occur before mailbox/side effects;
- tenant identity is runtime authority;
- stale ActorRefs are rejected;
- external metadata cannot add capabilities;
- transport auth does not replace application authorization;
- deadlines are checked at admission **and completion**;
- late/stale delivery attempts cannot settle a newer attempt;
- cancellation/terminal outcomes cannot be overwritten;
- payloads are validated against the portable manifest;
- secrets never enter portable actor manifests.

## Testing

#150 requires equivalence tests:

1. native local dispatch;
2. remote Star Actor2Actor transport;
3. upstream A2A mapping.

For the same canonical request and authority, all three must produce semantically equivalent terminal states and typed results.
