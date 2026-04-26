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

# Stub gh — looks for a comment containing the run ID.
mkdir -p "$scratch/bin"
cat > "$scratch/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "pr view "*"--json comments"*)
    cat "$STUB_COMMENTS_FILE" 2>/dev/null || echo '{"comments":[]}'
    ;;
  "rev-parse"*) echo "$STUB_HEAD_SHA" ;;
  *) echo '{}' ;;
esac
STUB
chmod +x "$scratch/bin/gh"
export PATH="$scratch/bin:$PATH"

# Stub git rev-parse via wrapper that the hook reads.
export STUB_HEAD_SHA="$SHA"

# Helper: stub git rev-parse via a temp git repo
GIT_REPO="$scratch/repo"
git init -q "$GIT_REPO"
( cd "$GIT_REPO" && git -c user.email=a@b -c user.name=a commit --allow-empty -m init -q )
HEAD_SHA="$(cd "$GIT_REPO" && git rev-parse --short HEAD)"
SHA="$HEAD_SHA"

# Place audit file
audit_file="$AUTOMATON_AUDIT_DIR/$REPO/$(date -u +%F).jsonl"
mkdir -p "$(dirname "$audit_file")"

# Case 1: no dry-run comment → block
export STUB_COMMENTS_FILE="$scratch/comments-empty.json"
echo '{"comments":[]}' > "$STUB_COMMENTS_FILE"
P="$(mk_pr_ready "gh pr ready 99")"
pushd "$GIT_REPO" >/dev/null
assert_blocks "$HOOK" "$P" "blocks when no dry-run comment"
popd >/dev/null

# Case 2: dry-run comment present, no tests_passed event → block
echo "{\"comments\":[{\"body\":\"Dry-run interpretation. Run ID: \\\"$RUN\\\"\"}]}" > "$STUB_COMMENTS_FILE"
pushd "$GIT_REPO" >/dev/null
assert_blocks "$HOOK" "$P" "blocks when no tests_passed for SHA"
popd >/dev/null

# Case 3: both present → allow
printf '%s\n' "$(jq -nc --arg sha "$SHA" --arg run "$RUN" --arg repo "$REPO" \
  '{ts:"x", run_id:$run, repo:$repo, sha:$sha, phase:"verify", event:"tests_passed"}')" \
  >> "$audit_file"
pushd "$GIT_REPO" >/dev/null
assert_allows "$HOOK" "$P" "allows when both gates satisfied"
popd >/dev/null

# Case 4: not a `gh pr ready` command → allow regardless
P_OTHER="$(mk_pr_ready "gh pr view 99")"
pushd "$GIT_REPO" >/dev/null
assert_allows "$HOOK" "$P_OTHER" "passes through non-pr-ready bash"
popd >/dev/null

summary
