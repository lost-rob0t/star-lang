# StarLang specification

Status: **normative implementation contract for the final compiler surface**.
The approved StarLang research/design corpus remains semantic design authority;
this document turns that design into the concrete source, portable-manifest,
wire, and generated-binding contract enforced by the final systems. Executable
ASDF, CI, conformance tests, and runtime behavior outrank stale implementation
status prose, but they do not silently redefine the approved semantic design.

StarLang is a closed, data-oriented language for declaring portable Star
contracts and actor interfaces. It is not a general replacement for Common
Lisp. The compiler is implemented in Common Lisp; generated bindings are
projections for consumers in other languages.

## 1. Source model

Star source is UTF-8 S-expression syntax parsed by the closed StarLang parser.
The parser does not expose the host Common Lisp reader and does not permit
arbitrary reader evaluation. Source identifiers, strings, integers, keywords,
and lists are converted into syntax objects carrying source spans and origin
data before lowering.

Normative field names use ASCII lower camelCase. A compiler must reject source
field names that would require silent wire-name rewriting.

## 2. Specification library

A portable contract begins with one `spec-library` form:

```lisp
(spec-library "org.example/contracts@1"
  (:version "1.0.0"
   :digest "sha256:...")

  (import "org.example/base@1"
    :version "1.0.0"
    :digest "sha256:...")

  ...declarations...)
```

`version` is exact. Imported identities are digest locked and do not float to a
newer version merely because one exists.

The closed specification declaration vocabulary is:

- `import`
- `scalar`
- `enum`
- `document`
- `predicate`
- `message`

Unknown declaration heads fail compilation.

## 3. Type system

Built-in portable wire types are:

- `any`
- `string`
- `symbol`
- `iso-date`
- `iso-datetime`
- `decimal`
- `integer`
- `boolean`
- `map`
- `reference`

Container type expressions are `(list TYPE)` and `(optional TYPE)`. A named
scalar, enum, or document may be used where a field type is accepted.

`decimal` is represented as a decimal string on the wire so precision is not
lost by runtimes whose native numeric representation differs.

### 3.1 Scalar

```lisp
(scalar confidence
  (:base decimal
   :minimum 0
   :maximum 1
   :scale 4))
```

A scalar is a named restriction over a built-in wire type. Supported portable
constraints are `pattern`, `format`, `minimum`, `maximum`, and `scale` where
applicable. A scalar base is always one of the built-in wire types.

### 3.2 Enum

```lisp
(enum state (pending running completed failed))
```

Enum values are closed and unique.

### 3.3 Document

```lisp
(document task
  (:persistence persistent)
  (id string :required)
  (displayName string :optional))

(document scheduled-task
  (:extends task
   :persistence persistent)
  (runAt iso-datetime :required))
```

Persistence is `persistent` or `transient`. Inheritance is single-parent,
additive, and acyclic. A locally available parent is validated recursively.
An imported parent may remain an external qualified contract reference until a
registry/runtime resolves the imported contract set.

Field presence and field value are separate concepts. `:required` means the
key must exist. `(optional TYPE)` means an explicit null/empty wire value may
also be represented according to the target adapter.

### 3.4 Predicate

```lisp
(predicate owns
  (:source org.example/person@1
   :destination org.example/account@1))
```

Predicates define typed graph edges. A local endpoint must be a document.
A non-local endpoint must be a qualified external contract identifier and is
resolved by the contract registry before typed graph operations are executed.

### 3.5 Message

```lisp
(message enrich
  (target reference :required)
  (options map :optional))
```

Messages are closed field contracts used by actor/runtime envelopes. Unknown
message fields are rejected by portable wire validation.

## 4. Actors

Actors are compiled separately from specification libraries and projected into
the portable manifest:

```lisp
(actor enrichment-worker
  (:runtime native
   :service-uri "star://starintel:localhost:enrichment-worker"
   :accepts (org.example/enrich@1)
   :produces (org.example/person@1)
   :handler enrichment-worker-handler
   :restart permanent
   :mailbox (bounded 256)
   :capabilities (network)))
```

Two runtimes are part of the closed actor contract:

- `native` — names a trusted runtime handler;
- `external` — names a protocol and endpoint adapter.

Portable actor manifests never carry live cells, queues, sockets, process IDs,
credentials, API keys, or executable closures. They contain runtime-neutral
wire contract data only.

`service-uri`, when present, must be canonical. `accepts` and `produces` are
bounded unique contract identifiers. Standalone actor manifests may legally
reference contracts not embedded in the same manifest; those references are
data and gain no authority merely by being declared. Duplicate capabilities
are invalid. Metadata keys use lower camelCase and metadata values are bounded
scalar strings/integers.

## 5. Portable manifest v1

The portable manifest is the language-neutral boundary consumed by runtimes,
registries, canonical JSON, and binding generators. Its top-level shape is
closed:

```text
wire-version
library
imports
types
predicates
messages
actors
```

Manifest validation is fail-closed. Implementations reject:

- unknown or duplicate plist keys;
- unknown top-level or contract keys;
- malformed imports or non-sha256 import locks;
- duplicate contract names, enum values, fields, capabilities, or metadata keys;
- invalid local type references;
- unknown unqualified field types;
- cyclic local document inheritance;
- local predicate endpoints that are not documents;
- malformed runtime/protocol/endpoint combinations;
- non-canonical actor service URIs;
- over-limit collections and identifiers;
- malformed metadata and scalar constraints.

Qualified external type/document references may remain unresolved inside a
portable manifest because imports and standalone actors are resolved by a
registry layer. Runtime payload validation that needs their concrete fields
must resolve and merge the relevant contract definitions first.

A manifest received from a peer and a manifest emitted locally by the compiler
pass through the same validator. Peer-controlled strings remain data and must
not be interned into the Lisp image by validation.

## 6. Object stub generation

The compiler owns one manifest-driven object generator. Every supported target
projects every portable object kind:

- scalar
- enum
- document
- predicate
- message
- actor

References to non-embedded contracts also receive an explicit opaque external
stub, so generated source never contains an undefined Star contract symbol just
because the contract is supplied by another library or actor registry entry.
Generated target names are deterministic and collision-safe: compact local
names are used when unique, otherwise the qualified contract identity is folded
into the generated identifier.

Current targets are:

```text
common-lisp
python
typescript
nim
java
kotlin
go
rust
elisp
prolog
```

Generated source is a compatibility surface, not semantic authority. The
validated portable manifest remains authoritative for wire field spelling,
requiredness, inheritance identity, actor contracts, and graph predicates.

The public compiler entry points are:

```lisp
(starlangcompiler:generate-object-bindings manifest :python)
(starlangcompiler:generate-all-object-bindings manifest)
```

## 7. Wire invariants

- Portable manifest wire version is `1`.
- JSON/document/message field names preserve lower camelCase source spelling.
- Peer-controlled strings are never interned as a validation side effect.
- Unknown fields fail closed for typed messages/documents.
- References carry `schema` and `id` string fields.
- Decimal wire values use strings.
- Actor capability declarations describe requested/required capabilities; host
  policy grants authority. A manifest cannot grant itself authority.
- Secrets and live transport/runtime handles are not portable manifest data.

## 8. Compatibility

A change is compatible when an existing valid manifest retains its meaning and
existing consumers can continue to validate the same contract. Adding a new
optional field is normally additive. Renaming/removing fields, changing a field
type, changing persistence, changing enum closure, or widening actor authority
requires an explicit compatibility/version decision.

A generated-language convenience must never weaken the portable manifest. When
a host language cannot express a Star constraint directly, generated code may
use a broader host type only while runtime validation still enforces the Star
contract.

## 9. Conformance requirements

A specification change is not complete until tests prove the final path:

1. closed source parse;
2. source-aware lowering;
3. portable manifest emission;
4. hardened manifest validation;
5. canonical wire projection where applicable;
6. generation for every supported language target;
7. deterministic collision handling and opaque external contract stubs;
8. runtime-boundary validation for actor/message semantics.

Prototype files may expose compatibility wrappers but must not contain a second
authoritative implementation of these semantics.
