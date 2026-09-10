#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
temporary_root="$(mktemp -d)"
trap 'rm -rf "$temporary_root"' EXIT

extract_agent_block() {
  awk '
    /^BEGIN STARLANG AGENT INSTRUCTIONS$/ { copying = 1 }
    copying { print }
    /^END STARLANG AGENT INSTRUCTIONS$/ { copying = 0 }
  ' "$1"
}

extract_agent_block "$repository_root/AGENTS.md" > "$temporary_root/agents.block"
extract_agent_block "$repository_root/README.md" > "$temporary_root/readme.block"

if ! cmp -s "$temporary_root/agents.block" "$temporary_root/readme.block"; then
  echo "README.md and AGENTS.md StarLang agent instruction blocks differ."
  diff -u "$temporary_root/agents.block" "$temporary_root/readme.block" || true
  exit 1
fi

if ! grep -q '^BEGIN STARLANG AGENT INSTRUCTIONS$' \
     "$temporary_root/agents.block"; then
  echo "Shared StarLang agent instruction block is missing."
  exit 1
fi

direct_backend_calls="$temporary_root/direct-backend-calls.txt"
while IFS= read -r -d '' source_file; do
  case "$source_file" in
    */star-sento-compat/tests/integration/*) continue ;;
  esac
  grep -En '(^|[^[:alnum:]_-])(asys|ac|act|rem):' "$source_file" \
    | sed "s|^|${source_file#"$repository_root/"}:|" \
    >> "$direct_backend_calls" || true
done < <(find "$repository_root" -type f -name '*.lisp' -print0)

if test -s "$direct_backend_calls"; then
  echo "Direct Sento calls escaped the final compatibility boundary:"
  cat "$direct_backend_calls"
  exit 1
fi
