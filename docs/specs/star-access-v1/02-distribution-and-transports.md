# STAR-ACCESS-002 — distribution, durability and transports

Status and dependencies: [specification index](README.md).
This document implements no broker, database or consensus algorithm. It states
what those implementations must prove to advertise the access profile.

## 1. Runtime actor topology

The server hosts bounded actors for ingress, routing/membership, partition access,
query coordination, Target control, durable outcome reconciliation and outbox
publication. Native server actors use the existing Sento/runtime boundary rather
than an ad hoc thread pretending to be an actor. Other language implementations
must prove semantic equivalence, not replace the native actor authority.

```text
Authenticated ingress: RabbitMQ / StarRouter / existing HTTP
                         |
            existing Actor2Actor lifecycle
                         |
           access application-service actor
               /                      \
     document/query path           Target-control path
             |                         |
    partition access actor       existing Target runtime
             |                         |
    trusted DB operation         schedule / lease / fence
             \                         /
              durable commit + outcome + outbox
                              |
                    bounded outbox publishers
```

Server PR #295 is the backend-neutral DB foundation. Access calls enter its trusted
named-operation registry and authorization path. The first implementation must
preserve `database:read`, `database:write`, `database:transaction`,
`database:subscribe`, `database:admin` and their actual database/dataset/tenant
scope checks. Target authorization is resolved by the existing Target runtime;
these DB permissions do not implicitly grant Target execution rights.

A mailbox or Rabbit competing-consumer queue does not own storage. Distribution
is a routing/application concern over the same logical persistence contract.

## 2. Membership and partition authority

A runtime registration records node/component identity, actor incarnation,
advertised profile/operation versions, logical scope, partition assignment,
readiness/pressure and expiry. Heartbeats and pressure are hints. A heartbeat
failure alone MUST NOT authorize another writer.

An authoritative partition assignment has a monotonic owner epoch and an explicit
owner lease or equivalent authority proof. Membership updates, owner promotion
and fencing require a coordinated authority mechanism with a documented failure
model. The partition owner epoch is distinct from node incarnation, document
revision, Target schedule generation and Target execution fencing token.

The selected backend's **commit boundary** must reject a superseded owner. A
check against a registry followed by an unfenced DB write is insufficient because
ownership can change between those steps. The implementation must demonstrate a
linearizable guard at the authoritative write path or equivalent fencing of the
old writer before promotion. All write access to that partition must obey it.

If a partition's authority cannot be established during a network split, writes
fail `unavailable`; the service does not prefer availability over split-brain
safety. Read-only replicas may serve only explicitly permitted consistency modes.
Independent writable CouchDB replicas with later conflict resolution do not
satisfy this authoritative-write requirement merely because each uses `_rev`.

Owner transition is: prevent new admissions on the old epoch; establish its write
fence; recover the durable mutation/outcome/outbox state; install the new epoch;
then publish readiness. Mutations accepted before the handoff remain resolvable.
Idempotency outcomes, unprocessed inbox entries, cursor/view state where retained,
and pending event identities must not disappear with the old process.

Before horizontal-write conformance, an adapter lacking this fencing proof may
advertise a single-authority deployment with no automatic failover. It MUST NOT
claim safe multi-owner failover. A many-node ingress/read topology is not evidence
that write-authority failover is implemented.

Requests route from logical scope through a frozen partition map revision.
Untrusted route hints are advisory only. A stale route may be refreshed before
admission. A `not-owner` response is not permission to replay a possibly committed
mutation with a new key. Handoffs preserve the original mutation identity.

## 3. Durable commit, outbox and recovery

A committed mutation means the authoritative state change, idempotency outcome and
event/dispatch intent have a single recoverable durability boundary. The adapter
must use its native transaction, one atomic aggregate record, or the existing
runtime's documented journal/recovery protocol. Unprotected sequential writes to
three unrelated records are forbidden.

For CouchDB, storage remains ordinary JSON. A per-document compare-and-set is not
a multi-document transaction, and bulk API success is not all-or-nothing commit.
A CouchDB adapter must demonstrate crash-safe co-location or journal recovery for
outcome and outbox intent without introducing a second public document model.
The profile does not require or permit Star source code to be stored as database
query/index instructions.

A successful `MutationReceipt` is sent only after authoritative commit. A durable
inbox acknowledgement may precede execution only when explicitly represented as
**accepted**, not committed/completed. After durable inbox acceptance the service
owns retry/recovery under the original deadline and authority; mailbox survival is
not the recovery strategy.

Required crash points:

| Crash interval | Recovery obligation |
| --- | --- |
| Before admission | No accepted mutation; bounded safe retry |
| After durable admission, before commit | Recover the same intent; no duplicate execution identity |
| During uncertain commit | Reconcile journal/authoritative state; do not assume rollback |
| After commit, before reply | Replay the original durable outcome |
| After commit, before event publication | Publish from the surviving outbox |
| After publication, before marking published | Republish the same event identity; consumers deduplicate |
| After outcome reply, before broker ACK | Redelivery replays outcome without another mutation |
| During ownership transfer | New owner recovers intent/outcome/outbox under a newer fence |

Event IDs and causation are allocated once per authoritative change. Outbox rows
become eligible through committed state, not a worker's unverified completion
message. A separately authorized publisher may deliver an already-committed event
after the original execution lease expires: it is fulfilling committed intent,
not granting the stale worker a new effect. Publisher claims are themselves
bounded/fenced so duplicate delivery cannot become duplicate state mutation.

No exactly-once claim is made for arbitrary external effects. An effect port must
provide fencing, stable idempotency or an explicit uncertainty/reconciliation
path. Retrying an unfenceable external action is not made safe by a local outbox.

## 4. RabbitMQ binding

RabbitMQ is the first distributed command transport. AMQP 0-9-1 broker details
are binding configuration, not fields of `star.access/1`.

### Topology and encoding

Command request/reply traffic and committed document/Target events use separate
logical channels/exchanges with scoped bindings. Deployments choose names and
queue policies. Authoritative partition routing precedes command dispatch;
competing consumers may share work only when they enter the same authority guard.

The message body is the canonical lifecycle serialization and typed domain
payload. AMQP `message_id` and `correlation_id` mirror generated lifecycle values
when representable. Any header/body discrepancy is rejected, not resolved by
trusting whichever arrived last. Binding-local metadata may carry version,
remaining delivery lifetime and trace information, but cannot redefine scope,
authority or the accepted deadline.

Durable command/event lanes use durable queues, persistent messages and publisher
confirms. Requests use routability detection such as `mandatory` publication.
Queue replication/HA policy is explicitly configured and tested. A publisher
confirm means broker acceptance, **not application commit**; a consumer ACK
settles a broker delivery, not storage ownership or a Target lease.

A reply destination is assigned/validated against the authenticated session or
service identity and broker ACLs. Arbitrary caller-controlled `reply_to` cannot be
used to exfiltrate another tenant's result. Ephemeral replies are allowed only
when clients can recover durable outcomes. Direct Reply-to, when used, cannot be
the only durable outcome channel.

### Authentication and settlement

Broker login authenticates a connection; it does not automatically authenticate
the business principal named in a JSON payload. A trusted ingress validates the
caller and provides a scoped, expiring authorization-context reference bound to
request identity and intended audience. The owner validates that reference and
current policy before effects. Bearer tokens are not copied into durable logs.
A context reference needed for recovery cannot depend solely on process memory.

Consumers use manual acknowledgement and bounded prefetch. A delivery is ACKed
only after a durable outcome or durable recoverable inbox acceptance. Definite
validation/authorization rejection is settled without infinite requeue; auditing
and rejection storage are bounded. Retryable pre-admission failures use bounded
backoff/dead-letter policy, not a hot `nack(requeue=true)` loop.

A channel failure after potential admission produces an unknown observation.
Redelivery reuses the original idempotency key and preserves earlier admission
state. The broker's `redelivered` flag is a hint, not a deduplication database.
Broker delivery tags never become public cursors or fencing tokens.

Broker TTL is an optimization. The application checks deadlines again at admission
and every authoritative side-effect boundary. Expired messages cannot extend a
Target's execution deadline or cause an unrecorded disappearance of accepted work.
Poison messages and exhausted delivery attempts enter a bounded quarantined lane
with redacted diagnostics; they are not marked successful.

## 5. StarRouter and future ZeroMQ binding

Preserve the existing STAR-SERVER-040 operation/result architecture and
STAR-SERVER-041 authority routing. Do not create an access-specific replacement
RPC envelope, URI scheme or transport-specific target scheduler.

StarRouter resolves a logical Star URI to a capability-compatible service and
ActorRef incarnation. It carries the existing message identity, operation,
idempotency, deadline, correlation/causation and result algebra unchanged. The
physical endpoint, ZeroMQ routing identity and local cancellation handle remain
adapter state.

Route caching is bounded and generation-aware. Every hop has a finite hop budget
and monotonic remaining timeout; forwarding cannot extend the original deadline.
Loops, unavailable routes and stale ActorRefs produce typed errors. Re-resolution
before dispatch is allowed. Failover after uncertain mutation admission requires
outcome reconciliation or replay under the same key, not speculative delivery to
multiple independent writers.

One-way network send completion is not durable acceptance. When a low-latency
transport has no durable queue, the destination still uses the server's durable
inbox/commit/outcome path. A socket disconnect neither rolls back a committed
mutation nor cancels a scheduled Target. Stream cancellation is separate from
Target execution cancellation.

A future binding is eligible for advertisement only after it passes the same
semantic fixtures as local and Rabbit paths. Do not advertise hypothetical ZeroMQ
or P2P support merely because the architecture permits it.

## 6. Existing HTTP/SSE remoting

Existing HTTP document remoting remains supported; this spec does not replace its
public route ownership. HTTP routes map to the same access application service.
Conditional requests map to opaque revision preconditions without exposing raw
backend revisions. HTTP idempotency handling enters the same durable outcome
store as Rabbit and StarRouter. Switching transport cannot create a fresh scope.

SSE is a presentation of the canonical bounded stream. SSE reconnect IDs map to
scoped checkpoints, not CouchDB sequences. An HTTP disconnect is an observation
failure, not evidence of transaction rollback. Authentication, rate limits and
cancellation preserve identical application semantics across bindings.

## 7. Capability advertisement and observability

Registration must distinguish configured, ready, degraded and unsupported
capabilities. Backend health is not a proof of consistency, transaction support
or write fencing. Generated capabilities describe only gates actually passed.

Every deployment fixes finite admission concurrency, mailbox size, batch size,
query scan/row/byte budget, fan-out, stream credit, broker prefetch, retry count,
hop count and retention. Configurations are validated at startup. Exhaustion is
typed and fail-closed; no silently unbounded fallback.

Metrics distinguish accepted, committed, outcome-unknown, duplicate-replayed,
precondition-rejected, stale-fence, partial-query, cursor-expired and history-lost.
They include outbox lag and recovery backlog. Sensitive identifiers and arbitrary
query values belong in authorized trace records, not unbounded metric labels.
Audit events preserve causation and policy decision references without secrets.

## 8. Source boundary

The broker distinction above follows RabbitMQ's primary documentation:
[Consumer Acknowledgements and Publisher Confirms](https://www.rabbitmq.com/docs/confirms).
The application durability, fencing and recovery requirements are Star access
design decisions, not guarantees supplied by RabbitMQ itself.
