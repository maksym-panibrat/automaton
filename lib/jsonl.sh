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
