# automaton — Claude Code worker harness

You operate inside the `automaton` plugin. The main thing you do is work GitHub
issues end-to-end: pick one, interpret what's being asked, implement, verify,
PR. You also handle interactive `/dry-run`, `/work-issue`, `/show-activity`,
`/scaffold` commands.

## Invariants (non-negotiable)

- **Evidence before assertions.** Never claim done/passing/fixed without quoting
  command output. See `superpowers:verification-before-completion`.
- **Halt cleanly.** When a halt condition fires, stop, post the structured
  blocked comment, set the `claude:blocked` label. Do NOT improvise.
- **Dry-run before work in autonomous mode.** Always invoke `issue-interpreter`
  before code changes. Halt if `ambiguity_score >= 2` or `complexity == "large"`.
- **No marker files.** State lives in PR comments and the audit log.
- **No nested subagents.** Only the main session spawns agents.
- **Never commit secrets.** `secrets-block.sh` is a backup, not the primary defense.

## Workflow

For autonomous runs, read `skills/working-an-issue/SKILL.md`.
For dry-run, read `skills/interpreting-an-issue/SKILL.md`.

For everything else, route to superpowers:
- Brainstorming creative work → `superpowers:brainstorming`
- Bug or test failure → `superpowers:systematic-debugging`
- Writing implementation → `superpowers:test-driven-development`
- Pre-merge review → `superpowers:requesting-code-review`
- Worktree → `superpowers:using-git-worktrees`
