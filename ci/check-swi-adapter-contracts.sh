#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
adapter="$root/star-logic-adapter-swi"
process_port="$root/star-process-port"

fail() {
  echo "SWI adapter contract violation: $*" >&2
  exit 1
}

if grep -Fqi 'starlang-prototype' "$adapter/star-logic-adapter-swi.asd"; then
  fail "final SWI adapter depends on starlang-prototype"
fi

if find "$adapter" -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' \) -print -quit | grep -q .; then
  fail "Python/Node helper found under final SWI adapter"
fi

if grep -REni 'swiplserver|(^|[^[:alnum:]_])(nc|socat)([^[:alnum:]_]|$)' \
     "$adapter/src" "$adapter/prolog"; then
  fail "forbidden helper runtime found in SWI adapter"
fi

if grep -REni '#:(run-prolog|query-prolog|execute-goal|call-predicate|call-prolog|consult)' \
     "$adapter/src/packages.lisp"; then
  fail "raw Prolog execution symbol exported"
fi

if grep -REni 'consult[[:space:]]*\(' "$adapter/src" "$adapter/prolog"; then
  fail "consult/1 construction found"
fi

load_files_hits="$(grep -RIl 'load_files' "$adapter/src" "$adapter/prolog" || true)"
if [[ -n "$load_files_hits" && "$load_files_hits" != "$adapter/src/bootstrap.lisp" ]]; then
  echo "$load_files_hits" >&2
  fail "load_files is permitted only in the private trusted-bootstrap builder"
fi

if grep -REni 'call[[:space:]]*\(' "$adapter/src" "$adapter/prolog"; then
  fail "arbitrary call/1 construction found"
fi

if grep -REni 'swi[-_ ]?prolog|swipl|(^|[^[:alnum:]_])mqi([^[:alnum:]_]|$)' \
     "$process_port/src"; then
  fail "SWI-specific behavior leaked into star-process-port"
fi

echo "SWI adapter static contracts OK"
