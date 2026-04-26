---
description: Scaffold the per-repo automaton config in the current repo. Copies the two GH workflow templates, .claude-harness.toml, and .claude/audit/.gitignore.
argument-hint: (no arguments; run from inside the target repo)
---

# /scaffold

Set up the current repo to be operable by automaton.

Steps:

1. Confirm we're at the repo root: `git rev-parse --show-toplevel` matches `pwd`.
2. Confirm the repo is not already scaffolded: if `.claude-harness.toml` exists, report and exit (do not overwrite).
3. Copy templates:
   ```bash
   cp "${CLAUDE_PLUGIN_ROOT}/templates/.claude-harness.toml" .claude-harness.toml
   mkdir -p .github/workflows .claude/audit
   cp "${CLAUDE_PLUGIN_ROOT}/templates/.github/workflows/pr-review.yml"  .github/workflows/
   cp "${CLAUDE_PLUGIN_ROOT}/templates/.github/workflows/triage.yml"     .github/workflows/
   cp "${CLAUDE_PLUGIN_ROOT}/templates/.claude/audit/.gitignore"          .claude/audit/.gitignore
   ```
4. Ensure `.worktrees/` is git-ignored at the repo root. The worker uses `superpowers:using-git-worktrees` for branch isolation, which requires this. Without it, every first run has to make a side commit and then carry it into the feature branch — a real-world halt-cascade observed in the v0.0.2 acceptance walk.
   ```bash
   touch .gitignore
   grep -qxF '.worktrees/' .gitignore || printf '\n# automaton worker isolation\n.worktrees/\n' >> .gitignore
   ```
5. Append the repo to `~/.claude/automaton/repos` if not already listed:
   ```bash
   repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
   mkdir -p "$HOME/.claude/automaton"
   touch "$HOME/.claude/automaton/repos"
   grep -qxF "$repo" "$HOME/.claude/automaton/repos" || echo "$repo" >> "$HOME/.claude/automaton/repos"
   ```
5. Print the next-step hint to the user:

   ```
   Scaffolded automaton in $repo.
   Next: gh secret set ANTHROPIC_API_KEY --repo "$repo"
   Then: open issues using docs/issue-template.md.
   Add `claude:ready` to issues you want worked.
   ```

Do not commit the scaffolded files for the user — let them review.
