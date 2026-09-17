% Final StarLang authority proof.
% This KB intentionally has no compatibility/prototype owner relation.

required_final_component(semantic_validation).
required_final_component(normalized_program_ir).
required_final_component(digest_lock_contract).
required_final_component(spec_loader).
required_final_component(cl_gserver_projection).
required_final_component(actor_runtime).

final_owner(semantic_validation, starlang_compiler).
final_owner(normalized_program_ir, starlang_compiler).
final_owner(digest_lock_contract, starlang_compiler).
final_owner(spec_loader, starlang_loader).
final_owner(cl_gserver_projection, star_sento_compat).
final_owner(actor_runtime, starlang_runtime).

retired_authority(starlang_prototype).

unique_final_owner(Component) :-
    required_final_component(Component),
    findall(Owner, final_owner(Component, Owner), Owners),
    sort(Owners, UniqueOwners),
    UniqueOwners = [_].

prototype_authority_exists :-
    final_owner(_, starlang_prototype).

all_required_components_final :-
    forall(required_final_component(Component), unique_final_owner(Component)).

final_authority_ok :-
    retired_authority(starlang_prototype),
    all_required_components_final,
    \+ prototype_authority_exists.

:- begin_tests(final_authority).

test(required_components_have_one_owner) :-
    all_required_components_final.

test(prototype_has_no_authority, [fail]) :-
    prototype_authority_exists.

test(final_certificate) :-
    final_authority_ok.

:- end_tests(final_authority).
