# Task 14: Rejected Event Handling

**Story**: 03-storage-layer
**Status**: Pending
**Estimated Complexity**: S (Small) -- 1-2 hours

---

## Description

Implement the `_rejected/` directory mechanism for events that fail validation. These are events that cannot be written to the main event log but should be preserved for debugging.

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/rejected.sh` | Create | Rejected event writing |
| `tests/lib/test_rejected.sh` | Create | Tests |

---

## Specification

Function: `gc_write_rejected_event(project_id, session_id, content, error_reason)`:

1. Create `$GC_EVENTS_DIR/{project_id}/{session_id}/_rejected/` if it does not exist.
2. Write a file named `{timestamp}-{uuid}.json` containing:
   ```json
   {
     "_rejected_at": "<ISO 8601>",
     "_reason": "<error_reason>",
     "_original_content": "<content or truncated preview>"
   }
   ```
3. This does not need flock (rejected files do not participate in sequencing).
4. Uses atomic write (Task 4).

---

## Dependencies

- **Task 01**: `/home/meywd/GlobalContext/tasks/03-storage-layer/01-shared-path-resolver.md` (paths.sh)
- **Task 03**: `/home/meywd/GlobalContext/tasks/03-storage-layer/03-session-directory-and-lock-files.md` (session_dir.sh)
- **Task 04**: `/home/meywd/GlobalContext/tasks/03-storage-layer/04-atomic-write-helper.md` (atomic_write.sh)

---

## Acceptance Tests

1. Write a rejected event -- file appears in `_rejected/` with correct structure.
2. Rejected files do not interfere with sequence numbering (not counted as events).
3. Multiple rejected events create separate files (no overwrites).
4. The `_reason` field explains why the event was rejected.
