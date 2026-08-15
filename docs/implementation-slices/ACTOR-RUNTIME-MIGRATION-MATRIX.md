# StarLang actor/runtime migration matrix

Status: active extraction ledger

The one-authority rule applies to every row: after a behavior is migrated, the prototype may retain only compatibility composition around the final implementation. A final package shell is not counted as migrated behavior.

## Status legend

- **FINAL** — the listed final ASDF system owns the behavior.
- **PARTIAL** — a coherent final subset is authoritative, but a richer prototype layer remains to extract.
- **PROTOTYPE** — working behavior is still owned by `prototype/`.
- **SURFACE ONLY** — the final API names the operation, but no migrated production behavior is claimed yet.

## Migration matrix

| Behavior | Prototype owner before/remaining | Final target system | Dependencies | Tests proving behavior | Migration status | Next extraction action |
| --- | --- | --- | --- | --- | --- | --- |
| actor definition | `actor-wire-prototype.lisp` still owns source actor lowering; old `prototype.lisp` contains historical toy definitions | `starlang-runtime` for executable definition; `starlang-compiler` later for lowering | `star-actor-protocol` | `starlang-runtime-tests.lisp`; prototype actor/compiler tests | PARTIAL | Move portable actor IR/lowering out of prototype compiler code without moving runtime behavior into the compiler |
| actor reference | none in final before this slice; opaque refs appear in runtime-directory/remoting prototype code | `star-actor-protocol` | STAR service URI | `star-actor-protocol-tests.lisp`; stale-ref runtime test | **FINAL in this slice** | Reuse the same reference type from runtime directory and Sento/remoting adapters |
| actor lifecycle | cl-gserver facade, domain gateway/remoting code | `starlang-runtime`, then `star-supervisor` | actor ref, mailbox | runtime spawn/stop/restart/shutdown tests | PARTIAL | Extract supervision-driven lifecycle and Sento lifecycle hooks |
| actor registration | deterministic dispatcher, runtime directory, domain remoting prototype | `starlang-runtime` local; runtime directory target still to choose/finalize | actor ref | final runtime registry tests | PARTIAL | Extract runtime-directory registration and remote registration |
| STAR URI resolution | compatibility wrappers in prototype; canonical parser already extracted by PR #22 | `star-actor-protocol` | none | `star-actor-protocol-tests.lisp` | **FINAL** | Switch remaining runtime-directory/remoting callers to the final reference type |
| spawn | cl-gserver facade uses injected actor-of; BBP creates Sento actor systems directly | `starlang-runtime`; `star-sento-compat` adapter | actor ref, mailbox | explicit `SPAWN` + registration test; compat port forwarding test | PARTIAL | Move concrete Sento actor-system/spawn adapter behind `star-sento-compat` |
| stop | cl-gserver facade and remoting adapter contain Sento stop paths | `starlang-runtime`; `star-sento-compat` adapter | mailbox | stop/restart/shutdown runtime tests; compat forwarding test | PARTIAL | Extract concrete Sento stop implementation |
| restart | prototype restart/recovery logic is distributed across facade/remoting/journal paths | `starlang-runtime`, then `star-supervisor` | generation, mailbox, journal later | restart/generation/stale-ref runtime tests | PARTIAL | Move policy enforcement to supervisor and connect durable recovery later |
| generation | not represented by the old final direct-call path | `star-actor-protocol` + `starlang-runtime` | actor ref | generation advance and stale reference tests | **FINAL for local runtime in this slice** | Carry generation through runtime directory/remoting |
| tell | cl-gserver facade and Sento remoting adapter; deterministic dispatcher queue is separate wire path | `starlang-runtime` + `star-mailbox`; Sento translation in `star-sento-compat` | mailbox, actor ref | tell-not-synchronous, FIFO, mailbox-full tests | **FINAL for local runtime in this slice** | Extract concrete Sento tell; later connect wire dispatcher to the same semantic contract |
| ask | lifecycle envelopes provide request/reply correlation; cl-gserver facade proves async result flow | `starlang-runtime`; Sento translation in `star-sento-compat` | mailbox, correlation | ask/reply, timeout, two-actor exchange, non-reentrant self-ask tests | **FINAL for deterministic local semantics in this slice** | Extract Sento ask semantics/equivalence; wire lifecycle envelopes remain separate |
| reply | `message-lifecycle-prototype.lisp` and dispatcher own wire reply envelopes | `star-actor-protocol` for wire contract; `starlang-runtime` for local completion | correlation | final ask/reply test; prototype lifecycle/dispatcher tests | PARTIAL | Extract command/reply/error envelope contract to `star-actor-protocol` |
| error | lifecycle/dispatcher prototype owns wire error envelopes | `star-actor-protocol` for wire contract; `starlang-runtime` for local failures | correlation, contracts | handler failure and contract rollback runtime tests; prototype lifecycle tests | PARTIAL | Extract typed wire error lifecycle |
| cancel | `message-lifecycle-prototype.lisp`, deterministic dispatcher, transport adapter | `star-actor-protocol` + `starlang-runtime` | lifecycle, dispatcher | prototype cancellation/race tests | PROTOTYPE | Extract lifecycle envelope contract before adding local cancellation helpers |
| mailbox | deterministic dispatcher used an internal list queue; cl-gserver tests used a fake queue; actor manifests declared bounded mailboxes | `star-mailbox` | none | `star-mailbox-tests.lisp`; runtime tell/order tests | **FINAL primitive in this slice** | Replace prototype dispatcher internal queue with `star-mailbox` when dispatcher extraction begins |
| mailbox bounds | manifest declaration normalized in prototype; no real old final runtime bound | `star-mailbox` + `starlang-runtime`; compiler declaration later | actor definition | capacity/full/closed tests | **FINAL runtime enforcement in this slice** | Lower prototype mailbox declaration into final actor IR/runtime capacity |
| dispatch | `deterministic-dispatcher-prototype.lisp`, transport adapter, domain gateways | `starlang-runtime` local scheduler; final wire dispatcher boundary still to extract | mailbox, lifecycle | dispatch-next/run-until-idle tests; prototype dispatcher tests | PARTIAL | Extract deterministic wire dispatcher without creating a second queue or handler path |
| dispatcher selection | Sento/prototype configuration and approved design | `star-sento-compat` / runtime configuration | adapter API | prototype integration evidence only | PROTOTYPE | Define final portable dispatcher assignment after concrete Sento adapter extraction |
| state ownership | old final runtime directly called handlers; prototype Sento/fake path serialized execution | `starlang-runtime` | mailbox | state transition, rollback, self-ask/non-reentrancy tests | **FINAL for local runtime in this slice** | Prove the same transition contract through real Sento |
| Sento integration | `cl-gserver-runtime-facade-prototype.lisp`, `sento-remoting-domain-adapter.lisp`, BBP remoting runtime | `star-sento-compat` | Sento/cl-gserver | compat port tests; prototype cl-gserver/BBP Sento smoke tests | PARTIAL | Move concrete Sento/remoting calls into `star-sento-compat` and switch prototype callers |
| watch | no stable final implementation; approved compatibility API requires it | `star-sento-compat` | Sento | none final | SURFACE ONLY | Implement only while extracting concrete Sento adapter, backed by real integration test |
| unwatch | same | `star-sento-compat` | Sento | none final | SURFACE ONLY | Same concrete adapter slice |
| link | same | `star-sento-compat` | Sento | none final | SURFACE ONLY | Same concrete adapter slice |
| supervision | restart metadata plus Sento/domain behavior; final system is a shell | `star-supervisor` | runtime, mailbox, Sento compat | prototype behavior only | PROTOTYPE | Extract after basic Sento lifecycle equivalence is green |
| restart strategy | actor manifest declares permanent/transient/temporary; final runtime stores metadata but does not enforce a supervisor strategy | `star-supervisor` | actor definition, lifecycle | prototype actor tests; local restart tests | PARTIAL | Implement strategy/intensity under supervisor, not a standalone runtime helper |
| runtime directory | `runtime-directory-prototype.lisp` | final runtime-directory ownership must be placed in runtime/protocol or a dedicated final system per approved extraction | actor ref, STAR URI | `runtime-directory-tests.lisp` | PROTOTYPE | Extract using final `star-actor-reference`; preserve missing vs unavailable distinction |
| remote actor registration | domain remoting/gateway/BBP prototype | `star-sento-compat` plus runtime directory | Sento remoting, actor ref | BBP domain remoting + two-process smoke | PROTOTYPE | Move Sento remoting adapter first, then registry translation |
| remote dispatch | domain remoting/gateway/BBP prototype | `star-sento-compat` + `starlang-runtime` dispatch contract | lifecycle, runtime directory | BBP remoting and two-process smoke | PROTOTYPE | Preserve existing smoke while switching to final compat API |
| journal | `runtime-journal-port-prototype.lisp`, `domain-remoting-journal-prototype.lisp` | `star-journal` | lifecycle, canonical encoding | prototype journal/recovery tests | PROTOTYPE | Defer until dispatcher/runtime-directory authority is extracted |
| replay | dispatcher idempotency plus journal/recovery prototype | `star-journal` + runtime | journal, lifecycle | BBP replay/recovery tests | PROTOTYPE | Move with journal, preserving exact replay behavior |
| idempotency | lifecycle envelope + deterministic dispatcher + BBP run-id logic | `star-journal`/runtime protocol boundary | lifecycle, journal | dispatcher/BBP idempotency tests | PROTOTYPE | Extract after lifecycle wire contract |
| lease | domain remoting lease prototype | `star-lease` | runtime directory, journal | domain remoting lease tests | PROTOTYPE | Move after remote registration is final-owned |
| fencing | domain remoting lease/recovery behavior | `star-lease` | lease, generation | prototype lease/remoting tests | PROTOTYPE | Preserve generation/lease epoch separation during extraction |
| external actor | actor-wire + transport/dispatcher prototype owns actual dispatch | `starlang-runtime` definition/resolve; `star-adapter-sdk`/ports for execution | actor ref, transport | final external boundary test; prototype transport tests | PARTIAL | Extract external dispatch so final runtime routes through an adapter instead of raising `dispatch required` |
| process transport | process tool runner/domain prototype; final system is a shell | `star-process-port` | adapter SDK | prototype process/remoting tests where applicable | PROTOTYPE | Defer until base external actor dispatch contract is final |
| HTTP transport | not actor-runtime-owned; final HTTP port was already implemented before this slice | `star-http-port` | none actor-specific | `star-http-port` and `star-scrape` tests | FINAL (pre-existing) | Keep independent; connect only through adapter SDK when external dispatch is extracted |
| capabilities | actor manifests declare capability tags; runtime directory carries them; final system is a shell | `star-capability` | actor IR, runtime directory | prototype manifest/directory tests | PROTOTYPE | Extract after runtime directory/ref ownership is final |

## Authority changes in this slice

1. `star-actor-protocol` now owns the portable generation-bearing actor reference.
2. `star-mailbox` now owns bounded FIFO queue mechanics and typed accepted/full/closed delivery results.
3. `starlang-runtime` now owns deterministic local actor execution through those mailboxes. `tell` no longer executes a handler synchronously; `ask` uses the same enqueue/dispatch path.
4. `starlang-runtime` now owns local spawn, stop, restart/generation, stale-reference rejection, serialized state mutation, rollback on handler/contract failure, and runtime shutdown.
5. `invoke-actor` remains only as a compatibility name over `ask`; it is no longer an independent direct-call implementation.
6. `star-sento-compat` now owns the generic Sento/cl-gserver operation port. The prototype cl-gserver façade retains only a compatibility constructor and composition around the final port.
7. Wire command/reply/error/cancel, deterministic transport dispatch, runtime directory, remoting, journal/replay/idempotency, leases/fencing, and concrete Sento remoting remain prototype-owned and are not reimplemented beside the prototype in this slice.

## Prototype reduction metric

Git comparison against `main` and the green CI metric artifact report:

- aggregate `prototype/**/*.lisp`: **19,868 LOC before → 19,845 LOC after**, delta **-23 LOC**;
- `prototype/cl-gserver-runtime-facade-prototype.lisp`: **+30 / -53**, net **-23 lines**;
- the removed lines are the prototype-owned runtime-port struct and operation wrappers;
- the remaining additions are compatibility composition and a standalone-test dependency loader that both call the final `star-sento-compat` implementation.

The aggregate `prototype/` directory still contains substantial runtime authority; this slice intentionally does not count untouched prototype code as migrated.

## Exact next extraction slice

Extract the concrete Sento actor-system/remoting adapter behind `star-sento-compat`:

1. move production `asys:`, `ac:`, `act:`, and `rem:` actor/remoting calls from `prototype/sento-remoting-domain-adapter.lisp` into a final `star-sento-compat` adapter;
2. switch `prototype/bbp-remoting-runtime-example.lisp` and domain-remoting callers to that final compatibility API;
3. retain the BBP domain fixtures and two-process Sento smoke as integration evidence, but make them exercise final compatibility entry points;
4. add lifecycle-equivalence cases shared by deterministic and Sento-backed execution for spawn, tell, ask/reply, stop, restart/generation, failure, and shutdown where Sento supports the semantic operation;
5. remove the corresponding direct production Sento calls from `prototype/` once callers are switched.

After that slice, extract the wire lifecycle contract and deterministic transport dispatcher/runtime directory using the already-final actor reference and mailbox primitives. Do not add supervisor/journal/lease implementations until the base execution path and concrete Sento adapter share one semantic contract.