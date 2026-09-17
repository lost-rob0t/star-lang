#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

fail() {
  echo "final-authority: $*" >&2
  exit 1
}

# Retirement is structural. The legacy system and source tree may not come back.
test ! -e starlang-prototype.asd || fail "starlang-prototype.asd still exists"
test ! -e prototype || fail "prototype/ still exists"

# Every product entry point must stay on final systems.
if grep -RInE \
  --include='*.asd' --include='*.yml' --include='*.yaml' --include='*.nix' --include='*.sh' \
  'asdf:(load-system|test-system)[^\n]*starlang-prototype|prototype/run-star\.lisp|depends-on[^\n]*starlang-prototype' \
  .github ci flake.nix ./*.asd */*.asd 2>/dev/null; then
  fail "active build/config still references prototype authority"
fi

# The final loader is a first-class independently loadable product system.
grep -Fxq 'starlang-loader' ci/target-systems.txt \
  || fail "starlang-loader is missing from ci/target-systems.txt"
test -f starlang-loader/starlang-loader.asd \
  || fail "final starlang-loader system is missing"

# Final compiler and runtime projection ownership must remain explicit.
test -f starlang-compiler/src/program-ir.lisp \
  || fail "final program IR compiler is missing"
test -f starlang-compiler/src/semantic-validation.lisp \
  || fail "final semantic validator is missing"
test -f star-sento-compat/src/program-binding.lisp \
  || fail "final Sento program binding is missing"

# CLI product code must not delegate to a retired source tree.
if grep -RInE 'prototype/run-star\.lisp|asdf:(load-system|test-system)[^\n]*starlang-prototype' \
  starlang-cli 2>/dev/null; then
  fail "CLI still delegates to prototype authority"
fi

echo "final-authority: OK"
