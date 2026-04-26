---
description: Run only the dry-run interpretation step against a single issue (no code changes). Posts the interpretation comment and exits.
argument-hint: <issue-number> [owner/repo]
---

# /dry-run

Run the `interpreting-an-issue` skill against issue `${1}` (and optionally repo `${2}` if provided; defaults to current repo).

Steps:

1. Determine `ISSUE_NUMBER` from `${1}`. If missing, prompt me to provide one and exit.
2. Determine `REPO`: `${2}` if provided; else `gh repo view --json nameWithOwner -q .nameWithOwner`.
3. Generate a `RUN_ID`: `run-$(date -u +%Y%m%d-%H%M)-${REPO##*/}-${ISSUE_NUMBER}`.
4. Set run state via `lib/run-state.sh run_state_set`: `RUN_ID`, `REPO`, `ISSUE=$ISSUE_NUMBER`.
5. Invoke `superpowers:interpreting-an-issue` (this plugin's skill) with those inputs.
6. On return, summarize to the user: ambiguity_score, complexity, link to the posted comment.
7. Clear run state.

Do NOT modify code. Do NOT add labels. Do NOT push commits. This is a read-only preview.
