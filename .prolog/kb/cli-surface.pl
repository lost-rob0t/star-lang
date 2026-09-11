% Final CLI surface facts after the first-class final-system CLI slice
% (2026-09-11, verified by the starlang-cli gate run).

% starlang-cli is the leaf of the final dependency graph: it depends only on
% star-actor-protocol, starlang-compiler, starlang-runtime, star-canonical-json,
% and ironclad, and must never load starlang-prototype or anything under
% prototype/. The fresh-process proof is starlang-cli/tests/cli-proof.lisp.
final_owner(starlang_cli_command_surface, starlang_cli).
asdf_dependency(starlang_cli, [star_actor_protocol, starlang_compiler,
                               starlang_runtime, star_canonical_json,
                               ironclad]).

% Installed wrapper dispatch: load/load-url as first argument still enter
% prototype/run-star.lisp (the spec-library loader is prototype-owned,
% ci/prototype-migration.tsv); every other invocation, including no
% arguments, enters starlang-cli/starlang-cli.lisp.
wrapper_dispatch(load_load_url, prototype_run_star).
wrapper_dispatch(other_or_empty, starlang_cli).

% Public API: run-cli returns the integer exit code (0 success, 1 runtime or
% diagnostic failure, 2 usage error) and the caller script quits with it.
cli_commands([version, check, compile, run, load, load-url]).

% Program manifests wrap the compiled single-actor unit in a synthetic
% spec-library envelope whose digest is the SHA-256 of the .star source
% octets ("sha256:<hex>") until program-level compilation lands.
program_manifest_shape(synthetic_single_library_envelope).

% The portable manifest is runtime-neutral and carries no handler identities;
% the run path resolves handlers from the compiled actor IR against the
% package named by --package, so run-actor-program takes both the manifest
% and the actor IR.
run_handler_resolution(needs_compiled_ir_plus_manifest).

% functionp returns NIL for fbound symbols (symbols are only function
% designators), so starlangruntime:register-dispatch-actor must receive
% (symbol-function symbol), not the symbol itself.
functionp_excludes_fbound_symbols(true).
dispatch_handler_must_be_passed_via_symbol_function(true).
