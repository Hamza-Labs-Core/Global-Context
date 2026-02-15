#!/usr/bin/env bash
# session_dir.sh -- Session directory creation and lock file management (plugin version).

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "$_LIB_DIR/paths.sh"
# shellcheck source=sanitize.sh
source "$_LIB_DIR/sanitize.sh"

# gc_ensure_session_dir(project_id, session_id)
gc_ensure_session_dir() {
  local project_id="${1:?gc_ensure_session_dir requires project_id as \$1}"
  local session_id="${2-}"

  local sanitized
  sanitized="$(gc_sanitize_session_id "$session_id")"

  local dir="$GC_EVENTS_DIR/$project_id/$sanitized"

  mkdir -p "$dir"
  touch "$dir/.lock"

  printf '%s' "$dir"
}
