#!/usr/bin/env bash
# hooks/session-start-summary.sh — SessionStart hook (opt-in).
# Reports in-flight autonomous runs across configured repos as a one-line summary.
# Disabled when AUTOMATON_SESSION_START_SUMMARY != "on" (default: on if wired).

set -euo pipefail

emit() {
  jq -nc --arg ctx "$1" '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}'
}

mode="${AUTOMATON_SESSION_START_SUMMARY:-on}"
[[ "$mode" == "on" ]] || { emit ""; exit 0; }

# Discard stdin payload; not used here.
cat >/dev/null

repos_file="${AUTOMATON_REPOS_FILE:-$HOME/.claude/automaton/repos}"
[[ -f "$repos_file" ]] || { emit ""; exit 0; }

repos=()
while IFS= read -r line; do
  [[ -n "$line" ]] && repos+=("$line")
done < <(awk 'NF && !/^#/{print $1}' "$repos_file")
[[ "${#repos[@]}" -gt 0 ]] || { emit ""; exit 0; }

# Aggregate in-flight issues across repos. One gh call per repo.
items=()
for r in "${repos[@]}"; do
  json="$(gh issue list --repo "$r" --label claude:in-progress --state open --json number,title,repository 2>/dev/null || echo '[]')"
  while IFS= read -r line; do
    [[ -n "$line" ]] && items+=("$line")
  done < <(jq -c '.[]?' <<<"$json")
done

count="${#items[@]}"
if (( count == 0 )); then emit ""; exit 0; fi

short=""
for it in "${items[@]}"; do
  num="$(jq -r '.number' <<<"$it")"
  ow="$(jq -r '.repository.nameWithOwner // ""' <<<"$it")"
  short+=" \`${ow##*/}#${num}\`,"
done
short="${short%,}"

emit "Heads up: ${count} in-flight autonomous run(s):${short}."
