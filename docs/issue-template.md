# Issue body template (required for automaton)

The automaton worker rejects issues missing any of the three required sections.

## Required structure

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

## Why each section matters

- **Goal** anchors the interpreter on outcome over implementation.
- **Acceptance criteria** are what the dry-run interpretation contract checks against.
- **Verification** is the only thing the worker treats as ground truth at Step 5; missing this means the worker cannot self-grade.

`triage.yml` will comment on issues missing required sections; the `/work-next` worker will additionally halt with `claude:blocked` reason "spec template incomplete" if it picks up a malformed issue.
