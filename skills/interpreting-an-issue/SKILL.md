---
name: interpreting-an-issue
description: Use when running `/dry-run NN` or executing Step 3 of `/work-next` / `/work-issue NN`. Invokes the `issue-interpreter` agent against a target issue and posts the result as a "Dry-run interpretation" comment. Halts the calling flow on `ambiguity_score >= 2` or `estimated_complexity == "large"` or missing required template sections.
---

# Interpreting an issue

This skill runs the dry-run interpretation gate (spec §5).

## Inputs

- `ISSUE_NUMBER` — required, integer.
- `REPO` — required, `owner/repo`. Defaults to `gh repo view --json nameWithOwner`.
- `RUN_ID` — required if you want the rendered comment to carry a Run ID line. The worker's pickup step provides it; for `/dry-run` invoked interactively, generate one (`run-$(date -u +%Y%m%d-%H%M)-${REPO##*/}-${ISSUE_NUMBER}`).
- `PR_NUMBER` — optional. If provided, post the dry-run comment on the PR rather than the issue.

## Steps

1. **Fetch issue.** `gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json number,title,body`. If the body is missing any of {`## Goal`, `## Acceptance criteria`, `## Verification`}, post the `claude:blocked` template (see §9.1) with reason "spec template incomplete" and exit. Do NOT invoke the agent.

2. **Gather context.**
   - `git log --oneline -20 main` (or the repo's default branch).
   - For each ` ` `glob` ` ` mentioned in the issue body, `printf '%s\n' globresult`. Combine into a `glob_hits` list.
   - Read the repo's `CLAUDE.md` if present.

3. **Invoke `issue-interpreter`.** Pass the issue title+body, recent_commits, glob_hits, repo_claude_md as the prompt. The agent returns one JSON object.

4. **Validate JSON.** Use `jq` to confirm the required fields exist. If invalid, retry once with a re-prompt that names the bad field. If still invalid, halt with `claude:blocked` reason "interpreter returned invalid JSON".

5. **Render the comment** (spec §5.3 template). Run-ID line included verbatim.

6. **Post the comment.**
   - If `$PR_NUMBER` is set: `gh pr comment "$PR_NUMBER" --repo "$REPO" --body-file <rendered>`.
   - Else: `gh issue comment "$ISSUE_NUMBER" --repo "$REPO" --body-file <rendered>`.

7. **Decide halt.**
   - If `.ambiguity_score >= 2` OR `.estimated_complexity == "large"`: halt the calling flow. Add the `claude:blocked` label, remove `claude:in-progress` if present, exit cleanly.
   - Otherwise: emit a `phase=interpret` audit event and return success to the caller.

## Outputs

- `INTERPRETER_JSON` (the raw JSON, available to the caller).
- `INTERPRETER_HALTED` ("yes" or "no").
- A posted comment whose body matches the §5.3 template.
