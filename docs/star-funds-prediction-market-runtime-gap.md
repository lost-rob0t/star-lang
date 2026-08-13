# Star Funds prediction-market actor/runtime gap analysis

## Status of this document

This is an **implementation-facing consumer gap analysis** for `lost-rob0t/star-funds`, not a replacement for the authoritative approved StarLang research corpus in `lost-rob0t/starintel-auto-research`.

It records what the current `star-lang` repository/prototype can already express, which capabilities are only transitional/prototype-level, what Star Funds still needs, and what should remain ordinary Common Lisp until the language/runtime surface is stable.

## Decision

Do **not** make Star Funds depend on new StarLang language features for its first Kalshi implementation.

Star Funds should proceed now as Common Lisp libraries + Sento actors + the existing durable boundaries. StarLang should evolve in parallel toward a small set of reusable actor/workflow primitives that can later describe the same system without financial-domain special cases.

The largest gap is not basic actor addressing. The current prototype already demonstrates logical STAR service URIs, actor manifests, capabilities, bounded mailbox declarations, command/reply/cancel lifecycle envelopes, idempotency/deadlines, deterministic dispatch, remote directory resolution, journaling, restart recovery, and leases/remoting work.

The gap is primarily:

1. **stabilization/extraction** of those prototype capabilities into the final `star-*` systems;
2. first-class declarative supervision/timer/retry/subscription/stream semantics;
3. typed keyed routing and workflow fan-out/fan-in;
4. durable actor-state/event-sourcing conventions above the raw journal;
5. health/telemetry/backpressure contracts;
6. a narrow foreign-service capability model for libraries such as SWI-Prolog;
7. enough compositional syntax to express a market pipeline without embedding domain logic into StarLang itself.

## Repository reality

The README describes the target Common Lisp-only systems:

```text
star-actor-protocol
star-sento-compat
star-mailbox
star-supervisor
star-journal
star-lease
star-capability
star-artifact
star-adapter-sdk
star-http-port
star-process-port
star-canonical-json
starlang-compiler
starlang-runtime
...
```

However, `prototype/` remains the authoritative working implementation while final systems are extracted incrementally. Some final package shells currently export little or nothing. Therefore this document distinguishes:

```text
EXISTS_IN_PROTOTYPE
FINALIZED_LIBRARY
FIRST_CLASS_LANGUAGE_SURFACE
MISSING_OR_UNPROVEN
```

A feature present in a prototype test is not automatically a stable public API.

## Existing capabilities relevant to Star Funds

### 1. Logical service URI / discovery — EXISTS_IN_PROTOTYPE

The prototype tests canonicalize and resolve addresses such as:

```text
star://quasar:localhost:user-hunt
star://bbp:localhost:nmap
```

The parsed structure already separates:

```text
domain
address
actorName
```

Actor manifests can carry `service-uri`, and a runtime directory can resolve the URI to an alive actor plus capabilities and an opaque actor reference. Missing versus unavailable services are differentiated.

This is enough conceptually for Star Funds addresses such as:

```text
star://funds:localhost:market-catalog-watcher
star://funds:localhost:mispricing-detector
star://funds:localhost:execution-supervisor
star://funds:localhost:prolog-kb
```

**Gap:** keying/sharding semantics are not yet a first-class address concept. Star Funds needs per-series/event/market instances without inventing thousands of global actor names.

Proposed later extension:

```text
star://funds:localhost:market-pricer?key=KXWTI-26JUN3014
```

or preferably a typed route key in message/manifest metadata rather than URI query-string semantics if the research design rejects query-bearing service IDs.

### 2. Actor manifest metadata — EXISTS_IN_PROTOTYPE

Current tests compile actor declarations with fields such as:

```lisp
(:runtime external
 :service-uri "star://quasar:localhost:user-hunt"
 :protocol star-message-v1
 :endpoint "fake:user-hunt"
 :accepts (ingest-page)
 :produces (index-fec-record)
 :restart permanent
 :mailbox (bounded 128)
 :capabilities (username-search social-account-discovery))
```

This already covers a substantial part of the Star Funds manifest need:

- logical service identity;
- accepted/produced messages;
- restart intent;
- bounded mailbox declaration;
- capability tags.

**Gaps:**

- structured restart strategy/intensity, not only a restart label;
- message-specific concurrency/backpressure policy;
- required upstream/downstream capabilities;
- subscriptions;
- timers;
- readiness dependencies;
- durable-state/replay policy;
- route-key/shard policy;
- security/credential isolation declaration.

### 3. Command/reply/cancel lifecycle — EXISTS_IN_PROTOTYPE

`message-lifecycle-tests.lisp` demonstrates:

- command envelopes;
- `reply-to`;
- correlation and causation IDs;
- idempotency key and scope;
- `sent-at` and deadline;
- acknowledgements for accepted/completed/retry;
- retry delay;
- retryable/non-retryable errors;
- cancellation targeting an original message;
- typed message contract validation;
- generated Python/TypeScript envelope bindings.

This means request/reply is **not** a greenfield gap.

**Gap:** a convenient runtime/language construct for awaiting/collecting replies, timeout/cancel propagation, and fan-in remains to be stabilized. Star Funds should not have to hand-build correlation maps in every actor.

### 4. Deterministic dispatch — EXISTS_IN_PROTOTYPE

The service URI tests demonstrate deterministic dispatch to a logical STAR target and stable acknowledgement emission.

This is directly useful for replaying financial actor workflows.

**Gap:** explicit deterministic scheduler/virtual-time semantics need to be exposed as a documented reusable runtime contract rather than only implementation tests.

### 5. Journal + restart recovery — EXISTS_IN_PROTOTYPE

The domain remoting journal tests demonstrate:

- memory/file journal ports;
- append/replay;
- defensive replay copies;
- durable pending transition before remote delivery;
- process restart restoring pending commands;
- redelivery after worker registration;
- terminal result journaling;
- replay preventing terminal command redelivery;
- duplicate command replay of prior terminal outcomes;
- route failure/retry recovery.

This is a strong base for Star Funds execution workflows.

**Gap:** the raw runtime journal is not yet a user-facing event-sourced actor state abstraction with snapshot/fold/version contracts.

### 6. Remoting / leases — EXISTS_IN_PROTOTYPE

The prototype loads remoting and lease components for domain gateways/workers. This is relevant to future multi-process Star Funds deployment.

**Gap:** Star Funds does not need distributed execution in its first domain slice. Keep local Sento actors until measured isolation/scale requires remoting.

### 7. Capabilities — EXISTS_IN_PROTOTYPE / TARGET_SYSTEM

Actor manifests already include capabilities and the repository targets a `star-capability` library.

**Gap:** capability tags need a stable authorization meaning, especially around dangerous ports. For Star Funds, `kalshi.public-read`, `kalshi.demo-order`, and future `kalshi.live-order` must be impossible to conflate.

## Required Star Funds capabilities and gap classification

| Capability | Prototype evidence | Star Funds immediate need | Gap |
| --- | --- | --- | --- |
| `star://` service address | yes | useful | stabilize/extract |
| actor manifests | yes | useful | enrich |
| typed messages | yes | required | stabilize/extract |
| request/reply | yes at envelope level | useful | runtime convenience |
| cancellation | yes at envelope level | required | propagation semantics |
| deadlines | yes in envelope | required | runtime enforcement |
| idempotency | yes | required | stabilize outcome store API |
| bounded mailbox | declared | required | runtime metrics/backpressure semantics |
| deterministic dispatch | yes | valuable | expose stable scheduler/replay contract |
| durable journal/replay | yes | required for execution | event-state abstraction |
| service directory | yes | useful | dynamic subscriptions/key routing |
| leases/remoting | prototype | not initial | defer |
| supervision tree | target system, restart metadata | required | first-class tree/intensity API |
| timers | not established as first-class surface here | required | add |
| recurring schedules | not established | useful | add after timers |
| pub/sub | not established as first-class surface here | useful | add |
| stream sequencing/gap semantics | not established | required for market feeds | add port/subscription contract |
| fan-out/fan-in | not established as first-class surface | useful | add combinator/runtime helper |
| keyed sharding | not established | useful at scale | add later |
| telemetry/health/readiness | not established as language surface | required operationally | add runtime APIs first |
| event-sourced actor state | journal lower layer exists | useful | add library abstraction |
| SWI-Prolog query port | generic process port targeted | required by Star Funds | implement as ordinary CL adapter first |
| credential capability isolation | capabilities exist conceptually | critical for execution | formalize before live execution |

"Not established" means not found as a stable first-class surface in the inspected repository/tests; it is not a claim that no experimental implementation exists anywhere.

## Gap 1 — typed route keys and actor instances

Star Funds has natural partition keys:

```text
seriesTicker
eventTicker
marketTicker
positionId
orderId
```

A single logical actor kind may have many keyed instances.

Desired semantics:

```text
actor type: market-pricer
key type: MarketTicker
placement: local|remote
state scope: per-key
mailbox: per-key bounded
```

Candidate StarLang surface, illustrative only:

```lisp
(actor market-pricer
  (:runtime local
   :key marketTicker
   :protocol prediction-market-v1
   :accepts (revalue-target book-updated forecast-updated)
   :produces (fair-value opportunity-rejected)
   :restart transient
   :mailbox (bounded 256)))
```

Then routing could use message metadata:

```text
actor = star://funds:localhost:market-pricer
routeKey = KXWTI-26JUN3014-T68.99
```

Keep logical identity separate from key value so service discovery does not become a registry entry per market.

### Immediate Star Funds implementation

Use a Common Lisp registry/hash from key -> Sento actor reference, owned by a supervisor. Preserve `routeKey` in the message envelope so migration to StarLang is mechanical later.

## Gap 2 — supervision trees and restart intensity

A financial actor system needs hierarchical failure containment:

```text
funds-supervisor
├── market-intelligence-supervisor
├── forecasting-supervisor
├── pricing-supervisor
├── prolog-supervisor
└── execution-supervisor
```

Required policies:

```text
permanent | transient | temporary child
one-for-one | one-for-all | rest-for-one
max restarts N per interval
backoff policy
escalation target
shutdown timeout
startup/readiness dependency
```

Candidate syntax:

```lisp
(supervisor execution-supervisor
  (:strategy one-for-one
   :max-restarts 3
   :within 60s
   :children
   ((order-manager :restart permanent)
    (fill-reconciler :restart permanent)
    (position-manager :restart permanent)
    (exit-policy-engine :restart permanent))))
```

### Immediate Star Funds implementation

Use Sento supervision/local wrapper policies. Store the desired declarative spec as Lisp data so it can later lower to StarLang.

## Gap 3 — timers and durable deadlines

Critical use cases:

- initialized market activation at `openTime`;
- opportunity expiry;
- forecast refresh;
- source poll schedule;
- cancel/replace timeout;
- order reconciliation timeout;
- pre-close exit/cancel deadline;
- retry/backoff.

Required primitives:

```text
schedule-once(actor, timerId, at|after, message)
cancel-timer(timerId)
reschedule(timerId)
recover-durable-timers()
```

Timer delivery should be idempotent and deterministic under virtual time/replay.

Candidate StarLang:

```lisp
(on market-target-created target
  (schedule activation-probe
    :at target.openTime
    :send (probe-activation target.targetId)
    :durable true))
```

### Immediate Star Funds implementation

Common Lisp timer service actor with persisted timer documents. Use monotonic local waits, but wall-clock target timestamps in durable records. On restart, reload pending timers and fire overdue timers under explicit policy.

## Gap 4 — retry/backoff as policy, not handler boilerplate

Existing lifecycle envelopes already support `retry` + `retryAfterMs`. Add a reusable execution policy:

```text
maxAttempts
baseDelay
maxDelay
exponentialFactor
jitter
retryable reason classes
deadline interaction
```

Candidate:

```lisp
(retry-policy kalshi-metadata
  (:max-attempts 8
   :backoff (exponential :base 100ms :max 5s :jitter full)
   :retry-on (timeout rate-limited temporarily-not-found)))
```

This directly models Kalshi's documented just-created-market 404 retry case.

### Immediate Star Funds implementation

Use a pure CL retry-policy struct shared by adapters/actors. Envelope retry semantics remain compatible.

## Gap 5 — subscriptions, streams, sequencing, and gap recovery

Prediction markets have long-lived feeds:

```text
market lifecycle
orderbook
trades
user orders/fills
weather/source observations
speech transcript segments
```

StarLang should avoid pretending a stream is just endless ordinary `tell` without sequence semantics.

Needed subscription contract:

```text
subscriptionId
source service/capability
topic/filter
sequence domain
snapshot + delta policy
resume cursor/sequence
gap event
backpressure policy
cancel/unsubscribe
```

Candidate:

```lisp
(subscription kalshi-lifecycle
  (:from "star://funds:localhost:kalshi-read-port"
   :channel marketLifecycleV2
   :produces market-lifecycle-observed
   :gap-policy reconcile-rest
   :mailbox (bounded 4096)))
```

For orderbooks, model snapshot+delta explicitly:

```text
BookSnapshot(seq=N)
BookDelta(seq=N+1)
...
Gap(expected=M, received=K)
```

The consumer becomes invalid until resnapshot/reconciliation completes.

### Immediate Star Funds implementation

Domain-specific Common Lisp subscription actors with explicit sequence state. Do not wait for StarLang.

## Gap 6 — fan-out/fan-in workflow primitives

Launch evaluation naturally fans out:

```text
TargetActive
  -> fresh book
  -> fresh domain forecast
  -> risk/account snapshot
  -> Prolog eligibility/coherence
  -> join before deadline
```

Without a helper, each actor builds correlation maps/timeouts manually.

Needed combinator semantics:

```text
parallel requests
join all|required subset|quorum
per-branch timeout
parent deadline
cancellation propagation
partial result/error representation
```

Candidate:

```lisp
(flow launch-evaluation (target)
  (parallel
    (book (ask market-data (fresh-book target.marketTicker)))
    (forecast (ask domain-forecaster (forecast target.targetId)))
    (account (ask risk-state (snapshot)))
    (proof (ask prolog (eligible target.targetId))))
  (join :all :deadline 1500ms)
  (send mispricing-detector
        (evaluate target book forecast account proof)))
```

This is illustrative; final syntax should follow approved StarLang research conventions.

### Immediate Star Funds implementation

Create a Common Lisp request-group helper using existing correlation/reply/deadline envelope concepts. Keep it library-level and deterministic.

## Gap 7 — event-sourced actor state above the journal

The prototype journal already proves durable pending/terminal recovery. Star Funds needs a higher-level state abstraction for:

- order state;
- position state;
- activation schedules;
- subscriptions;
- possibly actor-local calibrated model metadata.

Desired interface:

```text
append event
fold from snapshot + events
snapshot at version
replay to sequence/time
idempotent event identity
schema version
state hash/digest
```

Candidate declaration:

```lisp
(state position-state
  (:mode event-sourced
   :event position-event
   :fold fold-position
   :snapshot-every 100
   :replay deterministic))
```

### Immediate Star Funds implementation

Implement domain event folds in pure Common Lisp over canonical documents. The StarLang journal can later become a storage/runtime backend, not the domain model itself.

## Gap 8 — backpressure and bounded concurrency

A bounded mailbox declaration exists, but Star Funds needs explicit overload behavior:

```text
block producer
reject newest
reject oldest
coalesce by key
latest-wins only after raw evidence archived
bounded worker concurrency
source prefetch
priority classes
```

Financial correctness rule: never coalesce away unarchived source evidence. It is safe to collapse redundant **derived recompute requests** once the underlying observations are durable.

Candidate:

```lisp
(:mailbox
  (bounded 512
   :overflow (coalesce :key marketTicker :message revalue-target)))
```

### Immediate Star Funds implementation

Use Sento bounded actor wrappers and explicit coalescing actors only for derived work.

## Gap 9 — health, readiness, and telemetry

Required runtime signals:

```text
actor alive/restarting
mailbox depth
oldest message age
last successful source observation
retry rate
journal lag
subscription sequence/gap status
Prolog health/query latency
order adapter reconciliation status
kill-switch state
```

Health and readiness differ:

- `alive`: actor process running;
- `ready`: dependencies/source state safe for work;
- `degraded`: runs but must not produce trade opportunities;
- `failed`: unavailable.

Candidate manifest:

```lisp
(:readiness
  (requires kalshi-public-read prolog-kb)
  (max-source-age 5s))
```

Do not encode domain-specific age thresholds into generic StarLang syntax; use readiness probe capabilities/configuration.

### Immediate Star Funds implementation

Common Lisp metrics/probe protocol. Feed deterministic `SourceHealth` snapshots into risk/opportunity gates.

## Gap 10 — capability/security boundaries

This is critical before any real execution.

Desired capabilities:

```text
kalshi.publicRead
kalshi.authenticatedRead
kalshi.demoOrder
kalshi.liveOrder
prolog.namedQuery
artifact.read
artifact.write
```

A forecaster manifest must never request order capabilities. An execution adapter cannot be discovered merely because a strategy names it; runtime configuration/capability issuance controls access.

Candidate:

```lisp
(actor wti-forecaster
  (:requires (kalshi.publicRead artifact.read)
   :denies (kalshi.demoOrder kalshi.liveOrder)))
```

Whether explicit `:denies` belongs in the language needs research; capability allowlists alone may be cleaner.

### Immediate Star Funds implementation

Separate ASDF packages/config objects/processes and never pass authenticated adapter objects to forecast actors. Existing deterministic risk remains mandatory even when capabilities are later formalized.

## Gap 11 — Common Lisp library integration

The user explicitly wants Common Lisp as the library layer. StarLang must compose **with** Common Lisp, not replace it.

Desired boundary:

- pure/domain logic implemented as normal ASDF systems;
- StarLang actor declaration resolves only pre-registered exported handlers/capabilities;
- no arbitrary `eval` of source names;
- manifest pins library/system version/hash where needed;
- handler arguments/messages remain typed data contracts.

Illustrative adapter declaration:

```lisp
(port weather-forecast-library
  (:runtime common-lisp
   :system "star-funds-weather"
   :handler "STAR-FUNDS.WEATHER:HANDLE-FORECAST"
   :capabilities (weather.forecast)))
```

This syntax is **not approved**; the design requirement is a closed manifest-to-registered-handler lookup, not host-language evaluation.

### Immediate Star Funds implementation

Direct ASDF dependencies and ordinary function calls inside Sento actor handlers.

## Gap 12 — SWI-Prolog named-query integration

Star Funds already prefers a narrow local Prolog process/RPC, not arbitrary network Prolog queries.

Required generic runtime abstraction:

```text
process/service port
named operation whitelist
request/reply
bounded payload
hard timeout
deadline/cancel
restart policy
health/readiness
stdout/stderr capture policy
resource limits
```

Star Funds operations:

```text
loadFactBatch
retractProjectionBatch
queryNamedPredicate
explainConclusion
health
rebuild
```

Do not add Prolog-specific syntax to core StarLang. Implement it through a generic process/RPC adapter capability.

### Immediate Star Funds implementation

Use the existing Common Lisp Prolog bridge/process boundary. Later map it to `star-process-port` once that final system/API is stable.

## Gap 13 — declarative workflow graph

The useful end state is expressing orchestration, not forecast math, in StarLang.

Desired example:

```text
marketCreated
 -> reconcileMarket
 -> snapshotRules
 -> compileTarget
 -> persistTarget
 -> scheduleActivation

marketActive
 -> parallel(book, forecast, account, prolog)
 -> mispricing
 -> deterministicRisk
 -> orderIntent
 -> executionAdapter
 -> reconcile
```

Domain algorithms remain Common Lisp libraries.

An illustrative future surface:

```lisp
(flow market-launch (market-created)
  (call market-reconciler)
  (call market-rule-snapshotter)
  (call market-target-builder)
  (persist market-target)
  (schedule-at market-target.openTime
               (probe-activation market-target.targetId)))

(flow active-evaluation (market-active)
  (parallel
    (book (call market-data))
    (forecast (route-by target.forecastDomain))
    (account (call risk-state))
    (proof (call prolog-kb)))
  (join :all)
  (call mispricing-detector)
  (call deterministic-risk)
  (when allowed
    (call execution-supervisor)))
```

This is design pseudocode, not proposed parser syntax to implement blindly.

## What Star Funds should implement now in ordinary Common Lisp

Do now:

- domain document structs/validators;
- Sento actor supervisors;
- per-key actor registry/router;
- timer service actor;
- retry/backoff policy structs;
- subscription/orderbook sequence handling;
- request-group fan-out/fan-in helper;
- event folds for order/position state;
- metrics/readiness protocol;
- Prolog named-query bridge;
- authenticated adapter capability separation;
- deterministic risk/execution state machine.

Design these APIs so StarLang can later wrap them, but do not block on compiler/runtime extraction.

## Minimum StarLang additions for useful adoption

### P0 — stabilize existing prototype contracts

1. Extract/finalize actor protocol message lifecycle.
2. Extract/finalize service URI + runtime directory APIs.
3. Extract/finalize mailbox and deterministic dispatcher APIs.
4. Extract/finalize journal/replay and lease APIs.
5. Add conformance tests proving the final systems behave identically to the retained prototype paths.

This should happen before adding lots of syntax.

### P1 — runtime primitives

1. supervisor tree API with restart intensity;
2. timer/deadline scheduler with deterministic virtual-time tests;
3. retry policy helper integrated with lifecycle ACK/error semantics;
4. runtime ask/reply convenience with deadline/cancellation;
5. health/readiness/telemetry protocol;
6. bounded mailbox overflow/backpressure policies.

### P2 — orchestration

1. subscriptions with sequence/gap/reconcile contract;
2. route-key actor registry/sharding;
3. fan-out/fan-in request groups;
4. event-sourced state helper over journal;
5. durable timer recovery;
6. lifecycle hooks.

### P3 — language surface

Only after the runtime APIs are tested, lower declarative syntax into those capabilities:

- supervisor declarations;
- keyed actors;
- retry policies;
- subscriptions;
- schedules/timers;
- workflow `parallel/join`;
- state declarations;
- readiness/capability requirements.

Keep normalized IR runtime-neutral per existing StarLang architecture. Sento/cl-gserver names belong in adapter manifests, not core IR.

## Interaction with current research-conformance blockers

The repository is already blocked on research 000–009 integration items such as specification locks, relation-field migration, float support, and permanent conformance CI.

Do not let prediction-market workflow work weaken those gates.

Specific guidance:

- exact financial values remain `decimal`/fixed-point strings; future binary64 `float` support is appropriate for approximate measurements/probabilities only when the existing research permits it;
- probability fields should have an explicit numeric representation policy before wire schemas are standardized in StarLang;
- prediction-market documents must use lower camelCase field names to align with current StarLang requirements;
- no new source-language feature should route around the closed parser/checked IR architecture.

## Test requirements for Star Funds-driven additions

### Service routing

- logical URI + route key deterministically selects same actor instance;
- unavailable vs missing actor preserved;
- restart does not duplicate key ownership.

### Request/reply

- reply preserves correlation/causation;
- timeout emits stable terminal/retry state;
- cancel propagates to outstanding branches;
- duplicate reply does not complete join twice.

### Timer

- virtual-time deterministic firing;
- restart recovery;
- cancel/reschedule idempotency;
- overdue timer policy;
- no double fire after journal replay.

### Supervision

- child restart intensity cap;
- escalation;
- dependency readiness;
- execution subtree failure cannot make risk fail open.

### Subscription

- snapshot + ordered deltas;
- duplicate delta;
- sequence gap;
- resnapshot/recovery;
- bounded mailbox overload.

### Event state

- append/replay digest;
- snapshot + tail replay equals full replay;
- duplicate event idempotency;
- schema-version failure.

### Capabilities

- forecaster cannot resolve `liveOrder` adapter;
- demo and live capabilities are distinct;
- missing capability yields deterministic rejection, not fallback discovery.

## Alternatives

### Put all Star Funds actor logic directly into StarLang now

Rejected. It couples financial-domain implementation to a compiler/runtime that is still explicitly transitional and not fully research-conformant.

### Keep StarLang entirely out forever

Rejected. The prototype already contains useful reusable primitives and can eventually eliminate boilerplate in supervision, replay, addressing, lifecycle messages, and orchestration.

### Add financial primitives to StarLang core

Rejected. `MarketTarget`, WTI, mention matching, order sizing, Kalshi semantics, and stop-loss policy are Star Funds domain libraries. StarLang should provide generic actor/runtime composition only.

## Tradeoffs

Parallel evolution temporarily duplicates some orchestration helpers between Star Funds and StarLang. This is acceptable if the Star Funds helpers use explicit small interfaces and do not become a second language/runtime.

Stabilizing prototype APIs before adding syntax is slower than adding surface features immediately, but prevents the parser/IR from promising semantics the final runtime cannot yet enforce.

## Selected approach

1. Star Funds implements the researched prediction-market system now as Common Lisp/Sento libraries.
2. StarLang first completes existing conformance/extraction work.
3. Add runtime primitives for supervisors, timers, ask/reply, backpressure, subscriptions, keyed routing and event state.
4. Only then add declarative StarLang syntax that lowers into those proven APIs.
5. Keep SWI-Prolog and Kalshi as ordinary capability-bound adapter ports, not language special cases.

## Revisit conditions

Begin migrating Star Funds orchestration into StarLang when:

- final `star-*` systems expose stable APIs rather than empty/transitional shells;
- research 000–009 conformance CI is green;
- timer/supervisor/message/journal primitives have deterministic tests;
- Star Funds has a working Common Lisp actor flow that provides a behavioral reference fixture.

At that point, use Star Funds archived replay scenarios as a conformance workload: the StarLang-orchestrated version must emit the same document/order-intent outcomes under virtual time.

## Actionable conclusions

- **Do not block Star Funds on StarLang.**
- Treat current service URI, lifecycle envelope, deterministic dispatcher and journal/restart work as assets to stabilize, not reimplement.
- Highest-value missing runtime primitive for Star Funds: durable timers + first-class supervision + subscription/gap semantics.
- Highest-value language primitive after runtime stabilization: keyed actors and `parallel/join` workflow composition.
- Keep Common Lisp domain libraries authoritative; StarLang orchestrates them.
- Keep Prolog behind a generic named-query process port.
- Formalize execution capabilities before any live-order adapter exists.
