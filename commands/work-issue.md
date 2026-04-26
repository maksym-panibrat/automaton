---
description: Work a specific GitHub issue end-to-end. Skips the cross-repo pickup step. Use when you've already picked the issue.
argument-hint: <issue-number> [owner/repo]
---

# /work-issue

Run the six-step worker contract against issue `${1}` in repo `${2}` (defaults to current).

Steps:

1. Resolve `ISSUE_NUMBER=${1}`, `REPO=${2:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}`.
2. Generate `RUN_ID=run-$(date -u +%Y%m%d-%H%M)-${REPO##*/}-${ISSUE_NUMBER}`.
3. Set run state (`run_state_set`): RUN_ID, REPO, ISSUE.
4. Cache whether the issue carries `claude:auto-merge` for Step 6 use:
   `gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json labels` → if labels include `claude:auto-merge`, `run_state_set AUTO_MERGE 1`.
5. Add `claude:in-progress` label (race-resistant, 3 retries).
6. Invoke `superpowers:working-an-issue` skill. The skill handles Steps 2–6 of §4.
7. On halt or completion, the skill posts the appropriate comment and clears state.

Do not improvise around halt conditions; let the skill exit.
