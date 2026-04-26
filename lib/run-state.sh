#!/usr/bin/env bash
# lib/run-state.sh — read/write the current-run state file.
# Sourced by hooks and slash commands. Does not exit on its own.
#
# State directory: ${AUTOMATON_STATE_DIR:-$HOME/.claude/automaton/state}
# State file:      $AUTOMATON_STATE_DIR/current-run.env
# File format:     KEY=value (one per line, no quoting, no spaces in keys).

_run_state_dir() { printf '%s' "${AUTOMATON_STATE_DIR:-$HOME/.claude/automaton/state}"; }
_run_state_file() { printf '%s/current-run.env' "$(_run_state_dir)"; }

run_state_set() {
  local key="$1" value="$2"
  local dir file
  dir="$(_run_state_dir)"
  file="$(_run_state_file)"
  mkdir -p "$dir"
  if [[ -f "$file" ]] && grep -q "^${key}=" "$file" 2>/dev/null; then
    local tmp; tmp="$(mktemp)"
    grep -v "^${key}=" "$file" > "$tmp" || true
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

run_state_get() {
  local key="$1"
  local file; file="$(_run_state_file)"
  [[ -f "$file" ]] || return 1
  local line; line="$(grep "^${key}=" "$file" 2>/dev/null | tail -1)"
  [[ -n "$line" ]] || return 1
  printf '%s' "${line#*=}"
}

run_state_clear() {
  local file; file="$(_run_state_file)"
  [[ -f "$file" ]] && rm -f "$file"
  return 0
}

run_state_load_env() {
  # Source the file as KEY=value pairs, exporting AUTOMATON_<KEY>.
  local file; file="$(_run_state_file)"
  [[ -f "$file" ]] || return 0
  while IFS='=' read -r k v; do
    [[ -z "$k" || "$k" =~ ^# ]] && continue
    export "AUTOMATON_${k}=${v}"
  done < "$file"
}
