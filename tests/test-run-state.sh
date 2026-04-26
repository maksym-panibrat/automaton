#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/helpers.sh"
. "$DIR/lib/run-state.sh"

echo "tests: run-state"

t_set_get_clear() {
  local statedir; statedir="$(mktemp -d)"
  AUTOMATON_STATE_DIR="$statedir" run_state_set RUN_ID "run-X"
  AUTOMATON_STATE_DIR="$statedir" run_state_set REPO "owner/foo"
  local got; got="$(AUTOMATON_STATE_DIR="$statedir" run_state_get RUN_ID)"
  assert_eq "run-X" "$got" "set+get round-trips RUN_ID"
  AUTOMATON_STATE_DIR="$statedir" run_state_clear
  got="$(AUTOMATON_STATE_DIR="$statedir" run_state_get RUN_ID || echo MISSING)"
  assert_eq "MISSING" "$got" "clear removes the file"
  rm -rf "$statedir"
}

t_get_missing_returns_nonzero() {
  local statedir; statedir="$(mktemp -d)"
  if AUTOMATON_STATE_DIR="$statedir" run_state_get RUN_ID >/dev/null 2>&1; then
    assert_eq "nonzero" "zero" "get on missing file should fail"
  else
    assert_eq "nonzero" "nonzero" "get on missing file fails as expected"
  fi
  rm -rf "$statedir"
}

t_set_get_clear
t_get_missing_returns_nonzero
summary
