#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/helpers.sh"
HOOK="$DIR/hooks/pr-ready-gate.sh"

echo "tests: pr-ready-gate"

mk_pr_ready() {
  jq -nc --arg cmd "$1" '{tool_name:"Bash", tool_input:{command:$cmd}}'
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

export AUTOMATON_STATE_DIR="$scratch/state"
export AUTOMATON_AUDIT_DIR="$scratch/audit"
mkdir -p "$AUTOMATON_STATE_DIR"
RUN="run-20260425-1432-foo-42"
REPO="maksym-panibratenko/foo"
SHA="abc1234"
cat > "$AUTOMATON_STATE_DIR/current-run.env" <<EOF
RUN_ID=$RUN
REPO=$REPO
ISSUE=42
BRANCH=claude/issue-42-healthz
PHASE=land
PR_NUMBER=99
EOF

# Stub gh — returns the combined PR JSON (comments + body) the hook expects.
mkdir -p "$scratch/bin"
cat > "$scratch/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "pr view "*"--json"*)
    cat "$STUB_PR_FILE" 2>/dev/null || echo '{"comments":[],"body":""}'
    ;;
  "rev-parse"*) echo "$STUB_HEAD_SHA" ;;
  *) echo '{}' ;;
esac
STUB
chmod +x "$scratch/bin/gh"
export PATH="$scratch/bin:$PATH"

export STUB_HEAD_SHA="$SHA"

# Helper: ephemeral git repo so the hook's `git rev-parse --short HEAD` returns a real SHA.
GIT_REPO="$scratch/repo"
git init -q "$GIT_REPO"
( cd "$GIT_REPO" && git -c user.email=a@b -c user.name=a commit --allow-empty -m init -q )
HEAD_SHA="$(cd "$GIT_REPO" && git rev-parse --short HEAD)"
SHA="$HEAD_SHA"

audit_file="$AUTOMATON_AUDIT_DIR/$REPO/$(date -u +%F).jsonl"
mkdir -p "$(dirname "$audit_file")"

# Case 1: no dry-run reference (empty body, empty comments) → block.
export STUB_PR_FILE="$scratch/pr-empty.json"
echo '{"comments":[],"body":""}' > "$STUB_PR_FILE"
P="$(mk_pr_ready "gh pr ready 99")"
pushd "$GIT_REPO" >/dev/null
assert_blocks "$HOOK" "$P" "blocks when neither body nor comments mention the run id"
popd >/dev/null

# Case 2: dry-run in a comment, no tests_passed audit event → block.
echo "{\"comments\":[{\"body\":\"Dry-run interpretation. Run ID: \\\"$RUN\\\"\"}],\"body\":\"\"}" > "$STUB_PR_FILE"
pushd "$GIT_REPO" >/dev/null
assert_blocks "$HOOK" "$P" "blocks when no tests_passed for SHA"
popd >/dev/null

# Case 3: comment + tests_passed → allow.
printf '%s\n' "$(jq -nc --arg sha "$SHA" --arg run "$RUN" --arg repo "$REPO" \
  '{ts:"x", run_id:$run, repo:$repo, sha:$sha, phase:"verify", event:"tests_passed"}')" \
  >> "$audit_file"
pushd "$GIT_REPO" >/dev/null
assert_allows "$HOOK" "$P" "allows when both gates satisfied (run id in PR comment)"
popd >/dev/null

# Case 4: dry-run reference is in the PR body (no comments), tests_passed present → allow.
# This is the worker's default: Step 6 puts the dry-run interpretation in the PR body.
jq -nc --arg run "$RUN" '{comments:[], body:("## Dry-run interpretation\nRun ID: `" + $run + "`\n")}' > "$STUB_PR_FILE"
pushd "$GIT_REPO" >/dev/null
assert_allows "$HOOK" "$P" "allows when run id is in PR body (worker's default location)"
popd >/dev/null

# Case 5: not a `gh pr ready` command → pass through regardless.
P_OTHER="$(mk_pr_ready "gh pr view 99")"
pushd "$GIT_REPO" >/dev/null
assert_allows "$HOOK" "$P_OTHER" "passes through non-pr-ready bash"
popd >/dev/null

summary
