# Real actor-system test invariant

Status: design contract for issue #42

## Why this exists

StarLang has reached the point where a test can accidentally prove the wrong layer.

`starlang-runtime` now owns deterministic StarLang actor semantics using the final `star-mailbox` implementation. `star-sento-compat` is the replaceable concrete runtime adapter for Sento/cl-gserver. Those two responsibilities are intentionally different: StarLang owns the language semantics; Sento supplies a production actor-system implementation with real actor registration, message boxes, dispatch workers, actor references, lifecycle, and remoting.

The repository therefore needs two kinds of actor evidence. A deterministic semantic test proves StarLang's contract. A concrete backend test proves that the adapter actually realizes that contract over the actor runtime it claims to support.

A mock actor system cannot provide the second kind of evidence.

This document makes that distinction a repository invariant and defines the immediate implementation slice required by issue #42.

## Non-negotiable invariant

Any test whose assertion is about actor semantics MUST execute through the production actor-runtime boundary whose semantics it claims to test.

For deterministic StarLang actor semantics:

- instantiate the final `starlang-runtime`;
- create actual final runtime actor instances;
- use the actual `star-mailbox` implementation;
- route `tell` and `ask` through the normal mailbox/dispatch path;
- preserve deterministic scheduling where the test needs reproducibility.

For Sento compatibility or integration semantics:

- boot an actual Sento actor system;
- create actors through the final `star-sento-compat` entry points backed by Sento `actor-of`;
- use actual actor references and message boxes;
- send through actual Sento `tell` / `ask` operations exposed by the adapter;
- allow Sento's dispatcher workers to execute actor handlers;
- observe lifecycle through actual actor-system operations;
- stop actors and shut the actual actor system down during teardown.

Fakes and mocks MAY model non-actor effect boundaries such as:

- network responses;
- process execution;
- wall/virtual clocks;
- journals and artifact stores;
- remote services not under test;
- fault injection at a declared external port.

Fakes and mocks MUST NOT substitute for these behaviors when a test claims evidence about them:

- actor-system construction;
- actor creation/registration;
- actor references;
- actor message boxes/mailboxes;
- enqueue and delivery;
- `tell`;
- `ask` and reply correlation;
- per-actor serialization/concurrency;
- actor lookup or liveness;
- watch/termination notification;
- supervision/restart policy;
- stop;
- actor-system shutdown.

A narrow unit test MAY inject functions into `runtime-port` to prove forwarding, argument shape, error conversion, or optional-operation behavior. Such a test is classified as a port-wiring test and MUST NOT be cited as concrete actor-runtime evidence.

## Architectural boundary

The intended ownership remains:

```text
StarLang source / normalized IR
            |
            v
star-actor-protocol
  identities, actor refs, message/lifecycle contracts
            |
            v
starlang-runtime
  deterministic StarLang semantic authority
            |
            +--------------------------+
            |                          |
            v                          v
star-mailbox                     star-sento-compat
  deterministic bounded           concrete Sento translation
  mailbox primitive               / runtime backend
            |                          |
            v                          v
fast semantic tests          real Sento actor-system tests
```

`star-supervisor` remains the future owner of StarLang supervision policy. The Sento adapter may expose concrete lifecycle primitives needed by a supervisor, but it MUST NOT become the authority for StarLang restart strategies, restart intensity, generations, or policy semantics.

The same rule applies to journal, lease, capability, artifact, and transport systems: they may compose with actor execution but do not move actor-language authority into the backend.

## Required test layers

### Layer A: deterministic semantic conformance

Purpose: prove the StarLang actor contract quickly and reproducibly.

Owner: `starlang-runtime` plus final protocol/mailbox systems.

Required properties include:

- bounded mailbox acceptance/full behavior;
- FIFO behavior where promised;
- asynchronous `tell` with no handler execution on the caller's delivery operation;
- actor-private state transition and rollback;
- generation and stale-reference semantics;
- deterministic `ask` correlation and timeout behavior;
- input/output contract enforcement;
- stop/restart/shutdown semantics owned by the deterministic runtime;
- external-dispatch boundary behavior.

The existing final runtime tests are the baseline and remain mandatory.

### Layer B: concrete backend conformance

Purpose: prove that the final Sento adapter works against Sento itself rather than a stand-in.

Owner: `star-sento-compat` test systems.

The production `star-sento-compat` ASDF system may keep Sento as a soft/dynamic runtime dependency. The integration test system, however, MUST explicitly load/provide Sento so the concrete backend is exercised in CI.

Recommended test-system split:

```text
star-sento-compat-tests
  narrow unit/port-wiring tests

star-sento-compat-integration-tests
  test-only hard dependency on Sento/cl-gserver
  actual actor-system boot
  actual actors, message boxes, dispatcher workers
  actual lifecycle and teardown
```

Do not weaken production dependency boundaries merely to make tests convenient. Put hard backend dependencies in the test/integration layer when possible.

### Layer C: full mini actor-system topology

A concrete actor integration suite MUST use a multi-actor system. One actor receiving one host-language call is a smoke test, not evidence for an actor system.

Minimum topology:

```text
                    +------------------+
                    | coordinator/probe|
                    +--------+---------+
                             |
                 mailbox messages only
                             |
             +---------------+---------------+
             |                               |
             v                               v
     +---------------+              +----------------+
     | worker/echo   |              | stateful actor |
     | tell + reply  |              | serialized cnt |
     +---------------+              +----------------+
             |
             v
     +----------------+
     | lifecycle obs. |
     | when supported |
     +----------------+
```

The topology should be intentionally small, but every communication edge under assertion must be a real actor message.

Suggested responsibilities:

- `coordinator/probe`: receives completion/observation messages and gives tests a bounded way to observe results;
- `worker/echo`: proves `tell`, sender/reply, and request/reply mechanics;
- `stateful actor`: proves actor-owned serialized state transitions under concurrent submission;
- `lifecycle observer`: proves termination/watch only after final watch semantics exist.

Do not inspect implementation-private slots as the primary correctness oracle if the same property can be observed through actor messages or public actor-system APIs.

## Test harness rules

The concrete integration harness should provide a small reusable fixture API.

### `with-real-actor-system`

The fixture MUST:

1. create a fresh actor system for the test or suite isolation unit;
2. use unique actor names to prevent cross-test registry collisions;
3. register teardown before executing the test body;
4. shut the system down under `unwind-protect` even when assertions fail;
5. fail the test if teardown cannot terminate owned actor resources;
6. retain useful diagnostics about actors and observations on failure.

### Waiting and synchronization

Correctness MUST NOT depend on arbitrary `sleep` calls.

Use bounded synchronization based on the backend's public completion/future/reply mechanisms. Any wait must have:

- an explicit upper bound;
- a diagnostic timeout failure;
- no unbounded polling loop;
- no hidden global state shared across tests.

A tiny scheduler-yield/backoff may be used inside a bounded helper when no stronger primitive exists, but elapsed sleep time itself cannot be the assertion oracle.

### Failure diagnostics

A failing real-actor test should report enough state to debug concurrency rather than merely returning `NIL`.

Where public APIs permit, include:

- actor names/paths;
- actor running/liveness observations;
- messages observed by the probe actor;
- outstanding correlation identifiers/futures;
- operation being awaited;
- timeout bound;
- teardown outcome.

## Lifecycle-equivalence matrix

The deterministic runtime and Sento backend are not identical implementations. Equivalence means they implement the same StarLang-level claim where the final adapter says they do.

| Semantic claim | Deterministic runtime evidence | Concrete Sento evidence | Immediate status |
| --- | --- | --- | --- |
| spawn/register | final `starlang-runtime` actor | actual Sento actor created via final compat API | required now |
| async tell | real `star-mailbox` enqueue | actual Sento message-box/dispatcher delivery | required now |
| ask/reply | deterministic correlation cell | concrete Sento ask/reply adapter | required now if adapter exposes ask |
| per-actor serialization | deterministic non-reentrant dispatch | concurrent submissions to real Sento stateful actor | required now |
| stop | final runtime stop behavior | final compat -> actual Sento stop | required now |
| shutdown | final runtime shutdown | final compat -> actor-system shutdown | required now |
| lookup/liveness | final runtime/directory contract | real actor-system lookup/running API if exposed | required when final API claims it |
| remoting | final protocol/adapter contract | existing Sento two-process smoke through final API | migrate in this slice |
| failure mapping | typed deterministic failure | backend condition translated at final compat boundary | required for claimed operations |
| watch/unwatch | not yet final semantic authority | actual Sento watch support | do not claim until implemented/tested |
| restart/generation | StarLang generation semantics | backend lifecycle primitive + explicit StarLang mapping | do not claim direct equivalence yet |
| supervision strategy | future `star-supervisor` | backend lifecycle substrate | later slice |

If the backend cannot implement a StarLang semantic claim exactly, the adapter MUST either define an explicit translation contract or report the operation as unsupported. Tests must not paper over semantic mismatches.

## Concrete Sento adapter extraction

The current actor-runtime migration matrix names concrete Sento extraction as the exact next slice. Issue #42 adopts that direction and tightens its evidence requirements.

The implementation slice should:

1. move/finish production `asys:`, `ac:`, `act:`, and `rem:` operations behind final `star-sento-compat` functions;
2. keep package lookup/dynamic loading policy coherent with the desired soft production dependency;
3. switch `prototype/bbp-remoting-runtime-example.lisp` and related domain-remoting callers to final compat entry points;
4. ensure existing two-process/BBP smoke exercises those final entry points;
5. remove corresponding direct production Sento calls from `prototype/` after migration;
6. add concrete final-system tests using an actual actor system;
7. retain unit port-forwarding tests only as wiring tests, clearly distinct from integration evidence.

### Ask semantics

Sento exposes both synchronous and asynchronous ask forms. StarLang research prefers asynchronous actor-to-actor request/reply because a synchronous nested actor wait can produce wait cycles.

The concrete adapter uses Sento's asynchronous `ask`, which returns a future
and creates a temporary reply actor. Waiting is permitted only at an outer
caller/test boundary; an actor receive handler must not hold mailbox execution
while synchronously awaiting another actor. A timeout completes the future with
Sento's handler-error tuple, which `sento-future-result` maps to
`sento-ask-failure-error`. An explicit sender is rejected because Sento owns the
temporary reply actor used for correlation.

The current deterministic runtime still has a known separate limitation: nested A -> B -> A `ask` remains synchronous at the StarLang semantic layer and terminates via deterministic timeout instead of split-phase continuation progress. This design does not claim to solve that gap.

## CI contract

Real actor evidence must be a pull-request gate, not a nightly curiosity.

The flake-locked Nix environment supplies Sento to a separate hard-dependency
integration system. CI and Nix must continue to ensure that:

1. deterministic actor tests still run;
2. `star-sento-compat` wiring tests run;
3. real Sento actor-system integration tests run in a fresh SBCL process;
4. any remoting/two-process test required by the migrated adapter runs in a controlled process boundary;
5. failures preserve useful logs;
6. teardown failure is a test failure;
7. the job has a hard timeout to prevent CI deadlock from consuming a runner forever.

If remoting setup proves materially slower than local concrete actor tests, it may be a separate required CI job. It may not become optional solely because it is inconvenient.

## What counts as a full actor-system test

A test counts as full actor-system evidence only when all of the following are true:

- an actual actor system/runtime instance is constructed;
- at least two application/test actors communicate through real mailboxes/message boxes;
- the operation under assertion crosses the final production adapter/runtime boundary;
- actor work executes under the backend's normal dispatcher/scheduler rather than direct test invocation;
- observations come from public operations or actor-delivered probe messages;
- all waits are bounded;
- all runtime resources are shut down;
- the same test would fail if the concrete actor backend were materially broken.

A test does NOT count merely because a struct is named `actor`, a lambda is called `receive`, or a fake port records `(:tell ...)` in a list. Humans have invented enough ceremonial abstractions already.

## Acceptance gates for issue #42

The implementation PR is ready only when:

- concrete Sento tests boot a real actor system;
- a multi-actor topology proves real mailbox-mediated behavior;
- concrete spawn/tell/ask-reply/stop/shutdown claims execute through final compat entry points;
- any claimed lookup/liveness/remoting behavior also executes through final compat entry points;
- deterministic and concrete backend tests share a documented semantic matrix;
- mock/injected-port tests are explicitly classified as unit wiring evidence;
- `prototype/` no longer owns the migrated direct Sento calls;
- CI/Nix installs/loads the backend for integration tests and runs them on PRs;
- the test suite uses bounded waits and unconditional teardown;
- no leaked actor system/threads remain after a successful run;
- final runtime/protocol/compat suites are green;
- the nested split-phase ask problem is not falsely marked solved.

## Non-goals for this slice

Do not broaden this work into:

- a rewrite of StarLang semantics around Sento;
- a mandatory Sento dependency for every StarLang use case;
- journal/replay implementation;
- lease/fencing implementation;
- capability-system implementation;
- full `star-supervisor` policy implementation before base backend equivalence is green;
- split-phase continuation semantics for nested `ask` unless explicitly spun into a follow-up slice;
- Franklin-specific runtime policy.

## Follow-on order

After issue #42 is green, the preferred sequence remains:

1. finish concrete backend/lifecycle equivalence;
2. extract/finalize wire lifecycle and deterministic transport/runtime-directory authority;
3. implement split-phase actor request continuation semantics and static wait-cycle rejection;
4. implement `star-supervisor` strategies/intensity over the proven lifecycle substrate;
5. then integrate durable journal/replay, leases/fencing, and richer capability/runtime systems.

This keeps the actor substrate honest before durable/distributed semantics are layered on top of it.
