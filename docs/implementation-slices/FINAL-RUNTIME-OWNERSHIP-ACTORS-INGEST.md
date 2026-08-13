# Final runtime ownership: actors and ingest servers

## Problem

`prototype/` is still the authoritative StarLang implementation even though the repository already exposes final `star-*` and `starlang-*` ASDF systems. In particular, `starlang-runtime` currently contains only a package placeholder while actor compilation, actor runtime behavior, service URI dispatch, runtime-directory logic, and domain-server behavior remain owned by `starlang-prototype`.

This slice exists to make that transitional state end for the runtime path. The target is not a second implementation layered beside `prototype/`; source ownership must move into final systems and the prototype system must become a compatibility/test shell over those final systems until it can be deleted.

## Required user-visible capability

The final StarLang systems must be able to:

1. define/compile actors;
2. instantiate and register actor runtimes;
3. address actors by `star://domain:address:actor-name`;
4. dispatch messages to local or external actors through the existing runtime-neutral protocol boundary;
5. define and run ingest servers that accept inbound data/messages and feed StarLang actors/dataflows without embedding HTTP/process/RabbitMQ implementation details in normalized IR;
6. expose those capabilities from final ASDF systems without loading `starlang-prototype`.

## Existing implementation to migrate, not duplicate

The current prototype already contains proven behavior that should be extracted along dependency boundaries:

- `prototype/actor-wire-prototype.lisp`
  - actor compilation
  - runtime binding
  - portable actor manifests
  - wire envelopes
- `prototype/service-uri-prototype.lisp`
  - `star://domain:address:actor-name` parsing and canonicalization
- `prototype/runtime-directory-prototype.lisp`
  - service lookup and liveness
- `prototype/deterministic-dispatcher-prototype.lisp` and related dispatcher files
  - deterministic actor dispatch
- `prototype/domain-server-core-prototype.lisp`
  - keyed server definition/runtime engine
- `prototype/prototype.lisp`
  - legacy actor definition/registration/invocation and dataflow behavior
- adapter/transport prototype files
  - runtime-neutral transport boundary that ingest servers should use

The migration must move authoritative source into final systems. Do not copy these files into final directories while leaving another authoritative copy in `prototype/`.

## Target ownership

Use the existing final system boundaries unless dependency analysis proves a small additional final system is necessary:

- `star-actor-protocol`
  - actor contract IR
  - actor/service identity
  - wire envelopes and portable actor protocol data
- `starlang-runtime`
  - actor registry/instantiation/lifecycle
  - runtime directory
  - deterministic dispatch orchestration
  - domain/ingest server runtime orchestration
- `star-adapter-sdk`
  - inbound/outbound adapter abstraction used by ingest servers
- concrete port systems such as `star-http-port` and `star-process-port`
  - transport implementations only
- `starlang-compiler`
  - parsing/validation/compilation of actor and ingest-server declarations into runtime-neutral IR

`starlang-runtime` must not depend on `starlang-prototype`.

## Ingest-server model

First inspect the approved StarLang research/design documents and current grammar before choosing syntax. If an approved ingest-server declaration already exists, implement it exactly. If no approved syntax exists, add a narrowly scoped design document in this PR before implementing the language form.

The resulting semantics must follow these constraints:

- an ingest server is a supervised runtime endpoint, not an HTTP-specific language primitive;
- normalized IR describes accepted message/document contracts, routing target(s), capabilities, restart/mailbox policy, service identity, and adapter requirements;
- concrete HTTP/process/RabbitMQ/etc. configuration lives behind adapter manifests/ports;
- ingest servers can route to actors by actor name and canonical STAR service URI;
- inbound messages go through the same validation, idempotency, acknowledgement, and dispatch lifecycle used by ordinary actor commands;
- no LLM or dynamic host-language evaluation is part of dispatch;
- service registration and discovery use the existing `star://domain:address:actor-name` design.

## Migration rules

1. No final system may load files from `prototype/` as its implementation.
2. No duplicate authoritative function/package definitions may exist in both final and prototype trees.
3. Compatibility packages are allowed only as thin forwarding/re-export shells.
4. Final systems must form an acyclic ASDF dependency graph.
5. Tests should move with ownership. Transitional prototype tests may remain only as compatibility/end-to-end tests that load final systems.
6. `ci/target-systems.txt`, SBCL CI, and `nix flake check -L` must exercise the actual final implementation.
7. The CLI/package entry point should load final systems, not `starlang-prototype`, once the runtime slice is complete.

## Acceptance tests

Add final-system tests proving, in fresh SBCL processes where appropriate:

- `(asdf:load-system :star-actor-protocol)` exposes real actor/service protocol APIs;
- `(asdf:load-system :starlang-runtime)` exposes real runtime APIs and does not load `starlang-prototype`;
- a native actor can be defined/compiled, registered, invoked, and supervised;
- an external actor can be compiled with `star://quasar:localhost:user-hunt` and resolved through the runtime directory;
- `star://bbp:localhost:nmap` remains a valid independent service identity;
- actor service URI/name mismatches are rejected;
- an ingest server can be compiled/created and can accept a fixture ingest message such as `org.starintel/fec@1/ingest-page`;
- the ingest server routes a validated inbound message to a target actor/dataflow;
- stopped, missing, malformed, duplicate/idempotent, and invalid-contract cases fail deterministically;
- portable/canonical manifests remain byte stable or intentionally update the frozen fixture with a documented compatibility change;
- loading/testing `starlang-prototype` still passes during the transition, but it delegates to final systems for migrated runtime behavior.

## README/status exit condition

Only after the authoritative runtime/compiler path has moved should README stop claiming that the real implementation remains in `prototype/`.

The desired end state is that `prototype/` contains compatibility/end-to-end tests or disappears entirely; `starlang-prototype` must no longer be the product runtime loaded by the CLI, Nix package, or primary CI contract.
