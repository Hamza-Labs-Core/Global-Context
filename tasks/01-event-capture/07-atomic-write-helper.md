# Task 07: Atomic Write Helper

**Story**: 01-event-capture
**Estimated Complexity**: S (Small)
**Status**: Pending

---

## Description

Implement an atomic write function that writes event data to a temporary file and then renames it to the target path. This addresses review issue M-3 by aligning with Story 03's atomic write pattern.

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Add `atomic_write` function |

---

## Specification/Implementation Details

Pattern:
```
1. Generate temp filename: {target}.tmp.{pid}
2. Write complete content to temp file
3. (Optional) fsync the temp file for sync hooks
4. Rename temp file to target filename (atomic on POSIX)
```

For performance, `fsync` is applied selectively:
- **Sync hooks** (SessionStarted, UserPromptReceived, CompactionTriggered): include `fsync` because data integrity on these critical events is worth the ~10ms cost.
- **Async hooks** (all others): skip `fsync` to stay within the 50ms latency target.

The event type is passed as a parameter to the write function so it can decide whether to fsync.

```bash
SYNC_EVENT_TYPES="SessionStarted UserPromptReceived CompactionTriggered"

atomic_write() {
  local target="$1"
  local content="$2"
  local event_type="$3"
  local tmp="${target}.tmp.$$"

  printf '%s\n' "$content" > "$tmp" || { rm -f "$tmp"; return 1; }

  # fsync for sync/critical event types
  if [[ " $SYNC_EVENT_TYPES " == *" $event_type "* ]]; then
    if command -v sync &>/dev/null; then
      sync "$tmp" 2>/dev/null || true
    fi
  fi

  mv "$tmp" "$target" || { rm -f "$tmp"; return 1; }
}
```

On failure (disk full, permission denied), the temp file is cleaned up and the error propagates to the caller for logging.

---

## Dependencies

- [Task 01: Base Dir Resolution](/home/meywd/GlobalContext/tasks/01-event-capture/01-base-dir-resolution.md)

---

## Acceptance Tests

1. Call `atomic_write` with valid args. Verify the target file exists with correct content.
2. Verify no `.tmp.*` files remain after a successful write.
3. Simulate disk full (write to a full tmpfs). Verify the temp file is cleaned up and the function returns non-zero.
4. Verify that for a `SessionStarted` event, `sync` is called (if available).
5. Verify that for a `ToolCallCompleted` event, `sync` is not called.
6. Verify the written file has permissions `600` (set by umask or explicit chmod).
