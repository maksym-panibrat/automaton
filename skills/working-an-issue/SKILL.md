---
name: working-an-issue
description: Use this when invoked from `/work-next` (after pickup) or `/work-issue NN`. Drives the six-step worker contract end-to-end: pickup, read, interpret, work, verify, land. Halts cleanly on the spec §4 halt conditions, posting a structured `claude:blocked` comment.
---

# Working an issue

Implements spec §4 verbatim. Six steps. Halt-on-failure semantics throughout.

## Preconditions

The caller has set the run-state (`lib/run-state.sh run_state_set`) for: `RUN_ID`, `REPO`, `ISSUE`, optionally `BRANCH`. The issue has `claude:in-progress` (set during pickup, or before invoking this skill via `/work-issue`).

## Step 1 — Pickup

If the caller is `/work-next`: pickup is already done, jump to Step 2. If `/work-issue NN`:
1. Verify the issue is open: `gh issue view "$ISSUE" --json state -q .state` returns `OPEN`. Else halt.
2. Add label: `gh issue edit "$ISSUE" --add-label claude:in-progress`. On failure (e.g., already labelled by another run), retry up to 3 times with backoff. After 3 race-contention failures, halt with reason "race contention".

## Step 2 — Read

```bash
gh issue view "$ISSUE" --repo "$REPO" --json title,body,labels
git checkout "$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"
git pull --ff-only
git log --oneline -20
```

Cache repo as `AUTOMATON_REPO`.

## Step 3 — Interpret (the keystone gate)

Invoke `interpreting-an-issue` skill with `ISSUE_NUMBER=$ISSUE`, `REPO=$REPO`, `RUN_ID=$RUN_ID`. If `INTERPRETER_HALTED == "yes"`, exit (the skill already posted the blocked state).

Emit a phase event:
```bash
. lib/jsonl.sh
AUTOMATON_PHASE=interpret audit_emit_phase interpret interpreter_returned
```

## Step 4 — Work

1. Compute branch name: `slug="$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//' | cut -c1-40)"`; `BRANCH="claude/issue-$ISSUE-$slug"`.
2. Use `superpowers:using-git-worktrees` to create a worktree at `.worktrees/$BRANCH`.
3. `run_state_set BRANCH "$BRANCH"`.
4. Implement per the interpretation:
   - For new code: invoke `superpowers:test-driven-development`.
   - For bugfixes: invoke `superpowers:systematic-debugging`.
5. Commits: Conventional Commits format with `(#NN)` in the subject.
6. **Halt** if 2 consecutive same-approach tool failures occur.
7. **Halt** if a destructive op is needed (`git reset --hard`, `git push --force`, `git branch -D`, `git clean -fd`).

## Step 5 — Verify

Run each command from the interpretation's `verification_plan` (or the issue's `## Verification` block, equivalent). Quote stdout in a worker-internal note for Step 6.

If a command fails:
- Attempt #1: investigate root cause via `superpowers:systematic-debugging` and apply a fix.
- Attempt #2: same.
- After 2 attempts still failing: halt with reason "verification failed after 2 attempts".

On success, emit `tests_passed`:
```bash
. lib/jsonl.sh
AUTOMATON_PHASE=verify audit_emit_phase verify tests_passed
```

## Step 6 — Land

1. `git push -u origin "$BRANCH"`.
2. `gh pr create --draft --base main --head "$BRANCH" --title "<conventional title> (#$ISSUE)" --body-file <(render_pr_body)`. The PR body is the dry-run interpretation block (verbatim) plus a "Closes #$ISSUE" line.
3. `run_state_set PR_NUMBER "$(gh pr view --json number -q .number)"`.
4. Run `tools/safety-spotter.sh < <(git diff origin/main...HEAD)`. If exit 2, halt with `claude:blocked` reason "safety-spotter fired".
5. **Auto-merge gate** (spec §7.1): if all of:
   - The original issue had `claude:auto-merge` at pickup time (cached in run state).
   - `gh pr checks --required` reports green.
   - The diff matches an auto-merge-safe pattern from `.claude-harness.toml` (`deps-bump`, `docs-only`, `generated`, `formatting`).

   then `gh pr merge --auto --squash`.
6. Else: `gh pr ready` (this fires `pr-ready-gate.sh`; if it blocks, the gate's stderr explains).
7. Post the completion-summary PR comment.
8. Clear run state: `run_state_clear`.

## Halt template

```markdown
## Blocked: needs human triage

**Trigger:** <halt reason>

**What I attempted**
- <step 1>
- <step 2>

**What blocks progress**
<concrete description>

**Recommended next action**
- [ ] <option A>
- [ ] <option B>

**Run ID:** `$RUN_ID`
**Branch:** `$BRANCH`
**HEAD SHA:** `$(git rev-parse --short HEAD)`
```

Apply via `gh issue comment` (or `gh pr comment` if a draft PR exists) and `gh issue edit --add-label claude:blocked --remove-label claude:in-progress`. Then exit cleanly.
