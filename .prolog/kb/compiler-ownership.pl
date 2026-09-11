% Compiler ownership facts after the actor-compiler extraction (2026-09-10)
% and the shared RFC STAR URI canonicalization slice (2026-09-11).

% The closed StarLang compiler core and actor lowering are final-owned by
% starlang-compiler, package star-lang.compiler.core. Prototype files
% core-surface-prototype.lisp and actor-wire-prototype.lisp are compatibility
% shells; starlang-prototype loads them only as re-export/forwarding layers.
final_owner(closed_star_parser, starlang_compiler).
final_owner(star_syntax_model, starlang_compiler).
final_owner(grammar_validation, starlang_compiler).
final_owner(specification_lowering, starlang_compiler).
final_owner(actor_source_lowering, starlang_compiler).
final_owner(portable_actor_manifest_emission, starlang_compiler).
final_owner(star_uri_canonicalization, star_actor_protocol).
final_owner(star_service_uri_canonicalization, star_actor_protocol).
final_owner(star_uri_model, star_actor_protocol).
final_owner(legacy_tuple_compatibility, star_actor_protocol).
obsolete_contract(star_service_uri_tuple_canonical, superseded_by_star_server_041).
prototype_shell('prototype/core-surface-prototype.lisp', reexport).
prototype_shell('prototype/actor-wire-prototype.lisp',
                [bind_actor_runtime, wire_envelope_forwarders]).
prototype_shell('prototype/service-uri-prototype.lisp',
                [legacy_tuple_compatibility_forwarders,
                 migrate_legacy_star_uri_forwarder]).

% Actor declarations became real .star source in this extraction: the closed
% keyword table previously had no actor option vocabulary, and compile-actor
% only ever received trusted raw host forms.
actor_option_keywords([accepts, capabilities, endpoint, handler, mailbox,
                        metadata, produces, protocol, restart, runtime,
                        service_uri]).

% compile-actor accepts both closed syntax objects (from .star source) and
% trusted raw host forms (legacy tests); every option access must unwrap
% syntax atoms (e.g. service-uri arrives as a star-syntax :string node).
dual_representation(syntax_object_or_trusted_form).
representation_bug_pattern(forgotten_syntax_atom_unwrap).

% Actor declaration grammar (approved: STAR-LANG-RESEARCH-008 and the
% STAR-LANG-004 amendment; :service-uri is a canonical RFC actor URI):
%
%   (actor name
%     (:runtime native|external
%      [:service-uri "star://<authority>/actor/<actor-resource-path>"]
%      :accepts (types) :produces (types)
%      :handler id | :protocol id :endpoint "string"
%      :restart permanent|transient|temporary
%      :mailbox (bounded positive-integer)
%      [:capabilities (ids)]
%      [:metadata ((camelCaseKey "string"|integer)...)]))
%
% The URI must be canonical under the shared STAR-SERVER-041 v1 profile,
% address an actor resource, and end its actor resource path with the actor
% contract name. The legacy star://domain:address:actor-name tuple is not
% accepted by the compiler; it is compatibility input behind the explicit
% legacy API in star-actor-protocol/src/service-uri.lisp only.
% Metadata keys must be ASCII lower camelCase identifiers; values are
% strings or integers; IR shape is a deterministic string alist.
actor_grammar(approved_research_008_and_star_lang_004_amended).
service_uri_contract(canonical_rfc_actor_uri_required).
service_uri_name_rule(terminal_resource_path_segment_equals_actor_name).
metadata_key_rule(ascii_lower_camel_case).
metadata_value_rule(string_or_integer).

% Single-actor .star units compile through
% starlangcompiler:compile-actor-source / compile-actor-file:
% read-star-syntax -> expand-star-syntax -> validate head -> compile-actor.
actor_pipeline([read_star_syntax, expand_star_syntax, validate_head, compile_actor]).

% starlang-compiler depends on star-actor-protocol (plus star-logic-ir and
% star-logic-protocol); star-actor-protocol has no dependencies, so the final
% dependency graph stays acyclic.
asdf_dependency(starlang_compiler, [star_actor_protocol, star_logic_ir, star_logic_protocol]).
asdf_dependency(star_actor_protocol, []).
