#!/usr/bin/env bash
# tests/helpers.sh — shared assertions and fixtures for automaton tests.
# Source this from each test-*.sh.

set -euo pipefail

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_FAILED_NAMES=()

_red()   { printf '\033[31m%s\033[0m' "$*"; }
_green() { printf '\033[32m%s\033[0m' "$*"; }
_dim()   { printf '\033[2m%s\033[0m'  "$*"; }

assert_eq() {
  local expected="$1" actual="$2" name="${3:-assert_eq}"
  if [[ "$expected" == "$actual" ]]; then
    TESTS_PASSED=$((TESTS_PASSED+1))
    printf '  %s %s\n' "$(_green ✓)" "$name"
  else
    TESTS_FAILED=$((TESTS_FAILED+1))
    TESTS_FAILED_NAMES+=("$name")
    printf '  %s %s\n      expected: %s\n      actual:   %s\n' "$(_red ✗)" "$name" "$expected" "$actual"
  fi
}

assert_match() {
  local pattern="$1" actual="$2" name="${3:-assert_match}"
  if [[ "$actual" =~ $pattern ]]; then
    TESTS_PASSED=$((TESTS_PASSED+1))
    printf '  %s %s\n' "$(_green ✓)" "$name"
  else
    TESTS_FAILED=$((TESTS_FAILED+1))
    TESTS_FAILED_NAMES+=("$name")
    printf '  %s %s\n      pattern: %s\n      actual:  %s\n' "$(_red ✗)" "$name" "$pattern" "$actual"
  fi
}

assert_blocks() {
  # Runs $1 (a script path) with stdin from $2 (json string). Asserts non-zero exit.
  local script="$1" payload="$2" name="${3:-assert_blocks}"
  if printf '%s' "$payload" | "$script" >/dev/null 2>&1; then
    TESTS_FAILED=$((TESTS_FAILED+1))
    TESTS_FAILED_NAMES+=("$name")
    printf '  %s %s (expected block, got allow)\n' "$(_red ✗)" "$name"
  else
    TESTS_PASSED=$((TESTS_PASSED+1))
    printf '  %s %s\n' "$(_green ✓)" "$name"
  fi
}

assert_allows() {
  local script="$1" payload="$2" name="${3:-assert_allows}"
  if printf '%s' "$payload" | "$script" >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED+1))
    printf '  %s %s\n' "$(_green ✓)" "$name"
  else
    TESTS_FAILED=$((TESTS_FAILED+1))
    TESTS_FAILED_NAMES+=("$name")
    printf '  %s %s (expected allow, got block)\n' "$(_red ✗)" "$name"
  fi
}

with_tmp_home() {
  # Sets HOME to a fresh temp dir for the duration of one test, then restores.
  local _orig="$HOME"
  HOME="$(mktemp -d)"
  export HOME
  "$@"
  local rc=$?
  rm -rf "$HOME"
  HOME="$_orig"
  export HOME
  return $rc
}

summary() {
  echo
  if (( TESTS_FAILED == 0 )); then
    printf '%s %d passed\n' "$(_green PASS)" "$TESTS_PASSED"
    return 0
  fi
  printf '%s %d passed, %d failed\n' "$(_red FAIL)" "$TESTS_PASSED" "$TESTS_FAILED"
  for n in "${TESTS_FAILED_NAMES[@]}"; do printf '    - %s\n' "$n"; done
  return 1
}
