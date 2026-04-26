# Automaton Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `automaton` Claude Code plugin per the v2 design spec (`docs/superpowers/specs/2026-04-25-automaton-harness-design.md`) — a single-issue autonomous worker plugin with five slash commands, one Sonnet agent, four hooks, two skills, and two GitHub Actions templates, totalling under ~35 files and ~1500 LOC.

**Architecture:** Bash-first plugin. State persisted in PR comments and a JSONL audit log (no marker files). One agent (`issue-interpreter`, Sonnet 4.6) gates work behind a dry-run JSON; one shell tool (`safety-spotter.sh`) runs deterministic regex over diffs. The two skills (`working-an-issue`, `interpreting-an-issue`) hold the multi-step playbooks invoked from the slash commands. Local subscription quota drives `/work-next`; cloud API runs only the two `claude-code-action` workflows.

**Tech Stack:** Bash, `gh` CLI, `jq`, `git`, Claude Code plugin format, GitHub Actions, `anthropics/claude-code-action@v1`.

---

## Conventions used in this plan

- **Working directory** is `/Users/panibrat/dev/automaton/` unless stated otherwise.
- **Spec section refs** like §4.3 point at the design doc above.
- **Test runner is plain bash:** each test script `set -euo pipefail`, defines `assert_eq`, `assert_match`, `assert_blocks`, runs scenarios, exits 0/1. No bats/shunit dependency.
- **Hook payload format:** Claude Code passes a JSON event on stdin to each hook. Hooks may print JSON to stdout to influence the session, exit non-zero to block (PreToolUse). See [Claude Code hooks docs](https://docs.claude.com/en/docs/claude-code/hooks) — confirm payload field names against the live docs in Task A.5 before wiring tests.
- **Slash command format:** Markdown files in `commands/` whose body is the prompt Claude executes when the user types `/<name>`. Frontmatter declares `description`, optional `argument-hint`.
- **Agent format:** Markdown files in `agents/` with frontmatter (`name`, `description`, `tools`, `model`).
- **Skill format:** `skills/<name>/SKILL.md` with frontmatter (`name`, `description`).
- **Run state:** slash commands write `~/.claude/automaton/state/current-run.env` (key=value, sourced by hooks). Cleared on completion or halt.
- **Configured-repos file:** `~/.claude/automaton/repos`, plain text, one `owner/repo` per line, `#` comments allowed.
- **Audit log:** `~/.claude/audit/<owner>/<repo>/<YYYY-MM-DD>.jsonl`. Each line is one event, schema in §8.1.
- **Run ID format:** `run-YYYYMMDD-HHMM-<repo-suffix>-<issue-num>` (e.g., `run-20260425-1432-foo-42`). Generated once per `/work-*` invocation.
- **Commit style:** Conventional Commits with `(#NN)` for issue-scoped commits where applicable. The plugin repo itself does not have issues yet, so commits in this plan use plain Conventional Commits without issue numbers.

---

## File map (what gets created, where)

```
automaton/
├── .claude-plugin/
│   └── plugin.json                              # A.1
├── .gitignore                                    # already exists
├── CHANGELOG.md                                  # A.4
├── CLAUDE.md                                     # K.1
├── LICENSE                                       # already exists
├── Makefile                                      # A.3
├── README.md                                     # already exists, expand in K.2
├── settings.json                                 # C.4 + D.3 + E.3 + F.2 (finalized K.3)
├── agents/
│   └── issue-interpreter.md                      # G.1
├── commands/
│   ├── dry-run.md                                # H.1
│   ├── work-issue.md                             # H.2
│   ├── work-next.md                              # H.3
│   ├── show-activity.md                          # H.4
│   └── scaffold.md                               # H.5
├── hooks/
│   ├── audit-log.sh                              # D.2
│   ├── pr-ready-gate.sh                          # E.2
│   ├── secrets-block.sh                          # C.3
│   └── session-start-summary.sh                  # F.1
├── lib/
│   ├── secret-patterns.sh                        # C.2
│   ├── run-state.sh                              # B.2
│   └── jsonl.sh                                  # D.1 (extended in E.1)
├── skills/
│   ├── interpreting-an-issue/
│   │   └── SKILL.md                              # G.2
│   └── working-an-issue/
│       └── SKILL.md                              # G.3
├── templates/
│   ├── .claude/
│   │   └── audit/
│   │       └── .gitignore                        # J.1
│   ├── .claude-harness.toml                      # J.2
│   └── .github/
│       └── workflows/
│           ├── pr-review.yml                     # I.1
│           └── triage.yml                        # I.2
├── tools/
│   └── safety-spotter.sh                         # C.5
├── docs/
│   ├── issue-template.md                         # J.3
│   └── superpowers/
│       ├── specs/
│       │   └── 2026-04-25-automaton-harness-design.md  # exists
│       └── plans/
│           └── 2026-04-25-automaton-plugin-implementation.md  # this file
└── tests/
    ├── helpers.sh                                # B.1
    ├── fixtures/
    │   ├── secrets/                              # 7 files, C.1
    │   ├── issues/
    │   │   ├── well-formed.json                  # G.1
    │   │   ├── ambiguous.json                    # G.1
    │   │   └── missing-sections.json             # G.1
    │   └── diffs/
    │       ├── clean.diff                        # C.5
    │       └── leaks-aws-key.diff                # C.5
    ├── test-run-state.sh                         # B.2
    ├── test-secret-patterns.sh                   # C.2
    ├── test-secrets-block.sh                     # C.3
    ├── test-safety-spotter.sh                    # C.5
    ├── test-audit-log.sh                         # D.2
    ├── test-pr-ready-gate.sh                     # E.2
    ├── test-session-start-summary.sh             # F.1
    └── test-hooks.sh                             # K.4 (umbrella runner)
```

Total target: ~33 files, ~1400 LOC.

---

## Milestone A — Plugin shell

Goal: `/plugin install ./automaton` (local path) succeeds; the plugin appears in `/plugin list`. No behavior yet.

### Task A.1: Create `plugin.json`

**Files:**
- Create: `.claude-plugin/plugin.json`

- [ ] **Step 1: Create the manifest**

```bash
mkdir -p .claude-plugin
```

Write `.claude-plugin/plugin.json`:

```json
{
  "name": "automaton",
  "description": "Single-issue autonomous worker harness for Claude Code: pickup, dry-run interpretation, implementation, verification, PR — with halt-on-ambiguity and human-review-by-default.",
  "version": "0.0.1",
  "author": {
    "name": "Maksym Panibratenko",
    "email": "maksym@panibrat.com"
  },
  "homepage": "https://github.com/maksym-panibratenko/automaton",
  "repository": "https://github.com/maksym-panibratenko/automaton",
  "license": "MIT",
  "keywords": ["automation", "github-issues", "worker", "ci", "harness"]
}
```

- [ ] **Step 2: Validate JSON**

Run:
```bash
jq . .claude-plugin/plugin.json
```
Expected: pretty-printed JSON, exit 0.

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "feat: add plugin.json manifest"
```

### Task A.2: Create empty top-level scaffolding

**Files:**
- Create: `Makefile`, `CHANGELOG.md`

- [ ] **Step 1: Write `Makefile`**

```makefile
.PHONY: check test lint fmt clean

check: lint test

lint:
	@command -v shellcheck >/dev/null || { echo "shellcheck required"; exit 1; }
	@find hooks tools lib tests -name '*.sh' -print0 | xargs -0 shellcheck -x

test:
	@bash tests/test-hooks.sh

fmt:
	@command -v shfmt >/dev/null && find hooks tools lib tests -name '*.sh' -print0 | xargs -0 shfmt -w -i 2 -ci || echo "shfmt not installed; skipping"

clean:
	@find . -name '*.tmp' -delete
```

- [ ] **Step 2: Write `CHANGELOG.md`**

```markdown
# Changelog

All notable changes to `automaton` are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added
- Initial scaffolding: plugin.json, Makefile, CHANGELOG, design spec, implementation plan.
```

- [ ] **Step 3: Commit**

```bash
git add Makefile CHANGELOG.md
git commit -m "chore: scaffold Makefile and CHANGELOG"
```

### Task A.3: Verify plugin loads locally

- [ ] **Step 1: Install from local path**

Run in a fresh Claude Code session:
```
/plugin install /Users/panibrat/dev/automaton
```
Expected: success message naming `automaton` v0.0.1.

If the install command requires a marketplace URL instead of a local path, document the gap and stub a marketplace JSON in a `marketplace/` subdirectory. (The Claude Code plugin install spec at the time of build determines this — verify against [docs/plugins](https://docs.claude.com/en/docs/claude-code/plugins) before assuming.)

- [ ] **Step 2: Confirm listing**

Run:
```
/plugin list
```
Expected: `automaton 0.0.1` appears in output.

- [ ] **Step 3: No commit needed** (verification only).

### Task A.4: Verify hook event payload schema against live docs

This is a research task to lock the contract before writing hooks.

- [ ] **Step 1: Fetch hook docs**

Use `WebFetch` against `https://docs.claude.com/en/docs/claude-code/hooks` (or the equivalent current URL). Capture:
  - Exact JSON keys passed on stdin for `PreToolUse`, `PostToolUse`, `SessionStart`.
  - Whether the matcher syntax is `tool` name, command regex, or both.
  - Exit-code semantics (0 = allow; non-zero PreToolUse = block; other PostToolUse exits).
  - The `hookSpecificOutput` schema for SessionStart `additionalContext` injection.

- [ ] **Step 2: Record findings**

Append a "Hook payload reference" section at the bottom of `docs/superpowers/specs/2026-04-25-automaton-harness-design.md` with the verified schema. Future task code references this section.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-04-25-automaton-harness-design.md
git commit -m "docs(spec): append verified hook payload reference"
```

---

## Milestone B — Test harness foundation

Goal: bash test infrastructure that all hook/tool tests can use; run-state library shared by hooks and slash commands.

### Task B.1: Create `tests/helpers.sh`

**Files:**
- Create: `tests/helpers.sh`

- [ ] **Step 1: Write the helpers**

```bash
#!/usr/bin/env bash
# tests/helpers.sh — shared assertions and fixtures for automaton tests.
# Source this from each test-*.sh.

set -euo pipefail

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_FAILED_NAMES=()

_red()   { printf '\033[31m%s\033[0m' "$*"; }
_green() { printf '\033[32m%s\033[0m' "$*"; }
_dim()   { printf '\033[2m%s\033[0m'  "$*"; }

assert_eq() {
  local expected="$1" actual="$2" name="${3:-assert_eq}"
  if [[ "$expected" == "$actual" ]]; then
    TESTS_PASSED=$((TESTS_PASSED+1))
    printf '  %s %s\n' "$(_green ✓)" "$name"
  else
    TESTS_FAILED=$((TESTS_FAILED+1))
    TESTS_FAILED_NAMES+=("$name")
    printf '  %s %s\n      expected: %s\n      actual:   %s\n' "$(_red ✗)" "$name" "$expected" "$actual"
  fi
}

assert_match() {
  local pattern="$1" actual="$2" name="${3:-assert_match}"
  if [[ "$actual" =~ $pattern ]]; then
    TESTS_PASSED=$((TESTS_PASSED+1))
    printf '  %s %s\n' "$(_green ✓)" "$name"
  else
    TESTS_FAILED=$((TESTS_FAILED+1))
    TESTS_FAILED_NAMES+=("$name")
    printf '  %s %s\n      pattern: %s\n      actual:  %s\n' "$(_red ✗)" "$name" "$pattern" "$actual"
  fi
}

assert_blocks() {
  # Runs $1 (a script path) with stdin from $2 (json string). Asserts non-zero exit.
  local script="$1" payload="$2" name="${3:-assert_blocks}"
  if printf '%s' "$payload" | "$script" >/dev/null 2>&1; then
    TESTS_FAILED=$((TESTS_FAILED+1))
    TESTS_FAILED_NAMES+=("$name")
    printf '  %s %s (expected block, got allow)\n' "$(_red ✗)" "$name"
  else
    TESTS_PASSED=$((TESTS_PASSED+1))
    printf '  %s %s\n' "$(_green ✓)" "$name"
  fi
}

assert_allows() {
  local script="$1" payload="$2" name="${3:-assert_allows}"
  if printf '%s' "$payload" | "$script" >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED+1))
    printf '  %s %s\n' "$(_green ✓)" "$name"
  else
    TESTS_FAILED=$((TESTS_FAILED+1))
    TESTS_FAILED_NAMES+=("$name")
    printf '  %s %s (expected allow, got block)\n' "$(_red ✗)" "$name"
  fi
}

with_tmp_home() {
  # Sets HOME to a fresh temp dir for the duration of one test, then restores.
  local _orig="$HOME"
  HOME="$(mktemp -d)"
  export HOME
  "$@"
  local rc=$?
  rm -rf "$HOME"
  HOME="$_orig"
  export HOME
  return $rc
}

summary() {
  echo
  if (( TESTS_FAILED == 0 )); then
    printf '%s %d passed\n' "$(_green PASS)" "$TESTS_PASSED"
    return 0
  fi
  printf '%s %d passed, %d failed\n' "$(_red FAIL)" "$TESTS_PASSED" "$TESTS_FAILED"
  for n in "${TESTS_FAILED_NAMES[@]}"; do printf '    - %s\n' "$n"; done
  return 1
}
```

- [ ] **Step 2: Sanity check helpers load**

```bash
bash -n tests/helpers.sh
```
Expected: exit 0 (syntax OK).

- [ ] **Step 3: Commit**

```bash
git add tests/helpers.sh
git commit -m "test: add shared bash test helpers"
```

### Task B.2: Add `lib/run-state.sh`

**Files:**
- Create: `lib/run-state.sh`

- [ ] **Step 1: Write a failing test**

Create `tests/test-run-state.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/helpers.sh"
. "$DIR/lib/run-state.sh"

echo "tests: run-state"

t_set_get_clear() {
  local statedir; statedir="$(mktemp -d)"
  AUTOMATON_STATE_DIR="$statedir" run_state_set RUN_ID "run-X"
  AUTOMATON_STATE_DIR="$statedir" run_state_set REPO "owner/foo"
  local got; got="$(AUTOMATON_STATE_DIR="$statedir" run_state_get RUN_ID)"
  assert_eq "run-X" "$got" "set+get round-trips RUN_ID"
  AUTOMATON_STATE_DIR="$statedir" run_state_clear
  got="$(AUTOMATON_STATE_DIR="$statedir" run_state_get RUN_ID || echo MISSING)"
  assert_eq "MISSING" "$got" "clear removes the file"
  rm -rf "$statedir"
}

t_get_missing_returns_nonzero() {
  local statedir; statedir="$(mktemp -d)"
  if AUTOMATON_STATE_DIR="$statedir" run_state_get RUN_ID >/dev/null 2>&1; then
    assert_eq "nonzero" "zero" "get on missing file should fail"
  else
    assert_eq "nonzero" "nonzero" "get on missing file fails as expected"
  fi
  rm -rf "$statedir"
}

t_set_get_clear
t_get_missing_returns_nonzero
summary
```

```bash
chmod +x tests/test-run-state.sh
bash tests/test-run-state.sh
```
Expected: FAIL — `lib/run-state.sh` does not exist.

- [ ] **Step 2: Implement `lib/run-state.sh`**

```bash
#!/usr/bin/env bash
# lib/run-state.sh — read/write the current-run state file.
# Sourced by hooks and slash commands. Does not exit on its own.
#
# State directory: ${AUTOMATON_STATE_DIR:-$HOME/.claude/automaton/state}
# State file:      $AUTOMATON_STATE_DIR/current-run.env
# File format:     KEY=value (one per line, no quoting, no spaces in keys).

_run_state_dir() { printf '%s' "${AUTOMATON_STATE_DIR:-$HOME/.claude/automaton/state}"; }
_run_state_file() { printf '%s/current-run.env' "$(_run_state_dir)"; }

run_state_set() {
  local key="$1" value="$2"
  local dir file
  dir="$(_run_state_dir)"
  file="$(_run_state_file)"
  mkdir -p "$dir"
  if [[ -f "$file" ]] && grep -q "^${key}=" "$file" 2>/dev/null; then
    local tmp; tmp="$(mktemp)"
    grep -v "^${key}=" "$file" > "$tmp" || true
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

run_state_get() {
  local key="$1"
  local file; file="$(_run_state_file)"
  [[ -f "$file" ]] || return 1
  local line; line="$(grep "^${key}=" "$file" 2>/dev/null | tail -1)"
  [[ -n "$line" ]] || return 1
  printf '%s' "${line#*=}"
}

run_state_clear() {
  local file; file="$(_run_state_file)"
  [[ -f "$file" ]] && rm -f "$file"
  return 0
}

run_state_load_env() {
  # Source the file as KEY=value pairs, exporting AUTOMATON_<KEY>.
  local file; file="$(_run_state_file)"
  [[ -f "$file" ]] || return 0
  while IFS='=' read -r k v; do
    [[ -z "$k" || "$k" =~ ^# ]] && continue
    export "AUTOMATON_${k}=${v}"
  done < "$file"
}
```

- [ ] **Step 3: Run tests, expect pass**

```bash
bash tests/test-run-state.sh
```
Expected: `PASS 2 passed`.

- [ ] **Step 4: Lint**

```bash
shellcheck -x lib/run-state.sh tests/test-run-state.sh
```
Expected: no findings.

- [ ] **Step 5: Commit**

```bash
git add lib/run-state.sh tests/test-run-state.sh
git commit -m "feat(lib): add run-state read/write/clear with tests"
```

---

## Milestone C — Secrets defenses

Goal: `lib/secret-patterns.sh` (the canary regex set), `hooks/secrets-block.sh` (PreToolUse), `tools/safety-spotter.sh` (diff-scoped), all canary-tested.

### Task C.1: Enumerate canary patterns

**Files:**
- Create: `tests/fixtures/secrets/` (six fixture inputs)

- [ ] **Step 1: Create canary fixtures**

```bash
mkdir -p tests/fixtures/secrets
```

Create `tests/fixtures/secrets/aws-access-key.txt`:
```
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
```

Create `tests/fixtures/secrets/github-pat.txt`:
```
gh_token: ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

Create `tests/fixtures/secrets/anthropic-key.txt`:
```
ANTHROPIC_API_KEY=sk-ant-api03-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Create `tests/fixtures/secrets/openai-key.txt`:
```
OPENAI_API_KEY=sk-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

Create `tests/fixtures/secrets/ssh-private.txt`:
```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABAblahblahblahblah
-----END OPENSSH PRIVATE KEY-----
```

Create `tests/fixtures/secrets/generic-high-entropy.txt`:
```
api_secret = "a3Z9!q1bD7nLp2Xv8YkM4cR0gWj5HfTeUiOoSsAd"
```

Create `tests/fixtures/secrets/clean.txt` (must NOT match):
```
This file describes how to set ANTHROPIC_API_KEY in your environment without leaking real values.
Example placeholder: ANTHROPIC_API_KEY=<your-key-here>
```

- [ ] **Step 2: Commit fixtures**

```bash
git add tests/fixtures/secrets/
git commit -m "test(fixtures): add secret canaries and a clean control"
```

### Task C.2: Implement `lib/secret-patterns.sh`

**Files:**
- Create: `lib/secret-patterns.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-secret-patterns.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/helpers.sh"
. "$DIR/lib/secret-patterns.sh"

echo "tests: secret-patterns"

scan() { secret_patterns_scan_text "$(cat "$1")"; }

for f in tests/fixtures/secrets/aws-access-key.txt \
         tests/fixtures/secrets/github-pat.txt \
         tests/fixtures/secrets/anthropic-key.txt \
         tests/fixtures/secrets/openai-key.txt \
         tests/fixtures/secrets/ssh-private.txt \
         tests/fixtures/secrets/generic-high-entropy.txt; do
  if scan "$f" >/dev/null; then
    assert_eq "match" "match" "$(basename "$f") matches"
  else
    assert_eq "match" "nomatch" "$(basename "$f") matches"
  fi
done

if scan tests/fixtures/secrets/clean.txt >/dev/null; then
  assert_eq "nomatch" "match" "clean.txt does not match"
else
  assert_eq "nomatch" "nomatch" "clean.txt does not match"
fi

# Path-based: secrets-y filenames
if secret_patterns_scan_path ".env.production" >/dev/null; then
  assert_eq "match" "match" ".env.production path matches"
else
  assert_eq "match" "nomatch" ".env.production path matches"
fi
if secret_patterns_scan_path "src/foo.ts" >/dev/null; then
  assert_eq "nomatch" "match" "src/foo.ts path does not match"
else
  assert_eq "nomatch" "nomatch" "src/foo.ts path does not match"
fi

summary
```

```bash
chmod +x tests/test-secret-patterns.sh
bash tests/test-secret-patterns.sh
```
Expected: FAIL — `lib/secret-patterns.sh` missing.

- [ ] **Step 2: Implement the patterns**

Create `lib/secret-patterns.sh`:

```bash
#!/usr/bin/env bash
# lib/secret-patterns.sh — canary regex set for secret detection.
# Used by hooks/secrets-block.sh and tools/safety-spotter.sh.
#
# Two functions:
#   secret_patterns_scan_text   — scan stdin or a string arg; print first match line; exit 0 if matched.
#   secret_patterns_scan_path   — check a single path against secrets-y filenames; exit 0 if matched.

# Regex catalog. Keep ordered: high-confidence first.
SECRET_PATTERNS_CONTENT=(
  # AWS
  '\bAKIA[0-9A-Z]{16}\b'                                             # AWS access key id
  '\baws_secret_access_key[[:space:]]*=[[:space:]]*[A-Za-z0-9/+=]{40}\b'
  # GitHub
  '\bgh[pousr]_[A-Za-z0-9]{30,}\b'                                   # GitHub PAT family
  '\bgithub_pat_[A-Za-z0-9_]{20,}\b'
  # Anthropic
  '\bsk-ant-api[0-9]{2}-[A-Za-z0-9_-]{40,}\b'
  # OpenAI
  '\bsk-[A-Za-z0-9]{32,}\b'
  # SSH/PGP
  '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'
  # Generic: key=value with high-entropy 32+ chars near credential keywords
  '(api[_-]?secret|api[_-]?key|password|access[_-]?token|auth[_-]?token)[[:space:]]*[:=][[:space:]]*"?[A-Za-z0-9!@#$%^&*()_+=/-]{32,}"?'
)

SECRET_PATTERNS_PATHS=(
  '(^|/)\.env(\..+)?$'
  '(^|/)credentials(\..+)?$'
  '(^|/)id_rsa(\..+)?$'
  '\.pem$'
  '(^|/)\.aws/credentials$'
  '(^|/)\.ssh/'
)

secret_patterns_scan_text() {
  local input
  if [[ $# -gt 0 ]]; then input="$1"; else input="$(cat)"; fi
  for pat in "${SECRET_PATTERNS_CONTENT[@]}"; do
    local hit
    hit="$(printf '%s\n' "$input" | grep -E -m1 "$pat" || true)"
    if [[ -n "$hit" ]]; then
      printf 'pattern=%s\n%s\n' "$pat" "$hit"
      return 0
    fi
  done
  return 1
}

secret_patterns_scan_path() {
  local p="$1"
  for pat in "${SECRET_PATTERNS_PATHS[@]}"; do
    if [[ "$p" =~ $pat ]]; then
      printf 'path-pattern=%s\n' "$pat"
      return 0
    fi
  done
  return 1
}
```

- [ ] **Step 3: Run tests**

```bash
bash tests/test-secret-patterns.sh
```
Expected: `PASS 9 passed` (6 canary content checks + 1 clean control + 2 path checks).

- [ ] **Step 4: Lint**

```bash
shellcheck -x lib/secret-patterns.sh tests/test-secret-patterns.sh
```
Expected: no findings.

- [ ] **Step 5: Commit**

```bash
git add lib/secret-patterns.sh tests/test-secret-patterns.sh
git commit -m "feat(lib): add secret-patterns regex set with canary tests"
```

### Task C.3: Implement `hooks/secrets-block.sh`

**Files:**
- Create: `hooks/secrets-block.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-secrets-block.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/helpers.sh"
HOOK="$DIR/hooks/secrets-block.sh"

echo "tests: secrets-block hook"

# Synthetic PreToolUse payloads. Format must match the verified hook payload
# schema from Task A.4. Adjust keys here if the live schema differs.

mk_write() {
  # $1 = file_path; $2 = content
  jq -nc --arg p "$1" --arg c "$2" \
    '{tool_name:"Write", tool_input:{file_path:$p, content:$c}}'
}
mk_edit() {
  jq -nc --arg p "$1" --arg c "$2" \
    '{tool_name:"Edit", tool_input:{file_path:$p, new_string:$c}}'
}
mk_bash() {
  jq -nc --arg cmd "$1" '{tool_name:"Bash", tool_input:{command:$cmd}}'
}

# Block: writing AWS key to a .ts file
P_AWS="$(mk_write "src/config.ts" "const KEY='AKIAIOSFODNN7EXAMPLE';")"
assert_blocks "$HOOK" "$P_AWS" "blocks Write of AWS access key"

# Block: writing to .env
P_ENV="$(mk_write ".env.production" "DB_URL=postgres://localhost/db")"
assert_blocks "$HOOK" "$P_ENV" "blocks Write to .env.production"

# Block: editing in an SSH key
P_SSH="$(mk_edit "scripts/deploy.sh" "$(cat tests/fixtures/secrets/ssh-private.txt)")"
assert_blocks "$HOOK" "$P_SSH" "blocks Edit injecting an SSH private key"

# Block: bash heredoc writing a token
P_HEREDOC="$(mk_bash 'cat > config.json <<EOF
{"token":"ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
EOF')"
assert_blocks "$HOOK" "$P_HEREDOC" "blocks bash heredoc with GitHub PAT"

# Allow: routine src edit with no secrets
P_OK="$(mk_write "src/foo.ts" "export const greeting = 'hello';")"
assert_allows "$HOOK" "$P_OK" "allows ordinary code"

# Allow: docs that mention secrets without actually containing them
P_DOCS="$(mk_write "docs/secrets.md" "$(cat tests/fixtures/secrets/clean.txt)")"
assert_allows "$HOOK" "$P_DOCS" "allows clean documentation"

# Allow: non-write/edit/commit bash command
P_LS="$(mk_bash "ls -la")"
assert_allows "$HOOK" "$P_LS" "allows non-write bash"

summary
```

```bash
chmod +x tests/test-secrets-block.sh
bash tests/test-secrets-block.sh
```
Expected: FAIL — hook missing.

- [ ] **Step 2: Implement the hook**

Create `hooks/secrets-block.sh`:

```bash
#!/usr/bin/env bash
# hooks/secrets-block.sh — PreToolUse hook. Blocks tool calls that would write
# secrets to disk. Matches Edit/Write directly, and Bash commands that look
# like writes/commits (>, tee, heredoc, git commit, git stash store).
#
# Block = exit non-zero with a stderr message naming the matched pattern.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/lib/secret-patterns.sh"

payload="$(cat)"
tool_name="$(jq -r '.tool_name // empty' <<<"$payload")"

block() {
  printf 'BLOCKED by automaton/secrets-block: %s\n' "$1" >&2
  exit 2
}

scan_content() {
  local content="$1" path="${2:-}"
  if [[ -n "$path" ]] && secret_patterns_scan_path "$path" >/dev/null; then
    block "path matches secret-bearing filename ($path)"
  fi
  if [[ -n "$content" ]]; then
    local hit
    hit="$(secret_patterns_scan_text "$content" || true)"
    [[ -n "$hit" ]] && block "content matches secret pattern: ${hit%%$'\n'*}"
  fi
}

case "$tool_name" in
  Write)
    path="$(jq -r '.tool_input.file_path // ""' <<<"$payload")"
    content="$(jq -r '.tool_input.content // ""' <<<"$payload")"
    scan_content "$content" "$path"
    ;;
  Edit)
    path="$(jq -r '.tool_input.file_path // ""' <<<"$payload")"
    new="$(jq -r '.tool_input.new_string // ""' <<<"$payload")"
    scan_content "$new" "$path"
    ;;
  Bash)
    cmd="$(jq -r '.tool_input.command // ""' <<<"$payload")"
    case "$cmd" in
      *">"*|*"tee "*|*"<<"*|"git commit"*|"git stash store"*|"git tag"*)
        scan_content "$cmd" ""
        ;;
      *) : ;;
    esac
    ;;
  *) : ;;
esac

exit 0
```

```bash
chmod +x hooks/secrets-block.sh
```

- [ ] **Step 3: Run tests, expect pass**

```bash
bash tests/test-secrets-block.sh
```
Expected: `PASS 7 passed`.

- [ ] **Step 4: Lint**

```bash
shellcheck -x hooks/secrets-block.sh tests/test-secrets-block.sh
```
Expected: no findings.

- [ ] **Step 5: Commit**

```bash
git add hooks/secrets-block.sh tests/test-secrets-block.sh
git commit -m "feat(hooks): add secrets-block PreToolUse hook with canary tests"
```

### Task C.4: Wire `secrets-block.sh` in `settings.json`

**Files:**
- Create: `settings.json`

- [ ] **Step 1: Write minimal `settings.json`**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/secrets-block.sh" }
        ]
      }
    ]
  }
}
```

(If `${CLAUDE_PLUGIN_ROOT}` is not the supported variable per Task A.4 findings, swap to the verified placeholder.)

- [ ] **Step 2: Validate JSON**

```bash
jq . settings.json
```
Expected: pretty-printed, exit 0.

- [ ] **Step 3: Commit**

```bash
git add settings.json
git commit -m "feat(settings): wire secrets-block PreToolUse hook"
```

### Task C.5: Implement `tools/safety-spotter.sh`

**Files:**
- Create: `tools/safety-spotter.sh`, `tests/fixtures/diffs/leaks-aws-key.diff`, `tests/fixtures/diffs/clean.diff`

- [ ] **Step 1: Create fixtures**

Create `tests/fixtures/diffs/leaks-aws-key.diff`:

```diff
diff --git a/src/config.ts b/src/config.ts
index 0000000..1111111 100644
--- a/src/config.ts
+++ b/src/config.ts
@@ -1,2 +1,3 @@
 export const REGION = 'us-east-1';
+export const KEY = 'AKIAIOSFODNN7EXAMPLE';
```

Create `tests/fixtures/diffs/clean.diff`:

```diff
diff --git a/src/foo.ts b/src/foo.ts
index 0000000..1111111 100644
--- a/src/foo.ts
+++ b/src/foo.ts
@@ -1,2 +1,3 @@
 export const greeting = 'hello';
+export const farewell = 'bye';
```

- [ ] **Step 2: Write the failing test**

Create `tests/test-safety-spotter.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/helpers.sh"
SPOTTER="$DIR/tools/safety-spotter.sh"

echo "tests: safety-spotter"

# Spotter reads a diff on stdin. Exit 0 = clean. Exit 2 = secret found.

run_status() {
  local f="$1"
  if "$SPOTTER" < "$f" >/dev/null 2>&1; then echo 0; else echo $?; fi
}

assert_eq "0" "$(run_status tests/fixtures/diffs/clean.diff)" "clean diff exits 0"
assert_eq "2" "$(run_status tests/fixtures/diffs/leaks-aws-key.diff)" "leaking diff exits 2"

# Only added lines (lines starting with '+', not '+++') are scanned;
# diff context that contains the same string but not a real new addition does not fire.
CTX_DIFF="$(mktemp)"
cat > "$CTX_DIFF" <<'EOF'
diff --git a/README.md b/README.md
index 0000000..1111111 100644
--- a/README.md
+++ b/README.md
@@ -1,3 +1,4 @@
 The fixture file contains AKIAIOSFODNN7EXAMPLE for testing.
 (this is unchanged context, not an added line)
+No secrets here.
EOF
assert_eq "0" "$(run_status "$CTX_DIFF")" "context-only line with canary string is not flagged"
rm -f "$CTX_DIFF"

summary
```

```bash
chmod +x tests/test-safety-spotter.sh
bash tests/test-safety-spotter.sh
```
Expected: FAIL — spotter missing.

- [ ] **Step 3: Implement the spotter**

Create `tools/safety-spotter.sh`:

```bash
#!/usr/bin/env bash
# tools/safety-spotter.sh — diff-scoped secret scan.
# Reads a unified-diff on stdin. Considers only ADDED lines (lines starting
# with '+' but not the '+++ b/...' file header). Exit 0 if clean, exit 2 if
# any added line matches a known secret pattern.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/lib/secret-patterns.sh"

added=""
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    "+++ "*) continue ;;
    "+"*)    added+="${line:1}"$'\n' ;;
    *) : ;;
  esac
done

if [[ -z "$added" ]]; then
  exit 0
fi

if hit="$(secret_patterns_scan_text "$added")"; then
  printf 'BLOCKED by automaton/safety-spotter: secret in added lines\n%s\n' "$hit" >&2
  exit 2
fi

exit 0
```

```bash
chmod +x tools/safety-spotter.sh
```

- [ ] **Step 4: Run tests**

```bash
bash tests/test-safety-spotter.sh
```
Expected: `PASS 3 passed`.

- [ ] **Step 5: Lint**

```bash
shellcheck -x tools/safety-spotter.sh tests/test-safety-spotter.sh
```
Expected: no findings.

- [ ] **Step 6: Commit**

```bash
git add tools/safety-spotter.sh tests/test-safety-spotter.sh tests/fixtures/diffs/
git commit -m "feat(tools): add safety-spotter diff scanner with canary tests"
```

---

## Milestone D — Audit log

Goal: `hooks/audit-log.sh` writes one JSONL line per Bash/Edit/Write/Task tool call to `~/.claude/audit/<owner>/<repo>/<YYYY-MM-DD>.jsonl`, with the §8.1 schema.

### Task D.1: Implement `lib/jsonl.sh`

**Files:**
- Create: `lib/jsonl.sh`

- [ ] **Step 1: Write helper**

```bash
#!/usr/bin/env bash
# lib/jsonl.sh — append a JSON line to a JSONL file, creating parent dirs.

jsonl_append() {
  local file="$1" json="$2"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$json" >> "$file"
}

jsonl_iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

jsonl_today() {
  date -u +"%Y-%m-%d"
}
```

- [ ] **Step 2: Lint**

```bash
shellcheck -x lib/jsonl.sh
```
Expected: no findings.

- [ ] **Step 3: Commit**

```bash
git add lib/jsonl.sh
git commit -m "feat(lib): add jsonl append/timestamp helpers"
```

### Task D.2: Implement `hooks/audit-log.sh`

**Files:**
- Create: `hooks/audit-log.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-audit-log.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/helpers.sh"
HOOK="$DIR/hooks/audit-log.sh"

echo "tests: audit-log"

# Synthetic PostToolUse payload (per spec §17.3, verified 2026-04-25).
# Note: duration_ms is top-level, not under tool_response. tool_response shape
# is tool-specific; for Bash we leave it minimal.
mk_post_bash() {
  jq -nc --arg cmd "$1" --argjson dur "$2" '
    {tool_name:"Bash",
     tool_input:{command:$cmd},
     tool_response:{stdout:"", stderr:"", success:true},
     duration_ms:$dur}'
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# Provision a run-state file via env override so the hook picks up RUN_ID etc.
export AUTOMATON_STATE_DIR="$scratch/state"
mkdir -p "$AUTOMATON_STATE_DIR"
cat > "$AUTOMATON_STATE_DIR/current-run.env" <<EOF
RUN_ID=run-20260425-1432-foo-42
REPO=maksym-panibratenko/foo
ISSUE=42
BRANCH=claude/issue-42-healthz
PHASE=verify
EOF

export AUTOMATON_AUDIT_DIR="$scratch/audit"

P="$(mk_post_bash "pnpm test src/api/healthz.test.ts" 1240)"
printf '%s' "$P" | "$HOOK" >/dev/null

today="$(date -u +%F)"
file="$AUTOMATON_AUDIT_DIR/maksym-panibratenko/foo/$today.jsonl"
[[ -f "$file" ]] || { echo "expected $file"; exit 1; }
line="$(tail -1 "$file")"

assert_eq "Bash"                     "$(jq -r .tool      <<<"$line")" "tool field"
assert_eq "1240"                     "$(jq -r .duration_ms <<<"$line")" "duration_ms field"
assert_eq "verify"                   "$(jq -r .phase     <<<"$line")" "phase field"
assert_eq "42"                       "$(jq -r .issue     <<<"$line")" "issue field"
assert_eq "run-20260425-1432-foo-42" "$(jq -r .run_id    <<<"$line")" "run_id field"
assert_eq "maksym-panibratenko/foo"  "$(jq -r .repo      <<<"$line")" "repo field"
assert_match '^pnpm test'            "$(jq -r .cmd_summary <<<"$line")" "cmd_summary field"
# cmd_summary is truncated to 80 chars
P_LONG="$(mk_post_bash "$(printf 'echo %.0s' {1..200})" 12)"
printf '%s' "$P_LONG" | "$HOOK" >/dev/null
last="$(tail -1 "$file")"
len=$(jq -r '.cmd_summary | length' <<<"$last")
[[ "$len" -le 80 ]] || { echo "cmd_summary len $len > 80"; exit 1; }
assert_eq "true" "$([[ "$len" -le 80 ]] && echo true || echo false)" "cmd_summary <= 80 chars"

# When no run-state file exists, the hook must still succeed (silently no-op or write with empty fields).
rm -f "$AUTOMATON_STATE_DIR/current-run.env"
P2="$(mk_post_bash "ls" 5)"
printf '%s' "$P2" | "$HOOK" >/dev/null
assert_eq "0" "$?" "hook succeeds with no run state"

summary
```

```bash
chmod +x tests/test-audit-log.sh
bash tests/test-audit-log.sh
```
Expected: FAIL — hook missing.

- [ ] **Step 2: Implement the hook**

Create `hooks/audit-log.sh`:

```bash
#!/usr/bin/env bash
# hooks/audit-log.sh — PostToolUse hook. Appends one JSONL event per Bash/Edit/Write/Task call.
# Schema per spec §8.1.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/lib/run-state.sh"
. "$HERE/lib/jsonl.sh"

payload="$(cat)"
tool_name="$(jq -r '.tool_name // empty' <<<"$payload")"

# Only audit interesting tools; other PostToolUse payloads pass through silently.
case "$tool_name" in
  Bash|Edit|Write|Task) : ;;
  *) exit 0 ;;
esac

# Pull tool-specific summary
cmd_summary=""
case "$tool_name" in
  Bash)  cmd_summary="$(jq -r '.tool_input.command // ""' <<<"$payload")" ;;
  Edit)  cmd_summary="edit $(jq -r '.tool_input.file_path // "?"' <<<"$payload")" ;;
  Write) cmd_summary="write $(jq -r '.tool_input.file_path // "?"' <<<"$payload")" ;;
  Task)  cmd_summary="task $(jq -r '.tool_input.subagent_type // ""' <<<"$payload"): $(jq -r '.tool_input.description // ""' <<<"$payload")" ;;
esac
cmd_summary="${cmd_summary:0:80}"

# Per spec §17.3, duration_ms is a top-level field (not under tool_response).
# tool_response shape varies per tool; we capture .success when present (Write/Edit),
# leave it null for Bash/Task where the schema differs.
duration_ms="$(jq -r '.duration_ms // 0' <<<"$payload")"
success="$(jq -rc '.tool_response.success // null' <<<"$payload")"

run_state_load_env || true

run_id="${AUTOMATON_RUN_ID:-}"
repo="${AUTOMATON_REPO:-}"
issue="${AUTOMATON_ISSUE:-}"
branch="${AUTOMATON_BRANCH:-}"
phase="${AUTOMATON_PHASE:-}"
sha=""
if git rev-parse --short HEAD >/dev/null 2>&1; then
  sha="$(git rev-parse --short HEAD)"
fi

ts="$(jsonl_iso_now)"
day="$(jsonl_today)"

audit_root="${AUTOMATON_AUDIT_DIR:-$HOME/.claude/audit}"

if [[ -n "$repo" ]]; then
  out_file="$audit_root/$repo/$day.jsonl"
else
  out_file="$audit_root/_unknown/$day.jsonl"
fi

event="$(jq -nc \
  --arg ts "$ts" \
  --arg run_id "$run_id" \
  --arg repo "$repo" \
  --argjson issue "${issue:-null}" \
  --arg branch "$branch" \
  --arg sha "$sha" \
  --arg phase "$phase" \
  --arg tool "$tool_name" \
  --arg cmd_summary "$cmd_summary" \
  --argjson success "$success" \
  --argjson duration_ms "$duration_ms" '
  {ts:$ts, run_id:$run_id, repo:$repo, issue:$issue,
   branch:$branch, sha:$sha, phase:$phase, tool:$tool,
   cmd_summary:$cmd_summary, success:$success, duration_ms:$duration_ms}')"

jsonl_append "$out_file" "$event"
exit 0
```

```bash
chmod +x hooks/audit-log.sh
```

- [ ] **Step 3: Run tests**

```bash
bash tests/test-audit-log.sh
```
Expected: `PASS 9 passed` (7 field checks + cmd_summary length + no-state-file run). The `exit` field assertion was dropped because `tool_response.exit_code` is not a documented PostToolUse key — see spec §17.8.

- [ ] **Step 4: Lint**

```bash
shellcheck -x hooks/audit-log.sh tests/test-audit-log.sh
```
Expected: no findings.

- [ ] **Step 5: Commit**

```bash
git add hooks/audit-log.sh tests/test-audit-log.sh
git commit -m "feat(hooks): add audit-log PostToolUse hook with JSONL output"
```

### Task D.3: Wire audit-log in `settings.json`

- [ ] **Step 1: Add PostToolUse entry**

Edit `settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/secrets-block.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|Edit|Write|Task",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/audit-log.sh" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate**

```bash
jq . settings.json
```
Expected: parses cleanly.

- [ ] **Step 3: Commit**

```bash
git add settings.json
git commit -m "feat(settings): wire audit-log PostToolUse hook"
```

---

## Milestone E — PR-ready gate

Goal: `hooks/pr-ready-gate.sh` blocks `gh pr ready` unless (a) the current PR has a dry-run-interpretation comment for the active run, AND (b) the audit log contains a `tests_passed` event whose `sha` matches `git rev-parse --short HEAD`.

### Task E.1: Add the `tests_passed` event emitter helper

**Files:**
- Modify: `lib/jsonl.sh`

- [ ] **Step 1: Add `audit_emit_phase` helper**

Append to `lib/jsonl.sh`:

```bash
audit_emit_phase() {
  # $1 = phase, $2 = event name (e.g., tests_passed), $3+ = jq --arg pairs
  local phase="$1" event="$2"; shift 2
  local repo="${AUTOMATON_REPO:-_unknown}"
  local audit_root="${AUTOMATON_AUDIT_DIR:-$HOME/.claude/audit}"
  local file="$audit_root/$repo/$(jsonl_today).jsonl"
  local sha=""
  if git rev-parse --short HEAD >/dev/null 2>&1; then sha="$(git rev-parse --short HEAD)"; fi
  local json
  json="$(jq -nc \
    --arg ts "$(jsonl_iso_now)" \
    --arg run_id "${AUTOMATON_RUN_ID:-}" \
    --arg repo "$repo" \
    --argjson issue "${AUTOMATON_ISSUE:-null}" \
    --arg branch "${AUTOMATON_BRANCH:-}" \
    --arg sha "$sha" \
    --arg phase "$phase" \
    --arg event "$event" \
    '{ts:$ts, run_id:$run_id, repo:$repo, issue:$issue, branch:$branch, sha:$sha, phase:$phase, event:$event}')"
  jsonl_append "$file" "$json"
}
```

- [ ] **Step 2: Lint**

```bash
shellcheck -x lib/jsonl.sh
```
Expected: no findings.

- [ ] **Step 3: Commit**

```bash
git add lib/jsonl.sh
git commit -m "feat(lib): add audit_emit_phase for worker phase events"
```

### Task E.2: Implement `hooks/pr-ready-gate.sh`

**Files:**
- Create: `hooks/pr-ready-gate.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-pr-ready-gate.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/helpers.sh"
HOOK="$DIR/hooks/pr-ready-gate.sh"

echo "tests: pr-ready-gate"

mk_pr_ready() {
  jq -nc --arg cmd "$1" '{tool_name:"Bash", tool_input:{command:$cmd}}'
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

export AUTOMATON_STATE_DIR="$scratch/state"
export AUTOMATON_AUDIT_DIR="$scratch/audit"
mkdir -p "$AUTOMATON_STATE_DIR"
RUN="run-20260425-1432-foo-42"
REPO="maksym-panibratenko/foo"
SHA="abc1234"
cat > "$AUTOMATON_STATE_DIR/current-run.env" <<EOF
RUN_ID=$RUN
REPO=$REPO
ISSUE=42
BRANCH=claude/issue-42-healthz
PHASE=land
PR_NUMBER=99
EOF

# Stub gh — looks for a comment containing the run ID.
mkdir -p "$scratch/bin"
cat > "$scratch/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "pr view "*"--json comments"*)
    cat "$STUB_COMMENTS_FILE" 2>/dev/null || echo '{"comments":[]}'
    ;;
  "rev-parse"*) echo "$STUB_HEAD_SHA" ;;
  *) echo '{}' ;;
esac
STUB
chmod +x "$scratch/bin/gh"
export PATH="$scratch/bin:$PATH"

# Stub git rev-parse via wrapper that the hook reads.
export STUB_HEAD_SHA="$SHA"

# Helper: stub git rev-parse via a temp git repo
GIT_REPO="$scratch/repo"
git init -q "$GIT_REPO"
( cd "$GIT_REPO" && git -c user.email=a@b -c user.name=a commit --allow-empty -m init -q )
HEAD_SHA="$(cd "$GIT_REPO" && git rev-parse --short HEAD)"
SHA="$HEAD_SHA"

# Place audit file
audit_file="$AUTOMATON_AUDIT_DIR/$REPO/$(date -u +%F).jsonl"
mkdir -p "$(dirname "$audit_file")"

# Case 1: no dry-run comment → block
export STUB_COMMENTS_FILE="$scratch/comments-empty.json"
echo '{"comments":[]}' > "$STUB_COMMENTS_FILE"
P="$(mk_pr_ready "gh pr ready 99")"
( cd "$GIT_REPO" && assert_blocks "$HOOK" "$P" "blocks when no dry-run comment" )

# Case 2: dry-run comment present, no tests_passed event → block
echo "{\"comments\":[{\"body\":\"Dry-run interpretation. Run ID: \\\"$RUN\\\"\"}]}" > "$STUB_COMMENTS_FILE"
( cd "$GIT_REPO" && assert_blocks "$HOOK" "$P" "blocks when no tests_passed for SHA" )

# Case 3: both present → allow
printf '%s\n' "$(jq -nc --arg sha "$SHA" --arg run "$RUN" --arg repo "$REPO" \
  '{ts:"x", run_id:$run, repo:$repo, sha:$sha, phase:"verify", event:"tests_passed"}')" \
  >> "$audit_file"
( cd "$GIT_REPO" && assert_allows "$HOOK" "$P" "allows when both gates satisfied" )

# Case 4: not a `gh pr ready` command → allow regardless
P_OTHER="$(mk_pr_ready "gh pr view 99")"
( cd "$GIT_REPO" && assert_allows "$HOOK" "$P_OTHER" "passes through non-pr-ready bash" )

summary
```

```bash
chmod +x tests/test-pr-ready-gate.sh
bash tests/test-pr-ready-gate.sh
```
Expected: FAIL — hook missing.

- [ ] **Step 2: Implement the hook**

Create `hooks/pr-ready-gate.sh`:

```bash
#!/usr/bin/env bash
# hooks/pr-ready-gate.sh — PreToolUse hook on Bash. Blocks `gh pr ready ...`
# unless the current run has both:
#   1. A "Dry-run interpretation" PR comment whose body includes `Run ID: <run-id>`.
#   2. An audit event with phase=verify, event=tests_passed, sha=<HEAD short sha>.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/lib/run-state.sh"

payload="$(cat)"
tool_name="$(jq -r '.tool_name // empty' <<<"$payload")"

[[ "$tool_name" == "Bash" ]] || exit 0
cmd="$(jq -r '.tool_input.command // ""' <<<"$payload")"
case "$cmd" in
  "gh pr ready"*|*"gh pr ready"*) : ;;
  *) exit 0 ;;
esac

block() {
  printf 'BLOCKED by automaton/pr-ready-gate: %s\n' "$1" >&2
  exit 2
}

run_state_load_env || true
run_id="${AUTOMATON_RUN_ID:-}"
repo="${AUTOMATON_REPO:-}"
pr_number="${AUTOMATON_PR_NUMBER:-}"

[[ -n "$run_id" ]] || block "no AUTOMATON_RUN_ID in run state"
[[ -n "$repo" ]]   || block "no AUTOMATON_REPO in run state"
[[ -n "$pr_number" ]] || block "no AUTOMATON_PR_NUMBER in run state (open the draft PR before running gh pr ready)"

# Gate A: dry-run comment present
comments_json="$(gh pr view "$pr_number" --repo "$repo" --json comments 2>/dev/null || echo '{"comments":[]}')"
if ! grep -F "Run ID: \"$run_id\"" <<<"$comments_json" >/dev/null; then
  if ! grep -F "Run ID: \`$run_id\`" <<<"$comments_json" >/dev/null; then
    if ! grep -F "Run ID: $run_id" <<<"$comments_json" >/dev/null; then
      block "PR has no dry-run interpretation comment for run $run_id"
    fi
  fi
fi

# Gate B: tests_passed audit event for current SHA
sha="$(git rev-parse --short HEAD 2>/dev/null || true)"
[[ -n "$sha" ]] || block "git rev-parse --short HEAD failed"

audit_root="${AUTOMATON_AUDIT_DIR:-$HOME/.claude/audit}"
day="$(date -u +%F)"
audit_file="$audit_root/$repo/$day.jsonl"
[[ -f "$audit_file" ]] || block "no audit log for $repo today; run verification first"

found="$(jq -sc --arg run "$run_id" --arg sha "$sha" '
  map(select(.run_id==$run and .sha==$sha and .phase=="verify" and .event=="tests_passed"))
  | length' "$audit_file")"

[[ "$found" -gt 0 ]] || block "no tests_passed event for sha=$sha run=$run_id; re-run verification"

exit 0
```

```bash
chmod +x hooks/pr-ready-gate.sh
```

- [ ] **Step 3: Run tests**

```bash
bash tests/test-pr-ready-gate.sh
```
Expected: `PASS 4 passed`.

- [ ] **Step 4: Lint**

```bash
shellcheck -x hooks/pr-ready-gate.sh tests/test-pr-ready-gate.sh
```
Expected: no findings.

- [ ] **Step 5: Commit**

```bash
git add hooks/pr-ready-gate.sh tests/test-pr-ready-gate.sh
git commit -m "feat(hooks): add pr-ready-gate enforcing dry-run + tests_passed"
```

### Task E.3: Wire pr-ready-gate in `settings.json`

- [ ] **Step 1: Add a second PreToolUse matcher**

Edit `settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/secrets-block.sh" }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pr-ready-gate.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|Edit|Write|Task",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/audit-log.sh" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add settings.json
git commit -m "feat(settings): wire pr-ready-gate PreToolUse hook"
```

---

## Milestone F — Optional session-start summary

Goal: `hooks/session-start-summary.sh` injects a one-line "Heads up: 2 in-flight runs" message on session start, gated by an opt-in flag.

### Task F.1: Implement the hook

**Files:**
- Create: `hooks/session-start-summary.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-session-start-summary.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/helpers.sh"
HOOK="$DIR/hooks/session-start-summary.sh"

echo "tests: session-start-summary"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

mkdir -p "$scratch/bin"
cat > "$scratch/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"issue list"*"--label claude:in-progress"*)
    echo "$STUB_INFLIGHT"
    ;;
  *) echo '[]' ;;
esac
STUB
chmod +x "$scratch/bin/gh"
export PATH="$scratch/bin:$PATH"

repos_dir="$scratch/automaton"
mkdir -p "$repos_dir"
cat > "$repos_dir/repos" <<EOF
maksym-panibratenko/foo
maksym-panibratenko/bar
EOF
export AUTOMATON_REPOS_FILE="$repos_dir/repos"

# Case 1: no in-flight runs → empty additionalContext
export STUB_INFLIGHT='[]'
out="$(printf '{"source":"startup","cwd":"/tmp"}' | "$HOOK")"
ctx="$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out")"
assert_eq "" "$ctx" "no runs → empty context"

# Case 2: two runs across two repos
export STUB_INFLIGHT='[{"number":42,"title":"healthz","repository":{"nameWithOwner":"maksym-panibratenko/foo"}},{"number":17,"title":"refactor","repository":{"nameWithOwner":"maksym-panibratenko/bar"}}]'
out="$(printf '{"source":"startup","cwd":"/tmp"}' | "$HOOK")"
ctx="$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out")"
assert_match 'Heads up: 2 in-flight' "$ctx" "context names count"
assert_match 'foo#42'                "$ctx" "context names foo#42"
assert_match 'bar#17'                "$ctx" "context names bar#17"

# Case 3: opt-out env var → no output
export AUTOMATON_SESSION_START_SUMMARY=off
out="$(printf '{"source":"startup","cwd":"/tmp"}' | "$HOOK")"
ctx="$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out")"
assert_eq "" "$ctx" "opt-out disables hook"

summary
```

```bash
chmod +x tests/test-session-start-summary.sh
bash tests/test-session-start-summary.sh
```
Expected: FAIL — hook missing.

- [ ] **Step 2: Implement the hook**

Create `hooks/session-start-summary.sh`:

```bash
#!/usr/bin/env bash
# hooks/session-start-summary.sh — SessionStart hook (opt-in).
# Reports in-flight autonomous runs across configured repos as a one-line summary.
# Disabled when AUTOMATON_SESSION_START_SUMMARY != "on" (default: on if wired).

set -euo pipefail

emit() {
  jq -nc --arg ctx "$1" '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}'
}

mode="${AUTOMATON_SESSION_START_SUMMARY:-on}"
[[ "$mode" == "on" ]] || { emit ""; exit 0; }

# Discard stdin payload; not used here.
cat >/dev/null

repos_file="${AUTOMATON_REPOS_FILE:-$HOME/.claude/automaton/repos}"
[[ -f "$repos_file" ]] || { emit ""; exit 0; }

readarray -t repos < <(awk 'NF && !/^#/{print $1}' "$repos_file")
[[ "${#repos[@]}" -gt 0 ]] || { emit ""; exit 0; }

# Aggregate in-flight issues across repos. One gh call per repo.
items=()
for r in "${repos[@]}"; do
  json="$(gh issue list --repo "$r" --label claude:in-progress --state open --json number,title,repository 2>/dev/null || echo '[]')"
  while IFS= read -r line; do
    [[ -n "$line" ]] && items+=("$line")
  done < <(jq -c '.[]?' <<<"$json")
done

count="${#items[@]}"
if (( count == 0 )); then emit ""; exit 0; fi

short=""
for it in "${items[@]}"; do
  num="$(jq -r '.number' <<<"$it")"
  ow="$(jq -r '.repository.nameWithOwner // ""' <<<"$it")"
  short+=" \`${ow##*/}#${num}\`,"
done
short="${short%,}"

emit "Heads up: ${count} in-flight autonomous run(s):${short}."
```

```bash
chmod +x hooks/session-start-summary.sh
```

- [ ] **Step 3: Run tests**

```bash
bash tests/test-session-start-summary.sh
```
Expected: `PASS 5 passed`.

- [ ] **Step 4: Lint**

```bash
shellcheck -x hooks/session-start-summary.sh tests/test-session-start-summary.sh
```
Expected: no findings.

- [ ] **Step 5: Commit**

```bash
git add hooks/session-start-summary.sh tests/test-session-start-summary.sh
git commit -m "feat(hooks): add opt-in session-start-summary"
```

### Task F.2: Wire (commented out) in `settings.json`

- [ ] **Step 1: Add SessionStart with a comment header**

Edit `settings.json` to include the SessionStart wiring. Since strict JSON has no comments, use a top-level `_comments` array as documentation:

```json
{
  "_comments": [
    "SessionStart summary is opt-in. Set env AUTOMATON_SESSION_START_SUMMARY=on to enable when uncommented below."
  ],
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/secrets-block.sh" }]
      },
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pr-ready-gate.sh" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|Edit|Write|Task",
        "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/audit-log.sh" }]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start-summary.sh" }]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate JSON**

```bash
jq . settings.json
```
Expected: parses cleanly.

- [ ] **Step 3: Commit**

```bash
git add settings.json
git commit -m "feat(settings): wire optional session-start-summary hook"
```

---

## Milestone G — Decision/playbook layer

Goal: the `issue-interpreter` Sonnet agent and the two skills (`interpreting-an-issue`, `working-an-issue`) that hold the playbooks.

### Task G.1: Author `agents/issue-interpreter.md`

**Files:**
- Create: `agents/issue-interpreter.md`, `tests/fixtures/issues/well-formed.json`, `tests/fixtures/issues/ambiguous.json`, `tests/fixtures/issues/missing-sections.json`

- [ ] **Step 1: Create issue fixtures**

Create `tests/fixtures/issues/well-formed.json`:

```json
{
  "number": 42,
  "title": "Add /healthz endpoint",
  "body": "## Goal\nReturn 200 OK from a new `/healthz` endpoint for liveness checks.\n\n## Acceptance criteria\n- [ ] `GET /healthz` returns 200 with body `{\"status\":\"ok\"}`\n- [ ] Existing tests still pass\n\n## Verification\n```\npnpm test src/api/healthz.test.ts\n```\n"
}
```

Create `tests/fixtures/issues/ambiguous.json`:

```json
{
  "number": 43,
  "title": "Improve error handling in the auth flow",
  "body": "## Goal\nMake auth more robust.\n\n## Acceptance criteria\n- [ ] Errors are handled\n\n## Verification\n```\npnpm test\n```\n"
}
```

Create `tests/fixtures/issues/missing-sections.json`:

```json
{
  "number": 44,
  "title": "Refactor",
  "body": "Make the code cleaner.\n"
}
```

- [ ] **Step 2: Author the agent definition**

Create `agents/issue-interpreter.md`:

```markdown
---
name: issue-interpreter
description: Interpret a GitHub issue into a fixed-shape JSON dry-run plan. Use only inside the `working-an-issue` skill flow. Returns interpretation, files_to_touch, approach, out_of_scope, ambiguity_score, ambiguities, verification_plan, estimated_complexity. Halts the worker if the issue is too ambiguous.
tools: Read, Grep, Glob, Bash
model: claude-sonnet-4-6
---

# issue-interpreter

You receive a single GitHub issue plus surrounding repo context, and you produce ONE thing: a JSON dry-run plan describing what a worker would do if it picked up the issue.

## Inputs (provided in the prompt)

- `issue`: object with `number`, `title`, `body`.
- `recent_commits`: output of `git log --oneline -20 main` for the target repo.
- `glob_hits`: file paths matching any globs the issue body referenced (may be empty).
- `repo_claude_md`: the repo's `CLAUDE.md` content if present (may be empty).

## What you may do

- Read files via `Read`, `Grep`, `Glob` to pin down `files_to_touch`.
- Run read-only `gh issue view <N>` or `gh pr view <N>` or `git log` via `Bash` if you need clarification beyond the inputs.
- DO NOT modify files. DO NOT run commits, pushes, label changes, or PR comment writes — those are the worker's job.
- DO NOT call other agents.

## Output

A single JSON object, NO surrounding prose, NO Markdown fences. The exact shape:

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

### Field rules

- `ambiguity_score` is an integer 0–3.
  - 0 = unambiguous; you would proceed without asking.
  - 1 = a minor open detail with a defensible default.
  - 2 = real choice between plausible interpretations; halt and ask.
  - 3 = fundamentally unclear what the user wants.
- `estimated_complexity` is one of `trivial`, `small`, `medium`, `large`. Anchor: trivial < 20 lines of diff; small < 100; medium < 500; large >= 500.
- `files_to_touch` may be empty (you don't yet know).
- `out_of_scope` should call out plausible-but-unintended interpretations the issue rules out.
- If the issue body is missing any of {Goal, Acceptance criteria, Verification}, set `ambiguity_score=3`, list the missing sections in `ambiguities`, and leave other fields best-effort.

### Tone

Be concrete. No hedging. If the right answer is "I don't know what you want", say so via `ambiguity_score=2|3` and a precise `ambiguities` list. The worker downstream will halt cleanly on your signal — that is the desired behavior.
```

- [ ] **Step 3: Smoke-test the agent definition**

Run from the repo root:
```
gh repo view --json nameWithOwner   # any repo, irrelevant target
```
(That's a no-op; the real smoke test is in Milestone L when running `/dry-run` against a fixture issue.)

- [ ] **Step 4: Commit**

```bash
git add agents/issue-interpreter.md tests/fixtures/issues/
git commit -m "feat(agents): add issue-interpreter Sonnet agent + issue fixtures"
```

### Task G.2: Author `skills/interpreting-an-issue/SKILL.md`

**Files:**
- Create: `skills/interpreting-an-issue/SKILL.md`

- [ ] **Step 1: Write the skill**

```bash
mkdir -p skills/interpreting-an-issue
```

Create `skills/interpreting-an-issue/SKILL.md`:

```markdown
---
name: interpreting-an-issue
description: Use when running `/dry-run NN` or executing Step 3 of `/work-next` / `/work-issue NN`. Invokes the `issue-interpreter` agent against a target issue and posts the result as a "Dry-run interpretation" comment. Halts the calling flow on `ambiguity_score >= 2` or `estimated_complexity == "large"` or missing required template sections.
---

# Interpreting an issue

This skill runs the dry-run interpretation gate (spec §5).

## Inputs

- `ISSUE_NUMBER` — required, integer.
- `REPO` — required, `owner/repo`. Defaults to `gh repo view --json nameWithOwner`.
- `RUN_ID` — required if you want the rendered comment to carry a Run ID line. The worker's pickup step provides it; for `/dry-run` invoked interactively, generate one (`run-$(date -u +%Y%m%d-%H%M)-${REPO##*/}-${ISSUE_NUMBER}`).
- `PR_NUMBER` — optional. If provided, post the dry-run comment on the PR rather than the issue.

## Steps

1. **Fetch issue.** `gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json number,title,body`. If the body is missing any of {`## Goal`, `## Acceptance criteria`, `## Verification`}, post the `claude:blocked` template (see §9.1) with reason "spec template incomplete" and exit. Do NOT invoke the agent.

2. **Gather context.**
   - `git log --oneline -20 main` (or the repo's default branch).
   - For each ` ` `glob` ` ` mentioned in the issue body, `printf '%s\n' globresult`. Combine into a `glob_hits` list.
   - Read the repo's `CLAUDE.md` if present.

3. **Invoke `issue-interpreter`.** Pass the issue title+body, recent_commits, glob_hits, repo_claude_md as the prompt. The agent returns one JSON object.

4. **Validate JSON.** Use `jq` to confirm the required fields exist. If invalid, retry once with a re-prompt that names the bad field. If still invalid, halt with `claude:blocked` reason "interpreter returned invalid JSON".

5. **Render the comment** (spec §5.3 template). Run-ID line included verbatim.

6. **Post the comment.**
   - If `$PR_NUMBER` is set: `gh pr comment "$PR_NUMBER" --repo "$REPO" --body-file <rendered>`.
   - Else: `gh issue comment "$ISSUE_NUMBER" --repo "$REPO" --body-file <rendered>`.

7. **Decide halt.**
   - If `.ambiguity_score >= 2` OR `.estimated_complexity == "large"`: halt the calling flow. Add the `claude:blocked` label, remove `claude:in-progress` if present, exit cleanly.
   - Otherwise: emit a `phase=interpret` audit event and return success to the caller.

## Outputs

- `INTERPRETER_JSON` (the raw JSON, available to the caller).
- `INTERPRETER_HALTED` ("yes" or "no").
- A posted comment whose body matches the §5.3 template.
```

- [ ] **Step 2: Commit**

```bash
git add skills/interpreting-an-issue/SKILL.md
git commit -m "feat(skills): add interpreting-an-issue skill"
```

### Task G.3: Author `skills/working-an-issue/SKILL.md`

**Files:**
- Create: `skills/working-an-issue/SKILL.md`

- [ ] **Step 1: Write the skill**

```bash
mkdir -p skills/working-an-issue
```

Create `skills/working-an-issue/SKILL.md`:

```markdown
---
name: working-an-issue
description: Use this when invoked from `/work-next` (after pickup) or `/work-issue NN`. Drives the six-step worker contract end-to-end: pickup, read, interpret, work, verify, land. Halts cleanly on the spec §4 halt conditions, posting a structured `claude:blocked` comment.
---

# Working an issue

Implements spec §4 verbatim. Six steps. Halt-on-failure semantics throughout.

## Preconditions

The caller has set the run-state (`lib/run-state.sh run_state_set`) for: `RUN_ID`, `REPO`, `ISSUE`, optionally `BRANCH`. The issue has `claude:in-progress` (set during pickup, or before invoking this skill via `/work-issue`).

## Step 1 — Pickup

If the caller is `/work-next`: pickup is already done, jump to Step 2. If `/work-issue NN`:
1. Verify the issue is open: `gh issue view "$ISSUE" --json state -q .state` returns `OPEN`. Else halt.
2. Add label: `gh issue edit "$ISSUE" --add-label claude:in-progress`. On failure (e.g., already labelled by another run), retry up to 3 times with backoff. After 3 race-contention failures, halt with reason "race contention".

## Step 2 — Read

```bash
gh issue view "$ISSUE" --repo "$REPO" --json title,body,labels
git checkout "$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"
git pull --ff-only
git log --oneline -20
```

Cache repo as `AUTOMATON_REPO`.

## Step 3 — Interpret (the keystone gate)

Invoke `interpreting-an-issue` skill with `ISSUE_NUMBER=$ISSUE`, `REPO=$REPO`, `RUN_ID=$RUN_ID`. If `INTERPRETER_HALTED == "yes"`, exit (the skill already posted the blocked state).

Emit a phase event:
```bash
. lib/jsonl.sh
AUTOMATON_PHASE=interpret audit_emit_phase interpret interpreter_returned
```

## Step 4 — Work

1. Compute branch name: `slug="$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//' | cut -c1-40)"`; `BRANCH="claude/issue-$ISSUE-$slug"`.
2. Use `superpowers:using-git-worktrees` to create a worktree at `.worktrees/$BRANCH`.
3. `run_state_set BRANCH "$BRANCH"`.
4. Implement per the interpretation:
   - For new code: invoke `superpowers:test-driven-development`.
   - For bugfixes: invoke `superpowers:systematic-debugging`.
5. Commits: Conventional Commits format with `(#NN)` in the subject.
6. **Halt** if 2 consecutive same-approach tool failures occur.
7. **Halt** if a destructive op is needed (`git reset --hard`, `git push --force`, `git branch -D`, `git clean -fd`).

## Step 5 — Verify

Run each command from the interpretation's `verification_plan` (or the issue's `## Verification` block, equivalent). Quote stdout in a worker-internal note for Step 6.

If a command fails:
- Attempt #1: investigate root cause via `superpowers:systematic-debugging` and apply a fix.
- Attempt #2: same.
- After 2 attempts still failing: halt with reason "verification failed after 2 attempts".

On success, emit `tests_passed`:
```bash
. lib/jsonl.sh
AUTOMATON_PHASE=verify audit_emit_phase verify tests_passed
```

## Step 6 — Land

1. `git push -u origin "$BRANCH"`.
2. `gh pr create --draft --base main --head "$BRANCH" --title "<conventional title> (#$ISSUE)" --body-file <(render_pr_body)`. The PR body is the dry-run interpretation block (verbatim) plus a "Closes #$ISSUE" line.
3. `run_state_set PR_NUMBER "$(gh pr view --json number -q .number)"`.
4. Run `tools/safety-spotter.sh < <(git diff origin/main...HEAD)`. If exit 2, halt with `claude:blocked` reason "safety-spotter fired".
5. **Auto-merge gate** (spec §7.1): if all of:
   - The original issue had `claude:auto-merge` at pickup time (cached in run state).
   - `gh pr checks --required` reports green.
   - The diff matches an auto-merge-safe pattern from `.claude-harness.toml` (`deps-bump`, `docs-only`, `generated`, `formatting`).

   then `gh pr merge --auto --squash`.
6. Else: `gh pr ready` (this fires `pr-ready-gate.sh`; if it blocks, the gate's stderr explains).
7. Post the completion-summary PR comment.
8. Clear run state: `run_state_clear`.

## Halt template

```markdown
## Blocked: needs human triage

**Trigger:** <halt reason>

**What I attempted**
- <step 1>
- <step 2>

**What blocks progress**
<concrete description>

**Recommended next action**
- [ ] <option A>
- [ ] <option B>

**Run ID:** `$RUN_ID`
**Branch:** `$BRANCH`
**HEAD SHA:** `$(git rev-parse --short HEAD)`
```

Apply via `gh issue comment` (or `gh pr comment` if a draft PR exists) and `gh issue edit --add-label claude:blocked --remove-label claude:in-progress`. Then exit cleanly.
```

- [ ] **Step 2: Commit**

```bash
git add skills/working-an-issue/SKILL.md
git commit -m "feat(skills): add working-an-issue six-step playbook"
```

---

## Milestone H — Slash commands

Goal: the five slash commands wire the skills into one-line user-facing invocations.

### Task H.1: `/dry-run NN`

**Files:**
- Create: `commands/dry-run.md`

- [ ] **Step 1: Write the command**

```markdown
---
description: Run only the dry-run interpretation step against a single issue (no code changes). Posts the interpretation comment and exits.
argument-hint: <issue-number> [owner/repo]
---

# /dry-run

Run the `interpreting-an-issue` skill against issue `${1}` (and optionally repo `${2}` if provided; defaults to current repo).

Steps:

1. Determine `ISSUE_NUMBER` from `${1}`. If missing, prompt me to provide one and exit.
2. Determine `REPO`: `${2}` if provided; else `gh repo view --json nameWithOwner -q .nameWithOwner`.
3. Generate a `RUN_ID`: `run-$(date -u +%Y%m%d-%H%M)-${REPO##*/}-${ISSUE_NUMBER}`.
4. Set run state via `lib/run-state.sh run_state_set`: `RUN_ID`, `REPO`, `ISSUE=$ISSUE_NUMBER`.
5. Invoke `superpowers:interpreting-an-issue` (this plugin's skill) with those inputs.
6. On return, summarize to the user: ambiguity_score, complexity, link to the posted comment.
7. Clear run state.

Do NOT modify code. Do NOT add labels. Do NOT push commits. This is a read-only preview.
```

- [ ] **Step 2: Commit**

```bash
git add commands/dry-run.md
git commit -m "feat(commands): add /dry-run preview command"
```

### Task H.2: `/work-issue NN`

**Files:**
- Create: `commands/work-issue.md`

- [ ] **Step 1: Write the command**

```markdown
---
description: Work a specific GitHub issue end-to-end. Skips the cross-repo pickup step. Use when you've already picked the issue.
argument-hint: <issue-number> [owner/repo]
---

# /work-issue

Run the six-step worker contract against issue `${1}` in repo `${2}` (defaults to current).

Steps:

1. Resolve `ISSUE_NUMBER=${1}`, `REPO=${2:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}`.
2. Generate `RUN_ID=run-$(date -u +%Y%m%d-%H%M)-${REPO##*/}-${ISSUE_NUMBER}`.
3. Set run state (`run_state_set`): RUN_ID, REPO, ISSUE.
4. Cache whether the issue carries `claude:auto-merge` for Step 6 use:
   `gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json labels` → if labels include `claude:auto-merge`, `run_state_set AUTO_MERGE 1`.
5. Add `claude:in-progress` label (race-resistant, 3 retries).
6. Invoke `superpowers:working-an-issue` skill. The skill handles Steps 2–6 of §4.
7. On halt or completion, the skill posts the appropriate comment and clears state.

Do not improvise around halt conditions; let the skill exit.
```

- [ ] **Step 2: Commit**

```bash
git add commands/work-issue.md
git commit -m "feat(commands): add /work-issue command"
```

### Task H.3: `/work-next`

**Files:**
- Create: `commands/work-next.md`

- [ ] **Step 1: Write the command**

```markdown
---
description: Pick the top claude:ready issue across configured repos and run the six-step worker contract.
argument-hint: (no arguments)
---

# /work-next

Pickup + work loop. Reads `~/.claude/automaton/repos`, queries each repo for `claude:ready` issues, picks the highest priority, and hands off to the working-an-issue skill.

Steps:

1. Read configured repos:
   ```bash
   awk 'NF && !/^#/{print $1}' "${AUTOMATON_REPOS_FILE:-$HOME/.claude/automaton/repos}"
   ```
   If empty: tell me there are no configured repos and stop.

2. For each repo, query candidates:
   ```bash
   gh issue list --repo "$repo" --label claude:ready --state open --json number,title,labels,createdAt --limit 30
   ```
   Drop any whose labels include `claude:in-progress` or `claude:blocked`.

3. Sort the combined list by priority then by `createdAt` ascending. Priority order: `priority:p0` < `p1` < `p2` < `p3` < unspecified.

4. Pick the top entry. Construct `RUN_ID`. Cache `AUTO_MERGE` if `claude:auto-merge` present.

5. Race-resistant claim:
   ```bash
   gh issue edit "$ISSUE" --repo "$REPO" --add-label claude:in-progress
   ```
   On 3rd failure, halt with reason "race contention".

6. Set run state. Invoke `superpowers:working-an-issue`.

If no candidates anywhere: print a one-line "queue empty" message and exit.
```

- [ ] **Step 2: Commit**

```bash
git add commands/work-next.md
git commit -m "feat(commands): add /work-next cross-repo pickup"
```

### Task H.4: `/show-activity`

**Files:**
- Create: `commands/show-activity.md`

- [ ] **Step 1: Write the command**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add commands/show-activity.md
git commit -m "feat(commands): add /show-activity report"
```

### Task H.5: `/scaffold`

**Files:**
- Create: `commands/scaffold.md`

- [ ] **Step 1: Write the command**

```markdown
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
4. Append the repo to `~/.claude/automaton/repos` if not already listed:
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
```

- [ ] **Step 2: Commit**

```bash
git add commands/scaffold.md
git commit -m "feat(commands): add /scaffold per-repo setup"
```

---

## Milestone I — GitHub Actions templates

Goal: the two thin `claude-code-action@v1` workflows.

### Task I.1: `pr-review.yml`

**Files:**
- Create: `templates/.github/workflows/pr-review.yml`

- [ ] **Step 1: Write the workflow**

```bash
mkdir -p templates/.github/workflows
```

Create `templates/.github/workflows/pr-review.yml`:

```yaml
name: PR review
on:
  pull_request:
    types: [opened, synchronize]
permissions:
  pull-requests: write
  contents: read
jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          model: claude-sonnet-4-6
          prompt: |
            Review this PR against its linked issue's acceptance criteria.
            Flag: correctness gaps, security issues in the diff, missing tests
            for new behavior. Skip stylistic nits unless they affect behavior.
            Bullet points, not essays. <=200 words.
```

- [ ] **Step 2: Validate YAML**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('templates/.github/workflows/pr-review.yml'))"
```
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add templates/.github/workflows/pr-review.yml
git commit -m "feat(templates): add pr-review workflow template"
```

### Task I.2: `triage.yml`

**Files:**
- Create: `templates/.github/workflows/triage.yml`

- [ ] **Step 1: Write the workflow**

Create `templates/.github/workflows/triage.yml`:

```yaml
name: Issue triage
on:
  issues:
    types: [opened]
permissions:
  issues: write
jobs:
  triage:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          model: claude-haiku-4-5
          prompt: |
            Apply at most one priority:* (p0..p3) and one type:*
            (feat|fix|chore|refactor|docs) label to this issue.
            Do NOT apply claude:ready — that's human-only intent.
            If the issue body is missing Goal or Acceptance criteria sections,
            comment: "Spec template incomplete; see automaton/docs/issue-template.md".
```

- [ ] **Step 2: Validate YAML**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('templates/.github/workflows/triage.yml'))"
```
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add templates/.github/workflows/triage.yml
git commit -m "feat(templates): add issue triage workflow template"
```

---

## Milestone J — Per-repo scaffolding artifacts

Goal: `.claude-harness.toml`, `.claude/audit/.gitignore`, `docs/issue-template.md`.

### Task J.1: `.claude/audit/.gitignore`

**Files:**
- Create: `templates/.claude/audit/.gitignore`

- [ ] **Step 1: Write the file**

```bash
mkdir -p templates/.claude/audit
```

Create `templates/.claude/audit/.gitignore`:

```
*
!.gitignore
```

- [ ] **Step 2: Commit**

```bash
git add templates/.claude/audit/.gitignore
git commit -m "feat(templates): ignore audit log content per-repo"
```

### Task J.2: `.claude-harness.toml`

**Files:**
- Create: `templates/.claude-harness.toml`

- [ ] **Step 1: Write the template**

Create `templates/.claude-harness.toml`:

```toml
# automaton per-repo configuration. See docs/superpowers/specs/2026-04-25-automaton-harness-design.md §7.1.

[auto_merge]
# Subset of: deps-bump, docs-only, generated, formatting.
patterns = ["deps-bump", "docs-only", "formatting"]

[auto_merge.generated]
# Path globs (extended-glob) considered "generated" for the `generated` pattern.
# Edit this list to match your repo's checked-in generated artifacts.
globs = ["**/__snapshots__/**"]

[verification]
# Default verification command if an issue body omits the ## Verification block.
# The worker will halt rather than guess; this is just a hint for the issue author.
hint = "pnpm test"
```

- [ ] **Step 2: Validate TOML**

```bash
python3 -c "import tomllib; tomllib.load(open('templates/.claude-harness.toml','rb'))"
```
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add templates/.claude-harness.toml
git commit -m "feat(templates): add .claude-harness.toml per-repo config"
```

### Task J.3: `docs/issue-template.md`

**Files:**
- Create: `docs/issue-template.md`

- [ ] **Step 1: Write the template doc**

Create `docs/issue-template.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add docs/issue-template.md
git commit -m "docs: add required issue body template"
```

---

## Milestone K — Final wiring

### Task K.1: Final `CLAUDE.md`

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: Write the spine** (~30 lines per spec §12)

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

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "feat: add CLAUDE.md spine for plugin operation"
```

### Task K.2: Expand `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read current**

```bash
cat README.md
```

- [ ] **Step 2: Replace contents** with a user-facing intro + install + commands table

Write `README.md`:

```markdown
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
/plugin install https://github.com/maksym-panibratenko/automaton
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
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: expand README with install, commands, links"
```

### Task K.3: Settings sanity pass

**Files:**
- Modify: `settings.json`

- [ ] **Step 1: Re-read current settings**

```bash
jq . settings.json
```

- [ ] **Step 2: Confirm structure**

Spot-check that the four hook entries are present (`secrets-block`, `pr-ready-gate`, `audit-log`, `session-start-summary`). Confirm the `_comments` array still documents opt-in. No edit needed if all is in order.

- [ ] **Step 3: No-op commit if nothing changed.**

### Task K.4: Umbrella `tests/test-hooks.sh`

**Files:**
- Create: `tests/test-hooks.sh`

- [ ] **Step 1: Write the umbrella runner**

```bash
#!/usr/bin/env bash
# tests/test-hooks.sh — runs every hook + tool + lib test in sequence.

set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"

scripts=(
  test-run-state.sh
  test-secret-patterns.sh
  test-secrets-block.sh
  test-safety-spotter.sh
  test-audit-log.sh
  test-pr-ready-gate.sh
  test-session-start-summary.sh
)

failed=0
for s in "${scripts[@]}"; do
  printf '\n=== %s ===\n' "$s"
  if ! bash "$DIR/tests/$s"; then
    failed=$((failed+1))
  fi
done

if (( failed > 0 )); then
  printf '\n%d test file(s) failed.\n' "$failed"
  exit 1
fi
printf '\nAll test files passed.\n'
```

- [ ] **Step 2: Make executable, run**

```bash
chmod +x tests/test-hooks.sh
bash tests/test-hooks.sh
```
Expected: all individual files pass; final line `All test files passed.`

- [ ] **Step 3: Commit**

```bash
git add tests/test-hooks.sh
git commit -m "test: add umbrella test-hooks runner"
```

---

## Milestone L — Acceptance walkthrough

Goal: walk every spec §14 acceptance criterion. Each item below corresponds to one criterion. Where a criterion needs a real GitHub repo, use the `automaton` repo itself (after the push in Task L.7) or a disposable `automaton-acceptance` test repo.

### Task L.1: Local install

- [ ] **Step 1: In a fresh Claude Code session at `/Users/panibrat/dev`, run**

```
/plugin install /Users/panibrat/dev/automaton
/plugin list
```
Expected: `automaton 0.0.1` appears.

- [ ] **Step 2: Run `/help` and confirm all five commands appear:** `/work-next`, `/work-issue`, `/show-activity`, `/dry-run`, `/scaffold`.

- [ ] **Step 3: Note any failures and triage** by reading hook docs (Task A.4) or the manifest spec.

### Task L.2: `/dry-run` against a fixture issue

- [ ] **Step 1: Create a test repo** (`automaton-acceptance`) with three issues whose bodies match `tests/fixtures/issues/well-formed.json`, `ambiguous.json`, `missing-sections.json`.

- [ ] **Step 2: Run `/dry-run <well-formed-num>`**
Expected: the issue receives a dry-run interpretation comment with `ambiguity_score: 0`, no labels changed.

- [ ] **Step 3: Run `/dry-run <ambiguous-num>`**
Expected: comment with `ambiguity_score >= 2` and an `ambiguities` list. No labels changed (per `/dry-run` semantics — it's preview-only).

- [ ] **Step 4: Run `/dry-run <missing-sections-num>`**
Expected: a `claude:blocked`-style comment with reason "spec template incomplete". Per `/dry-run` semantics, no label is added; the comment alone signals the result.

### Task L.3: `/work-issue` happy path

- [ ] **Step 1: Pick the well-formed issue and run `/work-issue <num>`**

- [ ] **Step 2: Verify after completion:**
  - A draft PR exists with title `feat: ... (#NN)` (or appropriate type).
  - The PR body includes the dry-run interpretation block and `Closes #NN`.
  - The issue carries `claude:in-progress`, not `claude:blocked`.
  - The audit log file `~/.claude/audit/<repo>/<today>.jsonl` exists and contains both `tool` events and `phase` events including `tests_passed`.

### Task L.4: `/work-next` queue pickup

- [ ] **Step 1: Add `claude:ready` to two test issues; ensure `~/.claude/automaton/repos` lists the test repo.**

- [ ] **Step 2: Run `/work-next`.**
Expected: one issue gets `claude:in-progress` and is worked end-to-end. The second remains `claude:ready` (only one issue per run).

### Task L.5: Auto-merge gate

- [ ] **Step 1: Open a deps-bump issue (`Bump x@1.2.3 → 1.2.4`) with `claude:ready` AND `claude:auto-merge`. Acceptance criterion: tests pass; verification command is `<repo's lockfile-aware test>`.**

- [ ] **Step 2: Run `/work-issue NN`.**
Expected: branch pushed, draft PR opened, CI green (assume so for the test repo), `gh pr merge --auto --squash` invoked. The PR merges once CI completes.

- [ ] **Step 3: Open a non-deps issue with `claude:auto-merge` (e.g., adds a feature). Run `/work-issue NN`.**
Expected: PR opened in `ready` state (not auto-merged) because the diff doesn't match a registered auto-merge-safe pattern.

### Task L.6: Halt path

- [ ] **Step 1: Open an issue with deliberately ambiguous body ("Improve everything").**

- [ ] **Step 2: Add `claude:ready`. Run `/work-next`.**
Expected:
  - The issue receives a structured `claude:blocked` comment naming the halt trigger.
  - The label set on the issue is exactly `claude:blocked` (not `claude:in-progress`).
  - No commits, no branch pushed, no PR opened.

### Task L.7: GitHub push

- [ ] **Step 1: Create the GitHub repo** (per spec §15.2 resolution)

```bash
gh repo create maksym-panibratenko/automaton --public --source=. --push --description "Single-issue autonomous worker harness for Claude Code." --homepage "https://github.com/maksym-panibratenko/automaton"
```

- [ ] **Step 2: Verify**

```bash
gh repo view maksym-panibratenko/automaton --json name,visibility,url
```
Expected: name=automaton, visibility=PUBLIC.

- [ ] **Step 3: Confirm the manifest URL matches**

```bash
jq -r .repository .claude-plugin/plugin.json
```
Expected: `https://github.com/maksym-panibratenko/automaton`.

If the URL needs an update, fix it and amend the commit chain forward (a new commit, not an amend).

### Task L.8: File-count and LOC checks

- [ ] **Step 1: Count plugin files**

```bash
git ls-files | grep -v '^docs/' | grep -v '^tests/fixtures/' | wc -l
```
Expected: <= 35.

- [ ] **Step 2: Count custom code lines**

```bash
git ls-files | grep -v '^docs/' | grep -v '^tests/fixtures/' \
  | xargs wc -l | tail -1
```
Expected: <= 1500. If over budget, identify trim candidates.

- [ ] **Step 3: Final umbrella test**

```bash
bash tests/test-hooks.sh
```
Expected: all tests pass.

- [ ] **Step 4: Tag v0.0.1**

```bash
git tag v0.0.1
git push origin v0.0.1
```

- [ ] **Step 5: Add CHANGELOG entry, commit, push**

Append to `CHANGELOG.md`:

```markdown
## [0.0.1] — 2026-04-25

First public scaffold. Five slash commands, four hooks, one agent, two skills, two GH workflow templates. Acceptance criteria §14 walked successfully against the `automaton-acceptance` test repo.
```

```bash
git add CHANGELOG.md
git commit -m "chore: cut v0.0.1"
git push
```

---

## Self-review checklist (run before handing off)

- [ ] **Spec coverage:** §3.2 contributions all mapped (5 commands ✓ Milestone H, 1 agent ✓ G.1, 4 hooks ✓ C/D/E/F, 1 shell tool ✓ C.5, 2 skills ✓ G.2/G.3, 2 templates + .claude-harness.toml ✓ I/J, CLAUDE.md + settings.json ✓ K).
- [ ] **§4 worker contract:** all six steps in `working-an-issue/SKILL.md` (G.3) plus all halt conditions enumerated.
- [ ] **§5 dry-run protocol:** agent definition (G.1) + interpreting-an-issue skill (G.2) + comment template (G.2 + spec §5.3).
- [ ] **§7 label vocabulary:** all four `claude:*` labels referenced in skills and commands.
- [ ] **§7.1 auto-merge gate:** L.5 walks both true and false paths.
- [ ] **§8 hook schemas:** four hooks, all with PreToolUse/PostToolUse/SessionStart wirings and unit tests.
- [ ] **§9 observability:** PR-comment lifecycle (skill G.3), JSONL audit log (D), `/show-activity` (H.4).
- [ ] **§10 GH Actions:** both workflows scaffolded (I).
- [ ] **§11 packaging:** file map at top of plan covers every entry. (`README.md` already existed; we expand in K.2.)
- [ ] **§14 acceptance criteria:** L.1–L.8 walk all eleven items.
- [ ] **Placeholder scan:** every code step has actual code; no "TBD", no "implement later", no "similar to Task N".
- [ ] **Type/name consistency:** `run_state_set/get/clear/load_env`, `secret_patterns_scan_text/scan_path`, `audit_emit_phase`, `jsonl_append/iso_now/today` — same names everywhere they're called.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-25-automaton-plugin-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints.

Which approach?
