# Changelog

All notable changes to `automaton` are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Pending
- L.4 (`/work-next` cross-repo pickup) and L.5 (auto-merge gate true/false paths) acceptance walks.

## [0.0.3] — 2026-04-25

### Fixed
- `/automaton:scaffold` now adds `.worktrees/` to the target repo's `.gitignore`. Without this, the worker's first run on a new repo had to make a side commit ignoring `.worktrees/` (because `superpowers:using-git-worktrees` requires the directory to be ignored), which then bled into the feature branch and violated any `## Out of scope` constraint in the issue. Surfaced by the v0.0.2 acceptance walk against `maksym-panibrat/automaton-acceptance#1` — worker correctly halted via the spec §4 destructive-op gate.

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
