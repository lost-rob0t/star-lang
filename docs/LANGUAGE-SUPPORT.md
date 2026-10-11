# StarLang language support contract

StarLang is intentionally polyglot.

## Permanent invariants

- Common Lisp is a permanent first-class compiler and runtime backend.
- Kotlin/JVM is an additive peer runtime backend, not a Common Lisp replacement.
- The StarLang specification, normalized IR, wire contracts, canonical fixtures,
  and conformance tests define semantics across implementations.
- Runtime parity never authorizes deletion or demotion of another supported backend.
- Removing or demoting a supported backend requires a new explicit operator-approved decision.

## Current support matrix

| Language | Compiler/runtime role |
| --- | --- |
| Common Lisp | first-class compiler + runtime |
| Kotlin | peer JVM runtime + generated executable target |
| Java | JVM consumer ABI / generated boundary |
| Python | generated portable boundary / external actor integration |
| TypeScript | generated portable boundary / external actor integration |
| Nim | generated boundary + native/edge adapter option |
| Go | generated portable boundary |
| Rust | generated portable boundary |
| Emacs Lisp | generated portable boundary |
| Prolog | generated portable boundary + logic integration |

A generated boundary does not automatically claim a full native runtime.
Additional full runtimes may be added only by passing the same conformance suite.

## CI expectation

Repository policy and reviews must reject changes that describe Common Lisp as
temporary, fallback-only, legacy-only, retired, or scheduled for deletion as a
consequence of Kotlin/JVM parity work.

## Domain/service protocol integration slice

The Common Lisp `star-actor-protocol` system additionally owns the local
Actor2Actor task/stream projection and pure domain/service admission guards.
See [scope and verification limits](DOMAIN-SERVICE-CONTRACT.md). No new wire
schema, generated binding or JVM implementation is claimed by this slice;
all existing supported language roles above remain unchanged.

`star-actor-wire` is the shared Common Lisp canonical JSON codec extracted from
the existing ZMQ actor adapter. Rabbit and ZMQ projections share its exact bytes.
Native/Python/JS adapters may inject this authority rather than implement a second
serializer; golden lifecycle fixtures are provided, not a new generated language model.

## Bounded SWI relation integration

`star-logic-adapter-swi` owns a Common Lisp implementation of the existing logic
protocol for bounded `relation-neighbors` over the trusted Prolog `star_relation/4`
bridge. SWI executes the query; Lisp owns admission, session/operation lifecycle,
limits and process cleanup. This does not claim general query conformance, a
Kotlin engine adapter, a new generated language model, RPC/actor integration or
canonical server persistence. See [the adapter contract](../star-logic-adapter-swi/README.md).


## Installed Common Lisp/SWI host package

Issue #215 exports `packages.<system>.star-lang-logic-runtime`. It reuses the
existing CLI producer source and SBCL/SWI dependencies. `bin/starlang-sbcl`
sets the installed ASDF source registry and exact SWI executable; ordinary
SBCL arguments remain available to trusted host applications. This is a local
host executable, not an untrusted RPC evaluation endpoint.
`bin/starlang-swipl` exposes that same SWI package. Nix consumers obtain the
immutable source tree through `package.sourceRoot` or `share/star-lang` and
must pin the producer input and verify the identities their service requires.
No source checkout, credentials or live provider are required at runtime.

`checks.installed-logic-runtime` runs existing protocol, IR and real SWI adapter
suites from an empty temporary working directory using the installed wrapper.
The existing full StarLang check remains in force. Outputs follow the producer's
existing default systems; actual build/start evidence is limited to the systems
reported by CI. This does not make Star-KB's Linux supervisor portable and does
not complete its installed HTTP/ZMQ checks. No Kotlin or generated-boundary
ownership changes.
