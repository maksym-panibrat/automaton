---
description: Aggregate today's audit log across configured repos and print a summary.
argument-hint: [YYYY-MM-DD]
---

# /show-activity

Print a per-day activity report. Defaults to today (UTC); accept a `${1}` like `2026-04-25`.

Steps:

1. Determine `DAY=${1:-$(date -u +%F)}`.
2. Read configured repos.
3. For each repo, read `~/.claude/audit/$repo/$DAY.jsonl` (skip if missing).
4. Group events by `run_id`. For each run, derive:
   - issue number, title (from the first event with one) — or fetch the title via `gh issue view`.
   - outcome: `merged via auto-merge` (saw `phase=land event=auto_merged`), `ready for review` (`phase=land event=pr_ready`), `blocked: <reason>` (`phase=halt event=blocked`), or `in progress`.
   - tool-call count and total duration.
5. Format the report per spec §9.2 (header, table-ish lines, halt-reason rollup, open-blocked count).

Use only the audit JSONL files; do not call the GitHub API except to backfill issue titles when missing.
