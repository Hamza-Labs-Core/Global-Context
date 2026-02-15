#!/usr/bin/env bash
# timestamp.sh -- ISO 8601 timestamp generation (plugin version).
# Extracted from event_write.sh for shared use.

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect if date supports %3N (GNU date). BSD date does not.
_GC_DATE_HAS_MILLIS=""
_gc_check_date_millis() {
  if [ -z "$_GC_DATE_HAS_MILLIS" ]; then
    local test_val
    test_val="$(date -u +"%3N" 2>/dev/null)"
    if [[ "$test_val" =~ ^[0-9]{3}$ ]]; then
      _GC_DATE_HAS_MILLIS="yes"
    else
      _GC_DATE_HAS_MILLIS="no"
    fi
  fi
}

# gc_iso_timestamp()
#   Returns current UTC time in ISO 8601 format with milliseconds if supported.
gc_iso_timestamp() {
  _gc_check_date_millis
  if [ "$_GC_DATE_HAS_MILLIS" = "yes" ]; then
    date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
  else
    date -u +"%Y-%m-%dT%H:%M:%S.000Z"
  fi
}
