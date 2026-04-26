#!/usr/bin/env bash
# tests/test-hooks.sh — runs every hook + tool + lib test in sequence.

set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"

scripts=(
  test-run-state.sh
  test-secret-patterns.sh
  test-secrets-block.sh
  test-safety-spotter.sh
  test-audit-log.sh
  test-pr-ready-gate.sh
  test-session-start-summary.sh
)

failed=0
for s in "${scripts[@]}"; do
  printf '\n=== %s ===\n' "$s"
  if ! bash "$DIR/tests/$s"; then
    failed=$((failed+1))
  fi
done

if (( failed > 0 )); then
  printf '\n%d test file(s) failed.\n' "$failed"
  exit 1
fi
printf '\nAll test files passed.\n'
