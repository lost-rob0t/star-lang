#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

ledger="ci/prototype-migration.tsv"
asd="starlang-prototype.asd"
targets="ci/target-systems.txt"

fail() {
  printf 'prototype-migration: %s\n' "$*" >&2
  exit 1
}

[[ -f "$ledger" ]] || fail "missing $ledger"
[[ -f "$asd" ]] || fail "missing $asd"
[[ -f "$targets" ]] || fail "missing $targets"

invalid_rows="$(
  awk -F '\t' '
    $0 !~ /^#/ && NF {
      if (NF < 3 || ($3 != "compat" && $3 != "partial" && $3 != "prototype")) {
        print NR ":" $0
      }
    }
  ' "$ledger"
)"
[[ -z "$invalid_rows" ]] || fail "invalid ledger rows:\n$invalid_rows"

mapfile -t asd_components < <(
  sed '/(defsystem "starlang-prototype\/tests"/,$d' "$asd" |
    sed -n 's/.*(:file "\([^"]*\)").*/\1/p' |
    sort
)
mapfile -t ledger_components < <(
  awk -F '\t' '$0 !~ /^#/ && NF {print $1}' "$ledger" | sort
)

asd_list="$(printf '%s\n' "${asd_components[@]}")"
ledger_list="$(printf '%s\n' "${ledger_components[@]}")"
if ! diff -u <(printf '%s\n' "$asd_list") <(printf '%s\n' "$ledger_list"); then
  fail "ledger must account for every authoritative prototype component exactly once"
fi

while IFS=$'\t' read -r component owners state note; do
  [[ -n "$component" ]] || continue
  [[ "$component" != \#* ]] || continue
  [[ -n "$owners" ]] || fail "$component has no final owner"

  IFS='+' read -r -a owner_list <<< "$owners"
  for owner in "${owner_list[@]}"; do
    grep -Fxq "$owner" "$targets" ||
      fail "$component names unknown final owner $owner"
  done

done < "$ledger"

compat_count="$(awk -F '\t' '$0 !~ /^#/ && $3 == "compat" {count++} END {print count + 0}' "$ledger")"
partial_count="$(awk -F '\t' '$0 !~ /^#/ && $3 == "partial" {count++} END {print count + 0}' "$ledger")"
prototype_count="$(awk -F '\t' '$0 !~ /^#/ && $3 == "prototype" {count++} END {print count + 0}' "$ledger")"
total_count=$((compat_count + partial_count + prototype_count))

printf 'prototype-migration: tracked=%d compat=%d partial=%d prototype=%d\n' \
  "$total_count" "$compat_count" "$partial_count" "$prototype_count"

if [[ "${1:-}" == "--require-final" ]]; then
  remaining="$(
    awk -F '\t' '$0 !~ /^#/ && NF && $3 != "compat" {
      printf "%-44s %-9s %s\n", $1, $3, $2
    }' "$ledger"
  )"
  if [[ -n "$remaining" ]]; then
    printf 'prototype-migration: production release blocked; non-compat authority remains:\n%s\n' \
      "$remaining" >&2
    exit 1
  fi
fi
