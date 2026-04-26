#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/helpers.sh"
HOOK="$DIR/hooks/audit-log.sh"

echo "tests: audit-log"

# Synthetic PostToolUse payload (per spec §17.3, verified 2026-04-25).
# Note: duration_ms is top-level, not under tool_response. tool_response shape
# is tool-specific; for Bash we leave it minimal.
mk_post_bash() {
  jq -nc --arg cmd "$1" --argjson dur "$2" '
    {tool_name:"Bash",
     tool_input:{command:$cmd},
     tool_response:{stdout:"", stderr:"", success:true},
     duration_ms:$dur}'
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# Provision a run-state file via env override so the hook picks up RUN_ID etc.
export AUTOMATON_STATE_DIR="$scratch/state"
mkdir -p "$AUTOMATON_STATE_DIR"
cat > "$AUTOMATON_STATE_DIR/current-run.env" <<EOF
RUN_ID=run-20260425-1432-foo-42
REPO=maksym-panibratenko/foo
ISSUE=42
BRANCH=claude/issue-42-healthz
PHASE=verify
EOF

export AUTOMATON_AUDIT_DIR="$scratch/audit"

P="$(mk_post_bash "pnpm test src/api/healthz.test.ts" 1240)"
printf '%s' "$P" | "$HOOK" >/dev/null

today="$(date -u +%F)"
file="$AUTOMATON_AUDIT_DIR/maksym-panibratenko/foo/$today.jsonl"
[[ -f "$file" ]] || { echo "expected $file"; exit 1; }
line="$(tail -1 "$file")"

assert_eq "Bash"                     "$(jq -r .tool      <<<"$line")" "tool field"
assert_eq "1240"                     "$(jq -r .duration_ms <<<"$line")" "duration_ms field"
assert_eq "verify"                   "$(jq -r .phase     <<<"$line")" "phase field"
assert_eq "42"                       "$(jq -r .issue     <<<"$line")" "issue field"
assert_eq "run-20260425-1432-foo-42" "$(jq -r .run_id    <<<"$line")" "run_id field"
assert_eq "maksym-panibratenko/foo"  "$(jq -r .repo      <<<"$line")" "repo field"
assert_match '^pnpm test'            "$(jq -r .cmd_summary <<<"$line")" "cmd_summary field"
# cmd_summary is truncated to 80 chars
P_LONG="$(mk_post_bash "$(printf 'echo %.0s' {1..200})" 12)"
printf '%s' "$P_LONG" | "$HOOK" >/dev/null
last="$(tail -1 "$file")"
len=$(jq -r '.cmd_summary | length' <<<"$last")
[[ "$len" -le 80 ]] || { echo "cmd_summary len $len > 80"; exit 1; }
assert_eq "true" "$([[ "$len" -le 80 ]] && echo true || echo false)" "cmd_summary <= 80 chars"

# When no run-state file exists, the hook must still succeed (silently no-op or write with empty fields).
rm -f "$AUTOMATON_STATE_DIR/current-run.env"
P2="$(mk_post_bash "ls" 5)"
printf '%s' "$P2" | "$HOOK" >/dev/null
assert_eq "0" "$?" "hook succeeds with no run state"

summary
