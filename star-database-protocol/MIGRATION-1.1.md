# Database change-stream 1.1 migration

The portable database library remains `org.starintel/database@1`, while its
library version advances from 1.0.0 to 1.1.0.

Version 1.1 adds `db-stream-page`. A page carries the checkpoint it consumed
(`inputCheckpoint`) and the checkpoint that becomes durable only after all
items have been applied (`outputCheckpoint`).

Checkpoints are opaque strings. Portable runtimes compare them only for exact
identity. They do not parse CouchDB sequence tokens, increment them, sort them,
or assume they are numeric.

Every stream item map carries a stable non-empty `changeId`. Applying a change
is idempotent by that id. A reducer may replay already-applied changes after a
crash, but the durable checkpoint never advances until the whole page reports
either applied or duplicate.

The 1.0 `db-result` / `kind=stream-page` vocabulary remains available for
older readers. A 1.0 adapter can be wrapped into 1.1 only when it can provide:

1. the exact committed input checkpoint;
2. a non-empty output checkpoint; and
3. a stable change id for every item.

If those facts are unavailable, migration fails closed rather than guessing
progress.

For StarIntel Server's CouchDB adapter, the request `since` token maps to
`inputCheckpoint` and `_changes.last_seq` maps to `outputCheckpoint`.
Cursor persistence belongs after reducer commit. RabbitMQ and ZeroMQ are
delivery transports only; neither owns checkpoint or idempotency semantics.
