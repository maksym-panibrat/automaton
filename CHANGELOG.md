# Changelog

All notable changes to `automaton` are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Deferred
- End-to-end acceptance walkthrough against a live `automaton-acceptance` test repo (spec §14 items L.2–L.6).

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
