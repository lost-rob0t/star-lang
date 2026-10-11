# Research contracts in the 0.10.1 authority

`core.star` defines persistent `operation` and `investigation-target` documents.
They are not aliases of actor scheduler `target` or spatial `mission`. Dossier
has no verified executable contract and is intentionally not invented here.

Operation contains a mission, status and nonempty phase list. Its embedded
components are transient typed records without document envelopes. Consumers
must filter manifest kind=document AND persistence=persistent when enumerating
corpus dtypes: this release has 62 persistent dtypes and 8 transient components.
Never submit operation-phase or another embedded component as a corpus record.

Canonical operation semantics, declared beside the types in core.star, require
unique component IDs, a phase DAG, resolving local references, scope exclusions,
completion evidence, and terminal phases before operation completion. The
locked `operation_semantics.py` reference enforces those invariants after
structural generated-schema validation. All language consumers must implement
these same checks and run the locked `research-fixtures.json`; JSON Schema
validation alone is insufficient. This source change does not claim those
consumer implementations are all already migrated.

## Historical mapping

Historical nested data.operation fields move to the document root with explicit
snake_case to lowerCamelCase field mapping. Each typed operation component uses
the same mapping recursively; opaque metadata/config/selectors maps are preserved
byte-semantically and never key-normalized. IDs, local reference strings, enum
values, scope terms and evidence strings remain unchanged. Do not turn phase IDs
into remote Star references or infer completion from status labels.

`investigation-target` preserves its research question, hypotheses, selection
reasons, depth/breadth controls, sources, scopes, options and target string.
It requires target but does not require an actor. Priority/score number values
map to exact decimal strings; nullable next_run_at maps to nextRunAt unchanged.
This differs deliberately from actor scheduler target's Unix nextRunAt field.

No historical corpus record is rewritten by this release. Envelope migration
must preserve original timestamps, handling and evidence in an explicit reviewed
mapping; a version-only relabel or generic document fallback is not migration.
