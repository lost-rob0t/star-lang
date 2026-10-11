:- module(star_logic_bootstrap,
          [star_logic_handshake/5, star_logic_replace_relations/1,
           star_logic_neighbors/5]).

% This package is repository-owned verification code.  It is intentionally tiny:
% no caller-provided module, file, goal, or predicate indicator enters here.
star_logic_handshake('star.logic.bootstrap/1', 'swi-prolog', Major, Minor, Patch) :-
    current_prolog_flag(version_data, swi(Major, Minor, Patch, _)).


% Fixed data-only relation bridge. This is the star_relation/4 shape emitted
% by star-prolog-kb, not a second domain rule language or persistent database.

:- dynamic star_relation/4.

star_logic_replace_relations(CodeRows) :-
    maplist(star_logic_relation_row, CodeRows, Rows),
    transaction((retractall(star_relation(_, _, _, _)),
                 maplist(star_logic_assert_relation, Rows))).

star_logic_relation_row([I, S, P, D], [Id, Source, Predicate, Destination]) :-
    string_codes(Id, I), string_codes(Source, S),
    string_codes(Predicate, P), string_codes(Destination, D).

star_logic_assert_relation([Id, Source, Predicate, Destination]) :-
    assertz(star_relation(Id, Source, Predicate, Destination)).

star_logic_neighbors(NodeCodes, PredicateCodes, Direction, Limit, Rows) :-
    string_codes(Node, NodeCodes), string_codes(Predicate, PredicateCodes),
    memberchk(Direction, [out, in, both]),
    integer(Limit), between(1, 129, Limit),
    once(findnsols(Limit, [Id, Source, Predicate, Destination],
                  (star_relation(Id, Source, Predicate, Destination),
                   star_logic_direction(Direction, Node, Source, Destination)),
                  Rows)).

star_logic_direction(out, Node, Source, _) :- Node == Source.
star_logic_direction(in, Node, _, Destination) :- Node == Destination.
star_logic_direction(both, Node, Source, Destination) :-
    (Node == Source -> true ; Node == Destination).
