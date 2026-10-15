# StarLang Generic Database Runtime

Status: design for #147 and #148.

This document defines the ownership and source-design target for generic database access in StarLang. It does **not** claim that the proposed `database` and `database-operation` source forms compile today.

The current compiler accepts specification declarations `import`, `scalar`, `enum`, `document`, `predicate`, `message`, and `lifecycle`, plus program declarations including `actor`. The checked-in database message and actor fixtures therefore use only those current forms. New database declarations must be added to the same closed parser/validator/lowering pipeline; they must never be read with the Common Lisp reader.

## Ownership

StarLang owns:

- the closed S-expression grammar;
- portable database operation IR;
- typed request/result/error contracts;
- operation capabilities and effect classification;
- actor contracts;
- canonical manifest serialization;
- transport-neutral execution semantics.

A host such as StarIntel Server owns:

- credentials and secret files;
- DSNs/endpoints;
- connection pools;
- backend client libraries;
- tenant/principal policy;
- backend-specific prepared operation catalogs;
- deployment/runtime provider configuration.

Portable StarLang source must never contain passwords, tokens, access keys, credential-bearing URLs, private connection strings, AWS account data, or arbitrary host code.

## Universal rule: databases are actors

Application actors do not receive raw backend clients. They communicate with database actors using typed StarLang messages.

```text
application actor
      |
      | Star lifecycle message
      v
database read/write actor
      |
      | normalized DB operation
      v
runtime adapter registry
      |
      +-- CouchDB
      +-- PostgreSQL
      +-- Neo4j
      +-- OrientDB
      +-- Prolog / star-logic-protocol
```

Read and write authority are distinct. A read actor must be structurally unable to obtain mutation authority.

## Current compileable contract

`fixtures/star-database-core.star` defines the first portable wire vocabulary using the existing `spec-library` / `message` grammar.

`fixtures/actor-compiler/database-reader.star`,
`database-writer.star`, and `database-a2a-reader.star` use the existing actor grammar:

```lisp
(actor name
  (:runtime native|external
   :service-uri "star://domain:address:actor-name"
   :accepts (...)
   :produces (...)
   :handler handler-name
   :restart permanent
   :mailbox (bounded 256)
   :capabilities (...)))
```

Native actor bodies remain tracked by #69. Until that lands, a native DB actor uses a typed Common Lisp handler behind the normal StarLang actor boundary.

## Proposed database grammar

The target grammar extends the **existing** program surface rather than inventing a second file format.

Conceptual source:

```lisp
(database intel
  (:access read-write))

(database-operation person-by-id
  (:database intel
   :access read
   :kind lookup
   :parameters
   ((id string :required))
   :result org.starintel/core@1/person
   :cardinality optional-one
   :idempotency readonly
   :capabilities (databaseRead)))

(database-operation store-person
  (:database intel
   :access write
   :kind upsert
   :parameters
   ((document org.starintel/core@1/person :required)
    (expectedRevision string :optional))
   :result org.starintel/database@1/db-write-result
   :idempotency keyed
   :capabilities (databaseWrite)))
```

These forms are **proposed syntax for #147**. They become real only after they are added to the closed parser, validation, normalized IR, manifest emission, tests, and Nix/ASDF gates.

### `database`

A portable database declaration names a logical data capability, not a physical server.

Required concepts:

- logical id;
- allowed access mode;
- optional consistency requirements;
- optional transaction requirements;
- optional stream/subscription support.

It must not contain a DSN or credentials.

### `database-operation`

A named operation declares:

- logical database;
- read/write/transaction/subscribe/logic access class;
- semantic operation kind;
- typed parameters;
- typed result;
- cardinality;
- idempotency/precondition contract;
- required capabilities;
- deadline/result budgets;
- source span/provenance.

The source names the operation. A deployment binds that operation to a trusted prepared implementation.

## Portable operation classes

The initial closed operation vocabulary should cover:

### Read

- lookup
- query
- search
- aggregate
- traverse
- view
- logic
- head
- changes/subscription

### Write

- insert
- update
- upsert
- delete
- bulk-write

### Transaction

- begin/execute/commit as one bounded runtime operation;
- declared isolation/consistency requirement;
- no unbounded interactive transaction held by an untrusted remote client.

### Stream

- subscribe;
- resume from typed cursor/checkpoint;
- cancel;
- ordered events;
- bounded buffering/backpressure.

## Backend mapping

The portable operation is intentionally not SQL, Cypher, Mango, Orient SQL, or a Prolog goal.

Trusted deployment mappings implement a named operation per backend.

### CouchDB

Examples:

- lookup -> document GET;
- query/search -> Mango;
- view -> registered design-document view;
- write -> revision-aware PUT/DELETE;
- bulk-write -> `_bulk_docs`;
- subscribe -> `_changes`.

### PostgreSQL

- named prepared SELECT;
- named INSERT/UPDATE/DELETE;
- bounded transaction;
- cursor/result paging;
- LISTEN/NOTIFY or a later explicit CDC adapter.

Untrusted Actor2Actor messages cannot submit SQL text.

### Neo4j

- named parameterized Cypher operations;
- typed graph projection;
- bounded transaction;
- traversal result limits.

Untrusted Actor2Actor messages cannot submit Cypher text.

### OrientDB

- named prepared document/graph operations;
- typed projection;
- transaction support through the generic transaction contract.

Untrusted Actor2Actor messages cannot submit Orient SQL text.

### Prolog

Prolog is both a logic backend and a database-like fact source.

Reuse `star-logic-protocol` and `star-logic-ir`.

A DB/logic actor invokes a trusted named operation with typed bindings. Remote input cannot name arbitrary modules/files or supply a raw goal.

Typical flow:

```text
db-read actor
  -> named Star logic call
  -> SWI-Prolog / n-Prolog adapter
  -> typed fact/result messages
  -> consumer actor or LISA expert
```

## Capabilities

Initial capability vocabulary:

```text
databaseRead
databaseWrite
databaseTransaction
databaseSubscribe
databaseAdmin
```

Runtime provider access, network access, and secret access are separate capabilities. A database capability does not implicitly grant them.

## Actor patterns

### Read actor

A read actor accepts application or generic DB read requests and produces typed results/errors. Its runtime handle exposes only read methods.

### Write actor

A write actor requires `databaseWrite`; mutation requests carry an idempotency identity and optional optimistic precondition.

### Transaction actor

A transaction actor is bounded by deadline, operation count, result size, and isolation requirements. It reaches a terminal commit/abort/failure state exactly once.

### Subscription actor

A subscription actor owns a bounded stream session with explicit sequence, checkpoint, cancellation, and backpressure.

### Logic/fact actor

A logic actor calls a named Star logic operation and emits typed facts/results. This is the preferred bridge for Prolog-to-LISA expert pipelines.

## Error model

Portable failures should distinguish at least:

- invalidRequest
- unauthorized
- capabilityDenied
- databaseUnavailable
- operationUnavailable
- timeout
- cancelled
- conflict
- preconditionFailed
- transactionAborted
- resultLimitExceeded
- malformedBackendResult
- backendFault

Backend-specific diagnostics can be attached as redacted evidence but must not become portable control flow.

## Idempotency and writes

A write operation must declare one of:

- `keyed`: replay-safe under the Star message/idempotency identity;
- `preconditioned`: requires a revision/version predicate;
- `nonReplayable`: runtime must not blindly retry after an unknown outcome.

Unknown outcome is not success.

The actor/runtime journal records the operation identity and terminal outcome before replay can manufacture another write.

## Multi-database workflows

A user-defined StarLang actor may compose several logical DB actors:

```text
request
  -> CouchDB read actor
  -> Prolog fact actor
  -> Neo4j traversal actor
  -> PostgreSQL write actor
  -> typed reply
```

No distributed transaction is implied. Cross-backend workflows use actor/message idempotency, durable journals/outboxes, and compensation where required.

## Required compiler work

#147 owns:

1. add the database declaration heads to the closed grammar;
2. source-aware validation;
3. normalized DB IR;
4. deterministic portable manifest;
5. canonical JSON;
6. compiler errors for secrets/raw dynamic query text;
7. static capability/effect checks.

#148 owns the typed DB actor contract and read/write authority rules.

#150 owns Actor2Actor transport-neutral remote semantics.

#151 owns execution-provider placement.

## Acceptance invariant

A program may change database implementation without changing its application actor protocol when the bound named operations provide equivalent semantics.

That is the point of the layer: **actors depend on typed data capabilities, not database vendors.**
