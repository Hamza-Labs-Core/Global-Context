#!/usr/bin/env bash
# timestamp.sh -- ISO 8601 timestamp generation (plugin version).
# Extracted from event_write.sh for shared use.

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# gc_iso_timestamp()
#   Returns current UTC time in ISO 8601 format with milliseconds.
gc_iso_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
}
