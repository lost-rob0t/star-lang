% Testing facts: gate loudness and a Common Lisp scoping gotcha that produced
% latent test bugs.

% fiveam run! returns T only when every check passed, but asdf test-op
% perform functions that ignore the return value exit 0 on failure, so
% ASDF/Nix/CI gates pass silently. Test entries must raise on failure:
%
%   (unless (run! 'suite) (error "suite failed."))
fiveam_run_bang_returns_pass_boolean(true).
silent_gate_symptom(asdf_test_op_exit_zero_despite_fiveam_failures).
loud_test_entry_pattern(unless_run_bang_error).

% Per CLHS, LET init-forms are outside the scope of that LET's own bindings:
% a lambda created in one init-form cannot capture a sibling binding.
% Use LET* when an effect lambda must capture a sibling capture variable.
let_scope_rule(init_forms_outside_binding_scope).
latent_bug_pattern(parallel_let_effect_lambda_capture).
latent_bug_symptom('undefined variable SEEN warning; capture stays NIL').
latent_bug_fix(let_instead_of_star).

% The prototype test-runner is loud: it spawns `sbcl --script` children and
% fails on any non-zero child exit. star-actor-protocol, starlang-runtime,
% and star-canonical-json use assert-style tests that signal on failure.
loud_suites([starlang_prototype_runner_children,
             star_actor_protocol_asserts,
             starlang_runtime_asserts,
             star_canonical_json_asserts]).
