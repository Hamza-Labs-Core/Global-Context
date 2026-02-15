#!/usr/bin/env bash
# JSON validation helpers for GlobalContext event store (plugin version).

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# gc_validate_json(json_string) -> 0 (valid) or 1 (invalid)
gc_validate_json() {
  local json_string="${1:-}"

  if [ -z "$json_string" ]; then
    echo "gc_validate_json: empty input" >&2
    return 1
  fi

  if ! echo "$json_string" | jq empty 2>/dev/null; then
    echo "gc_validate_json: malformed JSON" >&2
    return 1
  fi

  return 0
}

# gc_validate_event_json(json_string) -> 0 (valid) or 1 (invalid)
gc_validate_event_json() {
  local json_string="${1:-}"

  if [ -z "$json_string" ]; then
    echo "gc_validate_event_json: empty input" >&2
    return 1
  fi

  if ! echo "$json_string" | jq empty 2>/dev/null; then
    echo "gc_validate_event_json: malformed JSON" >&2
    return 1
  fi

  local required_fields=("event_id" "event_type" "project_id" "session_id" "sequence" "timestamp" "data")
  for field in "${required_fields[@]}"; do
    local val
    val=$(echo "$json_string" | jq -r ".$field // \"__MISSING__\"")
    if [ "$val" = "__MISSING__" ]; then
      echo "gc_validate_event_json: missing required field '$field'" >&2
      return 1
    fi
  done

  local seq_type
  seq_type=$(echo "$json_string" | jq -r '.sequence | type')
  if [ "$seq_type" != "number" ]; then
    echo "gc_validate_event_json: 'sequence' must be a number, got $seq_type" >&2
    return 1
  fi

  local data_type
  data_type=$(echo "$json_string" | jq -r '.data | type')
  if [ "$data_type" != "object" ]; then
    echo "gc_validate_event_json: 'data' must be an object, got $data_type" >&2
    return 1
  fi

  return 0
}
