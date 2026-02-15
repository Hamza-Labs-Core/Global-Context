# Task 04: Auto-Init on First Use

**Story**: 06-plugin-packaging
**Estimated Complexity**: S (Small)
**Dependencies**:
- [Task 01 - Plugin Manifest and Directory Scaffold](/home/meywd/GlobalContext/tasks/06-plugin-packaging/01-plugin-manifest-scaffold.md)
- [Task 03 - Capture Event Script Adaptation](/home/meywd/GlobalContext/tasks/06-plugin-packaging/03-capture-script-adaptation.md) (gc-hook must exist to be modified)

---

## Description

The SessionStart hook checks if the data store exists and initializes it if needed. This replaces the manual `gc-init` / `install.sh` step from Story 00. The check must be fast (just a directory existence test) and idempotent.

When a user installs the plugin and starts their first session, the SessionStart hook fires. If `~/.claude-context/` does not exist, `gc-hook` runs the initialization logic before invoking `capture-event`. This is a one-time cost on the very first session; subsequent sessions skip initialization in under 1ms.

---

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `plugin/scripts/gc-init` | Create | Initialization script for the data store |
| `plugin/scripts/gc-hook` | Modify | Add auto-init check before capture-event invocation |

---

## Specification

### `plugin/scripts/gc-init`

```bash
#!/usr/bin/env bash
# GlobalContext store initialization
# Creates directory structure at $GC_ROOT
# Idempotent: safe to run multiple times

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$PLUGIN_ROOT/lib/paths.sh" 2>/dev/null || {
  GC_ROOT="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"
}

# Create directory structure
mkdir -p "$GC_ROOT/events" 2>/dev/null
mkdir -p "$GC_ROOT/projections" 2>/dev/null
mkdir -p "$GC_ROOT/logs" 2>/dev/null
chmod 700 "$GC_ROOT" 2>/dev/null

# Create config.json if missing
if [ ! -f "$GC_ROOT/config.json" ]; then
  cat > "$GC_ROOT/config.json" <<CONF
{
  "version": "1.0.0",
  "events_dir": "events",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source": "plugin"
}
CONF
fi

exit 0
```

### Modification to `gc-hook` (added before the capture-event invocation)

```bash
# Auto-init: check if store exists, run gc-init if not
if [ ! -d "$GC_BASE/events" ]; then
  "$PLUGIN_ROOT/scripts/gc-init" 2>/dev/null || true
fi
```

### Key Design Decisions

- The check is `[ -d "$GC_BASE/events" ]` -- a single stat syscall, effectively free.
- `gc-init` is idempotent: `mkdir -p` is a no-op if directories exist, `config.json` is only written if missing.
- Errors in `gc-init` are suppressed (`2>/dev/null || true`) -- if init fails (permissions, disk full), the session is not disrupted.
- The `config.json` gains a `"source": "plugin"` field to distinguish plugin-installed stores from manually installed ones.

---

## Acceptance Tests

1. On a system with no `~/.claude-context/`: run `echo '{"session_id":"init-test"}' | plugin/scripts/gc-hook SessionStarted`. Verify `~/.claude-context/events/` and `~/.claude-context/projections/` are created.
2. Verify `~/.claude-context/config.json` exists with `version`, `events_dir`, `created_at`, and `source` fields.
3. Verify `~/.claude-context/` has permissions `700`.
4. Run `gc-hook` again. Verify no errors and no duplicate initialization (idempotent).
5. Set `CLAUDE_CONTEXT_PATH=/tmp/gc-init-test`. Run `gc-hook`. Verify directories are created at the custom path.
6. Make `gc-init` fail (read-only filesystem). Verify `gc-hook` still exits 0 and the session is not disrupted.
7. Measure the time for the `[ -d ]` check on an existing store: under 1ms.
