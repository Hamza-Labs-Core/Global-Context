#!/usr/bin/env bash
# Atomic write helper for GlobalContext (plugin version).
# Writes content to a temp file, optionally fsyncs, then atomically renames.

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "$_LIB_DIR/paths.sh"

# gc_atomic_write target_path content [fsync]
gc_atomic_write() {
  if [[ $# -lt 2 ]]; then
    echo "gc_atomic_write: requires at least 2 arguments (target_path, content)" >&2
    return 1
  fi
  local target_path="$1"
  local content="$2"
  local fsync="${3:-false}"

  local target_dir
  target_dir="$(dirname "$target_path")"

  if [[ ! -d "$target_dir" ]]; then
    echo "gc_atomic_write: target directory does not exist: $target_dir" >&2
    return 1
  fi

  local tmp_path="${target_path}.tmp.${BASHPID:-$$}"

  _gc_atomic_cleanup() {
    rm -f "$tmp_path" 2>/dev/null || true
  }

  if ! printf '%s' "$content" > "$tmp_path"; then
    _gc_atomic_cleanup
    echo "gc_atomic_write: failed to write temp file: $tmp_path" >&2
    return 1
  fi

  if [[ "$fsync" == "true" ]]; then
    if ! _gc_fsync "$tmp_path"; then
      _gc_atomic_cleanup
      echo "gc_atomic_write: fsync failed for: $tmp_path" >&2
      return 1
    fi
  fi

  if ! mv -f "$tmp_path" "$target_path"; then
    _gc_atomic_cleanup
    echo "gc_atomic_write: rename failed: $tmp_path -> $target_path" >&2
    return 1
  fi

  return 0
}

_gc_fsync() {
  local file_path="$1"

  if command -v python3 &>/dev/null; then
    python3 -c "
import os, sys
fd = os.open(sys.argv[1], os.O_RDONLY)
os.fsync(fd)
os.close(fd)
" "$file_path" 2>/dev/null && return 0
  fi

  if dd if="$file_path" of="$file_path" conv=notrunc,fdatasync count=0 2>/dev/null; then
    return 0
  fi

  sync 2>/dev/null || true
  return 0
}
