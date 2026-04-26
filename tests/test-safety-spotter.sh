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
