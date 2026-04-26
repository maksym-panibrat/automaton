#!/usr/bin/env bash
# tools/safety-spotter.sh — diff-scoped secret scan.
# Reads a unified-diff on stdin. Considers only ADDED lines (lines starting
# with '+' but not the '+++ b/...' file header). Exit 0 if clean, exit 2 if
# any added line matches a known secret pattern.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/lib/secret-patterns.sh"

added=""
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    "+++ "*) continue ;;
    "+"*)    added+="${line:1}"$'\n' ;;
    *) : ;;
  esac
done

if [[ -z "$added" ]]; then
  exit 0
fi

if hit="$(secret_patterns_scan_text "$added")"; then
  printf 'BLOCKED by automaton/safety-spotter: secret in added lines\n%s\n' "$hit" >&2
  exit 2
fi

exit 0
