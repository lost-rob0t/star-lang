# STAR-ACCESS-001 — `star.access/1`

Status and dependencies: [specification index](README.md).

## 1. Composition, encoding and authority

An invocation is the existing Actor2Actor command/ask envelope, an operation
identity and the domain payload defined here. Replies, errors, cancellation and
stream lifecycle use existing Actor2Actor constructors. Message/correlation/
causation identity, deadline, idempotency key, sender, recipient and trace context
MUST NOT be redefined inside a parallel access envelope.

Notation below describes **domain payloads**, not complete wire messages or
already-generated types. `?` means optional; omission is not JSON null. A binding
MUST use the generated spelling of inherited fields. Newly defined payload fields
are lowerCamelCase. Unknown operation versions, unknown control fields, duplicate
JSON object keys and contradictory aliases MUST fail before effects. Extensions
require explicit negotiation; an extension cannot bypass these checks.

The authenticated boundary supplies principal, tenant and capabilities. A
caller-supplied tenant, owner, ActorRef generation, lease or fence is not proof of
authority. Authentication is revalidated on retries and result retrieval. Secrets
MUST NOT enter payloads, portable manifests, errors, event logs or source files.

### Shared payload definitions

| Type | Fields and meaning |
| --- | --- |
| `Scope` | `databaseId`, `datasetId`, optional `documentId`; logical identifiers, never a connection string. Document operations on one identity require `documentId`. |
| `ReadIntent` | `mode`: `authoritative`, `session` or `eventual`; `sessionToken` required for `session`. Default: `authoritative`. |
| `Precondition` | Exactly one of `ifAbsent: true` or `ifRevision: <opaque rev>`. No wildcard/unconditional mutation in this profile. |
| `ReadReceipt` | `servedConsistency`, `readAt`, optional `sessionToken`; any inability to meet the requested mode is an error, not a downgrade. |
| `MutationReceipt` | `documentId`, new `rev`, `committedAt`, `outcomeRef`, optional `sessionToken`. Issued only after durable authoritative commit. |
| `Budget` | Optional caller reductions of advertised row, byte, fan-out and work limits; never authority to increase server policy. |

Control-plane instants use RFC3339 UTC strings. Existing document timestamp
representations remain exactly those generated from `core.star`; adapters do not
rewrite them to match control timestamps. Opaque tokens are bounded strings and
MUST NOT be parsed by clients. Protocol metadata is distinct from document data.

The shared Star URI parser resolves logical resource URIs. A document URI uses
`star://<authority>/document/<opaque-id>` with platform-defined escaping; URI
resource identity and explicit scope MUST agree. Tenant boundaries are checked
after resolution and before backend work. User-selected partition hints, when
supported by routing, MUST be checked against the authoritative partition map.

## 2. Operation inventory and payloads

Each request below includes `scope`. Options such as `read`, `precondition` and
`budget` are payload members where specified. Idempotency and request deadlines
remain inherited lifecycle context. Every mutation requires an idempotency key.

| Operation | Additional request fields | Successful reply payload |
| --- | --- | --- |
| `star.documents.get@1` | `read?`, `revision?` | `document`, `rev`, `readReceipt` |
| `star.documents.head@1` | `read?` | `documentId`, `rev`, `deleted`, `readReceipt`; no document body |
| `star.documents.put@1` | `document`, `precondition` | `mutationReceipt` |
| `star.documents.patch@1` | `patch`, `precondition.ifRevision` | `mutationReceipt` |
| `star.documents.delete@1` | `precondition.ifRevision`, `reason?` | `mutationReceipt`, `deleted: true` |
| `star.documents.bulk-get@1` | `items`, `read?`, `budget?` | ordered `items` with individual value/error and `readReceipt` |
| `star.documents.bulk-write@1` | `items`, `atomicity: best-effort`, `budget?` | ordered `items` with individual receipt/error/unknown outcome; `complete` |
| `star.documents.query@1` | `queryRef`, `bindings`, `page`, `read?`, `allowPartial?`, `budget?` | `rows`, `coverage`, `page`, `readReceipt` |
| `star.documents.changes@1` | `from`, `filterRef?`, `bindings?`, `includeDocuments?`, `budget?` | bounded change stream and checkpoints |
| `star.targets.submit@1` | `target`, `scheduleIntent?` | durable `acceptanceReceipt` |
| `star.targets.get@1` | `read?` | canonical `target`, `rev`, `readReceipt` |
| `star.targets.status@1` | `executionId?` | authorized runtime-owned schedule/execution status projection |
| `star.targets.cancel@1` | `cancelScope`, scope-specific identifier, `reason?`, `expectedScheduleRevision?` | cancellation command receipt plus authoritative observed disposition |
| `star.targets.reschedule@1` | `scheduleIntent`, `expectedScheduleRevision` | new schedule revision and effective scheduling receipt |
| `star.targets.result@1` | `executionId`, `page?` | bounded immutable result references, execution disposition and continuation |

Document bodies MUST validate against the pinned generated 0.10.1 type plus its
semantic validators. A payload `schemaVersion` match alone is insufficient.
Legacy 0.9.x input requires an explicitly enabled compatibility ingress before
this boundary; this profile never silently treats legacy input as canonical.

### 2.1 Reads and revisions

`get` on an absent or deleted current document produces `not-found`, subject to
uniform authorization masking. `head` MAY reveal a tombstone only to an authorized
caller permitted to inspect deletion state. An unknown historical revision is
`revision-unavailable`, not proof the document never existed. A backend without
historical reads advertises that limitation and rejects a revision request.

Revisions identify authoritative versions and support equality comparison only.
They are not timestamps, content hashes by implication, partition epochs or
CouchDB revision syntax. The server MUST distinguish delete/recreate incarnations
so an old revision cannot authorize a new incarnation (ABA protection).

An authoritative read reflects the selected partition's committed authority; it
does not promise a global distributed snapshot. A session read MUST meet the
causal lower bound carried by the token. An eventual read may be stale but MUST
be explicitly requested and identified in its receipt. Unsupported guarantees
produce `consistency-unavailable`.

### 2.2 Mutations

`put` creates under `ifAbsent` or replaces under `ifRevision`. The document's `id`
MUST match the resolved identity. A submitted `rev`, when the generated type
allows it, MUST agree with the precondition and never chooses the next revision.
Backend `_id`/`_rev` keys are rejected at this public boundary. The server applies
its field-ownership policy in addition to schema validation.

`patch` is a bounded RFC6902 JSON Patch array. Paths, operation count, depth and
result size are validated. Immutable identity/type/version fields and all
runtime-owned fields are protected against direct, ancestor, array and escaped-
path edits. The fully patched document must pass canonical semantic validation.
A successful patch changes the revision once; failed tests or preconditions have
no authoritative side effects.

`delete` creates a logical tombstone and one durable change event. Physical purge
and retention administration are outside this profile. Replaying the same delete
key returns its original receipt. A different delete key with a stale revision
fails its precondition; it is not silently treated as that original deletion.

Generic document mutations MUST NOT bypass Target acceptance, scheduling, leases,
budgets or cancellation. Scheduler Target lifecycle fields are writable only by
the Target runtime. Read-only archival import, when separately authorized, cannot
dispatch work as a side effect. An `investigation-target` document does not become
executable merely because its name contains `target`.

### 2.3 Bulk access

A bulk request has one logical database/dataset scope. Each item has a unique,
caller-selected `itemId` and a `documentId`; get items optionally carry `revision`.
Write items contain `operation` from `put|patch|delete` plus that operation's
payload and precondition. Nested bulk requests are forbidden.

The full batch's shape, size, scopes and admission authorization are checked before
dispatch. Individual document validation and precondition failures are represented
per item without falsifying other outcomes. Results preserve input item order,
not completion order. The implementation derives stable item idempotency identities
from the parent scope/key and `itemId`; transport retries cannot reshuffle them.

V1 bulk writes are **not atomic across items or partitions**. Requesting stronger
atomicity fails before effects. `complete: true` means every item has a known
outcome, not that every item succeeded. After a deadline, undispatched items are
explicitly not executed; potentially committed items are `outcome-unknown` until
reconciled. A whole-batch retry resumes/replays individual durable outcomes and
never repeats already committed items.

## 3. Idempotency and uncertain outcomes

The mutation identity includes authenticated tenant, principal/delegation scope,
logical database/dataset, operation version and idempotency key. An implementation
MAY use a stricter scope, but MUST advertise it and preserve it across transports
and ownership changes. Routing node, reply queue and connection are not scope.

The server computes a deterministic digest of the normalized semantic request:
resource identity, operation, body, preconditions and schedule/execution intent.
Serialization differences do not change meaning. Transport delivery attempt,
trace headers, reply destination and channel wait timeout do not change the
digest. Canonicalization and numeric handling MUST be specified by generated
conformance fixtures before implementation release.

The acceptance sequence is: authenticate and validate; resolve idempotency;
verify current authority and preconditions; durably commit under the atomicity
requirements in the distribution spec; reply. Required behavior:

- Same key and same digest: replay the original receipt or observe the same
  in-progress operation; no new commit, dispatch or billable effect.
- Same key and different digest: `idempotency-conflict`, before effects.
- Concurrent duplicates: at most one authoritative admission/commit.
- Lost reply after a possible commit: `outcome-unknown`, not `failed` or
  `not-executed`; retry only with the original key or reconcile by `outcomeRef`.

The existing Actor2Actor status operation resolves `outcomeRef` under the original
authorization scope. This is not a second outcome-status protocol. An internal
outcome reference is not a capability. No record found after retention expiry
means `outcome-expired/unknown`, not proof of nonexecution. The service advertises
its replay horizon, returns `retainUntil` with durable outcomes, and retains
deduplication tombstones or otherwise refuses ambiguous expired-key reuse.

The original accepted execution deadline cannot be extended by retry. A caller
may retrieve an already committed receipt after that deadline, subject to the
new read request's deadline. A fresh, unadmitted expired mutation is rejected
before effects. Deadline expiration during an uncertain commit follows the
unknown-outcome path. A late network response cannot erase an earlier commit.

## 4. Target acceptance, scheduling and results

`target` is the imported scheduler Target type, not a locally redefined record.
A submission is a caller-input view of that type: persisted runtime-owned fields
in the generated record are not necessarily caller-writable. Submitted leases,
fences, execution generations, attempt state or server-assigned schedule identities
MUST be rejected rather than trusted. Known existing Target identities can be
referenced only through an authorized operation and appropriate precondition.

`acceptanceReceipt` contains runtime-assigned `targetId`, `scheduleId`, schedule
revision, durable acceptance time and `outcomeRef`. It includes an `executionId`
only if a concrete occurrence has actually been materialized. Acceptance does not
claim the actor ran or completed. The receipt is recoverable after process loss.
The Target record, schedule acceptance and dispatch intent must share a recoverable
durability boundary before success is returned.

`scheduleIntent` imports the scheduler contract from #154: not-before, recurrence,
evidence/freshness inputs, execution deadline and request/byte/spend ceilings.
This profile defines no new cron grammar. The scheduler normalizes instants,
preserves the requested time-zone semantics where recurrence needs them, rejects
invalid/ambiguous input under its declared DST policy, and atomically deduplicates
due occurrences. An exhausted budget or impossible not-before/deadline window
fails closed. Budget reservations and debits are durable and idempotent; retries
cannot mint fresh budget.

Stable Target identity, stable schedule identity, schedule revision, execution
identity, execution generation, attempt and lease/fence are separate concepts.
An occurrence is not a delivery attempt. A lease renewal does not create a new
occurrence. ActorRef incarnation is distinct from all schedule generations.
Their values come from the existing runtime; this profile does not create a
second allocation algorithm.

`reschedule` requires the expected schedule revision and changes future scheduling
atomically. It does not rewind or relabel a running/completed occurrence. Existing
pending dispatches from a superseded schedule revision cannot start afterward.
The receipt identifies affected pending work and the first effective due instant.
A running execution must be canceled explicitly before a requested replacement;
rescheduling alone neither cancels it nor authorizes parallel duplicate work.

`cancelScope` is explicitly `execution` or `schedule`. Execution cancellation
requires `executionId` and cannot cancel an unrelated occurrence. Schedule
cancellation requires `scheduleId` and `expectedScheduleRevision`, prevents future
admissions and reports already-running executions separately; it does not silently
cancel those executions. Target-wide UI actions compose explicit operations.

Cancellation acknowledgement means a durable control decision, not physical
rollback of arbitrary external effects. `cancel-requested` is a control flag,
not a new terminal Target state. Cancellation and completion race through the
same authoritative compare-and-set: first committed terminal state wins. Repeated
cancellation returns the observed disposition. Stale attempts cannot complete,
cancel, publish final results or debit budget for a newer generation.

`status` reports current runtime-owned identities and canonical states, plus any
control flags and pending-input reason. It does not invent new persisted Target
enum values for A2A convenience. `result` selects a concrete execution; a recurring
schedule's result cannot ambiguously mean its last, next or all occurrences.
Pending work returns `result-pending`, never an empty success. Completed artifacts
are immutable versioned references; paginated retrieval rechecks authorization.

## 5. Distributed query and pagination

`queryRef` identifies an authorized, versioned named DB operation from the existing
DB registry/IR. `bindings` are typed data. The remote caller cannot supply SQL,
Cypher, executable Prolog, code, credentials or an arbitrary new query language.
Search/geographic queries are named operations over stored JSON and declared
indexes. Star source text is not queried as a runtime database.

`page` requests `limit`, optional `cursor`, and `viewMode` from
`partition-snapshot|live-keyset`. Default is `partition-snapshot`; unsupported
snapshot retention yields `consistency-unavailable`. Snapshot mode pins a vector
of per-partition views, not a falsely advertised global transaction snapshot.
`live-keyset` must be explicitly selected and warns that concurrent updates can
move records across pages; it cannot be used to claim an exhaustive historical
snapshot. Cursor support is a declared capability, not assumed for every backend.

Before fan-out, the coordinator freezes the authorized partition plan and routing
revision. Child deadlines never exceed the parent deadline. The named operation
specifies typed sort/collation and a unique document-identity tiebreaker. Merge
state and rows/bytes/scanned-work/fan-out are bounded. Identical identity/revision
duplicates are collapsed; conflicting revisions in the same snapshot are an
`inconsistent-view`, not silently resolved by response arrival order.

Replies include `coverage: {complete, expectedCount, respondedCount,
missingPartitions}`. Missing entries carry scoped opaque partition references and
typed reasons; unauthorized topology is not disclosed. `allowPartial` defaults
to false. With missing partitions, false produces `incomplete-query`; true returns
explicitly partial data. Counts/aggregates from partial data cannot be described
as totals. An empty partial response is not evidence of an empty dataset.

Coverage completeness and pagination exhaustion are different. The reply's `page`
contains `hasMore`, optional `nextCursor`, and the effective view mode. A complete
page with `hasMore: true` is not an exhausted query. In V1 a partial response has
no continuation cursor: restart a new query to repair missing partitions. This
prevents late lower-sort rows from being silently skipped by a partial cursor.

A cursor is tamper-evident, opaque, scoped to the authenticated visibility/query/
projection/sort/bindings and view, and expires explicitly. It carries or references
partition positions and ownership/view revisions. Page size may only decrease
within the negotiated budget. Authorization is checked again on every page.
Changed topology or lost retained state yields `cursor-invalidated` or
`cursor-expired`; never silently restart at page one. A live-keyset cursor cannot
be upgraded into snapshot semantics by a subsequent request.

## 6. Changes and bounded streaming

`from` is either the explicit value `now` or an opaque checkpoint; omission is an
error. A checkpoint is a scoped vector across the subscribed partition set, not
a raw CouchDB sequence. Authorized filters use named operations, not caller code.
Each event identifies a stable `eventId`, document identity/revision, change kind,
commit time and per-partition ordering position. Bodies are optional and bounded.

Delivery is at least once; consumers deduplicate by stable event identity.
Ordering is per partition/document, not a fabricated total cluster order. The
stream uses the existing lifecycle's subscribe/resume/cancel and acknowledgement
mechanism, bounded credit and explicit terminal frames. Broker acknowledgement
and application checkpoint advancement are separate actions.

The service advertises frame, buffer, idle and replay-retention limits. A slow
consumer is paused within its credit window, then closed with `slow-consumer` and
the last resumable checkpoint; no silent drops or unbounded buffering. A missing
replay interval yields `history-lost`; the client must resnapshot. Disconnecting
one observer never cancels the underlying Target or another observer's stream.
Authorization is rechecked on resume and before protected events are emitted.

## 7. Error and capability requirements

Errors use the canonical lifecycle error representation. Access-specific codes
belong in its typed domain details, not a new transport-dependent error envelope:

`invalid-argument`, `unsupported-profile`, `unsupported-operation`,
`unauthenticated`, `permission-denied`, `not-found`, `revision-unavailable`,
`precondition-failed`, `idempotency-conflict`, `deadline-exceeded`,
`budget-exceeded`, `overloaded`, `unavailable`, `not-owner`, `stale-generation`,
`stale-fence`, `outcome-unknown`, `outcome-expired`, `consistency-unavailable`,
`incomplete-query`, `inconsistent-view`, `cursor-invalidated`, `cursor-expired`,
`history-lost`, `slow-consumer`, `result-pending`, `already-terminal`.

`retryable` does not grant permission to create a new idempotency key. Every
mutation error distinguishes `not-executed`, `committed` or `unknown` effect
knowledge. Debug details MUST redact credentials and inaccessible resource
existence. Error mapping cannot turn unknown commit state into a safe fresh retry.

The existing describe/discover mechanism advertises supported operations, schema
lock identity, read/view modes, named query versions, limits, checkpoint/outcome
retention, bindings and runtime readiness. All allocation/work limits are finite,
validated before work, and enforced during work. Unsupported capabilities fail
explicitly; transport changes never silently weaken the semantic contract.
