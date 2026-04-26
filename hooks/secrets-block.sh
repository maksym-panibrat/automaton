#!/usr/bin/env bash
# hooks/secrets-block.sh — PreToolUse hook. Blocks tool calls that would write
# secrets to disk. Matches Edit/Write directly, and Bash commands that look
# like writes/commits (>, tee, heredoc, git commit, git stash store).
#
# Block = exit non-zero with a stderr message naming the matched pattern.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/lib/secret-patterns.sh"

payload="$(cat)"
tool_name="$(jq -r '.tool_name // empty' <<<"$payload")"

block() {
  printf 'BLOCKED by automaton/secrets-block: %s\n' "$1" >&2
  exit 2
}

scan_content() {
  local content="$1" path="${2:-}"
  if [[ -n "$path" ]] && secret_patterns_scan_path "$path" >/dev/null; then
    block "path matches secret-bearing filename ($path)"
  fi
  if [[ -n "$content" ]]; then
    local hit
    hit="$(secret_patterns_scan_text "$content" || true)"
    [[ -n "$hit" ]] && block "content matches secret pattern: ${hit%%$'\n'*}"
  fi
  return 0
}

case "$tool_name" in
  Write)
    path="$(jq -r '.tool_input.file_path // ""' <<<"$payload")"
    content="$(jq -r '.tool_input.content // ""' <<<"$payload")"
    scan_content "$content" "$path"
    ;;
  Edit)
    path="$(jq -r '.tool_input.file_path // ""' <<<"$payload")"
    new="$(jq -r '.tool_input.new_string // ""' <<<"$payload")"
    scan_content "$new" "$path"
    ;;
  Bash)
    cmd="$(jq -r '.tool_input.command // ""' <<<"$payload")"
    case "$cmd" in
      *">"*|*"tee "*|*"<<"*|"git commit"*|"git stash store"*|"git tag"*)
        scan_content "$cmd" ""
        ;;
      *) : ;;
    esac
    ;;
  *) : ;;
esac

exit 0
