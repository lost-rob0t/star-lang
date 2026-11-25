% Durable knowledge: the StarLang logic execution contract — how logic calls
% are materialized and how backends execute operations (verified from source
% 2026-11-25 during the N-Prolog adapter lane; forgejo PR #218).

% Layered responsibility: star-logic-ir selects and materializes; backends
% execute; star-logic-testing defines the canonical execution semantics.
logic_layering(selection,
               'materialize-logic-call (star-logic-ir) selects a backend from the registry via a selection request (policy, semantic profile, required capabilities/hard-limits/isolation) and produces a materialized-logic-call PLAN; it never executes. Plans bind backend id/version/build-id exactly; ensure-materialized-backend-compatible fails closed on cross-backend or cross-build recovery').
logic_layering(execution,
               'execution is generic-based on star-logic-protocol: invoke-logic-operation(backend session operation-id parameters &key limits) returns an operation handle; next-logic-result(backend session handle) returns (values answer-or-nil status); apply-logic-fact-delta, cancel-logic-operation, logic-operation-status complete the surface; default methods on backend t fail closed with unsupported-logic-operation-error').

% Canonical execution semantics, defined by the fake backend in
% star-logic-testing/src/fake-backend.lisp — any real backend implements the
% same contract shape (verified 2026-11-25).
execution_semantics(operation_handles,
                    'invoke-logic-operation returns an opaque string operation handle; sessions track per-handle state in a map; unknown handle or closed session is a logic-session-error').
execution_semantics(next_result_statuses,
                    'next-logic-result returns (values answer status): :answer with a copied portable answer while answers remain; nil + +logic-operation-completed+ after the last answer when at least one was delivered; nil + +logic-operation-no-answer+ when none; nil + +logic-operation-cancelled+ after cancel-logic-operation; terminal states are sticky').
execution_semantics(fact_deltas,
                    'apply-logic-fact-delta applies an assert!/retract! delta on the session and returns :applied; deltas are copied data, never closures or engine handles').
execution_semantics(cancel,
                    'cancel-logic-operation marks a non-terminal operation cancelled with a reason and returns the new status; completed/no-answer/cancelled operations are left untouched').

% Portable values (star-logic-ir %copy-portable-value): native objects,
% symbols, functions, and engine handles are forbidden in normalized logic IR;
% records are alists with unique string fields, sorted deterministically.
portable_value_rules(forbidden,
                     'native objects, symbols, functions, engine handles are forbidden in normalized logic IR (invalid-logic-value-error); records must be proper alists with non-empty unique string keys; values are deep-copied on the way in').

% Operation kinds (star-logic-ir +logic-operation-kinds+): assert!, retract!,
% solve, solutions, exists?, explain. Named operations ride package identity:
% logic-package-identity carries package id/version/digest PLUS mapping
% id/digest — the mapping from named operation to engine behavior lives in a
% digest-locked package, parameters stay data (never goal-text concatenation).
logic_call_rules(named_operations,
                 'logic calls carry operation-id, named-operation-id, operation-kind, and package identity; backends map named operations to engine behavior through the digest-locked package mapping, so callers never send raw goal text; solving happens against consulted package content, not caller-supplied code').

% Backend registration: descriptor profiles/capabilities gate auto selection.
% The N-Prolog adapter keeps capabilities empty until query slices prove
% semantics; the fake backend declares ("named-query" "bounded-results") and
% ("star.logic.query/1") as the profile shape to grow into.
backend_selection_gates(auto_profile_shape,
                        'auto selection requires declared semantic profiles/capabilities; the testing fake declares ("star.logic.query/1") profiles and ("named-query" "bounded-results") capabilities — that is the shape the n-prolog descriptor must grow into when query operations land, via conformance evidence not declaration alone').
