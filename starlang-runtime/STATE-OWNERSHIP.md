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
second copier or serializer. The admitted transition-state values are the existing
portable value grammar:

- `NIL` and `T`;
- integers;
- symbols;
- characters;
- strings;
- proper lists whose members are admitted values; and
- vectors whose elements are admitted values.

Mutable strings, lists, and vectors are copied recursively. Circular aggregates,
improper lists, unsupported host objects/resources, nesting beyond 128 levels, and
more than 65,536 aggregate nodes are rejected deterministically. At the native actor
boundary these snapshot failures are reported as `actor-contract-error`; failed
admission does not advance the invocation count or replace committed state.

The depth/node limits and portable-value grammar remain owned by
`star-actor-protocol`. `starlang-runtime` owns only the transition-time use of that
contract and the commit boundary.

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
