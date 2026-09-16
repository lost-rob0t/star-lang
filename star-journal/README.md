# star-journal

`star-journal` is the final Common Lisp runtime-journal port used for bounded
runtime coordination recovery. It stores journal values; it is not an
application database or a general serializer for arbitrary Common Lisp objects.

## Value ownership

`runtime-journal-append` takes ownership by value before validation or backend
publication. The backend append callback receives an owned snapshot, so later
mutation of caller-owned strings, conses, vectors, or nested leaves cannot
rewrite recorded history.

`runtime-journal-replay` snapshots backend-returned data before validating it and
returns that owned snapshot. Mutating a replay result therefore cannot change a
later replay or mutate backend-owned state.

The shared final boundary is
`staractorprotocol:snapshot-portable-wire-value`. It admits:

- `nil` and `t`;
- integers and symbols;
- strings, copied by value;
- cons/list structures, recursively copied;
- vectors, recursively copied, with strings handled as strings.

Maps remain ordinary portable list representations such as keyword plists or
string-keyed alists. Hash tables, functions, pathnames, streams, arbitrary CLOS
instances, floating-point values, and other host objects are not journal values
at this boundary. Cycles are rejected. Shared but acyclic structures are copied
by value rather than preserving mutable alias identity.

## Snapshot limits

The default portable snapshot budgets are deliberately finite:

| Budget | Limit |
| --- | ---: |
| Maximum recursive depth | 64 |
| Maximum visited values | 100,000 |
| Maximum string length | 1,048,576 characters |
| Maximum aggregate copied string length | 8,388,608 characters |
| Maximum vector length | 65,536 elements |

Recursive depth measures nested value structure. Advancing through sibling cells
of one proper list does not consume additional depth; those cells still consume
the visited-value budget. Proper-list spines are traversed iteratively, so host
call-stack depth follows semantic nesting rather than sequential list
cardinality. This keeps a long shallow journal history from becoming invalid or
unsafe merely because it contains more events.

The aggregate string budget counts every copied string occurrence, including
repeated references to the same source string. Together with the visited-value
and container limits, this prevents a compact shared input from expanding into
unbounded copied string data during snapshotting.

The reusable protocol primitive accepts explicit smaller/different positive
limits for callers and focused tests. `star-journal` uses the defaults for both
append and replay boundaries. A rejected append does not invoke the backend
append callback and therefore cannot partially extend prior journal history.

These limits bound ownership/snapshot traversal. They do **not** claim that the
current file-backed Common Lisp reader is allocation-bounded before it creates a
value; corrupt/truncated file-reader hardening remains separate work tracked by
issue #82.

## Verification

Run the final systems directly:

```sh
asdf:test-system :star-actor-protocol
asdf:test-system :star-journal
```

The journal tests cover caller mutation after append, replay-result mutation,
nested mutable leaves, vectors, custom backend isolation, cycle/depth/size
rejection, long shallow replay, aggregate alias-amplification bounds,
failed-append history preservation, file round-trip behavior, and prototype
independence.
