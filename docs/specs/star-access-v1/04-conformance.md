# STAR-ACCESS-004 — conformance and rollout

Status and dependencies: [specification index](README.md).

## 1. Evidence classes

The [scenario inventory](../../../fixtures/star-access/v1/scenarios.json) is a
machine-readable set of required tests. Its `status: required` entries are not
passing test results. The inventory checker validates specification packaging,
operation coverage and scenario metadata only. It executes neither actors nor
brokers and MUST NOT be reported as runtime conformance evidence.

Implementation PRs must add canonical encoded request/result fixtures and
executable test adapters at the final-owned runtime boundaries. A stub, direct
handler call, fake actor or mocked mailbox cannot prove actor semantics. External
effect ports may be controlled test doubles where explicitly identified; real
Sento/local actor execution remains required.

## 2. Required scenario groups

| IDs | Required evidence |
| --- | --- |
| ACCESS-001–009 | Canonical schema/version, explicit legacy conversion, untrusted control fields, duplicate JSON keys, scope checks and ActorRef incarnation |
| ACCESS-010–013 | Concurrent revision CAS, delete/recreate ABA, protected patch paths and ordered per-item bulk outcomes |
| ACCESS-014–021 | Stable idempotency, conflicts, concurrent duplicates, cross-transport retry, lost replies, outcome retention and deadlines |
| ACCESS-022–031 | Read guarantees, partial-query policy, completeness versus exhaustion, scoped cursors, topology change, view consistency and bounded merge |
| ACCESS-032–035 | Slow consumers, replay gaps, duplicate events and observer disconnect semantics |
| ACCESS-036–045 | Durable Target acceptance, caller-owned-field rejection, document-write bypass, recurrence, reschedule/cancel races, fences and budgets |
| ACCESS-046–048 | Commit-time owner fencing, partition splits and ownership-handoff recovery |
| ACCESS-049–054 | Broker versus application acknowledgement, outbox crash windows, durable inbox recovery, poison messages, reply authorization and router loops |
| ACCESS-055–062 | A2A versioning, ID/metadata isolation, unknown-send outcome, stale binding, chunk replay, stream reconciliation, external-effect uncertainty and URL policy |
| ACCESS-063–064 | Concrete Target result selection and same-version/different-hash dependency drift |

All applicable scenarios run against each advertised binding. Local/Rabbit/
StarRouter/A2A results are normalized only for transport-local metadata. They must
agree on semantic outcome, authoritative state, event identities, idempotency,
authorization and effect counts. Unsupported optional capabilities are explicit
skips tied to unadvertised capabilities; skipped tests cannot support a readiness
claim. Required baseline features cannot be skipped into a green result.

## 3. Deterministic harness requirements

Use a controllable clock, deterministic identifiers and a bounded fault scheduler.
Inject crashes at admission, conditional commit, reply, ACK, publication and owner
handoff boundaries. Advance the clock across deadline/lease/retention boundaries;
do not rely on sleeps as race evidence. Preserve an execution trace containing
request identity, authorized scope, owner epoch, execution/attempt identity,
committed revision, event ID and settlement decision, with secrets redacted.

For concurrent histories verify one winner under the advertised atomicity model,
no stale-generation/fence commits, no false success, no duplicate budget debit,
and eventual reconciliation when the modeled backend becomes available again.
Do not demand progress during a split where safe authority cannot be established.
Safety must hold under every tested interleaving; liveness requirements state their
connectivity and fairness assumptions.

Target tests must observe the existing scheduler/lease store and real actor path.
The harness cannot maintain an independent fake scheduler whose behavior merely
matches the desired answer. Recurrence tests distinguish schedule, occurrence,
attempt and lease renewal identities. Every run has finite steps/time/resources
and fails visibly on timeout instead of returning a false green.

## 4. Codec and generated-contract gates

The normative semantics must be lowered through the existing Star Language
specification/compiler path. There is no approval to invent unsupported `.star`
syntax, manually maintain another document JSON Schema, or relabel this scenario
inventory as a generated wire fixture.

Required before an implementation release:

1. Pin the accepted StarIntel 0.10.1 commit and existing release-lock hashes; run
   regeneration/reproducibility and canonical semantic validators. Prove that
   `operation`, `investigation-target` and scheduler Target remain distinct.
2. Pin the resolved upstream A2A protocol-definition commit, definition hashes and
   generated codecs. Exercise protocol `1.0` with the supported 1.0.x spec/codecs;
   reject silent legacy downgrade. Validate actual Part/Task/Artifact encodings.
3. Generate and round-trip approved access boundary definitions for Common Lisp,
   Python, TypeScript and Nim, while preserving the repository's other supported
   language boundaries. Test exact large-integer/token handling and deterministic
   semantic-request digest fixtures across languages.
4. Run real local actor, RabbitMQ, backend durability/owner-fencing and A2A gateway
   integration suites. StarRouter/ZeroMQ may remain unadvertised until its own
   real binding passes the same semantic corpus.
5. Run affected ASDF/final-system tests, surrounding regression suites,
   cross-runtime gates and `nix flake check -L` at the exact proposed head.

The default-main branch currently lacks some dependency artifacts because the
referenced work is still in open PRs. Specs may be reviewed independently, but
consumers must not silently build against stale main or claim dependency merges
that have not occurred.

## 5. Multi-repository ownership and merge order

| Owner | Deliverable | Must not duplicate |
| --- | --- | --- |
| `star-lang` #198 | Approved profile, imported/generated boundary types and language-neutral fixtures | Existing lifecycle envelope, StarIntel document schema or DB query IR |
| `star-lang` #154 / #159 / #160 | Scheduler and Actor2Actor/A2A foundations | A second access-only scheduler |
| `starintel-server` #315 | Access service actor, partition authority, named DB operations and Rabbit binding over PR #295 | StarLang grammar or StarRouter transport |
| `starintel-server` A2A gateway lane | Peer trust, durable bindings, credentials, reconciliation and result settlement | Upstream protocol schema or independent Target authority |
| `starRouter` | Existing routing/operation API projection, generation-aware routes and bounded transport | Storage ownership, persistence or Target leases |
| Consumer language repositories | Consume exact generated contract pins and run shared cases | Hand-copied schema authority |
| `starintel-auto-research` #263 | Record review decisions and cross-repository evidence | Runtime execution or automatic design approval |

Merge in dependency order: approve semantics and reconcile inherited contracts;
merge/generated-lock the document and lifecycle dependencies; implement portable
access types; implement the server's local authority path; add real Rabbit and
A2A bindings; add StarRouter; repin consumers and run end-to-end gates. Parallel
work is allowed, but capability advertisement follows evidence, not issue status.

## 6. Rollout and rollback

A service advertises a profile only when its own codec, persistence and transport
checks pass. New and old deployments exchange exact profile/operation/schema-lock
capabilities before admission. Unknown profile/operation versions fail closed;
legacy conversion is an explicitly enabled boundary, not automatic fallback.

A canary starts with authorized read-only access, then isolated conditional writes,
then Target submission/cancellation, followed by failure/recovery probes. Capture
a durable test receipt and observe its document/change/Target state through a
different transport. Verify original-key replay after a disconnected response.

Rollback drains admission while preserving accepted intents, outcome records,
outboxes, schedule state and bindings. Do not delete retained idempotency records
or restart lease counters to make an older binary appear compatible. An old
binary unable to interpret new durable state remains nonready until a compatible
recovery path is available.

## 7. Review decisions still required

The normative behavior above is concrete, but implementation selection must still
record: the authoritative ownership/fencing mechanism for each backing adapter;
exact existing lifecycle field mappings for domain errors/status; the scheduler's
canonical schedule-intent representation and DST policy; the generated semantic
request canonicalizer; upstream A2A extension publication and codec hashes; and
configured limits/retention. None may be papered over with a mock or invented
runtime claim. Record resolutions in #198/#315/#263 and update fixtures together.
