# Document bus boundary guards

This local implementation slice adds `star-document-bus`, a Common Lisp library
above `star-actor-protocol`. It does not introduce a wire envelope, document type,
DB query language, actor runtime, durable outcome store, scheduler, or transport.

## Ownership and specification provenance

- Baseline: StarLang main `e9ec1d883627d186aafe0b3647bdc29baea03543`.
- Semantic issue: StarLang #198; transport issue: starRouter #5.
- Application owner: StarIntel Server #315 and DB runtime PR #295, inspected at
  `aee24f1c8ec0bc35ae118d0854b15574bc9f9980` (open draft).
- Access specification proposal: StarLang PR #199 at
  `b75fba66da3a9ffec3559c66b373475cf63991e3` (open draft). Its acceptance,
  distribution and bounded-change requirements informed these guards. This does
  not promote that draft into a published generated profile.
- Existing generated StarIntel 0.10.1 document/Target types remain authoritative.
  The inspected server lock pins `d6ca8780845c4296f64ac8e65aaa9db143842460`;
  verification using this merged-main checkout's Git history passes. This does
  not mean the server lock has been repinned to current main.

The implementation is language-independent in behavior, with a Common Lisp
helper implementation only. Python/TypeScript/Nim and other supported boundary
languages keep their existing generated document/lifecycle authority; no parity
for these new local helper APIs is advertised.

## Delivery evidence API

`make-delivery-observation` snapshots and validates an existing lifecycle command.
`observe-delivery` consumes trusted service evidence. A remote caller must never
supply these evidence symbols as proof of its own durable commit.

- Broker publisher confirmation and consumer acknowledgement establish no
  application commit and do not permit settlement by themselves.
- Durable inbox acceptance permits settlement, but is not completed work.
- An authoritative precondition rejection may follow durable admission.
- Disconnection without a known authoritative outcome means unknown; it never
  rolls back committed knowledge or terminalizes a Target execution.
- A durable committed receipt can reconcile unknown knowledge. Repeated receipts
  must agree exactly (case-sensitive plist/alist and nested vector values); contradictory evidence
  fails. A receipt must already have been validated by the service.
- Publication evidence requires committed state. It is not proof that every
  subscriber received or acknowledged the event.
- Retry advice preserves the original idempotency key. Unknown knowledge requires
  reconciliation; the helper cannot verify retention or durable deduplication.

This is a bounded observation object, not an authoritative ledger. It cannot
make arbitrary external effects exactly once. Authentication, deadline checks,
request canonicalization, durable outcomes, idempotency conflict detection,
commit-time partition fencing, and state/outcome/outbox coupling remain service
and backend responsibilities. A NOT-EXECUTED observation requires authoritative
evidence, not a timeout, broker NACK, or missing expired outcome record.

## Bounded change observation API

`make-change-observer` fixes trusted authorization scope, credit, and finite
retention. `observe-change` takes event identity, logical partition, normalized
monotonic ordering position and a service-issued opaque checkpoint. These are
internal adapter arguments, not a new wire record. Actual cursors remain opaque;
no CouchDB sequence or broker delivery tag becomes a public checkpoint.

Duplicate identity/position is suppressed within the local retained window.
Contradictory identity/position fails. Older unrecognized positions fail with
history-lost rather than silently pretending complete replay. Sparse increasing
positions are permitted for filtered streams. No global partition ordering is
invented. Pending deliveries, retained dedup entries, and partition bookkeeping
are bounded. Credit exhaustion rejects the new event before state changes.

`acknowledge-change` advances only the contiguous locally processed delivery
prefix. Broker settlement does not call it. The service must ensure its supplied
opaque vector includes no unprocessed events. `close-observer` closes only this
observer and returns its last resumable checkpoint; it cannot cancel Target work.

Authorization must be revalidated by the service before every event/resume/ACK.
Matching scope strings alone are not authentication. This helper neither issues
nor verifies cursor signatures, restores backend history, provides automatic
reconnection, nor owns a durable subscription registry. Retention here is a
bounded local count, not the service's advertised time-based replay horizon.

## Backend integration contract

Reuse server PR #295's named operation registry and database read/write/
transaction/subscribe ports. Logical tenant/dataset/database authorization runs
before adapters. Target operations enter the existing Target runtime.

The inspected server's `source/databases/outbox.lisp` already co-locates mutation
ledger and pending events with the document revision and uses CAS conflict
retries. Its mutation content hash and per-document sequence must not be silently
replaced by these helpers. CouchDB, Postgres and filesystem adapters must prove
their own recoverable commit and fencing boundary before reporting COMMITTED.
Native live backend and actor tests remain required; memory-only guard tests do
not prove those properties.

## Verification

Run `asdf:test-system "star-document-bus"`, followed by
`asdf:test-system "star-actor-protocol"`. Both passed with SBCL 2.2.9.
The tests execute the real shared lifecycle constructors/validators, but are
helper tests, not actor/broker/server integration tests. ASDF cache output was
redirected into /tmp because the default home cache is unwritable.

A focused RED test exposed rejecting an authoritative precondition failure after
durable admission; allowing that no-effect outcome made it GREEN. The first
attempt to run tests was an environment/cache failure and is not counted as RED.
Full ASDF/Gradle/cross-runtime/Nix, live Rabbit, ZeroMQ and backend conformance were
not run by this slice. Nix is not installed in this executor. No socket test,
installation, publication, merge, deployment or schema repin was performed.

Independent review follow-on: repeated vector-valued receipts are now compared by
owned portable value rather than vector storage identity. A regression reproduces
the former false conflict and checks case and list/vector distinctions. The full
document-bus and protocol suites passed locally after this repair.

Composed exact-JSON integration: receipt replay comparison also recognizes the
protocol-owned exact JSON numeric token by lexeme, so owned snapshots do not
create false receipt conflicts. Different tokens remain conservatively distinct;
this is immutable receipt identity, not a new numeric normalization algorithm.
A regression covers identical and changed symbolic huge-exponent receipts.
