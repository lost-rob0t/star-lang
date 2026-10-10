# StarIntel Prolog KB

`star-prolog-kb` is the Common Lisp StarLang extension for a durable StarIntel
logic/catalog store. The source reader is the canonical StarLang reader; this
package does **not** parse a second Lisp-ish language. A `.star` unit is read and
macro-expanded by `starlang-compiler`, then checked against the grammar below.

The durable store is Tek9. StarIntel documents are Tek9 documents and graph
nodes. A StarIntel `relation` document is also mirrored as a Tek9 graph edge.
Raw Prolog blocks are preserved as source and are appended verbatim when a
Prolog snapshot is materialized.

## Grammar

The notation below describes the extension grammar after the canonical StarLang
reader has produced syntax objects.

```text
prolog-kb-unit :=
  (prolog-kb STRING kb-options declaration*)

kb-options :=
  (:version STRING
   :runtime tek9
   :persistence persistent
   [:protocol STRING])

declaration := schema | index | prolog

schema :=
  (schema IDENTIFIER
    (:source STRING
     :version STRING
     [:digest STRING]))

index :=
  (index IDENTIFIER
    (:source DOCUMENT-TYPE
     :fields (selector+)
     [:kind auto|multi|unique]))

selector := FIELD | (FIELD FIELD+)

prolog :=
  (prolog IDENTIFIER
    (:source STRING
     [:kind source|rules|bootstrap])
    STRING)
```

`selector` is a field path. `username` selects a top-level field;
`(profile provider)` selects a nested value. Multiple selectors make one
compound index. `auto` and `multi` use Tek9 DUPSORT postings; `unique` is a
unique secondary index and rejects list-valued root fields.

The grammar deliberately reuses keywords already owned by the closed StarLang
reader (`:version`, `:runtime`, `:persistence`, `:protocol`, `:source`,
`:fields`, `:kind`, `:digest`). That keeps one reader and one syntax-object
model.

## Automatic indexes

Every effective field in the referenced StarLang schema is indexed. Inherited
fields count: if `user` extends `document`, the base fields still participate in
the automatic index plan.

Automatic indexes are global by field name:

```text
field/id
field/dtype
field/dataset
field/sourceUrls
field/tags
field/username
...
```

A scalar field emits one posting. A `(list T)` field emits one posting per list
element. `field/id` is unique; other automatic indexes are non-unique. Values
are converted to deterministic, type-tagged strings before they reach Tek9 so
strings, numbers, symbols, structured maps, and references cannot collide by
accidental printing.

The global shape is intentional: `field/dataset = X` can find every document
kind in dataset `X`. Use a custom `:source` index when a document-type-specific
index is useful.

## Defining new indexes

Indexes can be declared in StarLang:

```lisp
(index userByPlatform
  (:source user
   :fields (platform username)
   :kind auto))

(index provider
  (:source document
   :fields ((externalIds provider))
   :kind multi))
```

They can also be added to an already-open KB from Common Lisp:

```lisp
(star-prolog-kb:define-index
 kb
 "byDatasetAndType"
 :source "document"
 :fields '("dataset" "dtype")
 :kind :auto)
```

`DEFINE-INDEX` registers the Tek9 secondary index and, by default, rebuilds it
from existing documents. `OPEN-STARINTEL-KB` reserves LMDB named-DB headroom
above the schema's initial index count so a normal number of runtime indexes can
be added without reopening the environment.

## Tek9 mapping

| StarIntel / StarLang | Tek9 |
| --- | --- |
| document | main Tek9 document + graph node |
| document `id` | Tek9 primary document id / graph external node id |
| every field | `field/<fieldName>` secondary index |
| list field | multi-valued DUPSORT index postings |
| custom `index` | Tek9 secondary index |
| `relation` document | document + node + graph edge |
| `source/predicate/destination` | graph edge source/predicate/target |
| raw `prolog` block | `star/prolog-source` Tek9 document DB |

Document, node, and relation-edge writes participate in one explicit Tek9 write
transaction.

## Raw Prolog bridge

The generated snapshot exposes only three stable bridge predicates:

```prolog
star_document(Id, DType, Dataset).
star_field(Id, Field, Value).
star_relation(RelationId, SourceId, Predicate, DestinationId).
```

Then each StarLang `(prolog ...)` body is appended verbatim. The library does
not translate those rules into a home-grown logic syntax.

Example:

```lisp
(prolog graph-rules
  (:source "starintel/graph-rules" :kind rules)
  ":- table reachable/2.
reachable(A,B) :- star_relation(_, A, _, B).
reachable(A,C) :- star_relation(_, A, _, B), reachable(B,C).")
```

`PROLOG-SNAPSHOT-STRING` returns the complete generated program;
`WRITE-PROLOG-SNAPSHOT` writes it to a stream. Execution remains behind
StarLang's logic backend boundary rather than introducing another SWI-Prolog
runner in this package.

## Lisp surface

```lisp
(defparameter *program*
  (star-prolog-kb:load-prolog-kb-file
   #P"fixtures/starintel-prolog-kb.star"))

(defparameter *spec*
  (starlangcompiler:compile-spec-library
   (starlangcompiler:read-star-syntax
    (uiop:read-file-string #P"fixtures/starintel-core.star"))))

(defparameter *kb*
  (star-prolog-kb:open-starintel-kb
   *program* *spec*
   :path #P"./var/starintel-kb/"))

(star-prolog-kb:put-starintel-document *kb* document)
(star-prolog-kb:query-field *kb* "username" "alice")
(star-prolog-kb:query-index *kb* "userByPlatform" "mastodon" "alice")
```

Tek9 is loaded lazily at the storage boundary. Grammar and index planning can be
used without Tek9 installed; opening the durable KB requires the `tek9` ASDF
system.