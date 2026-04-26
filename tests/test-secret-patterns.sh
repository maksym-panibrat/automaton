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
