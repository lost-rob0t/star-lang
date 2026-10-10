# Native actor state ownership

`starlang-runtime` treats a native actor transition as a commit-after-success operation.
The actor instance owns the committed state; handlers never receive that object graph
directly.

For each native dispatch, the runtime snapshots the committed state into an owned
working value and passes that snapshot to the handler. A handler that signals an
error, returns an output rejected by its output contract, or completes after its
actor incarnation becomes stale cannot mutate the committed state through the
working value. Mutating the working value and returning only one value also does
not implicitly commit it.

A handler requests a state commit by returning a second value. After output
validation, the runtime snapshots that next-state value again before committing it.
The committed state therefore does not retain mutable aliases owned by handler code.
A later mutation through a retained handler reference cannot retroactively change the
actor instance.

## Closed bounded state-value grammar

Transition working/commit snapshots reuse
`star-actor-protocol:snapshot-portable-wire-value`; `starlang-runtime` does not own a
second copier or serializer. The transition-state grammar is therefore exactly the
existing portable snapshot grammar: `NIL`/`T` and other symbols, integers, strings,
cons structures whose components are themselves admitted values, and vectors whose
elements are admitted values. Strings, conses, and vectors are copied recursively;
shared-but-acyclic mutable input is copied by value rather than preserved as an
alias.

The runtime uses the portable snapshot defaults owned by `star-actor-protocol`:

- maximum nested depth: 64;
- maximum aggregate nodes: 100,000;
- maximum single-string length: 1,048,576 characters;
- maximum aggregate string length: 8,388,608 characters; and
- maximum vector length: 65,536 elements.

Circular aggregates, unsupported host objects/resources, and values exceeding any
of those bounds are rejected deterministically. At the native actor boundary these
snapshot failures are reported as `actor-contract-error`; failed admission does not
advance the invocation count or replace committed state.

The grammar and resource limits remain owned by `star-actor-protocol`.
`starlang-runtime` owns only the transition-time use of that contract and the commit
boundary.

## Lifecycle interaction

The existing dispatch-incarnation fence remains authoritative. A stop, restart,
unregister, or runtime shutdown that makes a handler completion stale prevents that
completion from committing state. Restart continues to preserve the last committed
state while replacing the mailbox/generation; it does not preserve an abandoned
working copy.

## Scope boundary

This contract covers transition-time isolation for issue #77. It does **not** change
initial-state construction/admission semantics; caller/factory ownership at actor
creation is tracked separately by issue #78. It also does not add durable state,
event sourcing, effect continuations, wire-dispatcher semantics, or a second actor
runtime.
