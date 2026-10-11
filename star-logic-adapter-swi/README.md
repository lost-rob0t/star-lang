# star-logic-adapter-swi

Final Common Lisp ownership for the SWI-Prolog MQI backend boundary.

This system owns worker/transport trust and one bounded data-only relation query: exact executable
identity, embedded MQI startup, UTF-8 byte framing, authentication, MQI version
validation, a repository-owned bootstrap handshake, process-isolated sessions,
health, and orderly shutdown/reaping, plus the relation primitive below.

It deliberately does **not** implement `star.logic.query/1`, portable query
operations, arbitrary fact mutation, tabling, constraints, proofs, cancellation escalation,
or worker pooling/reset.

## Executable and build identity

`make-swi-backend` requires an explicit executable path. It never discovers
`swipl` through ambient `PATH`. The path is resolved to its exact file, the
version is obtained by launching that exact executable with `--version`, and
`backendBuildId` is the SHA-256 digest of the resolved executable bytes. Under
Nix, descriptor metadata also retains the exact store executable path.

Before every session open, the adapter rechecks path, version, and executable
digest. The worker itself then proves the expected version triplet through the
trusted bootstrap predicate. Any mismatch fails closed.

## MQI framing

Outbound commands are trusted adapter-owned Prolog messages encoded using MQI's
UTF-8 byte-count framing. Incoming responses use the same bounded frame header,
with heartbeat bytes handled before the header, but the counted response body is
parsed as JSON rather than reinterpreted as caller-controlled Prolog text.

The decoder accepts both the raw JSON response body emitted by the pinned SWI
runtime and the generic MQI dot/newline suffix when that suffix is present. Frame
length, UTF-8 decoding, and JSON parsing remain bounded and fail closed.

The real integration gate currently proves SWI-Prolog 10.0.2 negotiating MQI
protocol 1.0.

## Trusted bootstrap

`prolog/star_logic_bootstrap.pl` is part of this ASDF system. Its path is derived
internally from ASDF and cannot be supplied by a caller. Its SHA-256 digest is
recorded at backend construction and revalidated immediately before every worker
launch, before any subprocess is spawned. The adapter's private MQI grammar loads
only this file and invokes only its fixed handshake and relation predicates.

There is no exported raw Prolog goal, predicate, consult, or file-loading API.



## Bounded relation-neighbors primitive

The Common Lisp adapter now implements the existing generic protocol for one
fixed named operation. This is a building block for a shared KB service. It is
not an actor, RPC server, durable KB, general query profile or full StarIntel E2E.
Semantic profiles/capabilities remain empty, so general `:auto` selection still
cannot mistake this primitive for `star.logic.query/1` conformance.

`apply-logic-fact-delta` accepts a closed string-keyed alist containing only
`relations`, whose value is a proper list of closed records with exactly `id`,
`source`, `predicate`, and `destination` strings. Despite the generic method's
name, this slice supports **whole-snapshot replacement only**. It reuses the
`star_relation(RelationId, SourceId, Predicate, DestinationId)` bridge documented
in [the existing Prolog KB slice](https://github.com/lost-rob0t/star-lang/pull/120).
The source relation ID is retained in every result as its evidence reference.
No inferred relation is asserted and no canonical document schema is changed.

The adapter copies/validates the input, rejects duplicate IDs, sorts by ID and
computes SHA-256 over the deterministic bracketed decimal-code-point row array
(no whitespace). The method returns `:applied` or `:unchanged`, and this digest
as a second value. Identical reordered snapshots replay identically. SWI applies
replacement in a transaction. Every operation pins the snapshot and trusted
bootstrap digest. Facts cannot change while any operation has pending results.
Facts are ephemeral; closing/replacing a worker requires explicit snapshot replay.

`invoke-logic-operation` accepts only `"relation-neighbors"`. Its parameters
are a closed alist with required `node`, `predicate`, and `direction` strings.
Direction is exactly `out`, `in`, or `both`; it selects original source or
destination matching and never invents an inverse predicate. Returned rows
retain their original source/predicate/destination direction. A self-loop is
returned once for `both`. Output is sorted by relation ID.

Optional `limits` is a closed alist with `answers` and/or `output-bytes` positive
integers. Limits can only lower these hard adapter maxima:

- 256 facts; 512 Unicode scalar characters per nonempty string (NUL rejected)
- 131,072 aggregate UTF-8 input string bytes per snapshot
- 128 answers; 65,536 UTF-8 bytes for the complete JSON array of result records
- 128 total operation handles per session; open a new session after exhaustion

The query fetches at most answer-limit plus one rows in actual SWI. Any answer
or output overflow fails the operation before any result is published, rather
than silently reporting a truncated result as complete. Caller strings enter
MQI as numeric character lists and are converted to Prolog strings; quoting,
newlines and Prolog-looking text remain data. No user-provided predicate/goal,
module name, rule source or file path can enter executable grammar.

An operation starts `:pending`; its first `next-logic-result` performs the bounded
query and returns `(values record :answer)` until exhausted, then a terminal
`:completed` or `:no-answer`. Cancellation discards pending/unread results and
preserves terminal states. Per-session locking serializes transport calls.
This synchronous slice does not interrupt a query already holding that lock:
MQI uses a two-second query timeout; SBCL additionally uses a five-second
transport watchdog and disposes/reaps the worker on transport failure.
Cross-thread in-flight cancellation escalation remains unimplemented.

Invalid input leaves the current facts intact. Query limit failures leave the
session usable. A crashed worker, malformed reply or uncertain mutation retires
the session and reaps its process; callers must create a fresh session and
explicitly replay their snapshot. Foreign/closed-session handles are rejected.
Status can still inspect an owned terminal operation after failure/close.

The real integration tests exercise the public generic methods with actual SWI,
including isolation, no-answer, Unicode/source-injection strings, snapshot replay,
input/output limits, pending cancellation, terminal stability and crash cleanup.
They do not substitute a Lisp evaluator for Prolog.

## Remaining integration gates

The shared KB service still needs canonical StarLang-generated document projection
and exact rule-package reconciliation with `starintel-labs/star-kb`; that project's
historical projector and this four-field bridge are not interchangeable. Reusable
domain/inference rules remain Star KB-owned. Shared durable storage ownership and
snapshot lifecycle must be agreed without creating a parallel database authority.
Later StarLang actors, real RabbitMQ/ZeroMQ requests, and canonical derived-document
server persistence/readback are separate gates, not evidence supplied by this slice.
