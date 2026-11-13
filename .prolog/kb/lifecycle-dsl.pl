% Document lifecycle DSL facts (star-lang#142, merged PR #145).

% Lifecycle policy lowering is final-owned by starlang-compiler; it is
% declarative closed-vocabulary data with no host eval anywhere.
final_owner(document_lifecycle_dsl, starlang_compiler).
lifecycle_ir_kind(:lifecycle).
lifecycle_manifest_wire_version(1).

% The closed keyword table *star-source-keywords* is consulted ONLY for
% ':'-prefixed tokens (assoc on token minus ':' in the .star lexer). Adding
% vocabulary there cannot change identifier lexing; .star field names like
% `to`/`from` (fixtures/starintel-core.star, fixtures/star-cl.star) still
% compile. Verified empirically at PR #145 head.
keyword_table_scope(colon_prefixed_tokens_only).
lifecycle_added_keywords([action, applies, emit, encryption, events, from,
                          guard, hold, indexing, initial, on, retention,
                          states, storage, supersedes, to, transitions, ttl]).

% Re-export rule: public-surface.lisp re-export-from imports+exports core
% symbols into starlangcompiler. Symbols re-exported this way must NOT also
% appear in the defpackage :export list -- defpackage interns a fresh symbol
% and SBCL raises NAME-CONFLICT at import time (emit-portable-manifest
% precedent: defpackage lists only self-defined/imported-statically symbols).
reexport_rule(defpackage_must_not_list_reexported_symbols).
name_conflict_symptom('Unhandled SB-EXT:NAME-CONFLICT on IMPORT during re-export-from').

% Lifecycle lowering contract (compile-time rejections, all deterministic):
lifecycle_rejections([duplicate_state, duplicate_from_event_pair,
                      unreachable_state, undeclared_state_or_event,
                      out_of_vocabulary_option, non_positive_version,
                      destroy_under_retention_or_hold]).
lifecycle_safety_invariant(destroy_erases_provenance_rejected_while_evidence_or_hold).
lifecycle_action_vocabulary([keep, archive, redact, tombstone, destroy]).
lifecycle_row_shape([from, on, to, guard_opt, action, emit_opt, supersedes_opt]).

% Fixture feed for the LATER server lifecycle executor slice
% (starintel-server#240): fixtures/lifecycle/ carries the .star source, its
% RFC 8785 canonical JSON manifest, and a regeneration driver over the single
% test-owned mapping (:starlang-lifecycle-tests:manifest-fixture-json). The
% byte-determinism test re-derives committed JSON on every gate run.
lifecycle_fixture_consumer(starintel_server_240).
lifecycle_duration_normalization(months_30_years_365_integer_days).
