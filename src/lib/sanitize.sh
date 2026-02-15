#!/usr/bin/env bash
# Session ID sanitization -- single authoritative implementation.
# All stories must call this function, never re-implement the rules.
#
# Rules:
#   1. Allowed characters: a-z A-Z 0-9 - _
#   2. Everything else is stripped (using tr -cd).
#   3. Dots are stripped by the character class, preventing path traversal.
#   4. If the result is empty, fall back to "unknown".
#   5. Truncate to 255 characters after sanitization.
#   6. The mapping is deterministic.
set -euo pipefail

gc_sanitize_session_id() {
  local raw_id="${1:-}"
  local sanitized

  # Strip all characters not in the allowed set
  sanitized="$(printf '%s' "$raw_id" | tr -cd 'a-zA-Z0-9_-')"

  # Fall back to "unknown" if empty
  if [[ -z "$sanitized" ]]; then
    sanitized="unknown"
  fi

  # Truncate to 255 characters
  sanitized="${sanitized:0:255}"

  printf '%s' "$sanitized"
}
