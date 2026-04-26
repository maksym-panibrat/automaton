#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/helpers.sh"
HOOK="$DIR/hooks/secrets-block.sh"

echo "tests: secrets-block hook"

# Synthetic PreToolUse payloads (per spec §17.2, verified 2026-04-25).

mk_write() {
  jq -nc --arg p "$1" --arg c "$2" \
    '{tool_name:"Write", tool_input:{file_path:$p, content:$c}}'
}
mk_edit() {
  jq -nc --arg p "$1" --arg c "$2" \
    '{tool_name:"Edit", tool_input:{file_path:$p, new_string:$c}}'
}
mk_bash() {
  jq -nc --arg cmd "$1" '{tool_name:"Bash", tool_input:{command:$cmd}}'
}

# Block: writing AWS key to a .ts file
P_AWS="$(mk_write "src/config.ts" "const KEY='AKIAIOSFODNN7EXAMPLE';")"
assert_blocks "$HOOK" "$P_AWS" "blocks Write of AWS access key"

# Block: writing to .env
P_ENV="$(mk_write ".env.production" "DB_URL=postgres://localhost/db")"
assert_blocks "$HOOK" "$P_ENV" "blocks Write to .env.production"

# Block: editing in an SSH key
P_SSH="$(mk_edit "scripts/deploy.sh" "$(cat tests/fixtures/secrets/ssh-private.txt)")"
assert_blocks "$HOOK" "$P_SSH" "blocks Edit injecting an SSH private key"

# Block: bash heredoc writing a token
P_HEREDOC="$(mk_bash 'cat > config.json <<EOF
{"token":"ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
EOF')"
assert_blocks "$HOOK" "$P_HEREDOC" "blocks bash heredoc with GitHub PAT"

# Allow: routine src edit with no secrets
P_OK="$(mk_write "src/foo.ts" "export const greeting = 'hello';")"
assert_allows "$HOOK" "$P_OK" "allows ordinary code"

# Allow: docs that mention secrets without actually containing them
P_DOCS="$(mk_write "docs/secrets.md" "$(cat tests/fixtures/secrets/clean.txt)")"
assert_allows "$HOOK" "$P_DOCS" "allows clean documentation"

# Allow: non-write/edit/commit bash command
P_LS="$(mk_bash "ls -la")"
assert_allows "$HOOK" "$P_LS" "allows non-write bash"

summary
