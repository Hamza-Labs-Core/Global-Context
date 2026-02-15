# Task 11: Add Debug Logging to gc-hook (Review Fix G-4)

**Story**: 02-hook-integration
**Status**: Pending
**Estimated Complexity**: S (Small) -- conditional wrapper around existing invocation, plus a small helper

---

## Description

Add optional debug logging to `gc-hook` so that stderr from async hook invocations is not silently lost. By default, stderr remains suppressed (production safety). When the `GC_DEBUG=1` environment variable is set, `gc-hook` writes diagnostic output to a log file instead.

This addresses **review issue G-4**: async hooks run with stderr suppressed (`2>/dev/null`), so if `capture-event` fails, there is no trace.

---

## Files to Modify

| File | Change |
|------|--------|
| `src/gc-hook` (from Task 1) | Add conditional debug logging |

## Files to Create

| File | Purpose |
|------|---------|
| `src/lib/debug_log.sh` | Shared debug logging helper (log rotation, file creation) |
| `tests/02-debug-log-tests.sh` | Tests for debug logging behavior |

---

## Specification / Implementation Details

### Debug Logging Helper (`src/lib/debug_log.sh`)

```bash
#!/usr/bin/env bash
# Debug logging for GlobalContext hooks
# Only active when GC_DEBUG=1

GC_LOG_DIR="${GC_BASE:-$HOME/.claude-context}/logs"
GC_LOG_FILE="$GC_LOG_DIR/hook.log"
GC_LOG_MAX_BYTES=1048576  # 1MB

gc_debug_log() {
  [ "${GC_DEBUG:-0}" != "1" ] && return 0
  mkdir -p "$GC_LOG_DIR" 2>/dev/null || return 0

  # Rotate if over 1MB
  if [ -f "$GC_LOG_FILE" ]; then
    local size
    size=$(stat -c%s "$GC_LOG_FILE" 2>/dev/null || stat -f%z "$GC_LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt "$GC_LOG_MAX_BYTES" ]; then
      mv "$GC_LOG_FILE" "$GC_LOG_FILE.old" 2>/dev/null
    fi
  fi

  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$GC_LOG_FILE" 2>/dev/null
}
```

### Modified gc-hook (Task 1 update)

```bash
# In gc-hook, replace the capture-event invocation:
if [ "${GC_DEBUG:-0}" = "1" ]; then
  source "$GC_BASE/lib/debug_log.sh" 2>/dev/null
  gc_debug_log "gc-hook invoked: event_type=$EVENT_TYPE"
  ("$GC_BASE/bin/capture-event" "$EVENT_TYPE" </dev/stdin >/dev/null 2>>"$GC_LOG_FILE") || {
    gc_debug_log "capture-event failed: exit=$?"
    true
  }
else
  ("$GC_BASE/bin/capture-event" "$EVENT_TYPE" </dev/stdin >/dev/null 2>/dev/null) || true
fi
```

### Key Design Decisions

- **Default off**: No performance impact in production. Zero filesystem writes when `GC_DEBUG` is unset.
- **1MB rotation**: Keeps a single `.old` backup. No unbounded growth.
- **Best-effort**: All logging operations fail silently (logging must never break the exit-0 guarantee).
- **Platform-compatible stat**: Tries Linux (`-c%s`) then macOS (`-f%z`) syntax.

---

## Dependencies

- [Task 01: gc-hook wrapper](/home/meywd/GlobalContext/tasks/02-hook-integration/01-gc-hook-wrapper.md) -- gc-hook must exist

---

## Acceptance Tests

1. Run gc-hook with `GC_DEBUG` unset -- no log file created, no log directory created.
2. Run gc-hook with `GC_DEBUG=1` -- log file created at `$GC_BASE/logs/hook.log`.
3. Log entry contains timestamp, event type, and outcome.
4. When capture-event fails with `GC_DEBUG=1` -- failure is logged with exit code.
5. Write 1.5MB of log entries -- file is rotated, `hook.log.old` exists, `hook.log` is small.
6. `GC_DEBUG=1` gc-hook still exits 0, still produces zero stdout/stderr.
7. Corrupt or read-only log directory -- gc-hook still exits 0 (logging failure is silent).
