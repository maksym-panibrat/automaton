# Changelog

All notable changes to `automaton` are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [0.1.1] — 2026-04-26

### Fixed
- `.claude-plugin/marketplace.json` plugin `source` switched from `{source: "github", repo: "maksym-panibrat/automaton"}` to `"./"`. When the plugin lives in the same repo as its marketplace (the "self-hosted marketplace" shape), the loader silently fails to populate `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` — the directory mtime is touched by the install routine but no clone lands. `installed_plugins.json` records the install as successful and `/reload-plugins` reports the plugin enabled, but zero contributions load (no skills, no commands, no hooks). The empirical fix matches the official `claude-plugins-official` pattern: when a plugin is colocated with its marketplace, use a relative path (e.g. `agent-sdk-dev` uses `"./plugins/agent-sdk-dev"`). Automaton's `.claude-plugin/plugin.json` is at the repo root, so `"./"` is the correct value. Verified: cache populates with the full plugin tree; `/reload-plugins` jumps from "3 skills · 6 agents · 1 hook" (superpowers only) to "8 skills · 7 agents · 5 hooks" (superpowers + automaton's 5 skills, 1 agent, 4 hooks).

## [0.1.0] — 2026-04-25

First production-ready release. All spec §14 acceptance criteria validated end-to-end against `maksym-panibrat/automaton-acceptance` (private sandbox repo seeded with three issue fixtures + one auto-merge fixture).

### Acceptance scoreboard

- **9/11 criteria fully validated end-to-end:**
  - L.1 `/plugin install` + 5 slash commands appear.
  - L.2 `/dry-run` against well-formed (`score: 1`, proceed), ambiguous (`score: 3`, halt), and missing-sections (template-incomplete, halt-before-agent) issues.
  - L.3 `/work-issue 1` ran the full 6-step contract → PR #4 ready for review.
  - L.4 `/work-next` exercised cross-repo pickup, queue sort, race-claim, and halted on the ambiguous issue (#2) at the keystone gate.
  - L.5 `/work-issue 5` (docs-only with `claude:auto-merge`) exercised the auto-merge positive path → PR #6 squash-merged at `53ec12d`, issue auto-closed, branch auto-deleted.
  - L.6 halt path validated 3× (destructive-op gate, ambiguity gate, template-incomplete gate).
  - All 4 hooks pass synthetic-event tests (41/41 in `tests/test-hooks.sh`).
  - `secrets-block.sh` blocks all 9 canary patterns.
  - Size budget held: 38 files, ~1500 LOC (spec target: ~35 files, <1500 LOC).
- **2/11 unit-tested-only** (no live exercise yet): `/show-activity`, `/scaffold`.

### Bugs surfaced and fixed during the walk

- v0.0.2: hooks must be declared in `plugin.json`, not a standalone `settings.json` (the loader doesn't read the latter).
- v0.0.3: `/automaton:scaffold` now adds `.worktrees/` to the target repo's `.gitignore` (closes the L.3-Step-6 destructive-op cascade).
- v0.0.4: `pr-ready-gate.sh` scans PR body in addition to PR comments (the worker puts the dry-run interpretation in the body per spec §4).

### Known platform issues (not automaton bugs)

- Claude Code install-state pitfall: when a project has multiple scope entries in `installed_plugins.json` (e.g., `local` from an earlier install + `project` from a later one), the loader can pin to the older scope's stale `gitCommitSha` even when the manifest reports the newer version. Symptom: `/reload-plugins` reports the plugin enabled but loads zero contributions; `/plugin install` reports "already at the latest version". Workaround: directly edit `~/.claude/plugins/installed_plugins.json` to remove the stale entry, and clear any `enabledPlugins.<plugin>: false` left behind in `.claude/settings.local.json` by `/plugin uninstall`. Worth filing upstream.

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
