#!/usr/bin/env bash
set -euo pipefail

# install-hooks.sh -- Deploy Story 02 (Hook Integration Layer) components
# This script installs gc-hook and gc-install-hooks, then registers hooks
# in Claude Code's settings.json.
#
# Prerequisites:
#   - Story 01 must be installed (capture-event at $GC_BASE/bin/capture-event)
#   - jq must be on PATH
#
# Usage: bash src/install-hooks.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GC_BASE="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"

echo "GlobalContext Hook Integration -- Installer"
echo "Store: $GC_BASE"
echo ""

# Verify prerequisites
if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required but not found on PATH" >&2
  exit 1
fi

if [ ! -d "$GC_BASE" ]; then
  echo "error: GlobalContext store not found at $GC_BASE" >&2
  echo "hint: run Story 01 install first (gc-init)" >&2
  exit 1
fi

if [ ! -x "$GC_BASE/bin/capture-event" ]; then
  echo "error: capture-event not found at $GC_BASE/bin/capture-event" >&2
  echo "hint: run Story 01 install first" >&2
  exit 1
fi

# Ensure bin directory exists
mkdir -p "$GC_BASE/bin"
mkdir -p "$GC_BASE/lib"
mkdir -p "$GC_BASE/etc"

# Deploy hook wrapper (Story 02)
echo "Deploying gc-hook..."
cp "$SCRIPT_DIR/gc-hook" "$GC_BASE/bin/gc-hook"
chmod +x "$GC_BASE/bin/gc-hook"

# Deploy hook installer (Story 02)
echo "Deploying gc-install-hooks..."
cp "$SCRIPT_DIR/gc-install-hooks" "$GC_BASE/bin/gc-install-hooks"
chmod +x "$GC_BASE/bin/gc-install-hooks"

# Deploy hook config
echo "Deploying hook-config.json..."
cp "$SCRIPT_DIR/hook-config.json" "$GC_BASE/etc/hook-config.json"

# Deploy debug logging helper
if [ -f "$SCRIPT_DIR/lib/debug_log.sh" ]; then
  echo "Deploying debug_log.sh..."
  cp "$SCRIPT_DIR/lib/debug_log.sh" "$GC_BASE/lib/debug_log.sh"
fi

# Deploy gc-uninstall
if [ -f "$SCRIPT_DIR/bin/gc-uninstall" ]; then
  echo "Deploying gc-uninstall..."
  cp "$SCRIPT_DIR/bin/gc-uninstall" "$GC_BASE/bin/gc-uninstall"
  chmod +x "$GC_BASE/bin/gc-uninstall"
fi

# Register hooks in Claude Code settings
echo ""
echo "Registering hooks in Claude Code settings..."
"$GC_BASE/bin/gc-install-hooks" install

echo ""
echo "Installation complete."
