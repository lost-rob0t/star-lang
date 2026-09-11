#!/usr/bin/env bash
# with-nix-sbcl.sh -- run SBCL/ASDF operations with the flake-pinned toolchain
# and a correctly ordered source registry.
#
# Usage:
#   ci/with-nix-sbcl.sh --eval '(require :asdf)' --eval '(asdf:test-system :starlang-compiler)' --eval '(sb-ext:quit)'
#   STARLANG_NIX_WRAPPER=/path/to/sbcl ci/with-nix-sbcl.sh --script prototype/foo.lisp
#
# Why this exists (local verification hazard):
#
# The sbcl.withPackages wrapper prefixes its store paths to any pre-existing
# CL_SOURCE_REGISTRY using a trailing ':' separator. That join produces an
# empty registry entry, and ASDF splices the default configuration at that
# position. On machines where that default includes the ~/common-lisp/ tree
# (an ASDF built-in default), a stale clone there silently shadows the
# checkout under test and gates run the wrong sources. The nix build sandbox
# has no ~/common-lisp, so CI cannot catch this.
#
# This helper probes the wrapper's pristine environment once, then execs the
# underlying SBCL with the current repository placed FIRST in the source
# registry, the nix dependency stores after it, and --no-sysinit so host
# quicklisp setups cannot interfere. It is a local verification convenience;
# CI and nix flake check do not depend on it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="${STARLANG_NIX_WRAPPER:-}"
if [[ -z "$WRAPPER" ]]; then
  WRAPPER="$(nix --extra-experimental-features 'nix-command flakes' \
    develop "$REPO_ROOT" -c bash -c 'command -v sbcl' 2>/dev/null | grep -a '^/' | tail -1)"
fi
[[ -x "$WRAPPER" ]] || { echo "no usable SBCL wrapper found at: $WRAPPER" >&2; exit 1; }

# The wrapper is a compiled binary; ask it where the real SBCL runtime lives.
RAW_SBCL="${STARLANG_NIX_SBCL:-}"
if [[ -z "$RAW_SBCL" ]]; then
  RAW_SBCL="$(env -u CL_SOURCE_REGISTRY "$WRAPPER" --no-sysinit --non-interactive \
    --eval '(progn (format t "~A~%" (namestring sb-ext:*runtime-pathname*)))' \
    --eval '(sb-ext:quit)' 2>/dev/null | grep -a '^/' | head -1)"
fi
[[ -n "$RAW_SBCL" && -x "$RAW_SBCL" ]] || { echo "no usable SBCL runtime found" >&2; exit 1; }

# Probe the wrapper's environment (its store-path prefixing already applied).
probe_file="$(mktemp)"
env -u CL_SOURCE_REGISTRY -u ASDF_OUTPUT_TRANSLATIONS -u ASDF \
  "$WRAPPER" --no-sysinit --non-interactive \
  --eval '(progn (require :asdf)
                 (format t "~A~%" (or (uiop:getenv "ASDF") ""))
                 (format t "~A~%" (or (uiop:getenv "CL_SOURCE_REGISTRY") ""))
                 (format t "~A~%" (or (uiop:getenv "ASDF_OUTPUT_TRANSLATIONS") "")))' \
  --eval '(sb-ext:quit)' >"$probe_file" 2>/dev/null || true
probe="$(grep -a '^/nix/store' "$probe_file" | head -3)"
rm -f "$probe_file"
ASDF_FASL="$(sed -n 1p <<<"$probe")"
STORE_REGISTRY="$(sed -n 2p <<<"$probe")"
OUT_TRANSLATIONS="$(sed -n 3p <<<"$probe")"

# Repository first; nix dependency stores after; no empty entry in between.
export CL_SOURCE_REGISTRY="${REPO_ROOT}//:${STORE_REGISTRY%/}"
[[ -n "$ASDF_FASL" ]] && export ASDF="$ASDF_FASL"
[[ -n "$OUT_TRANSLATIONS" ]] && export ASDF_OUTPUT_TRANSLATIONS="$OUT_TRANSLATIONS"
cd "$REPO_ROOT"
exec "$RAW_SBCL" --dynamic-space-size 3000 --no-sysinit "$@"
