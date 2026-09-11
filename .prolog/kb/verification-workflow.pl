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
