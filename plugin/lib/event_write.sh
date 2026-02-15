#!/usr/bin/env bash
# event_write.sh -- Core event writing pipeline for GlobalContext (plugin version).
# Constructs the 7-field event envelope, assigns a sequence number under flock,
# validates, writes atomically, and updates per-session metadata.

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "$_LIB_DIR/paths.sh"
# shellcheck source=sanitize.sh
source "$_LIB_DIR/sanitize.sh"
# shellcheck source=session_dir.sh
source "$_LIB_DIR/session_dir.sh"
# shellcheck source=atomic_write.sh
source "$_LIB_DIR/atomic_write.sh"
# shellcheck source=json_validate.sh
source "$_LIB_DIR/json_validate.sh"
# shellcheck source=session_meta.sh
source "$_LIB_DIR/session_meta.sh"
# shellcheck source=uuid.sh
source "$_LIB_DIR/uuid.sh"
# shellcheck source=timestamp.sh
source "$_LIB_DIR/timestamp.sh"

# _gc_next_sequence(session_dir)
_gc_next_sequence() {
  local session_dir="$1"
  local highest=0

  local files
  files="$(find "$session_dir" -maxdepth 1 -name '[0-9]*.json' -not -name 'session.json' 2>/dev/null || true)"

  if [[ -z "$files" ]]; then
    printf '%d' 1
    return
  fi

  local f base num
  while IFS= read -r f; do
    base="$(basename "$f" .json)"
    num=$((10#$base))
    if (( num > highest )); then
      highest=$num
    fi
  done <<< "$files"

  printf '%d' $(( highest + 1 ))
}

# gc_write_event(session_id, event_type, data_json)
gc_write_event() {
  local session_id="${1:?gc_write_event requires session_id as \$1}"
  local event_type="${2:?gc_write_event requires event_type as \$2}"
  local data_json="${3:?gc_write_event requires data_json as \$3}"

  local sanitized_session_id
  sanitized_session_id="$(gc_sanitize_session_id "$session_id")"

  local project_dir="${GC_PROJECT_DIR:-$PWD}"
  local project_id
  project_id="$(gc_derive_project_id "$project_dir")"

  local session_dir
  session_dir="$(gc_ensure_session_dir "$project_id" "$sanitized_session_id")"

  local lock_file="$session_dir/.lock"
  local flock_acquired=true

  exec 9>"$lock_file"

  if ! flock -w 5 9; then
    flock_acquired=false
  fi

  if [[ "$flock_acquired" == "true" ]]; then
    local sequence
    sequence="$(_gc_next_sequence "$session_dir")"

    if (( sequence > 999999 )); then
      exec 9>&-
      return 1
    fi

    local event_id timestamp
    event_id="$(gc_generate_uuid)"
    timestamp="$(gc_iso_timestamp)"

    local envelope
    envelope="$(jq -c -n \
      --arg eid "$event_id" \
      --arg etype "$event_type" \
      --arg pid "$project_id" \
      --arg sid "$sanitized_session_id" \
      --argjson seq "$sequence" \
      --arg ts "$timestamp" \
      --argjson data "$data_json" \
      '{
        event_id: $eid,
        event_type: $etype,
        project_id: $pid,
        session_id: $sid,
        sequence: $seq,
        timestamp: $ts,
        data: $data
      }')"

    local padded_seq filename target_path
    padded_seq="$(printf "%06d" "$sequence")"
    filename="${padded_seq}.json"
    target_path="$session_dir/$filename"

    if ! gc_atomic_write "$target_path" "$envelope" false; then
      exec 9>&-
      return 1
    fi

    if [[ ! -f "$session_dir/session.json" ]]; then
      gc_session_meta_create "$session_dir" "$sanitized_session_id" "$project_id" \
        "$project_dir" "claude-code" "unknown" "$timestamp"
    else
      gc_session_meta_update "$session_dir" "$event_type" "$timestamp"
    fi

    exec 9>&-
    printf '%s' "$target_path"
    return 0
  else
    exec 9>&-

    local event_id timestamp orphan_uuid orphan_filename
    event_id="$(gc_generate_uuid)"
    timestamp="$(gc_iso_timestamp)"
    orphan_uuid="$(gc_generate_uuid)"
    orphan_filename="orphan-${orphan_uuid}.json"

    local envelope
    envelope="$(jq -c -n \
      --arg eid "$event_id" \
      --arg etype "$event_type" \
      --arg pid "$project_id" \
      --arg sid "$sanitized_session_id" \
      --argjson seq 0 \
      --arg ts "$timestamp" \
      --argjson data "$data_json" \
      '{
        event_id: $eid,
        event_type: $etype,
        project_id: $pid,
        session_id: $sid,
        sequence: $seq,
        timestamp: $ts,
        data: $data
      }')"

    local target_path="$session_dir/$orphan_filename"

    if ! gc_atomic_write "$target_path" "$envelope" false; then
      return 1
    fi

    printf '%s' "$target_path"
    return 0
  fi
}
