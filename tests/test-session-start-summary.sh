#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/helpers.sh"
HOOK="$DIR/hooks/session-start-summary.sh"

echo "tests: session-start-summary"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

mkdir -p "$scratch/bin"
cat > "$scratch/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"--repo maksym-panibratenko/foo"*"--label claude:in-progress"*)
    echo "$STUB_INFLIGHT_FOO"
    ;;
  *"--repo maksym-panibratenko/bar"*"--label claude:in-progress"*)
    echo "$STUB_INFLIGHT_BAR"
    ;;
  *) echo '[]' ;;
esac
STUB
chmod +x "$scratch/bin/gh"
export PATH="$scratch/bin:$PATH"

repos_dir="$scratch/automaton"
mkdir -p "$repos_dir"
cat > "$repos_dir/repos" <<EOF
maksym-panibratenko/foo
maksym-panibratenko/bar
EOF
export AUTOMATON_REPOS_FILE="$repos_dir/repos"

# Case 1: no in-flight runs → empty additionalContext
export STUB_INFLIGHT_FOO='[]'
export STUB_INFLIGHT_BAR='[]'
out="$(printf '{"source":"startup","cwd":"/tmp"}' | "$HOOK")"
ctx="$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out")"
assert_eq "" "$ctx" "no runs → empty context"

# Case 2: two runs across two repos
export STUB_INFLIGHT_FOO='[{"number":42,"title":"healthz","repository":{"nameWithOwner":"maksym-panibratenko/foo"}}]'
export STUB_INFLIGHT_BAR='[{"number":17,"title":"refactor","repository":{"nameWithOwner":"maksym-panibratenko/bar"}}]'
out="$(printf '{"source":"startup","cwd":"/tmp"}' | "$HOOK")"
ctx="$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out")"
assert_match 'Heads up: 2 in-flight' "$ctx" "context names count"
assert_match 'foo#42'                "$ctx" "context names foo#42"
assert_match 'bar#17'                "$ctx" "context names bar#17"

# Case 3: opt-out env var → no output
export AUTOMATON_SESSION_START_SUMMARY=off
out="$(printf '{"source":"startup","cwd":"/tmp"}' | "$HOOK")"
ctx="$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out")"
assert_eq "" "$ctx" "opt-out disables hook"

summary
