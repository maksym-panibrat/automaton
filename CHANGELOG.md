# Changelog

All notable changes to `automaton` are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Validated
- **L.5 acceptance (auto-merge gate, positive path):** `/automaton:work-issue 5` against `maksym-panibrat/automaton-acceptance#5` (a docs-only issue with `claude:auto-merge`) ran cleanly through all 6 steps. Auto-merge gate evaluated all three conditions: `claude:auto-merge` label present ✓, no required CI checks (vacuously green) ✓, diff matches `docs-only` pattern (only `README.md` changed) ✓ — `gh pr merge --auto --squash` invoked. PR #6 merged to `main` at commit `53ec12d`, issue #5 auto-closed via `Closes #5`, feature branch auto-deleted. Spec §14 acceptance criterion #9 satisfied.

### Notes
- Real-world install-state pitfall surfaced during the L.5 setup: when a project has multiple scope entries in `installed_plugins.json` (e.g., `local` from an earlier install + `project` from a later one), Claude Code's loader can pin to the older scope's stale `gitCommitSha` even when the manifest reports the newer version. Symptom: `/reload-plugins` reports the plugin enabled but loads zero contributions, and `/plugin install` reports "already at the latest version". Workaround: directly edit `~/.claude/plugins/installed_plugins.json` to remove the stale entry, and clear any `enabledPlugins.<plugin>: false` flags in the project's `.claude/settings.local.json` left behind by `/plugin uninstall`. Worth filing upstream against Claude Code.

## [0.0.4] — 2026-04-25

### Fixed
- `hooks/pr-ready-gate.sh` now scans the PR body in addition to PR comments for the dry-run `Run ID: <id>` reference. The worker's `working-an-issue` Step 6 puts the dry-run interpretation in the PR *body* (per spec §4), but the gate previously queried only `gh pr view --json comments`, forcing the worker to manually re-post the interpretation as a comment to satisfy the gate. Now `gh pr view --json comments,body` is queried and either location passes. Surfaced by the v0.0.3 L.3 retry against `maksym-panibrat/automaton-acceptance#1` (PR #4).

### Validated
- L.3 acceptance retry: `/automaton:work-issue 1` ran cleanly through all 6 steps end-to-end. PR #4 opened draft → safety-spotter clean → both pr-ready gates satisfied (after the workaround above) → marked ready for review → completion comment posted → run state cleared.

## [0.0.3] — 2026-04-25

### Fixed
- `/automaton:scaffold` now adds `.worktrees/` to the target repo's `.gitignore`. Without this, the worker's first run on a new repo had to make a side commit ignoring `.worktrees/` (because `superpowers:using-git-worktrees` requires the directory to be ignored), which then bled into the feature branch and violated any `## Out of scope` constraint in the issue. Surfaced by the v0.0.2 acceptance walk against `maksym-panibrat/automaton-acceptance#1` — worker correctly halted via the spec §4 destructive-op gate.

### Validated
- L.4 acceptance: `/automaton:work-next` against `maksym-panibrat/automaton-acceptance` correctly read the configured-repos file, queried candidates, filtered by `claude:in-progress`/`claude:blocked` exclusions, sorted by priority then `createdAt ASC`, race-claimed `claude:in-progress`, and handed off to `automaton:working-an-issue`. The Step 3 keystone gate fired on the deliberately ambiguous fixture (#2): `ambiguity_score=3`, `complexity=large` — both halt conditions tripped, structured §5.3 comment posted, label swapped to `claude:blocked`, run state cleared. Validates cross-repo pickup logic + race-claim + halt path inside a real worker invocation.

## [0.0.2] — 2026-04-25

### Fixed
- Plugin hooks now declared in `plugin.json` directly (per `code.claude.com/docs/en/plugin-marketplaces`). The standalone `settings.json` was never read by the plugin loader, so the four hooks did not register at install time. Removed `settings.json`.

### Validated
- L.2 acceptance: `/automaton:dry-run` against three issue shapes (well-formed, ambiguous, missing-sections) on `maksym-panibrat/automaton-acceptance` — comments posted, ambiguity scoring matches the spec §5.2 rubric.
- L.3 acceptance (substantially): `/automaton:work-issue 1` ran Steps 1–5 cleanly, halted at Step 6 on the destructive-op gate (root cause: missing `.worktrees/` in `.gitignore`, fixed in 0.0.3).
- L.6 acceptance: structured §9.1 blocked comment posted, `claude:in-progress` → `claude:blocked` swap, run state cleared. Validated incidentally via the L.3 halt above.

## [0.0.1] — 2026-04-25

First public scaffold. Implementation complete through milestones A–K of the implementation plan.

### Added
- Plugin manifest (`.claude-plugin/plugin.json`).
- Five slash commands: `/work-next`, `/work-issue`, `/dry-run`, `/show-activity`, `/scaffold`.
- One agent: `issue-interpreter` (Sonnet 4.6) producing a fixed-shape JSON dry-run plan.
- Two skills: `interpreting-an-issue`, `working-an-issue` (the 6-step worker contract).
- Four hooks wired in `settings.json`:
  - `secrets-block.sh` (PreToolUse) — blocks Write/Edit/Bash carrying secret patterns.
  - `pr-ready-gate.sh` (PreToolUse on Bash) — blocks `gh pr ready` unless dry-run comment + `tests_passed` audit event for the current SHA both exist.
  - `audit-log.sh` (PostToolUse) — appends per-tool JSONL events.
  - `session-start-summary.sh` (SessionStart, opt-in) — heads-up summary of in-flight runs.
- One shell tool: `safety-spotter.sh` — diff-scoped regex check (deterministic, no LLM).
- Three lib helpers: `run-state.sh`, `secret-patterns.sh` (shared with safety-spotter), `jsonl.sh` (incl. `audit_emit_phase`).
- Two GitHub Actions workflow templates: `pr-review.yml`, `triage.yml`.
- Per-repo scaffolding: `.claude-harness.toml`, audit `.gitignore`.
- Documentation: `CLAUDE.md` spine, expanded `README.md`, `docs/issue-template.md`.
- Test harness: `tests/helpers.sh` plus 7 test files (40 assertions total) and an umbrella runner `tests/test-hooks.sh`.

### Notes
- 37 plugin files, ~1487 LOC — within the spec §14 budget (target ~35 files, <1500 LOC).
- Hook payload schema verified against live docs (spec §17). Three divergences from the plan's initial draft were reconciled (`tool` → `tool_name`, `tool_response.exit_code` removed, `duration_ms` lifted to top-level).
