% Durable knowledge: N-Prolog engine + adapter facts (verified live 2026-11-24
% from upstream pin 13d43e0c1b084d736ba15d26f1da085f00224b93, npl 5.20).
% Source: https://github.com/sasagawa888/nprolog (modified BSD; unrelated
% namesake exists — descriptor metadata carries engine-upstream).

npl_identity(version_float, 'VERSION is a single float printed %1.2f; identity is a major.minor pair (5.20), not a SWI-style triplet').
npl_identity(v_flag, 'npl -v prints exactly "N-Prolog Ver 5.20" and exits 0 — the identity probe').
npl_repl(plain_mode, '-r is the only machine-usable REPL; the default REPL is an ncurses editable line editor').
npl_repl(ansi_in_plain_mode, 'the plain -r REPL still emits ESC[0m before verdicts; machine reads strip ANSI escapes before matching (observed on the "yes" verdict)').
npl_repl(startup_banner, 'first stdout line is "N-Prolog Ver X.Y [NNM cells]"; prompt "?- " prints without a trailing newline').
npl_transport(script_mode, '-s FILE consults FILE then exits EXIT_SUCCESS — deterministic process-per-job batch shape').
npl_transport(startup_consult, '-c FILE consults FILE then enters the REPL — the launch vector for a digest-locked bridge file').
npl_transport(tcpip_predicates, 'create_server_socket/2, create_client_socket/3, send_socket/2, recv_socket/2, close_socket/1 (document/TCPIP.md, tests/socket.pl) — in-engine socket boundary; the slice-2 socket-bridge transport').
npl_transport(send_socket_wire_truth, 'superset.c b_send_socket: char buf[256], strcpy payload, write(fd, buf, 256) — every send is exactly 256 bytes with payload NUL-terminated by strcpy followed by UNINITIALIZED STACK PADDING; atoms >=256 bytes would overflow the upstream buffer, so callers bound payloads at 255 bytes and truncate at first NUL (upstream-contribution candidate: no memset before write)').
npl_transport(recv_socket_wire_truth, 'superset.c b_recv_socket: one raw read(2) up to STRSIZE-1 (2047), makeconst truncates the atom at the first NUL — coalesced frames silently lose data, so the wire must be strict lock-step (one request, one reply, no pipelining)').
npl_transport(create_server_socket_truth, 'superset.c b_create_server_socket: binds INADDR_ANY (not loopback), blocks in accept() inline, port argument is input-only and never reported — adapter probes a free loopback port (bind 0, read, close) and passes the number into the bridge goal; one retry covers the probe-to-bind race').
npl_transport(batch_s_truth, '-s FILE consults FILE then exits EXIT_SUCCESS UNCONDITIONALLY — consult failures, syntax errors, and missing files all exit 0; a clean consult prints nothing (no banner; -s exits before the banner). Batch validation is therefore fail-closed on output: valid iff exit 0 AND empty stdout after ANSI strip (verified live 2026-11-25)').
npl_transport(consult_path_resolution, 'builtin.c prolog_file_name: names starting ./ or ../ resolve verbatim against the child CWD (ahead of NPROLOG_HOME then $HOME/nprolog); the adapter launches workers with :directory = bridge dir and -c ./star-logic-bridge.pl — no env plumbing needed').
npl_transport(network_mode, '-n starts upstream parent/child distribution (parallel.c init_parent/init_creceiver) — experimental parallel pools, no trust claims').
npl_compiler(compile_file, 'use_module(compiler), compile_file/1 lowers predicates to C and invokes GCC; compile_file(F,c|o|co) variants; an execution accelerator for hot rules, not a transport').
npl_shutdown(halt, 'halt. prints "- good bye -" and exits 0').
npl_build(makefile, 'npl target compiles with plain gcc -lm -ldl -pthread; ncurses headers required at build time (compat/term_stubs.h -> term.h) even though npl itself does not link ncurses (edlog does)').
npl_build(nix_pin, 'flake.nix: fetchFromGitHub 13d43e0c1b084d736ba15d26f1da085f00224b93, sha256-8+GWpfmhkIXlUg67kZPb1jp2iHnmnvbShtlokFELWUg=, buildInputs ncurses, buildPhase "make npl", install $out/bin/npl; STARLANG_NPROLOG_EXECUTABLE exported across dev shell/build/check/starlang-test').

adapter_foundation(nprolog_adapter,
                   'star-logic-adapter-nprolog (PR #218, commit 4b22ce30): explicit-path identity, -r worker, bounded banner handshake, true. canary, halt. shutdown, honest-empty descriptor, package expectations fail closed. Slice 2+ roadmap in starintel-auto-research roam/design/star-lang/STARLANG-NPL-000 (socket bridge = persistent fast path; batch -s; compiler accelerator; -n experimental)').
adapter_slice(socket_bridge,
              '2026-11-25 slice 2 (commit 0f6e4a39): prolog/star-logic-bridge.pl shipped as the adapter single trusted package identity (protocol star-logic-nprolog-bridge-1: hello handshake, ping liveness, quit unblock); sha256 digest-pinned and revalidated before every launch; workers launch -r -c ./star-logic-bridge.pl with the adapter pinning the child working directory to the bridge directory; package expectations must match the bridge identity or fail closed; session close = quit frame then halt. requiring exit 0').
adapter_slice(batch_validation,
              '2026-11-25 slice 3 (commit e6ffe8ef): nprolog-batch-validate backend file - loads a Prolog file with -s ./<name> in the file parent directory; upstream -s always exits 0 even on consult/syntax failures and a clean consult prints nothing, so validation is output-based: valid iff exit 0 AND empty stdout after ANSI strip; report carries sha256 of validated bytes; dotless names refused pre-launch (upstream consult appends .pl to dot-free names)').
