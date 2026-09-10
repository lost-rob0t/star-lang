#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log_dir="${STARLANG_SMOKE_LOG_DIR:-$repo_root}"
work_dir="$(mktemp -d)"
main_pid=""
worker_pid=""

mkdir -p "$log_dir"
main_log="$log_dir/real-sento-remoting-main.log"
worker_log="$log_dir/real-sento-remoting-worker.log"

cleanup() {
  local pid
  for pid in "$worker_pid" "$main_pid"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

fail_with_logs() {
  printf '%s\n' "Real Sento remoting smoke failed." >&2
  if [[ -f "$main_log" ]]; then
    printf '%s\n' "--- main ---" >&2
    cat "$main_log" >&2
  fi
  if [[ -f "$worker_log" ]]; then
    printf '%s\n' "--- worker ---" >&2
    cat "$worker_log" >&2
  fi
  exit 1
}

cd "$work_dir"

sbcl --script "$repo_root/prototype/bbp-sento-smoke-main.lisp" \
  >"$main_log" 2>&1 &
main_pid=$!

ready=0
for _ in $(seq 1 300); do
  if [[ -s bbp-sento-main.ready ]]; then
    ready=1
    break
  fi
  if ! kill -0 "$main_pid" 2>/dev/null; then
    fail_with_logs
  fi
  sleep 0.05
done

if [[ "$ready" -ne 1 ]]; then
  fail_with_logs
fi

sbcl --script "$repo_root/prototype/bbp-sento-smoke-worker.lisp" \
  >"$worker_log" 2>&1 &
worker_pid=$!

main_status=0
worker_status=0
wait "$main_pid" || main_status=$?
wait "$worker_pid" || worker_status=$?
main_pid=""
worker_pid=""

if [[ "$main_status" -ne 0 || "$worker_status" -ne 0 ]]; then
  fail_with_logs
fi

if [[ ! -s bbp-sento-smoke.success ]]; then
  fail_with_logs
fi

printf '%s\n' "Real two-process Sento remoting smoke passed."
