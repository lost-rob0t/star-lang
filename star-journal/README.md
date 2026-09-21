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

## File replay bounds

The file-backed port preserves the readable event representation produced by
`make-file-runtime-journal-port`, but it no longer hands an unbounded file
straight to the host Common Lisp reader. Replay first enforces finite source
budgets and a data-only reader subset, then invokes `read` with `*read-eval*`
bound to `nil`, then applies the normal owned-value and event validation.

The pre-reader budgets are:

| Budget | Limit |
| --- | ---: |
| Maximum file size | 67,108,864 bytes |
| Maximum reader nesting depth | 64 |
| Maximum reader tokens | 50,000 |
| Maximum records | 50,000 |
| Maximum source string length | 1,048,576 characters |
| Maximum aggregate source string length | 8,388,608 characters |
| Maximum `#*` bit-vector length | 65,536 bits |

The admitted reader subset covers the forms emitted for supported journal
values: ordinary atoms, strings, proper or dotted lists, vectors, bounded array
syntax used by SBCL for readable specialized one-dimensional arrays, bit-vectors,
keywords, package-qualified symbols, and uninterned symbols. The writer uses
`*print-circle* nil`, so shared-but-acyclic values are serialized by value and do
not require graph labels on disk.

Reader evaluation (`#.`), graph labels (`#n=`/`#n#`), numeric dispatch prefixes
such as compact oversized vectors, reader abbreviations, structure/pathname/
character/radix dispatch extensions, and other non-writer syntax are rejected
with `star-journal-error` before `read` can execute or expand them. Numeric array
prefixes remain rejected; only the non-prefixed readable array form observed from
the existing SBCL writer is admitted, with its following structure subject to
the same depth/token limits.

Malformed or truncated input is never silently dropped. Reader failures are
collapsed to bounded `star-journal-error` reports rather than interpolating an
attacker-controlled reader condition. A file that grows while a replay snapshot
is being read is also rejected instead of returning a partial prefix.

These file limits are intentionally in addition to the portable snapshot limits:
the first layer bounds host-reader work and allocation, while the second layer
continues to own and validate the resulting StarLang values.

## Verification

Run the final systems directly:

```sh
asdf:test-system :star-actor-protocol
asdf:test-system :star-journal
```

The journal tests cover caller mutation after append, replay-result mutation,
nested mutable leaves, vectors, custom backend isolation, cycle/depth/size
rejection, long shallow replay, aggregate alias-amplification bounds,
failed-append history preservation, file round-trip behavior, bounded corrupt
file replay, disabled reader evaluation, malformed/truncated records, and
prototype independence. The corrupt-file watchdog cases run replay in isolated
SBCL children with a hard timeout and constrained heap so a regression cannot
hang or exhaust the parent test process.
