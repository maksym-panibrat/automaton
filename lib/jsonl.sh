#!/usr/bin/env bash
# lib/jsonl.sh — append a JSON line to a JSONL file, creating parent dirs.

jsonl_append() {
  local file="$1" json="$2"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$json" >> "$file"
}

jsonl_iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

jsonl_today() {
  date -u +"%Y-%m-%d"
}

audit_emit_phase() {
  # $1 = phase, $2 = event name (e.g., tests_passed), $3+ = jq --arg pairs
  local phase="$1" event="$2"; shift 2
  local repo="${AUTOMATON_REPO:-_unknown}"
  local audit_root="${AUTOMATON_AUDIT_DIR:-$HOME/.claude/audit}"
  local file
  file="$audit_root/$repo/$(jsonl_today).jsonl"
  local sha=""
  if git rev-parse --short HEAD >/dev/null 2>&1; then sha="$(git rev-parse --short HEAD)"; fi
  local json
  json="$(jq -nc \
    --arg ts "$(jsonl_iso_now)" \
    --arg run_id "${AUTOMATON_RUN_ID:-}" \
    --arg repo "$repo" \
    --argjson issue "${AUTOMATON_ISSUE:-null}" \
    --arg branch "${AUTOMATON_BRANCH:-}" \
    --arg sha "$sha" \
    --arg phase "$phase" \
    --arg event "$event" \
    '{ts:$ts, run_id:$run_id, repo:$repo, issue:$issue, branch:$branch, sha:$sha, phase:$phase, event:$event}')"
  jsonl_append "$file" "$json"
}
