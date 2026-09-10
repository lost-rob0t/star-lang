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
| spawn | prototype facade is compatibility composition only | `starlang-runtime`; `star-sento-compat` adapter | actor ref, mailbox | deterministic spawn tests; real Sento actor-system integration | **FINAL for local deterministic and concrete paths** | Carry final spawn/ref identity into later remote-directory extraction |
| stop | prototype remoting wrapper delegates to final compatibility entry points | `starlang-runtime`; `star-sento-compat` adapter | mailbox | deterministic lifecycle tests; blocking real Sento stop/lookup evidence | **FINAL for base local lifecycle** | Define richer policy only in `star-supervisor` |
| restart | prototype restart/recovery logic is distributed across facade/remoting/journal paths | `starlang-runtime`, then `star-supervisor` | generation, mailbox, journal later | restart/generation/stale-ref runtime tests | PARTIAL | Move policy enforcement to supervisor and connect durable recovery later |
| generation | not represented by the old final direct-call path | `star-actor-protocol` + `starlang-runtime` | actor ref | generation advance and stale reference tests | **FINAL for local runtime in this slice** | Carry generation through runtime directory/remoting |
| tell | prototype remoting composition delegates; deterministic wire dispatcher remains separate migration debt | `starlang-runtime` + `star-mailbox`; Sento translation in `star-sento-compat` | mailbox, actor ref | deterministic FIFO/bounds tests; real multi-actor Sento topology | **FINAL for local deterministic and concrete paths** | Connect the wire dispatcher to the same semantic contract later |
| ask | wire lifecycle envelopes remain prototype debt | `starlang-runtime`; asynchronous Sento translation in `star-sento-compat` | mailbox, correlation | deterministic ask tests; real Sento future/reply and timeout mapping | **FINAL for ordinary local request/reply** | Implement split-phase deterministic nested ask separately; extract wire envelopes later |
| reply | `message-lifecycle-prototype.lisp` and dispatcher own wire reply envelopes | `star-actor-protocol` for wire contract; `starlang-runtime` for local completion | correlation | final ask/reply test; prototype lifecycle/dispatcher tests | PARTIAL | Extract command/reply/error envelope contract to `star-actor-protocol` |
| error | lifecycle/dispatcher prototype owns wire error envelopes | `star-actor-protocol` for wire contract; `starlang-runtime` for local failures | correlation, contracts | handler failure and contract rollback runtime tests; prototype lifecycle tests | PARTIAL | Extract typed wire error lifecycle |
| cancel | `message-lifecycle-prototype.lisp`, deterministic dispatcher, transport adapter | `star-actor-protocol` + `starlang-runtime` | lifecycle, dispatcher | prototype cancellation/race tests | PROTOTYPE | Extract lifecycle envelope contract before adding local cancellation helpers |
| mailbox | deterministic dispatcher used an internal list queue; cl-gserver tests used a fake queue; actor manifests declared bounded mailboxes | `star-mailbox` | none | `star-mailbox-tests.lisp`; runtime tell/order tests | **FINAL primitive in this slice** | Replace prototype dispatcher internal queue with `star-mailbox` when dispatcher extraction begins |
| mailbox bounds | manifest declaration normalized in prototype; no real old final runtime bound | `star-mailbox` + `starlang-runtime`; compiler declaration later | actor definition | capacity/full/closed tests | **FINAL runtime enforcement in this slice** | Lower prototype mailbox declaration into final actor IR/runtime capacity |
| dispatch | `deterministic-dispatcher-prototype.lisp`, transport adapter, domain gateways | `starlang-runtime` local scheduler; final wire dispatcher boundary still to extract | mailbox, lifecycle | dispatch-next/run-until-idle tests; prototype dispatcher tests | PARTIAL | Extract deterministic wire dispatcher without creating a second queue or handler path |
| dispatcher selection | Sento/prototype configuration and approved design | `star-sento-compat` / runtime configuration | adapter API | prototype integration evidence only | PROTOTYPE | Define final portable dispatcher assignment after concrete Sento adapter extraction |
| state ownership | prototype facade is compatibility composition | `starlang-runtime`; concrete execution translated by `star-sento-compat` | mailbox | deterministic rollback tests; concurrent-producer real Sento counter | **FINAL for base local paths** | Supervision/restart policy remains separate |
| Sento integration | prototype BBP/domain code is a thin composition wrapper | `star-sento-compat` | Sento/cl-gserver | wiring tests plus hard-dependency real actor-system integration; BBP smoke uses final entry points | **FINAL for claimed local operations and concrete remoting translation** | Extend claims only when real evidence exists; watch/link remain unsupported |
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
6. `star-sento-compat` owns the generic port and concrete local Sento construction, spawn, tell, asynchronous ask/reply, lookup/liveness, stop, shutdown, and remoting translation.
7. The real integration system hard-depends on the flake-locked Sento package while production compatibility loading remains soft.
8. Prototype Sento/remoting files retain composition and end-to-end fixtures only; static CI rejects direct backend calls returning outside the final boundary.
9. Wire command/reply/error/cancel, deterministic transport dispatch, runtime directory, journal/replay/idempotency, and leases/fencing remain prototype-owned and are not reimplemented beside the prototype in this slice.

## Prototype reduction metric

CI reports the exact branch-relative prototype LOC delta on every pull request.
This slice removes obsolete backend audit markers and keeps the remaining Sento
prototype adapter as composition only. The aggregate `prototype/` directory
still contains substantial unrelated runtime authority; untouched code is not
counted as migrated.

## Exact next extraction slice

Extract the wire lifecycle contract and deterministic transport
dispatcher/runtime directory using the already-final actor reference, mailbox,
and concrete Sento boundary. Do not broaden that work into supervision,
journal, or lease policy. Split-phase nested ask remains a separately tracked
semantic slice rather than an accidental consequence of backend integration.
