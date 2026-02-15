# Task 11: Projection Directory and File Scaffolding

**Story**: 03-storage-layer
**Status**: Pending
**Estimated Complexity**: M (Medium) -- 2-3 hours

---

## Description

Implement the projection storage structure: per-session projection directories, projection file metadata format, staleness detection, and the atomic write pattern for projection files. This task creates the scaffolding -- the actual projection logic (timeline, files-touched, etc.) is Story 04's responsibility.

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/projection_store.sh` | Create | Projection directory creation, staleness check, metadata handling |
| `tests/lib/test_projection_store.sh` | Create | Tests |

---

## Specification

Function: `gc_ensure_projection_dir(project_id, session_id)`:

- Creates `$GC_PROJECTIONS_DIR/{project_id}/{session_id}/` if it does not exist.
- Returns the directory path.

Function: `gc_write_projection(project_id, session_id, projection_name, data_json, event_count, last_sequence)`:

- Wraps data in metadata envelope:
  ```json
  {
    "_projection": "<projection_name>",
    "_project_id": "<project_id>",
    "_session_id": "<session_id>",
    "_rebuilt_at": "<ISO 8601 now>",
    "_event_count": <event_count>,
    "_last_sequence": <last_sequence>,
    "data": <data_json>
  }
  ```
- Writes atomically to `$GC_PROJECTIONS_DIR/{project_id}/{session_id}/{projection_name}.json`.

Function: `gc_is_projection_stale(project_id, session_id, projection_name) -> 0 (stale) or 1 (current)`:

- Read `_last_sequence` from the projection file.
- Count `[0-9]*.json` files in `$GC_EVENTS_DIR/{project_id}/{session_id}/` (excludes session.json, lock files, rejected).
- If event count > `_last_sequence`: projection is stale (return 0).
- If projection file does not exist: stale (return 0).
- Otherwise: current (return 1).

Function: `gc_read_projection(project_id, session_id, projection_name) -> json`:

- Reads and returns the projection file content.
- Returns empty string if file does not exist.

Projection file definitions (schema owned by Story 04, listed here for reference):

| File | Purpose |
|---|---|
| `timeline.json` | Ordered chronological summary |
| `files-touched.json` | File operation tracking |
| `decisions.json` | Intent-to-action chains |
| `context.json` | Full reconstructable context |

---

## Dependencies

- **Task 01**: `/home/meywd/GlobalContext/tasks/03-storage-layer/01-shared-path-resolver.md` (paths.sh)
- **Task 04**: `/home/meywd/GlobalContext/tasks/03-storage-layer/04-atomic-write-helper.md` (atomic_write.sh)

---

## Acceptance Tests

1. `gc_ensure_projection_dir "proj-abc123" "s1"` creates `projections/proj-abc123/s1/`.
2. `gc_write_projection "proj-abc123" "s1" "timeline" '[]' 10 10` creates `timeline.json` with metadata.
3. Verify metadata fields: `_projection` is `"timeline"`, `_project_id` is `"proj-abc123"`, `_session_id` is `"s1"`, `_event_count` is 10, `_last_sequence` is 10.
4. `gc_is_projection_stale "proj-abc123" "s1" "timeline"` returns 1 (current) when event count matches.
5. Add an event file to the session, call `gc_is_projection_stale` -- returns 0 (stale).
6. Projection writes are atomic (verified by concurrent read during write).
7. Deleting all projection files is safe -- `gc_is_projection_stale` returns 0 for all.
