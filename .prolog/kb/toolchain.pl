% Toolchain facts: how to run the authoritative SBCL/ASDF gates locally.

% ci/with-nix-sbcl.sh runs the flake-pinned SBCL with the repository first in
% the source registry, the nix dependency stores after it, and --no-sysinit.
gate_runner('ci/with-nix-sbcl.sh').
gate_runner_usage('ci/with-nix-sbcl.sh --eval "(require :asdf)" --eval "(asdf:test-system :SYSTEM)" --eval "(sb-ext:quit)"').

% The sbcl.withPackages wrapper prefixes store paths onto CL_SOURCE_REGISTRY
% with a trailing ':', creating an empty registry entry; ASDF splices the
% default configuration there. Wherever ~/common-lisp holds a stale star-lang
% clone it silently shadows the checkout under test. The nix sandbox has no
% ~/common-lisp, so CI cannot catch this; local gates must reorder the
% registry (the helper does).
registry_hazard(sbcl_withpackages_empty_entry).
registry_hazard_effect(stale_checkout_shadowing_under_common_lisp).
registry_hazard_mitigation('repo tree first in CL_SOURCE_REGISTRY; see ci/with-nix-sbcl.sh').

% System SBCL + quicklisp and the nix flake both provide SBCL 2.6.7 with
% fiveam-20241012; the nix toolchain is authoritative for gates.
authoritative_toolchain(nix_flake_sbcl).
