% star-logic-bridge.pl — trusted N-Prolog bridge for the StarLang logic adapter.
%
% Shipped as package "star-logic-bridge"; the adapter pins this file's bytes
% by SHA-256 and revalidates the digest before every worker launch.
%
% Wire contract (verified against upstream builtin.c, npl 5.20):
% - send_socket/2 writes exactly 256 bytes: payload, one NUL from strcpy,
%   then uninitialized stack padding. Receivers truncate at the first NUL.
% - recv_socket/2 is one raw read(2): coalesced frames would lose data, so
%   the protocol is strict lock-step — one request, one reply, no pipelining.
% - create_server_socket/2 binds INADDR_ANY and blocks in accept(); the
%   adapter therefore chooses a free loopback port and connects immediately.
%
% Requests (plain atoms, protocol star-logic-nprolog-bridge-1):
%   hello -> star-logic-nprolog-bridge-1   (handshake)
%   ping  -> pong                          (liveness)
%   quit  -> closes the socket and returns to the REPL

star_logic_bridge_start(Port) :-
    create_server_socket(Socket, Port),
    star_logic_bridge_loop(Socket).

star_logic_bridge_loop(Socket) :-
    recv_socket(Socket, Request),
    ( Request == 'hello' ->
        send_socket(Socket, 'star-logic-nprolog-bridge-1'),
        star_logic_bridge_loop(Socket)
    ; Request == 'ping' ->
        send_socket(Socket, 'pong'),
        star_logic_bridge_loop(Socket)
    ; Request == 'quit' ->
        close_socket(Socket)
    ; send_socket(Socket, 'error-unknown-request'),
      star_logic_bridge_loop(Socket) ).
