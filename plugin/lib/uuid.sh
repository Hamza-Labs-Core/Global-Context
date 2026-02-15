#!/usr/bin/env bash
# uuid.sh -- UUID v4 generation with fallback chain (plugin version).
# Extracted from event_write.sh for shared use.

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# gc_generate_uuid()
#   Generates a UUID v4 string. Tries /proc, then uuidgen, then pseudo-random.
gc_generate_uuid() {
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  elif command -v uuidgen &>/dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    # Fallback: pseudo-random hex
    printf '%04x%04x-%04x-%04x-%04x-%04x%04x%04x' \
      $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM
  fi
}
