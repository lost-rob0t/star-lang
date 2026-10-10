# Star distributed document and Target access — v1

Status: **normative proposal for review; not an implementation or deployment claim**.
Written: 2026-10-03 (America/New_York).
Tracking: [StarLang #198](https://github.com/lost-rob0t/star-lang/issues/198),
[Server #315](https://github.com/lost-rob0t/starintel-server/issues/315),
[ARADR #263](https://github.com/lost-rob0t/starintel-auto-research/issues/263).

## Specification set

1. [Access profile](01-access-profile.md): operation identities, payload shapes, revisions, idempotency, Target control, queries and changes.
2. [Distribution and transports](02-distribution-and-transports.md): partition authority, commit/outbox recovery, RabbitMQ, StarRouter and HTTP projections.
3. [A2A binding](03-a2a-binding.md): execution mapping, negotiation, remote effects and reconciliation.
4. [Conformance and rollout](04-conformance.md): adversarial cases, implementation ownership and acceptance gates.
5. [Machine-readable scenario inventory](../../../fixtures/star-access/v1/scenarios.json): language-neutral test requirements, not test results or generated wire schemas.

MUST, MUST NOT, SHOULD and MAY denote normative requirements in this proposal.
The profile is `star.access/1`, layered on `star.actor2actor/1` and the existing
`star-actor-protocol` lifecycle. `star.documents.*@1` and `star.targets.*@1` are
sibling operation families. The profile introduces neither another envelope nor
another database query language, scheduler, persistence model or authorization engine.

## Authority boundaries

| Concern | Authority |
| --- | --- |
| StarIntel documents, including scheduler Target, operation and investigation-target | `org.starintel/core@1`, generated StarIntel 0.10.1 |
| Access semantics and portable boundary definitions | Star Language; this proposal under #198 |
| Message identity, correlation/causation, ActorRef and lifecycle | `star-actor-protocol` / `star.actor2actor/1` |
| Platform URI grammar and resource-kind registry | Shared Star URI authority; not a new StarLang-owned URI grammar |
| DB connections, trusted named operations, authorization, partition ownership and durable execution | StarIntel Server |
| Network delivery and routing | RabbitMQ / StarRouter / HTTP adapters |
| Upstream A2A protocol types | Pinned upstream A2A definitions |

CouchDB persists ordinary JSON. Star Language generates contracts; it is not a
CouchDB indexing language or a storage representation. Backend `_id`, `_rev`,
queue names, connection strings and routing identities do not become public
access-profile fields. Canonical payload keys remain lowerCamelCase.

A scheduler Target, an `investigation-target` research document and an `operation`
research document are distinct types. This profile does not alias them. A2A Task
is an interoperability projection of a runtime execution, not a replacement for
any of these persistent types.

## Reviewed dependency snapshots

These are evidence/reference pins, **not a new release lock**. The existing
`specs/starintel/0.10.1/release-lock.json` remains authoritative for generated
artifacts. All referenced open PRs still require their own review and merge gates.

| Dependency | Snapshot inspected |
| --- | --- |
| StarIntel 0.10.1 research/operation additions, PR #197 | `debb752b1264a9d237cb51dce7d3bde345b2d8b5`, open draft |
| Its `core.star` SHA-256 | `8024f94a1f1c34fcbdb3ea27f9fc0efc6dedd45b6f85af7094427c4d0e3cad9f` |
| Its generated `schema.json` SHA-256 | `dbef552ecef812b19760c649059a7015d250f99ca257f6490f8e075f02304766` |
| Actor2Actor design, PR #152 | `f35b95f573df348a0aff41ac700b03bd7250a1e4`, open draft |
| Server DB runtime, PR #295 | `aee24f1c8ec0bc35ae118d0854b15574bc9f9980`, open draft |
| Upstream A2A release | `v1.0.1`; published 2026-05-28T11:34:36Z |
| A2A release target commit reported by upstream | `3303592588e388e62e0f69f701af531d2f4e3991` |
| A2A protocol negotiation | `1.0`, independently of StarIntel `0.10.1` |

Before implementation release, resolve the upstream tag to its commit, pin the
actual protocol-definition bytes and generated codecs, and run the compatibility
matrix. A mutable `latest` URL is research provenance, not a build dependency.
Repinning StarIntel requires regenerating and checking its existing release lock;
matching only the string `0.10.1` is insufficient.

## Compatibility corrections made explicit

The older PR #152 design contains a colon-delimited actor-address example. This
profile uses the platform-wide RFC3986 hierarchy
`star://<authority>/<resource-kind>/<resource-path>` and MUST NOT revive that old
example as a second URI grammar. A resource identifier is not a credential or a
physical route. Parsing/escaping comes from the shared URI implementation.

The older task-state discussion also lists `outcomeUnknown`. Here an uncertain
**invocation observation** is explicitly distinct from an execution terminal
state: losing a reply cannot mark a still-running Target failed or terminal.
The same execution may later reconcile to its already committed outcome. This
clarification preserves first-terminal-wins rather than weakening it.

## Implementation status and generation

This change specifies behavior and test requirements only. It does not add
working transports, storage adapters, a scheduler or generated language types.
The request/result notation in these documents defines domain payloads inside the
existing lifecycle, not an alternative JSON Schema. Implementers MUST lower the
approved access definitions through the final-owned Star Language specification
and code-generation path, reusing upstream types rather than hand-maintaining
parallel Common Lisp/Python/TypeScript/Nim definitions. Other supported language
boundaries remain supported; this proposal removes none.

The operator authorized writing the specifications. That does not automatically
approve every design detail, merge dependency PRs or authorize deployment.

## Primary references

- [Scope and required operations, StarLang #198](https://github.com/lost-rob0t/star-lang/issues/198).
- [Server application-service scope, Server #315](https://github.com/lost-rob0t/starintel-server/issues/315).
- [Scheduling contract, StarLang #154](https://github.com/lost-rob0t/star-lang/issues/154).
- [Actor2Actor design at inspected revision](https://github.com/lost-rob0t/star-lang/blob/f35b95f573df348a0aff41ac700b03bd7250a1e4/docs/STAR-ACTOR2ACTOR.md).
- [StarIntel release lock at inspected revision](https://github.com/lost-rob0t/star-lang/blob/debb752b1264a9d237cb51dce7d3bde345b2d8b5/specs/starintel/0.10.1/release-lock.json).
- [A2A release v1.0.1](https://github.com/a2aproject/A2A/releases/tag/v1.0.1).
- [A2A protocol specification](https://a2a-protocol.org/latest/specification/), sections 3–5 and 7–9; inspected 2026-10-03.
- [A2A task lifecycle](https://a2a-protocol.org/latest/topics/life-of-a-task/); inspected 2026-10-03.
- [A2A streaming and asynchronous operations](https://a2a-protocol.org/latest/topics/streaming-and-async/); inspected 2026-10-03.
- [RabbitMQ acknowledgements and confirms](https://www.rabbitmq.com/docs/confirms); inspected 2026-10-03.
