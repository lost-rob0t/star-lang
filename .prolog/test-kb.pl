% Regression checks for this repository's durable KB loader.
:- use_module(library(plunit)).
:- use_module(library(readutil)).
:- multifile user:message_hook/3.
user:message_hook(Term, Level, _) :-
    memberchk(Level, [warning, error]),
    format(user_error, 'KB load diagnostic (~w): ~q~n', [Level, Term]),
    halt(1).

:- ensure_loaded('kb/load.pl').

:- begin_tests(kb_loader).
knowledge_files(Files) :-
    once((source_file_property(Loader, modified(_)),
    file_base_name(Loader, 'load.pl'))),
    file_directory_name(Loader, Dir),
    atom_concat(Dir, '/*.pl', Pattern),
    expand_file_name(Pattern, Files),
    Files = [_|_].

test(every_knowledge_file_loaded) :-
    knowledge_files(Files),
    forall(member(File, Files), source_file_property(File, modified(_))).

stored_ground_fact(Fact) :-
    knowledge_files(Files),
    member(File, Files),
    read_file_to_terms(File, Terms, []),
    member(Fact, Terms), ground(Fact),
    Fact \= (:- _), Fact \= (_ :- _).

test(every_ground_fact_queryable) :-
    forall(stored_ground_fact(Fact), call(Fact)).

test(no_duplicate_ground_facts) :-
    findall(Fact, stored_ground_fact(Fact), Facts),
    sort(Facts, Unique),
    same_length(Facts, Unique).

test(regression_queries, [nondet]) :-
    final_owner(closed_star_parser, starlang_compiler), final_owner(starlang_cli_command_surface, starlang_cli), asdf_dependency(star_actor_protocol, []), asdf_dependency(starlang_cli, _).
:- end_tests(kb_loader).

:- initialization((run_tests -> halt(0) ; halt(1)), main).
