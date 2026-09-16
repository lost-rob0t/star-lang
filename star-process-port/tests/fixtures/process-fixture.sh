#!/bin/sh
set -eu

mode="${1:-}"
case "$mode" in
  echo)
    printf '%s' "${2-}"
    ;;
  flood)
    count="${2:-0}"
    while [ "$count" -gt 0 ]; do
      printf 'o'
      printf 'e' >&2
      count=$((count - 1))
    done
    ;;
  exit)
    code="${2:-0}"
    printf 'stdout-before-exit'
    printf 'stderr-before-exit' >&2
    exit "$code"
    ;;
  spin)
    while :; do :; done
    ;;
  ignore-term)
    trap '' TERM
    while :; do :; done
    ;;
  descendant-holds-pipes)
    hold_seconds="${2:-2}"
    sleep "$hold_seconds" &
    printf 'root-exit'
    exit 0
    ;;
  descendant-holds-pipes-spin)
    hold_seconds="${2:-2}"
    sleep "$hold_seconds" &
    while :; do :; done
    ;;
  *)
    printf 'unknown fixture mode: %s\n' "$mode" >&2
    exit 64
    ;;
esac
