#!/usr/bin/env bash
# hooks/audit-log.sh — PostToolUse hook. Appends one JSONL event per Bash/Edit/Write/Task call.
# Schema per spec §8.1, with reconciliations from §17.8 (duration_ms top-level; success replaces exit).

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/lib/run-state.sh"
. "$HERE/lib/jsonl.sh"

payload="$(cat)"
tool_name="$(jq -r '.tool_name // empty' <<<"$payload")"

# Only audit interesting tools; other PostToolUse payloads pass through silently.
case "$tool_name" in
  Bash|Edit|Write|Task) : ;;
  *) exit 0 ;;
esac

# Pull tool-specific summary
cmd_summary=""
case "$tool_name" in
  Bash)  cmd_summary="$(jq -r '.tool_input.command // ""' <<<"$payload")" ;;
  Edit)  cmd_summary="edit $(jq -r '.tool_input.file_path // "?"' <<<"$payload")" ;;
  Write) cmd_summary="write $(jq -r '.tool_input.file_path // "?"' <<<"$payload")" ;;
  Task)  cmd_summary="task $(jq -r '.tool_input.subagent_type // ""' <<<"$payload"): $(jq -r '.tool_input.description // ""' <<<"$payload")" ;;
esac
cmd_summary="${cmd_summary:0:80}"

# Per spec §17.3, duration_ms is a top-level field (not under tool_response).
# tool_response shape varies per tool; we capture .success when present (Write/Edit),
# leave it null for Bash/Task where the schema differs.
duration_ms="$(jq -r '.duration_ms // 0' <<<"$payload")"
success="$(jq -rc '.tool_response.success // null' <<<"$payload")"

run_state_load_env || true

run_id="${AUTOMATON_RUN_ID:-}"
repo="${AUTOMATON_REPO:-}"
issue="${AUTOMATON_ISSUE:-}"
branch="${AUTOMATON_BRANCH:-}"
phase="${AUTOMATON_PHASE:-}"
sha=""
if git rev-parse --short HEAD >/dev/null 2>&1; then
  sha="$(git rev-parse --short HEAD)"
fi

ts="$(jsonl_iso_now)"
day="$(jsonl_today)"

audit_root="${AUTOMATON_AUDIT_DIR:-$HOME/.claude/audit}"

if [[ -n "$repo" ]]; then
  out_file="$audit_root/$repo/$day.jsonl"
else
  out_file="$audit_root/_unknown/$day.jsonl"
fi

event="$(jq -nc \
  --arg ts "$ts" \
  --arg run_id "$run_id" \
  --arg repo "$repo" \
  --argjson issue "${issue:-null}" \
  --arg branch "$branch" \
  --arg sha "$sha" \
  --arg phase "$phase" \
  --arg tool "$tool_name" \
  --arg cmd_summary "$cmd_summary" \
  --argjson success "$success" \
  --argjson duration_ms "$duration_ms" '
  {ts:$ts, run_id:$run_id, repo:$repo, issue:$issue,
   branch:$branch, sha:$sha, phase:$phase, tool:$tool,
   cmd_summary:$cmd_summary, success:$success, duration_ms:$duration_ms}')"

jsonl_append "$out_file" "$event"
exit 0
