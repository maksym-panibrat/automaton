# automaton

A small, debuggable Claude Code plugin: a single-issue autonomous worker that picks GitHub issues from your `claude:ready` queue, interprets them, implements them, verifies, and opens a PR — halting cleanly when the work is ambiguous instead of producing wrong PRs.

## Highlights

- **6-step worker contract** — pickup → read → interpret → work → verify → land. Halt on first failure; emit a `claude:blocked` comment naming the trigger.
- **Dry-run interpretation gate** — a Sonnet 4.6 agent posts a JSON-rendered "what I will do" comment before any code changes. Halts on `ambiguity_score >= 2` or estimated complexity `large`.
- **Two-label autonomy** — humans set `claude:ready` (work it) and optionally `claude:auto-merge` (merge it on green CI for safe diff classes). Worker manages `claude:in-progress` and `claude:blocked`.
- **Four hooks, one shell tool** — secrets-block (PreToolUse), audit-log (PostToolUse), pr-ready-gate (PreToolUse), session-start-summary (opt-in), plus safety-spotter (diff-scoped regex).
- **Cloud thin layer** — two GitHub Actions workflows (`pr-review.yml`, `triage.yml`) using `anthropics/claude-code-action@v1`.

## Install

```sh
/plugin install https://github.com/maksym-panibrat/automaton
```

Then in any repo you want to operate on:

```sh
/scaffold
```

`/scaffold` copies the two workflow templates, the per-repo `.claude-harness.toml`, and adds the repo to `~/.claude/automaton/repos`. Set the secret:

```sh
gh secret set ANTHROPIC_API_KEY --repo <owner/repo>
```

## Commands

| Command | What it does |
|---|---|
| `/work-next` | Pickup the top `claude:ready` issue across configured repos and run the six-step contract. |
| `/work-issue NN [owner/repo]` | Run the contract against a specific issue. |
| `/dry-run NN [owner/repo]` | Post the dry-run interpretation only — no code changes. |
| `/show-activity [YYYY-MM-DD]` | Aggregate the day's audit log across configured repos. |
| `/scaffold` | Set up the current repo (templates + config + register in repos list). |

## Issue body template

The interpreter and worker both reject issues missing any of `## Goal`, `## Acceptance criteria`, `## Verification`. See [docs/issue-template.md](docs/issue-template.md).

## Architecture

See [docs/superpowers/specs/2026-04-25-automaton-harness-design.md](docs/superpowers/specs/2026-04-25-automaton-harness-design.md).

## License

MIT — see [LICENSE](LICENSE).
