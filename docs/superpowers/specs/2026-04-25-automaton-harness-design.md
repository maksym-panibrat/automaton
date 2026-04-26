# `automaton` — Claude Code harness v2 (design)

**Status:** draft, awaiting user review
**Date:** 2026-04-25
**Supersedes:** the existing `panibrat-claude-harness` repo at `~/dev/panibrat-claude-harness` (referred to here as "v1")
**Owner:** Maksym Panibratenko

## 1. Context

### 1.1 What v1 tried to do

`panibrat-claude-harness` (v1) was a CCA-F-aligned Claude Code configuration with:
- 4 specialist agents (`safety-reviewer`, `issue-decomposer`, `test-author`, `plan-critic`)
- 8 hook wirings (PR-readiness gate via marker files, plan-critic gate, audit log, secrets, session-start context, etc.)
- 7 path-scoped rule files auto-loaded by glob (`safety-patterns.md`, `prompt-templates.md`, `eval-harness.md`, `rag-pipeline.md`, `api-contracts.md`, `github-actions.md`, `test-conventions.md`)
- 7 user-level rule files (`_routing.md`, `_plan-mode.md`, `_escalation.md`, `_verification.md`, `_marker-conventions.md`, `_model-defaults.md`, `_superpowers-routing.md`)
- 12 GitHub Actions workflow templates
- 3 custom skills (`design-it-twice`, `pattern-miner`, `weekly-audit-report`)
- A marker-file system at `.claude/markers/<branch>-<sha>-<source>.ok` gating PR creation
- 8 slash commands

~99 files, ~5800 LOC.

### 1.2 What went wrong

In descending impact order (per user assessment):

1. **Wrong work / spec ambiguity (E).** Worker picked up issues with hidden ambiguities, produced PRs that missed the point, requiring human cleanup. Most expensive failure mode.
2. **Over-delegation (C).** Routing pushed many operations into subagents (Explore for any 5+ file question, plan-critic on every multi-phase plan, safety-reviewer on every PR). Each subagent round-trip dwarfed the work.
3. **Adversarial gates flagged trivia (A).** `safety-reviewer` ran on every PR and produced findings on routine code; the agent spent tokens addressing or arguing with them.
4. **Plan critique = ceremony (B).** `plan-critic` produced verbose multi-section critiques on simple work that the main agent then processed before doing the actual task.
5. **Rules re-read repeatedly (D).** Many auto-loaded rules + path-scoped rules + CLAUDE.md spent budget re-establishing context every turn.

### 1.3 Constraints for v2

- **Primary use case (80%):** local autonomous issue-queue worker. Wakes on cron several times per day, picks the top `claude:ready` issue across configured repos, implements, opens PR, halts cleanly when stuck.
- **Secondary use case (20%):** lean interactive amplifier. Same slash commands available in normal Claude Code sessions.
- **Scale:** 3-8 repos, ~20-50 autonomous issues/week.
- **Cost model:** subscription quota (Pro/Max) on the autonomous loop; effectively "fill the 5h refresh window with useful work." API spend is acceptable only on event-driven cloud workflows.
- **Trust model:** human-review-by-default with opt-in auto-merge for narrow safe categories.
- **Observability:** PR-comment lifecycle + per-repo JSONL audit log + a `/show-activity` command that aggregates the day.
- **Portfolio framing:** packaged as a Claude Code plugin to demonstrate plugin-building experience.

## 2. Goals and non-goals

### Goals

- A small, debuggable Claude Code plugin (`automaton`) installable via `/plugin install`.
- A six-step worker contract that halts cleanly on ambiguity instead of producing wrong PRs.
- A cheap "dry-run interpretation" gate that catches misreads before implementation budget is spent.
- A two-label autonomy/auto-merge taxonomy (instead of v1's three-label gate stack).
- Four hooks total (audit log, secrets block, PR-ready gate, optional session-start summary). No marker-file system.
- Two GitHub Actions workflow templates total (PR review + issue triage). No autonomous-pickup workflow.
- An on-demand skill model: behavior lives in skills loaded by slash commands, not in auto-loaded rules.

### Non-goals

- Cross-repo orchestration. The worker handles one issue per run.
- Cost dashboards beyond what `/show-activity` provides.
- Auto-decomposition of high-level goals into issues (`issue-decomposer` is dropped; user writes their own issues).
- Universal scaffolding for arbitrary project types.
- Replacing or duplicating `superpowers` skills. The plugin routes to them at named inflection points.

## 3. Architecture

### 3.1 Topology

```
┌──────────────────────────────────────────────────────┐
│ LOCAL (subscription quota)                           │
│                                                      │
│   /schedule cron (every 2h, work hours)              │
│       │                                              │
│       ▼                                              │
│   Claude Code session                                │
│       │                                              │
│       ▼                                              │
│   /work-next  ────►  one issue, one repo, one PR     │
│                                                      │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│ CLOUD (API billed)                                   │
│                                                      │
│   pull_request: opened/synchronize                   │
│       │                                              │
│       ▼                                              │
│   pr-review.yml  (Sonnet)  ──►  review comment       │
│                                                      │
│   issues: opened                                     │
│       │                                              │
│       ▼                                              │
│   triage.yml  (Haiku)  ──►  priority/type labels     │
│                                                      │
└──────────────────────────────────────────────────────┘
```

The two worlds do not overlap. Local does production work. Cloud does cheap reactive labeling/review.

### 3.2 Plugin contributions

- **5 slash commands:** `/work-next`, `/work-issue`, `/show-activity`, `/dry-run`, `/scaffold`
- **1 specialist agent:** `issue-interpreter` (Sonnet 4.6, 5 tools). `safety-spotter` is a shell tool, not an agent — see §15.2.
- **4 hooks:** `audit-log.sh`, `secrets-block.sh`, `pr-ready-gate.sh`, `session-start-summary.sh`
- **1 shell tool:** `tools/safety-spotter.sh` (deterministic regex over the diff; shares `lib/secret-patterns.sh` with `secrets-block.sh`)
- **2 skills:** `working-an-issue/SKILL.md`, `interpreting-an-issue/SKILL.md`
- **2 templates:** `pr-review.yml`, `triage.yml`, plus `.claude-harness.toml`
- **1 short CLAUDE.md** (~30 lines) and `settings.json` for hook wirings

## 4. Worker contract

`/work-next` and `/work-issue NN` share one playbook (`skills/working-an-issue/SKILL.md`). Six steps, halt-on-failure semantics.

### Step 1 — Pickup

- `/work-next`: query across configured repos for issues with `claude:ready`, no `claude:in-progress`, no `claude:blocked`. Sort by `priority:p0/1/2/3` then `created_at` ASC. Pick the top one.
- `/work-issue NN`: skip pickup, use the given issue number. Ignores `claude:ready` (you typed the number, you meant it).
- Race-resistant claim: `gh issue edit NN --add-label claude:in-progress`. On conflict (someone else already added it), retry the next issue. After 3 conflicts, halt with `claude:blocked` reason "race contention".

### Step 2 — Read

Fetch issue body, repo state (current branch, recent commits on `main`, open PRs touching files mentioned in the issue). Cache `gh repo view --json nameWithOwner` as `$AUTOMATON_REPO`.

### Step 3 — Interpret (the keystone gate)

Invoke the `issue-interpreter` agent with: issue title + body, the recent-commits summary, the list of files matching any glob hints in the issue body. The agent returns a fixed-shape JSON (see §5).

Worker renders the JSON as a Markdown comment with heading **"Dry-run interpretation — please confirm or push back"** and posts it on the issue (or on the draft PR if one exists from a previous attempt).

**Halt if any of:**
- `ambiguity_score >= 2`
- `estimated_complexity == "large"`
- Required template sections missing from the issue body (Goal, Acceptance criteria, Verification — see §6)

Halt action: post a `claude:blocked` comment quoting the ambiguity, add `claude:blocked` label, remove `claude:in-progress`, exit cleanly.

### Step 4 — Work

- Create branch `claude/issue-NN-<slug>` via `superpowers:using-git-worktrees` (worktree at `.worktrees/<branch>`).
- Implement per the interpretation. Use `superpowers:test-driven-development` for new code; `superpowers:systematic-debugging` for bugfixes.
- Write commits with Conventional Commits format and `(#NN)` in subject.

### Step 5 — Verify

Run the verification commands from the issue body. Quote actual stdout in a worker-internal note (passed to step 6 for the PR comment). If tests fail and worker can't fix in **2** attempts, halt to step 6 with `claude:blocked` reason "verification failed after 2 attempts".

### Step 6 — Land

- Push the branch.
- Open a draft PR with the dry-run interpretation comment as the description (and link the issue with `Closes #NN`).
- Run `tools/safety-spotter.sh` on the diff (`git diff origin/main...HEAD`) — a deterministic shell regex check sharing the canary set with `secrets-block.sh`. If it fires, halt with `claude:blocked`.
- If issue had `claude:auto-merge` AND CI is green AND diff matches a registered auto-merge-safe pattern (§7) → `gh pr merge --auto --squash`.
- Otherwise: `gh pr ready` (mark for human review). Post the completion-summary comment.

### Halt conditions (summary)

Any of these halts the run, posts `claude:blocked`, sets the label, exits cleanly:

- Required template sections missing from issue body
- Interpreter `ambiguity_score >= 2` or `complexity == "large"`
- 2 consecutive same-approach tool failures
- Destructive operation needed beyond auto-allow (`git reset --hard`, `git push --force`, `branch -D`, `clean -fd`)
- Verification command absent and not derivable
- `safety-spotter` fires on the diff
- 3+ race-contention failures during pickup

## 5. Dry-run interpretation protocol

### 5.1 Purpose

The dry-run is the keystone fix for failure mode E. It catches misread issues for ~2-5K tokens instead of finding them out after burning 50-500K on a wrong implementation.

### 5.2 The interpreter agent

`agents/issue-interpreter.md` — Sonnet 4.6.

**Tools:** Read, Grep, Glob, Bash (restricted to `gh issue view`, `gh pr view`, `git log`).

**Inputs (passed in prompt, not inherited from caller):**
- Issue title + body (from `gh issue view NN --json title,body`)
- Recent commits to `main` (`git log --oneline -20 main`)
- File listings for any globs in the issue body
- Repo's CLAUDE.md and any project-level `.claude/CLAUDE.md`

**Output: fixed-shape JSON**

```json
{
  "interpretation": "<2-4 sentence restatement of what the worker will do>",
  "files_to_touch": ["src/foo.ts", "tests/foo.test.ts"],
  "approach": "<one paragraph: how>",
  "out_of_scope": ["<thing X explicitly not done>"],
  "ambiguity_score": 0,
  "ambiguities": [],
  "verification_plan": ["pnpm test tests/foo.test.ts"],
  "estimated_complexity": "small"
}
```

**Field specifications:**
- `ambiguity_score`: integer 0-3. 0 = unambiguous; 1 = minor open detail with a defensible default; 2 = real choice between plausible interpretations; 3 = fundamentally unclear what the user wants.
- `estimated_complexity`: enum `trivial`, `small`, `medium`, `large`. Anchored to lines-of-diff: trivial < 20, small < 100, medium < 500, large >= 500.
- `files_to_touch`: best-effort list. Empty list is allowed (interpreter doesn't know yet).

### 5.3 Comment rendering

Posted to the issue (or PR if one exists), Markdown:

```markdown
## Dry-run interpretation — please confirm or push back

**What I will do:** <interpretation>

**Files I will touch:** `src/foo.ts`, `tests/foo.test.ts`

**Approach:** <approach>

**Out of scope:** thing X, thing Y

**Verification I will run:**
- `pnpm test tests/foo.test.ts`

**Estimated complexity:** small (~50 LOC)
**Ambiguity score:** 0

---
*Run ID: `run-20260425-1432-foo-42`. To stop this run, comment "halt" on this issue or remove the `claude:in-progress` label.*
```

If `ambiguity_score >= 1`, an extra section lists each ambiguity verbatim.

### 5.4 Interactive flavor

`/dry-run NN` performs only Step 3 (interpret + post comment) and exits. No code changes. Use case: "I just wrote this issue, let me see what the worker would do before I label it `claude:ready`."

## 6. Issue body template

The interpreter and the worker both reject issues missing required sections.

```markdown
## Goal
<one-sentence outcome>

## Acceptance criteria
- [ ] <verifiable outcome 1>
- [ ] <verifiable outcome 2>

## Verification
\`\`\`
<exact commands the worker should run; stdout/exit code is the truth>
\`\`\`

## Out of scope
- <explicit non-goal>     (optional)

## Notes
<context, links, gotchas>  (optional)
```

**Required:** Goal, Acceptance criteria, Verification.

The `triage.yml` workflow comments on incomplete issues with: *"Spec template incomplete; see automaton/docs/issue-template.md"*. It does not auto-fix.

## 7. Label vocabulary

Four `claude:*` labels. Two human-set, two worker-set.

| Label | Set by | Meaning |
|---|---|---|
| `claude:ready` | human | go work this unattended via `/work-next` |
| `claude:auto-merge` | human | additionally, merge if CI green and diff matches an auto-merge-safe pattern |
| `claude:in-progress` | worker | active claim; race-resistant |
| `claude:blocked` | worker | halted; latest comment explains why |

Standard `priority:p0/1/2/3` and `type:feat/fix/chore/refactor/docs` labels are kept for queue sorting and PR title templating, but are not load-bearing in worker logic.

### 7.1 Auto-merge gate

Worker auto-merges iff **all three** hold:

1. Issue had `claude:auto-merge` at pickup time.
2. PR is green on all required CI checks (`gh pr checks --required`).
3. Diff matches a registered auto-merge-safe pattern.

Built-in patterns (configured in `.claude-harness.toml`, defaults shipped):

- **deps-bump:** only `package*.json`, `pnpm-lock.yaml`, `requirements*.txt`, `Cargo.lock`, `go.sum`, `Pipfile.lock`, `poetry.lock` changed
- **docs-only:** only `*.md`, `docs/**` changed
- **generated:** only files matching the repo's configured generated globs (e.g., `**/*.snap`, `**/dist/**` if checked in)
- **formatting:** diff is empty after running the repo's formatter against `HEAD~1`

`.claude-harness.toml` example:

```toml
[auto_merge]
patterns = ["deps-bump", "docs-only", "formatting"]

[auto_merge.generated]
globs = ["**/__snapshots__/**"]
```

## 8. Hooks

Four hooks total. The first three are required; the fourth (`session-start-summary.sh`) is opt-in via settings. All shell scripts; no external deps beyond `gh`, `jq`, `git`.

### 8.1 `audit-log.sh` — PostToolUse, Bash + Task + Edit + Write

Appends one JSONL event per tool call to `~/.claude/audit/<owner>/<repo>/<YYYY-MM-DD>.jsonl`.

Event shape (15 fields):

```json
{
  "ts": "2026-04-25T14:32:11Z",
  "run_id": "run-20260425-1432-foo-42",
  "repo": "maksym-panibrat/foo",
  "issue": 42,
  "branch": "claude/issue-42-healthz",
  "sha": "a1b2c3d",
  "phase": "verify",
  "tool": "Bash",
  "cmd_summary": "pnpm test src/api/healthz.test.ts",
  "exit": 0,
  "duration_ms": 1240
}
```

`run_id` is set as an env var by `/work-next` at pickup; `phase` is set by the worker at each step transition. `cmd_summary` is the first 80 chars of the command (no env vars, no full args).

Phase-transition events are emitted by the worker (not by the hook):

```json
{"ts":"...","run_id":"...","phase":"interpret","event":"interpreter_returned","ambiguity_score":1,"complexity":"small"}
```

Deliberately excluded: full command, file diffs, stdout/stderr content, token counts (Claude Code hooks don't expose them reliably).

### 8.2 `secrets-block.sh` — PreToolUse, Edit + Write + Bash matching write/commit patterns

Greps the staged content (or the file being written) against secret patterns: AWS keys, GitHub PATs, Anthropic keys, OpenAI keys, SSH private keys, generic high-entropy patterns near `key|secret|token|password`. Also blocks paths matching `.env*`, `*.pem`, `credentials`, `id_rsa`, `.aws/credentials`, `.ssh/`.

Block returns a non-zero exit + a clear stderr message naming the matched pattern.

### 8.3 `pr-ready-gate.sh` — PreToolUse, Bash matching `gh pr ready`

Blocks unless **both** of these are true:

1. The PR has a dry-run interpretation comment for the current run (matched by `Run ID:` in the comment body — see §5.3). The dry-run is per-run, not per-SHA: it's posted in Step 3 before any commits exist for the working branch.
2. The audit log contains a `tests_passed` phase event whose `sha` field matches the current `git rev-parse --short HEAD`. This event is per-SHA: any new commit invalidates it, and the worker must re-run verification.

This replaces v1's marker-file system. The "marker" is now (a) a human-readable PR comment scoped to the run, and (b) a structured audit event scoped to the SHA. Both are queryable, neither requires a separate file.

### 8.4 `session-start-summary.sh` — SessionStart (optional, opt-in via settings)

Runs `gh issue list --label claude:in-progress --json number,title,repository` across configured repos and injects a one-line summary: *"Heads up: 2 in-flight autonomous runs (`foo#42`, `bar#17`)."* into the session.

Not the v1 "case-facts injection" — just runtime state about background work.

## 9. Observability

### 9.1 PR-comment lifecycle

Each autonomous run posts at most three comments:

1. **Dry-run interpretation** (always, before any code work) — see §5.3.
2. **Completion summary** (on success) — files changed, verification command output snippets, "merging via auto-merge" or "ready for human review".
3. **Blocked** (only on halt) — structured per the v1 escalation template:

```markdown
## Blocked: needs human triage

**Trigger:** <which halt condition fired>

**What I attempted**
- <step 1>
- <step 2>

**What blocks progress**
<concrete description>

**Recommended next action**
- [ ] <option A>
- [ ] <option B>

**Run ID:** `run-20260425-1432-foo-42`
**Branch:** `claude/issue-42-healthz`
**HEAD SHA:** `a1b2c3d`
```

### 9.2 JSONL audit log + `/show-activity`

The audit log is at `~/.claude/audit/<owner>/<repo>/<YYYY-MM-DD>.jsonl` per §8.1.

`/show-activity` (slash command) aggregates the day across all configured repos:

```
== automaton activity, 2026-04-25 ==

Issues attempted (5):
  ✅ maksym-panibrat/foo#42  healthz endpoint            merged via auto-merge   24 tool calls   18s
  ✅ maksym-panibrat/foo#43  retry on 503                ready for review        67 tool calls   3m12s
  ⚠️  maksym-panibrat/bar#17  refactor auth middleware    blocked: ambiguous     4 tool calls    11s
  ✅ maksym-panibrat/baz#9   bump pydantic 2.10          merged via auto-merge   8 tool calls    7s
  ⚠️  maksym-panibrat/foo#44  fix flaky export test       blocked: 2 verify fails 31 tool calls   2m41s

Halt reasons:
  ambiguity_score>=2: 1
  verification failed after 2 attempts: 1

Open claude:blocked issues: 3 (use `gh issue list --label claude:blocked` to see)
```

No HTML, no separate dashboard. Grep-friendly JSONL is the whole forensics surface.

## 10. GitHub Actions thin layer

Two workflow templates ship in `templates/.github/workflows/`. Copied per-repo by `/scaffold`.

### `pr-review.yml`

```yaml
name: PR review
on: { pull_request: { types: [opened, synchronize] } }
jobs:
  review:
    runs-on: ubuntu-latest
    permissions: { pull-requests: write, contents: read }
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          model: claude-sonnet-4-6
          prompt: |
            Review this PR against its linked issue's acceptance criteria.
            Flag: correctness gaps, security issues in the diff, missing tests
            for new behavior. Skip stylistic nits unless they affect behavior.
            Bullet points, not essays. ≤200 words.
```

### `triage.yml`

```yaml
name: Issue triage
on: { issues: { types: [opened] } }
jobs:
  triage:
    runs-on: ubuntu-latest
    permissions: { issues: write }
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          model: claude-haiku-4-5
          prompt: |
            Apply at most one priority:* (p0..p3) and one type:* (feat|fix|chore|refactor|docs) label.
            Do NOT apply claude:ready — that's human-only intent.
            If issue body is missing Goal or Acceptance criteria sections, comment:
            "Spec template incomplete; see automaton/docs/issue-template.md".
```

These two are the entire CI surface from the plugin. No autonomous-pickup workflow (the local `/schedule` does that). No CVE scan, dep-bump, eval-drift, debt-scan, docs-freshness, weekly-digest, stale-PR-poke, decompose-on-label.

## 11. Plugin packaging structure

```
automaton/
├── .claude-plugin/
│   └── plugin.json                # name, version, description, author, repository
├── README.md
├── LICENSE                        # MIT
├── CHANGELOG.md
├── Makefile                       # `make check` runs shellcheck, jsonlint, hook tests
├── CLAUDE.md                      # ~30 lines: invariants + skill pointers
├── settings.json                  # plugin's own hook wirings + permissions
├── commands/
│   ├── work-next.md
│   ├── work-issue.md
│   ├── show-activity.md
│   ├── dry-run.md
│   └── scaffold.md
├── agents/
│   └── issue-interpreter.md       # Sonnet 4.6, 5 tools
├── hooks/
│   ├── audit-log.sh
│   ├── secrets-block.sh
│   ├── pr-ready-gate.sh
│   └── session-start-summary.sh
├── lib/
│   └── secret-patterns.sh         # shared canary regex set
├── tools/
│   └── safety-spotter.sh          # diff-scoped regex check (Step 6)
├── skills/
│   ├── working-an-issue/SKILL.md
│   └── interpreting-an-issue/SKILL.md
├── templates/
│   ├── .github/workflows/
│   │   ├── pr-review.yml
│   │   └── triage.yml
│   ├── .claude-harness.toml       # per-repo config (auto-merge-safe patterns)
│   └── .claude/audit/.gitignore   # `*\n!.gitignore`
└── tests/
    ├── fixtures/                  # sample issues, sample diffs
    ├── test-hooks.sh              # exercises each hook with synthetic events
    └── test-secrets-block.sh      # canary secret patterns shouldn't leak
```

Target file count: ~30 (vs v1's ~99). Target LOC: under 1500 (vs v1's ~5800).

## 12. CLAUDE.md (the ~30-line spine)

```markdown
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
```

## 13. Explicitly dropped from v1

| Dropped | Why |
|---|---|
| `issue-decomposer` agent + `/plan-issues` | Spec quality is the keystone, not spec quantity. User writes own issues. |
| `plan-critic` agent + `/critique-plan` + plan-critic gate | Over-think on simple plans. Use `superpowers:requesting-code-review` instead. |
| `safety-reviewer` heavyweight agent + adversarial gate | Too noisy on routine code. Replaced by Haiku `safety-spotter` (regex only, no judgment). |
| `test-author` agent + `/write-tests` | Use `superpowers:test-driven-development` instead. |
| 7 path-scoped rules files | Auto-load caused context bloat; not even shipping as opt-in templates. |
| 7 user-level `_*.md` rule files | Replaced by one short CLAUDE.md + on-demand skills. |
| Marker file system (`.claude/markers/`) | Bookkeeping cost > value. PR comments + audit events replace it. |
| 10 of 12 GH Actions workflows | Each adds API spend and noise. Keeping only `pr-review` + `triage`. |
| `requirements-grill` agent | Use `superpowers:brainstorming` instead. |
| `design-it-twice`, `pattern-miner`, `weekly-audit-report` skills | Don't earn keep for primary use case. |
| v1's `SessionStart` case-facts injection | Replaced by lighter `session-start-summary.sh` (just in-flight runs). |
| Settings template + complex install.sh merge logic | Plugin install model handles installation. |

## 14. Acceptance criteria for the `automaton` repo

The plugin is "v2 done" when:

- [ ] `/plugin install automaton` from a marketplace works; all five slash commands appear.
- [ ] `/work-issue NN` against a real test issue completes the 6-step contract end-to-end and opens a draft PR with a dry-run interpretation comment.
- [ ] `/work-next` against a repo with two `claude:ready` issues picks one, claims it via `claude:in-progress`, completes or blocks cleanly.
- [ ] `/dry-run NN` posts an interpretation comment and exits without touching code.
- [ ] `/show-activity` aggregates the day's audit log across configured repos.
- [ ] `/scaffold` in a fresh repo creates `.claude/audit/.gitignore`, copies the two GH workflow templates and `.claude-harness.toml`, prints the `gh secret set ANTHROPIC_API_KEY` hint.
- [ ] All four hooks pass synthetic-event tests in `tests/test-hooks.sh` (the optional session-start-summary tested in addition to the three required hooks).
- [ ] `secrets-block.sh` blocks all canary patterns in `tests/test-secrets-block.sh`.
- [ ] Auto-merge: issue with `claude:auto-merge` and a deps-bump-only diff merges automatically when CI green; same issue with non-deps changes does not.
- [ ] Halt path: issue with deliberately ambiguous body produces `claude:blocked` label + structured comment, no code commits.
- [ ] Total file count under ~35; total custom code under ~1500 LOC.

## 15. Open questions

### 15.1 Still deferred to implementation

- Exact `plugin.json` schema fields (depend on Claude Code plugin spec at time of build).
- `.claude-harness.toml` parser — `tomllib` (Python) vs a small `jq`-based pattern. Decide during implementation.

### 15.2 Resolved

- **Repo decision (2026-04-25):** `automaton` lives in a fresh repo at `~/dev/automaton/`. The existing `panibrat-claude-harness` repo will be deprecated (not renamed in place).
- **Configured-repos list (2026-04-25):** plain newline-delimited file at `~/.claude/automaton/repos`, one `owner/repo` per line, `#` comments allowed. Read by `/work-next` via `awk 'NF && !/^#/'`. Rejected: TOML/JSON (parser overkill for a flat list at this scale), `gh search --topic automaton-watch` (per-pickup network cost), env var (per-shell state is fragile). The per-repo `.claude-harness.toml` keeps its richer schema (auto-merge patterns).
- **safety-spotter (2026-04-25):** pure shell regex, no LLM call. Implemented as `tools/safety-spotter.sh`, sharing the canary regex set with `hooks/secrets-block.sh` via a sourced `lib/secret-patterns.sh`. Removes the `agents/safety-spotter.md` LLM agent entirely (plugin contributions in §3.2 drop to **1 specialist agent**: `issue-interpreter`). Rationale: deterministic, zero API cost, same canary set already enumerated in `tests/test-secrets-block.sh`; if classes of secrets emerge that regex cannot catch, an LLM step can be reintroduced behind the same interface.
- **GitHub push (2026-04-25):** push now as a public repo at `github.com/maksym-panibratenko/automaton`. Acceptance criterion §14[1] requires marketplace install (stable URL); `plugin.json.repository` needs a URL; implementation will exercise `/plugin install` against the live remote; portfolio framing benefits from visibility. Reversible (private toggle). Push action is staged after the implementation plan is produced.

## 16. Next step

Hand off to `superpowers:writing-plans` for the implementation plan.

## 17. Hook payload reference (verified 2026-04-25)

Source: `https://code.claude.com/docs/en/hooks` (canonical redirect from `https://docs.claude.com/en/docs/claude-code/hooks`, which 301s to the `code.claude.com` domain).

---

### 17.1 Common fields (all events)

Every hook receives these fields on stdin regardless of event type:

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf-19fa-41d2-8238-13269b9b3ca0.jsonl",
  "cwd": "/Users/my-project",
  "permission_mode": "default|plan|acceptEdits|auto|dontAsk|bypassPermissions",
  "hook_event_name": "PreToolUse",
  "agent_id": "string (optional, subagent only)",
  "agent_type": "string (optional, subagent only)"
}
```

---

### 17.2 PreToolUse payload

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/my-project",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_use_id": "toolu_01ABC123...",
  "tool_input": {
    // Tool-specific — see per-tool schemas below
  }
}
```

Key `tool_input` sub-schemas used by automaton hooks:

| Tool   | Relevant keys in `tool_input`                                  |
|--------|----------------------------------------------------------------|
| `Bash` | `command` (string), `description` (string, opt), `timeout` (int, opt), `run_in_background` (bool, opt) |
| `Write`| `file_path` (string), `content` (string)                       |
| `Edit` | `file_path` (string), `old_string` (string), `new_string` (string), `replace_all` (bool, opt) |
| `Read` | `file_path` (string), `offset` (int, opt), `limit` (int, opt)  |

---

### 17.3 PostToolUse payload

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/my-project",
  "permission_mode": "default",
  "hook_event_name": "PostToolUse",
  "tool_name": "Write",
  "tool_use_id": "toolu_01ABC123...",
  "duration_ms": 12,
  "tool_input": {
    "file_path": "/path/to/file.txt",
    "content": "file content"
  },
  "tool_response": {
    "filePath": "/path/to/file.txt",
    "success": true
  }
}
```

**Important:** `duration_ms` is a **top-level** field, not nested under `tool_response`. See Plan reconciliation (§17.7) for details.

---

### 17.4 SessionStart payload

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/my-project",
  "hook_event_name": "SessionStart",
  "source": "startup|resume|clear|compact",
  "model": "claude-sonnet-4-6"
}
```

Note: `SessionStart` does **not** include `permission_mode` in the common fields (it fires before the session's permission mode is established).

---

### 17.5 Exit-code semantics

#### PreToolUse
| Exit code | Behavior |
|-----------|----------|
| `0`       | Tool call proceeds. Any JSON stdout is processed for `permissionDecision` / `updatedInput` / `additionalContext`. |
| `2`       | Tool call **blocked**. stderr is shown to Claude as the reason. |
| Other     | Non-blocking error. stderr shown to user in transcript; execution continues. |

#### PostToolUse
| Exit code | Behavior |
|-----------|----------|
| `0`       | Success. JSON stdout processed; `additionalContext` injected if present. |
| `2`       | Blocking error. stderr is shown to **Claude** (tool already ran). |
| Other     | Non-blocking error. stderr shown to Claude; execution continues. |

#### SessionStart
| Exit code | Behavior |
|-----------|----------|
| `0`       | Success. Plain stdout or JSON `additionalContext` added to Claude's context. |
| `2`       | Blocking error. stderr shown to **user only**; session still starts. |
| Other     | Non-blocking error. stderr shown to user; full error in debug log. |

**Key distinction:** Exit 2 on `PreToolUse` blocks the tool. Exit 2 on `PostToolUse`/`SessionStart` does NOT block — the tool already ran / the session already started; exit 2 only controls where stderr surfaces.

---

### 17.6 Matcher syntax

Matchers live in `settings.json` under `hooks[].matcher`. The evaluation rule:

| Matcher value | Evaluated as | Example |
|---------------|-------------|---------|
| `"*"`, `""`, or omitted | Match all | — |
| Only `[A-Za-z0-9_|]` chars | Exact string or `\|`-separated list | `Bash`, `Edit\|Write` |
| Any other character present | JavaScript regex | `^Notebook`, `mcp__memory__.*` |

For `PreToolUse` / `PostToolUse` the matcher is compared against `tool_name`. Examples:

```json
"matcher": "Bash"               // exact match
"matcher": "Write|Edit"         // pipe-separated list (no regex)
"matcher": "Write|Edit|Bash"    // three tools
"matcher": "^Notebook"          // regex prefix
"matcher": "mcp__memory__.*"    // all tools from a named MCP server
```

For `SessionStart` the matcher is compared against `source` (`startup`, `resume`, `clear`, `compact`).

There is also an **`if` field** (separate from `matcher`) that uses permission-rule syntax `ToolName(pattern)` and is evaluated only on tool events. Hook runs only when the `if` expression matches. This is in addition to — not a replacement for — the `matcher`.

---

### 17.7 hookSpecificOutput schemas

#### PreToolUse output (stdout, exit 0)

```json
{
  "continue": true,
  "suppressOutput": false,
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask|defer",
    "permissionDecisionReason": "Shown to user (allow/ask) or to Claude (deny)",
    "updatedInput": { /* modified tool_input fields */ },
    "additionalContext": "string added to Claude context"
  }
}
```

Decision precedence: `deny` > `defer` > `ask` > `allow`.

To **block** a tool call: either exit 2 (stderr as reason), or exit 0 with `permissionDecision: "deny"` (reason via `permissionDecisionReason`).

#### PostToolUse output (stdout, exit 0)

```json
{
  "decision": "block",
  "reason": "Shown to Claude if decision is block",
  "continue": true,
  "suppressOutput": false,
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "string",
    "updatedMCPToolOutput": "string (MCP tools only)"
  }
}
```

#### SessionStart output (stdout, exit 0)

```json
{
  "continue": true,
  "suppressOutput": false,
  "systemMessage": "optional string",
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "string — concatenated from all SessionStart hooks"
  }
}
```

---

### 17.8 Plan reconciliation

The implementation plan (Tasks C.3, D.2, E.2, F.1) assumed several field names and semantics. Verified status:

| Plan assumption | Verified field / behavior | Status |
|-----------------|---------------------------|--------|
| `tool` (top-level key for tool name) | Actual key is **`tool_name`** | **DIVERGENCE** — tasks must use `.tool_name`, not `.tool` |
| `tool_input.file_path` | `tool_input.file_path` ✓ | Confirmed |
| `tool_input.content` | `tool_input.content` ✓ | Confirmed |
| `tool_input.new_string` | `tool_input.new_string` ✓ | Confirmed |
| `tool_input.command` | `tool_input.command` ✓ | Confirmed |
| `tool_response.exit_code` | `tool_response` shape is tool-specific; for `Write` it is `{"filePath":"...", "success": true}`. **No `exit_code` field** in the documented `PostToolUse` payload. | **DIVERGENCE** — `exit_code` is not a documented `tool_response` key; audit-log hook must not rely on it |
| `tool_response.duration_ms` | `duration_ms` exists but is a **top-level** field in `PostToolUse`, not nested under `tool_response` | **DIVERGENCE** — use `.duration_ms` (top-level), not `.tool_response.duration_ms` |
| `source` field on SessionStart | `source: "startup\|resume\|clear\|compact"` ✓ | Confirmed |
| SessionStart output: `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}` | Schema confirmed ✓ | Confirmed |
| PreToolUse blocking via exit non-zero (plan uses exit 2) | Exit 2 blocks the tool call ✓ | Confirmed |
| settings.json matcher uses tool-name regex like `Write\|Edit\|Bash` | Pipe-separated list without other special chars = exact-match list (not regex), but works as intended ✓ | Confirmed (exact-match list, not regex, but achieves same result) |

**Summary of required adjustments for subsequent tasks:**

1. **All hooks:** Replace `.tool` with `.tool_name` when reading the tool name from stdin JSON.
2. **audit-log hook (Task D.2 / E.2):** Remove any reference to `.tool_response.exit_code` — this field does not exist in the documented schema. Record `.tool_response.success` (boolean) for `Write`/`Edit`, or parse `.tool_response` as-is for other tools. The hook may safely log the raw `tool_response` object.
3. **audit-log hook (Task D.2 / E.2):** Change `.tool_response.duration_ms` → `.duration_ms` (top-level).
4. **secrets-block hook (Task C.3):** No changes needed — it reads `.tool_input.command`, `.tool_input.content`, `.tool_input.new_string`, and exits 2 to block. All confirmed.
5. **pr-ready-gate hook (Task F.1):** Reads `tool_name` and `tool_input.command`. Change `.tool` → `.tool_name`. Exit 2 semantics confirmed.
6. **session-start-summary hook (Task E.2 / wherever assigned):** `additionalContext` under `hookSpecificOutput.hookEventName: "SessionStart"` confirmed.
