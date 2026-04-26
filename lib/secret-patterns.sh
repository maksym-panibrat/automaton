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
  '-----BEGIN.*PRIVATE KEY-----'
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
    hit="$(printf '%s\n' "$input" | grep -E -m1 -- "$pat" || true)"
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
