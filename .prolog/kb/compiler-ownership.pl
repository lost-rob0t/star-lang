% Compiler ownership facts after the actor-compiler extraction (2026-09-10).

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
final_owner(star_service_uri_canonicalization, star_actor_protocol).
prototype_shell('prototype/core-surface-prototype.lisp', reexport).
prototype_shell('prototype/actor-wire-prototype.lisp',
                [bind_actor_runtime, wire_envelope_forwarders]).

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

% Actor declaration grammar (approved: STAR-LANG-RESEARCH-008 and
% STAR-LANG-004; legacy tuple URIs remain the executable contract):
%
%   (actor name
%     (:runtime native|external
%      [:service-uri "star://domain:address:actor-name"]
%      :accepts (types) :produces (types)
%      :handler id | :protocol id :endpoint "string"
%      :restart permanent|transient|temporary
%      :mailbox (bounded positive-integer)
%      [:capabilities (ids)]
%      [:metadata ((camelCaseKey "string"|integer)...)]))
%
% Metadata keys must be ASCII lower camelCase identifiers; values are
% strings or integers; IR shape is a deterministic string alist.
actor_grammar(approved_research_008_and_star_lang_004).
service_uri_contract(legacy_tuple_supported).
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
