# Task 03: Capture Event Script Adaptation

**Story**: 06-plugin-packaging
**Estimated Complexity**: M (Medium)
**Dependencies**:
- [Task 01 - Plugin Manifest and Directory Scaffold](/home/meywd/GlobalContext/tasks/06-plugin-packaging/01-plugin-manifest-scaffold.md)
- [Task 08 - Shared Library Bundling](/home/meywd/GlobalContext/tasks/06-plugin-packaging/08-shared-library-bundling.md) (shared libraries must be bundled for sourcing)

---

## Description

Adapt the `capture-event` and `gc-hook` scripts to work from `${CLAUDE_PLUGIN_ROOT}` instead of the hardcoded `~/.claude-context/bin/` path. The scripts themselves are deployed as `plugin/scripts/capture-event` and `plugin/scripts/gc-hook`. All code paths resolve relative to the plugin root; all data paths resolve to `~/.claude-context/` (or `$CLAUDE_CONTEXT_PATH`).

This is the critical distinction in the plugin model: **code lives in the plugin directory, data lives in the user's home directory**. The plugin may be installed in a read-only location managed by Claude Code's plugin system. The data store must remain in a user-writable location.

---

## Files to Create

| File | Purpose |
|------|---------|
| `plugin/scripts/gc-hook` | Hook wrapper adapted for plugin root |
| `plugin/scripts/capture-event` | Event capture script adapted for plugin root |

---

## Specification

### `plugin/scripts/gc-hook` (adapted from `src/gc-hook`)

```bash
#!/usr/bin/env bash
# GlobalContext plugin hook wrapper v1
# Usage: gc-hook <EventType>
# Called by Claude Code hooks. Reads JSON from stdin, passes to capture-event.
# GUARANTEES: exit 0, zero stdout, zero stderr.

EVENT_TYPE="${1:?Missing event type}"

# Resolve code paths from plugin root
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Resolve data path: CLAUDE_CONTEXT_PATH env var, or default
GC_BASE="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"

# Source shared libraries from plugin
source "$PLUGIN_ROOT/lib/paths.sh" 2>/dev/null || true

# Run capture-event from plugin scripts directory
if [ "${GC_DEBUG:-0}" = "1" ]; then
  source "$PLUGIN_ROOT/lib/debug_log.sh" 2>/dev/null
  gc_debug_log "gc-hook invoked: event_type=$EVENT_TYPE"
  ("$PLUGIN_ROOT/scripts/capture-event" "$EVENT_TYPE" </dev/stdin >/dev/null 2>>"$GC_LOG_FILE") || {
    gc_debug_log "capture-event failed: exit=$?"
    true
  }
else
  ("$PLUGIN_ROOT/scripts/capture-event" "$EVENT_TYPE" </dev/stdin >/dev/null 2>/dev/null) || true
fi

exit 0
```

### `plugin/scripts/capture-event` (adapted from `src/capture-event`)

Key changes from the standalone version:
- Resolves shared libraries via `$PLUGIN_ROOT/lib/` instead of `$GC_BASE/lib/`
- All `source` commands reference `$PLUGIN_ROOT/lib/paths.sh`, `$PLUGIN_ROOT/lib/sanitize.sh`, `$PLUGIN_ROOT/lib/atomic_write.sh`
- Data paths still use `$GC_ROOT` (resolved by `paths.sh` from `$CLAUDE_CONTEXT_PATH` or `~/.claude-context/`)
- The `PLUGIN_ROOT` is derived from `$(cd "$(dirname "$0")/.." && pwd)` -- one level up from `scripts/`

### Path Resolution Model

```
Code paths (read-only, plugin-managed):
  ${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook
  ${CLAUDE_PLUGIN_ROOT}/scripts/capture-event
  ${CLAUDE_PLUGIN_ROOT}/lib/paths.sh
  ${CLAUDE_PLUGIN_ROOT}/lib/sanitize.sh
  ${CLAUDE_PLUGIN_ROOT}/lib/atomic_write.sh
  ${CLAUDE_PLUGIN_ROOT}/lib/*.js

Data paths (read-write, user-managed):
  ~/.claude-context/events/{project-id}/{session-id}/*.json
  ~/.claude-context/projections/{project-id}/{session-id}/*.json
  ~/.claude-context/config.json
  ~/.claude-context/logs/hook.log
```

---

## Acceptance Tests

1. `plugin/scripts/gc-hook` is executable and exits 0 when run with `echo '{}' | plugin/scripts/gc-hook TestEvent`.
2. `plugin/scripts/gc-hook` produces zero stdout and zero stderr under all conditions (missing capture-event, crash, empty stdin).
3. `plugin/scripts/capture-event` correctly resolves `$PLUGIN_ROOT/lib/` for code and `$GC_ROOT` for data.
4. Running `echo '{"session_id":"test-s1"}' | CLAUDE_CONTEXT_PATH=/tmp/gc-test plugin/scripts/gc-hook SessionStarted` writes an event to `/tmp/gc-test/events/`.
5. No hardcoded `~/.claude-context/bin/` paths remain in either script.
6. Both scripts work when the plugin directory is at an arbitrary location (not `~/.claude-context/`).
