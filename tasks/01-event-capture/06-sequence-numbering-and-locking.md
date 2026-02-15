# Task 06: Sequence Numbering with flock-Based Locking

**Story**: 01-event-capture
**Estimated Complexity**: M (Medium)
**Status**: Pending

---

## Description

Implement the per-session sequence number assignment using `flock` for exclusive locking. This addresses review issue C-1 by using `.lock` (not `_seq.lock`) as the lock file name.

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Add sequence assignment logic inside flock subshell |

---

## Specification/Implementation Details

The sequence assignment runs inside a flock-guarded subshell:

```bash
SESSION_DIR="$EVENTS_DIR/$project_id/$safe_session_id"
LOCK_FILE="$SESSION_DIR/.lock"
mkdir -p "$SESSION_DIR"

(
  flock -w 5 200 || { echo "[capture-event] WARN: Lock timeout after 5s, dropping event." >&2; exit 0; }

  # Count existing event files (only numbered files, exclude session.json)
  existing=$(ls "$SESSION_DIR"/[0-9]*.json 2>/dev/null | wc -l)
  next_seq=$((existing + 1))
  padded=$(printf "%06d" "$next_seq")

  # ... (write event file here, see Task 7/8)

) 200>"$LOCK_FILE"
```

If `flock` is not available:
- Log a warning to stderr.
- Attempt write without locking (best-effort).
- To mitigate collision risk, append a random suffix to the filename: `{padded}_{random4hex}.json`. This breaks the clean naming convention but preserves data. Document this as a known degradation mode.

Lock file:
- Located at `$SESSION_DIR/.lock` (not `_seq.lock` -- per C-1 resolution).
- Created implicitly by the flock redirect (`200>"$LOCK_FILE"`).
- Never deleted by the capture script.

---

## Dependencies

- [Task 01: Base Dir Resolution](/home/meywd/GlobalContext/tasks/01-event-capture/01-base-dir-resolution.md)
- [Task 03: Session ID Sanitization](/home/meywd/GlobalContext/tasks/01-event-capture/03-session-id-sanitization.md) -- sanitized session dir path is needed.

---

## Acceptance Tests

1. Fire 5 events sequentially for the same session. Verify files `000001.json` through `000005.json` exist.
2. Verify the `sequence` field inside each JSON envelope matches its filename number.
3. Fire 10 events concurrently (`&` + `wait`) for the same session. Verify all 10 files exist with unique, sequential numbers (no gaps, no duplicates).
4. Simulate lock timeout (hold the lock with a separate process for > 5s). Verify the capture script logs a warning and exits 0.
5. Verify the lock file is at `$SESSION_DIR/.lock`, not `_seq.lock`.
6. Verify `flock` availability check works: temporarily rename `flock` binary and verify the fallback path is taken with a warning.
