#!/usr/bin/env bash
# Opt-in local/Forgejo runner; no workflow, production service, or worker changes.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
command -v sbcl >/dev/null || { echo "SBCL is required (enter nix develop first)." >&2; exit 127; }
export CL_SOURCE_REGISTRY="$root//:${CL_SOURCE_REGISTRY-}"
for system in star-mailbox starlang-runtime star-supervisor; do
  sbcl --non-interactive \
    --eval '(require :asdf)' \
    --eval "(asdf:test-system \"$system\")"
done
for example in counter restart-classes backoff-and-drain; do
  sbcl --script "star-supervisor/examples/$example.lisp"
done
