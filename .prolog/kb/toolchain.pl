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

% Registry facts verified by the 2026-09-11 crash fix
% (prototype/core-surface-load-tests.lisp is the executable evidence):
% - (merge-pathnames "../" <file-truename>) yields a FILE pathname (name and
%   type inherited, ":up" appended unresolved), so passing it to an ASDF
%   :tree entry makes ASDF drop the entry: the tree never enters the registry.
% - ASDF searches source-registry entries in order and :inherit-configuration
%   expands the inherited environment configuration at its position, so a
%   :tree entry placed after it loses to a stale ~/common-lisp clone even when
%   the tree path is valid. Registry-resolved systems also outrank systems
%   registered later via asdf:load-asd.
% - Correct pattern used by prototype/core-surface-prototype.lisp and
%   starlang-cli/starlang-cli.lisp: register
%   (list :source-registry (list :tree <repo-root-directory-namestring>)
%         :inherit-configuration)
%   with the repo root computed as a directory pathname via
%   (butlast (pathname-directory *load-truename*)).
registry_tree_rule(file_pathname_dropped_by_asdf_tree).
registry_tree_rule(tree_before_inherit_configuration).
registry_tree_rule(repo_root_directory_from_butlast_of_truename_directory).
regression_test(prototype_core_surface_load_tests, decoy_registry_red_green).

% System SBCL + quicklisp and the nix flake both provide SBCL 2.6.7 with
% fiveam-20241012; the nix toolchain is authoritative for gates.
authoritative_toolchain(nix_flake_sbcl).
