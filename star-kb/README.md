# star-kb

`star-kb` is the backend-neutral Common Lisp storage boundary for StarLang
symbolic catalogs and actor-owned knowledge bases.

It deliberately does **not** implement a second actor runtime, Prolog engine,
Datalog evaluator, or compiler. StarLang owns those semantics; a KB backend owns
persistence, indexes and graph traversal.

## Data model

An **entry** is a portable StarLang record with:

- stable `id` and `namespace`;
- semantic `kind` (for example `actor`, `document`, `predicate`, `dataset`);
- optional dataset identity;
- a flat string-keyed `fields` alist whose keys preserve canonical schema/path
  spelling;
- portable metadata and provenance.

A **relation** has stable identity, namespace, source, predicate and target plus
optional dataset, metadata and provenance.

All values are copied through
`staractorprotocol:snapshot-portable-wire-value` at the public boundary. Host
objects, cyclic graphs and unbounded aliases therefore do not become backend
state accidentally.

## Common Lisp

```lisp
(asdf:load-system :star-kb)

(defparameter *kb* (star-kb:make-memory-kb-store))

(star-kb:kb-put-entry
 *kb*
 (star-kb:make-kb-entry
  "person:ada"
  :kind "person"
  :dataset "people"
  :fields '(("name" . "Ada") ("country" . "US"))))

(star-kb:kb-find-entries-by-field *kb* "default" "country" "US")
```

The memory backend is a reference implementation for tests and local fixtures.
Use `star-kb-tek9` for durable embedded storage.

## Ownership boundary

This package is intentionally independent from `starlang-runtime`: application
knowledge is not runtime journal state. Actors may own/use a `kb-store`, while
runtime generation, message settlement, leases and replay remain owned by their
existing final systems.
