# star-kb-tek9

`star-kb-tek9` is the durable embedded backend for `star-kb`. It uses
[lost-rob0t/tek9](https://github.com/lost-rob0t/tek9), which stores documents,
secondary indexes and graph adjacency on LMDB.

## Layout

Catalog records live in one named document database, `star-kb/records`, so the
number of LMDB DBIs stays bounded. The adapter registers durable indexes for:

- entry `(namespace, kind)`;
- entry `(namespace, dataset)`;
- every entry `(namespace, canonical-field-path, portable-value)`;
- relation `(namespace, predicate)`;
- relation `(namespace, dataset)`.

Graph nodes and edges use Tek9's constant `graph/v2` physical keyspace. A KB
namespace maps to a Tek9 logical graph name, so repeated entry/edge IDs in other
namespaces remain isolated without allocating DBIs per namespace.

Relations are intentionally dual-materialized. The indexed catalog record owns
metadata and provenance; the Tek9 edge owns the traversal hot path. Both writes,
all secondary-index changes and adjacency changes occur inside **one Tek9/LMDB
write transaction**. Failed endpoint validation therefore rolls the record back
instead of leaving a half-written catalog.

Deleting an entry also removes all incident relation records in the same
transaction before Tek9 removes the node and its adjacency.

## Common Lisp

```lisp
(asdf:load-system :star-kb-tek9)

(defparameter *kb*
  (star-kb-tek9:open-tek9-kb-store #P"/var/lib/star/catalog/"))

(star-kb:kb-put-entry
 *kb*
 (star-kb:make-kb-entry
  "actor:userhunt"
  :kind "actor"
  :dataset "actors"
  :fields '(("runtime" . "sento")
            ("language" . "common-lisp"))))

(star-kb:kb-close *kb*)
```

## Scope

This package is storage only. It does not claim Prolog/Datalog/tabling semantics
or wire itself into `starlang-runtime`. Those semantics remain behind the
backend-neutral StarLang logic/runtime boundaries.
