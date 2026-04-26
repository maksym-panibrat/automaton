#!/usr/bin/env bash
# hooks/pr-ready-gate.sh — PreToolUse hook on Bash. Blocks `gh pr ready ...`
# unless the current run has both:
#   1. A "Dry-run interpretation" reference on the PR (in the body OR any comment)
#      whose text includes `Run ID: <run-id>`.
#   2. An audit event with phase=verify, event=tests_passed, sha=<HEAD short sha>.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/lib/run-state.sh"

payload="$(cat)"
tool_name="$(jq -r '.tool_name // empty' <<<"$payload")"

[[ "$tool_name" == "Bash" ]] || exit 0
cmd="$(jq -r '.tool_input.command // ""' <<<"$payload")"
case "$cmd" in
  "gh pr ready"*|*"gh pr ready"*) : ;;
  *) exit 0 ;;
esac

block() {
  printf 'BLOCKED by automaton/pr-ready-gate: %s\n' "$1" >&2
  exit 2
}

run_state_load_env || true
run_id="${AUTOMATON_RUN_ID:-}"
repo="${AUTOMATON_REPO:-}"
pr_number="${AUTOMATON_PR_NUMBER:-}"

[[ -n "$run_id" ]] || block "no AUTOMATON_RUN_ID in run state"
[[ -n "$repo" ]]   || block "no AUTOMATON_REPO in run state"
[[ -n "$pr_number" ]] || block "no AUTOMATON_PR_NUMBER in run state (open the draft PR before running gh pr ready)"

# Gate A: dry-run reference on the PR (body OR comments). The worker's Step 6
# puts the dry-run interpretation in the PR body; users can also comment it.
# Either location satisfies the gate so long as `Run ID: <run-id>` appears.
pr_json="$(gh pr view "$pr_number" --repo "$repo" --json comments,body 2>/dev/null || echo '{"comments":[],"body":""}')"
if ! grep -F "Run ID: \\\"$run_id\\\"" <<<"$pr_json" >/dev/null; then
  if ! grep -F "Run ID: \`$run_id\`" <<<"$pr_json" >/dev/null; then
    if ! grep -F "Run ID: $run_id" <<<"$pr_json" >/dev/null; then
      block "PR has no dry-run interpretation reference (body or comments) for run $run_id"
    fi
  fi
fi

# Gate B: tests_passed audit event for current SHA
sha="$(git rev-parse --short HEAD 2>/dev/null || true)"
[[ -n "$sha" ]] || block "git rev-parse --short HEAD failed"

audit_root="${AUTOMATON_AUDIT_DIR:-$HOME/.claude/audit}"
day="$(date -u +%F)"
audit_file="$audit_root/$repo/$day.jsonl"
[[ -f "$audit_file" ]] || block "no audit log for $repo today; run verification first"

found="$(jq -sc --arg run "$run_id" --arg sha "$sha" '
  map(select(.run_id==$run and .sha==$sha and .phase=="verify" and .event=="tests_passed"))
  | length' "$audit_file")"

[[ "$found" -gt 0 ]] || block "no tests_passed event for sha=$sha run=$run_id; re-run verification"

exit 0
