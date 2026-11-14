# STAR-ACCESS-003 — upstream A2A binding

Status and pins: [specification index](README.md).

## 1. Upstream baseline and Star-specific requirements

The upstream baseline is A2A release `v1.0.1`; protocol negotiation is `1.0`.
The [upstream specification](https://a2a-protocol.org/latest/specification/)
defines server-created Task IDs, contextual grouping, structured parts, protocol
negotiation and optional send-message deduplication. Its
[task lifecycle](https://a2a-protocol.org/latest/topics/life-of-a-task/) and
[streaming guidance](https://a2a-protocol.org/latest/topics/streaming-and-async/)
are the primary references for task observation and asynchronous delivery.

Everything below is the Star binding's additional contract. It does not claim
that a generic A2A peer already implements Star persistence, cancellation,
scheduling, idempotency or fencing.

The gateway MUST use codecs generated from pinned upstream definitions rather
than hand-writing an approximate A2A schema. StarIntel payloads inside those
objects still use generated StarIntel 0.10.1 definitions. Neither version number
substitutes for the other. Outbound HTTP requests explicitly send
`A2A-Version: 1.0`; wire negotiation does not distinguish specification patch
releases. No automatic downgrade to 0.3 is permitted on this profile.

## 2. Discovery and extension negotiation

An exported actor/profile is advertised through an Agent Card generated from the
authorized portable manifest. Expose only ready operations and actual transport
interfaces. Public card data contains no credentials, private topology, tenant
records, internal broker routes or lease material. Private capabilities require
an authenticated discovery surface.

The proposed Star access extension identity is
`https://starintel.actor/protocols/star-access/v1`. This URI names the extension;
it is not a claim that a documentation endpoint is already deployed. Its
publication and generated declaration are implementation acceptance gates.

The extension carries `star.access/1` operation semantics, the StarIntel schema
lock reference, structured payloads, error detail mapping and declared retry/
remote-effect guarantees. It MUST be negotiated before a gateway advertises
full Star access equivalence. Unknown required extensions fail before execution.
An ordinary A2A agent without this extension may still be invoked through a
separately declared, reduced-guarantee integration; it MUST NOT be labeled a
conforming distributed document service.

The selected AgentInterface's routing tenant, where present, is a transport
selector. It does not set the authenticated Star tenant. Discovery endpoints,
redirects and retrieved resources pass URL/network policy and size/time limits;
Agent Card fields do not authorize arbitrary network access.

## 3. Binding record and identity

For stateful delegated work, the gateway durably records:

| Field | Authority / purpose |
| --- | --- |
| `bindingId` | Server-assigned binding identity |
| `localTenantId`, `principalBinding` | Trusted Star authorization boundary |
| `targetId`, `scheduleId` | Existing durable runtime identities |
| `executionId`, `executionGeneration`, `attemptId` | Concrete occurrence/attempt selected by Star runtime |
| `bindingGeneration` | Monotonic runtime-owned remote association version |
| `peerIdentity`, `peerInterface`, `protocolVersion` | Authenticated/validated remote association |
| `requestMessageId` | Stable outbound initiation identity |
| `remoteTaskId?` | Peer-issued locator, absent until observed/created |
| `remoteContextId?` | Opaque correlation only |
| `lastObservedState`, `reconciliationState` | Observation metadata, not authority to change execution |
| `artifactCheckpoints` | Bounded, version-aware retrieval state |
| `remoteEffectSafety` | Per-operation verified integration guarantee |

This is a runtime binding record, not a new canonical StarIntel document type.
Its persistence uses the existing runtime's private state facilities. Public
results expose only authorized projections. Lease credentials are not included
in public Agent Cards, metadata or artifacts.

Task lookup keys include tenant, authenticated peer and binding identity; remote
Task IDs are not assumed globally unique. A2A `contextId`, `taskId`, metadata or
referenceTaskIds MUST NOT choose a local lease, schedule, execution generation,
principal or capability. A matching-looking ID from another tenant or peer is
not the same authority. Context mismatches fail without leaking task existence.

The association is durably created before a remote effect-capable send. Its
outbound message identity survives process restart. At most one current binding
per execution/delegation slot may settle the local result. An old binding remains
available for audit/reconciliation but cannot settle its replacement.

## 4. Operation projections

| Star operation family | A2A projection required by this binding |
| --- | --- |
| Describe/discover | Authorized Agent Card metadata and extension declaration |
| Immediate document command/query | Structured request part containing the canonical operation identity and payload; typed structured result |
| Target schedule submission/reschedule | Structured control invocation and durable acceptance receipt, not an infinite recurring A2A Task |
| Concrete delegated Target execution | One current A2A Task association for that execution/delegation slot |
| Execution status | Get Task observation reconciled through the binding and Star runtime |
| Execution cancellation | Cancel Task request plus local durable cancellation arbitration |
| Execution observation | Task subscription/stream or authorized push notifications |
| Execution output | Artifact containing typed result data or authorized immutable document references |

A schedule may have many occurrences. The gateway MUST NOT reuse one completed
A2A Task as the mutable state of every future occurrence. A future schedule
acceptance may return a structured Message receipt without manufacturing an
execution or a remote Task. Task creation happens when concrete work exists.

Document commands do not become scheduler Targets merely because A2A transports
them. A peer may use an A2A Task for its own processing; the gateway records that
as an invocation association, not a second Star scheduling authority.

The binding uses the upstream codec's real Part/Message/Artifact fields and enum
values. Do not copy 0.3 `kind` discriminators or old method spellings into a 1.0
codec. Invocation and result examples used by conformance tests must validate
against the actual pinned upstream schema, not this prose's abbreviated notation.

## 5. State projection and arbitration

The following is the **Star mapping**, not a new upstream state machine:

| Authoritative Star execution observation | Exported A2A state |
| --- | --- |
| Accepted concrete occurrence, awaiting execution | `TASK_STATE_SUBMITTED` |
| Active execution | `TASK_STATE_WORKING` |
| Runtime-approved wait for additional input | `TASK_STATE_INPUT_REQUIRED` |
| Runtime-approved wait for additional authorization | `TASK_STATE_AUTH_REQUIRED` |
| Committed successful terminal outcome | `TASK_STATE_COMPLETED` |
| Committed cancellation | `TASK_STATE_CANCELED` |
| Committed refusal/rejection | `TASK_STATE_REJECTED` |
| Committed failure or execution deadline exhaustion | `TASK_STATE_FAILED`, with typed Star reason |
| Transport loss / uncertain observation | No invented terminal transition; retain last known state and reconcile |

An imported terminal notification is only a candidate outcome. Settlement verifies
peer identity, binding generation, concrete execution/attempt, current lease/fence,
deadline, budget and existing terminal state at the authoritative commit boundary.
The peer's reported timestamp cannot retroactively win a local terminal race.
Artifact validation and durable persistence precede successful final settlement.

Input/auth-required observations do not create new stored Target enum values.
The existing runtime must explicitly support and authorize that wait condition;
otherwise the adapter reports an unsupported interaction. Untrusted peer requests
cannot obtain broader credentials. Remote wait time still counts against the
original execution deadline and budgets.

A cancel request is not a terminal cancellation. Cancellation and completion
compete through the same Star compare-and-set. An already-completed execution
stays completed; a committed cancellation cannot be replaced by late completion.
A schedule cancellation remains a separate local control operation from canceling
one remote Task. Closing a task stream never cancels either one.

## 6. Retry, remote effects and outcome uncertainty

The gateway classifies each effect-capable remote operation:

| Safety class | Required evidence | Permitted recovery |
| --- | --- | --- |
| `fenced` | Peer/effect sink validates a current scoped generation/fence atomically at effects | Recover under a current binding; stale writers cannot affect that protected sink |
| `idempotent` | Peer contract durably deduplicates the original semantic request/key | Replay the same request identity; retain cancellation limitations |
| `unprotected` | Neither guarantee established | No automatic effectful resend after uncertain admission; reconcile or require an explicit operator decision |

These are Star integration classifications, not guarantees inferred from an A2A
Agent Card skill name. A JSON metadata field containing a fence is not evidence
that the peer enforces fencing. An idempotent peer may still finish an earlier
action after cancellation; idempotency is not revocation or rollback.

For a lost response to initial Send Message, no `remoteTaskId` may be available.
Recovery uses the persisted binding and a negotiated deduplication/reconciliation
mechanism. Stable `messageId` alone is not proof a generic peer deduplicates.
Without that mechanism, classify outcome as unknown and do not create a second
remote Task by blind retry or another provider's route.

Remote-effect guarantees and Star result-settlement guarantees are separate.
Star can reject a stale result even when it cannot undo an external peer's action.
Such actions must be surfaced as uncertain/possibly completed, not claimed absent.
Budget reservation remains held or explicitly reconciled while paid effects are
unknown; restarting the gateway never replenishes the execution budget.

## 7. Streams, push and artifacts

Stream disconnection triggers Get Task/result reconciliation under the existing
binding, not a new execution. Ordered delivery on one connection does not prove
all earlier updates survived a disconnect. Persist checkpoints for Star-owned
streams and reconcile upstream snapshots when reliable replay is not negotiated.

Push callbacks authenticate the peer, bind the request to the expected task and
tenant, enforce replay/time/size limits and acknowledge only after durable inbox
acceptance. Duplicate notifications are harmless; out-of-order nonterminal events
cannot regress a terminal state. A Task snapshot is fetched when notification
ordering or completeness is uncertain.

Do not assume upstream supplies a globally unique event ID. For artifact append
streams, negotiate stable chunk identity/offsets and deduplicate by those offsets.
Content hash alone is insufficient because two legitimate chunks may be identical.
Without reliable chunk positions, callbacks trigger bounded full-artifact
reconciliation rather than blind append. Completion cannot finalize an artifact
with unresolved gaps or conflicting bytes.

Artifact URLs are untrusted references. Fetching requires authorization, destination
policy, redirect revalidation, time/byte ceilings and digest verification when a
digest is provided. Preserve source provenance. A result URL is not a permission
to bypass the canonical document access boundary or exfiltrate local credentials.

## 8. Conformance boundary

The A2A integration must prove equivalent Star outcomes for the same authorized
request through local, Rabbit and upstream A2A paths. Test encoded objects against
the pinned upstream codecs and Star payloads against the generated 0.10.1 release.
The tests must include unknown initial-send outcome, metadata authority injection,
cross-peer ID collision, stale bindings, callback replay, duplicate artifact chunks,
missing stream intervals and cancel-vs-complete races.

Generic A2A compatibility alone does not pass this stronger Star access profile.
The server gateway owns remote credentials, peer trust, bindings and durable
settlement; StarLang owns the semantic definitions and portable conformance data.
