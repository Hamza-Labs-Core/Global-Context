#!/usr/bin/env bash
# install.sh -- Provision the GlobalContext directory structure and install capture-event.
#
# Idempotent: safe to run multiple times without overwriting existing data.
#
# Environment:
#   CLAUDE_CONTEXT_PATH - override storage root (default: ~/.claude-context)
set -euo pipefail

# Resolve the directory where this script lives (for locating capture-event source)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# === Base directory resolution: source paths.sh if available, else inline pattern ===
PATHS_SH="$SCRIPT_DIR/lib/paths.sh"
if [ -f "$PATHS_SH" ]; then
  # shellcheck source=lib/paths.sh
  source "$PATHS_SH"
  BASE_DIR="$GC_ROOT"
  EVENTS_DIR="$GC_EVENTS_DIR"
  PROJECTIONS_DIR="$GC_PROJECTIONS_DIR"
  BIN_DIR="$GC_BIN_DIR"
  CONFIG_FILE="$GC_CONFIG_FILE"
else
  # Fallback inline pattern for standalone operation
  BASE_DIR="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"
  EVENTS_DIR="$BASE_DIR/events"
  PROJECTIONS_DIR="$BASE_DIR/projections"
  BIN_DIR="$BASE_DIR/bin"
  CONFIG_FILE="$BASE_DIR/config.json"
fi

# === Dependency validation ===
echo "Checking dependencies..."

# jq: required -- abort if missing
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not found." >&2
  echo "  Install with: sudo apt-get install jq (Debian/Ubuntu)" >&2
  echo "                brew install jq (macOS)" >&2
  exit 1
fi
echo "  jq: found ($(jq --version 2>/dev/null || echo 'unknown version'))"

# flock: required -- warn if missing
if ! command -v flock &>/dev/null; then
  echo "  WARNING: flock not found. Event capture will work but without locking." >&2
  echo "  Install with: sudo apt-get install util-linux (Debian/Ubuntu)" >&2
else
  echo "  flock: found"
fi

# uuidgen: optional -- note fallback
if ! command -v uuidgen &>/dev/null; then
  echo "  uuidgen: not found (will use /proc/sys/kernel/random/uuid or bash fallback)"
else
  echo "  uuidgen: found"
fi

# sha256sum: needed for project_id derivation -- check with fallbacks
if command -v sha256sum &>/dev/null; then
  echo "  sha256sum: found"
elif command -v shasum &>/dev/null; then
  echo "  sha256sum: not found (using shasum -a 256 fallback)"
elif command -v openssl &>/dev/null; then
  echo "  sha256sum: not found (using openssl dgst -sha256 fallback)"
else
  echo "ERROR: No SHA-256 tool found. Need one of: sha256sum, shasum, or openssl." >&2
  echo "  Install with: sudo apt-get install coreutils (Debian/Ubuntu)" >&2
  echo "                (shasum/openssl are pre-installed on macOS)" >&2
  exit 1
fi

# === Create directory structure ===
echo ""
echo "Creating directory structure at $BASE_DIR..."

# Root directory
mkdir -p "$BASE_DIR"
chmod 700 "$BASE_DIR"
echo "  $BASE_DIR/ (root, mode 700)"

# Events directory
mkdir -p "$EVENTS_DIR"
echo "  $EVENTS_DIR/"

# Projections directory
mkdir -p "$PROJECTIONS_DIR"
echo "  $PROJECTIONS_DIR/"

# Bin directory
mkdir -p "$BIN_DIR"
echo "  $BIN_DIR/"

# === Install capture-event to bin/ ===
CAPTURE_EVENT_SRC="$SCRIPT_DIR/capture-event"
CAPTURE_EVENT_DST="$BIN_DIR/capture-event"

if [ -f "$CAPTURE_EVENT_SRC" ]; then
  cp "$CAPTURE_EVENT_SRC" "$CAPTURE_EVENT_DST"
  chmod 755 "$CAPTURE_EVENT_DST"
  echo "  Installed capture-event to $CAPTURE_EVENT_DST (mode 755)"
else
  echo "  WARNING: capture-event not found at $CAPTURE_EVENT_SRC" >&2
fi

# === Create config.json (only if it does not exist) ===
if [ -f "$CONFIG_FILE" ]; then
  echo ""
  echo "config.json already exists, preserving."
else
  CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq -n \
    --arg version "1.0.0" \
    --arg events_dir "events" \
    --arg created_at "$CREATED_AT" \
    '{
      version: $version,
      events_dir: $events_dir,
      created_at: $created_at
    }' > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  echo ""
  echo "Created config.json:"
  cat "$CONFIG_FILE"
fi

echo ""
echo "GlobalContext store ready at $BASE_DIR"
