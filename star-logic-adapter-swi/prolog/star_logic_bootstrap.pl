:- module(star_logic_bootstrap, [star_logic_handshake/5]).

% This package is repository-owned verification code.  It is intentionally tiny:
% no caller-provided module, file, goal, or predicate indicator enters here.
star_logic_handshake('star.logic.bootstrap/1', 'swi-prolog', Major, Minor, Patch) :-
    current_prolog_flag(version_data, swi(Major, Minor, Patch, _)).
