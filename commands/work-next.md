---
description: Pick the top claude:ready issue across configured repos and run the six-step worker contract.
argument-hint: (no arguments)
---

# /work-next

Pickup + work loop. Reads `~/.claude/automaton/repos`, queries each repo for `claude:ready` issues, picks the highest priority, and hands off to the working-an-issue skill.

Steps:

1. Read configured repos:
   ```bash
   awk 'NF && !/^#/{print $1}' "${AUTOMATON_REPOS_FILE:-$HOME/.claude/automaton/repos}"
   ```
   If empty: tell me there are no configured repos and stop.

2. For each repo, query candidates:
   ```bash
   gh issue list --repo "$repo" --label claude:ready --state open --json number,title,labels,createdAt --limit 30
   ```
   Drop any whose labels include `claude:in-progress` or `claude:blocked`.

3. Sort the combined list by priority then by `createdAt` ascending. Priority order: `priority:p0` < `p1` < `p2` < `p3` < unspecified.

4. Pick the top entry. Construct `RUN_ID`. Cache `AUTO_MERGE` if `claude:auto-merge` present.

5. Race-resistant claim:
   ```bash
   gh issue edit "$ISSUE" --repo "$REPO" --add-label claude:in-progress
   ```
   On 3rd failure, halt with reason "race contention".

6. Set run state. Invoke `superpowers:working-an-issue`.

If no candidates anywhere: print a one-line "queue empty" message and exit.
