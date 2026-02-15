#!/usr/bin/env bash
# debug_log.sh -- Debug logging with rotation for GlobalContext (plugin version).
# Only active when GC_DEBUG=1.

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "$_LIB_DIR/paths.sh"

# Max log file size before rotation (1MB)
_GC_MAX_LOG_SIZE=1048576

# gc_debug_log(message)
#   Writes a timestamped log entry to $GC_LOG_FILE if GC_DEBUG=1.
#   Creates the log directory if needed. Rotates if log exceeds max size.
gc_debug_log() {
  [[ "${GC_DEBUG:-0}" == "1" ]] || return 0

  local message="$1"
  local log_dir
  log_dir="$(dirname "$GC_LOG_FILE")"

  # Create log directory if needed
  mkdir -p "$log_dir" 2>/dev/null || return 0

  # Rotate if needed
  if [[ -f "$GC_LOG_FILE" ]]; then
    local size
    size=$(stat -c '%s' "$GC_LOG_FILE" 2>/dev/null || stat -f '%z' "$GC_LOG_FILE" 2>/dev/null || echo 0)
    if [[ "$size" -gt "$_GC_MAX_LOG_SIZE" ]]; then
      mv -f "$GC_LOG_FILE" "${GC_LOG_FILE}.1" 2>/dev/null || true
    fi
  fi

  # Write log entry
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
  printf '%s [%s] %s\n' "$ts" "$$" "$message" >> "$GC_LOG_FILE" 2>/dev/null || true
}
