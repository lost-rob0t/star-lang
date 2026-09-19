% Verification workflow: how gates are recorded and checked for this repo.

% Machine-recorded evidence: run every gate through prolog-verify observe so
% argv, exit status, output digest, HEAD, and worktree digest are captured.
observe_example('prolog-verify observe -- ./ci/with-nix-sbcl.sh --eval "(require :asdf)" --eval "(progn (asdf:test-system :starlang-compiler-tests) (format t \\"COMPILER-GATE-OK~%\\"))" --eval "(sb-ext:quit)"').

% Evidence is only current for the recorded HEAD and worktree digest; after
% any file change or commit, re-run the observed gates before claiming
% completion, then run `prolog-verify check`.
evidence_staleness_rule(rerun_after_head_or_digest_change).

% Full gate set for compiler-affecting changes:
%   1. ci/with-nix-sbcl.sh ... (asdf:test-system :starlang-compiler-tests)
%   2. ci/with-nix-sbcl.sh ... (asdf:test-system :star-actor-protocol)
%   3. ci/with-nix-sbcl.sh ... (asdf:test-system :starlang-runtime)
%   4. ci/with-nix-sbcl.sh ... (asdf:test-system :starlang-prototype)
%   5. bash ci/check-prototype-migration.sh && bash ci/check-repository-contracts.sh
%   6. nix flake check -L   (only git-tracked files are in the flake source;
%      stage new files first or the nix build cannot see them)
required_gates([compiler_tests, actor_protocol_tests, runtime_tests,
                prototype_tests, ci_contract_scripts, nix_flake_check]).
flake_source_note('flake source contains only git-tracked files; git add before nix flake check').

% Runtime state (.prolog/runs, facts.kb, verify.pl, result.json) stays local
% via .git/info/exclude; .prolog/kb is durable and tracked.
prolog_runtime_state(local_only).
prolog_kb(tracked).

% prolog-verify observe records only exit(0) successes; RED/failed runs
% stay out of the machine evidence and must be narrated in the run log.
observe_records_successful_exits_only(true).

% Host-environment flake failure (verified 2026-09-19): star-process-port
% descendant-held-pipes tests fail on this host inside and outside the
% nix sandbox with PROCESS-OUTPUT-ERROR while draining subprocess output,
% identically at base commit c9d56a38 extracted to a throwaway tree, and
% identically across retries (3/3). GitHub runners pass the same commit.
% The local flake gate is therefore differential: run nix flake check -L
% on the branch and on the extracted base tree and require the identical
% failing-test-system set plus the branch-specific system green inside
% the flake build. Exact-head GitHub nix CI remains the release arbiter.
local_flake_environmental_failure(star_process_port_descendant_pipes).
local_flake_gate(differential_vs_base_tree).
