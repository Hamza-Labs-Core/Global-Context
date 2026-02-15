# Task 06: Event File Writing (Envelope, Sequence, Session Metadata)

**Story**: 03-storage-layer
**Status**: Pending
**Estimated Complexity**: L (Large) -- 4-6 hours

---

## Description

Implement the core event writing pipeline: construct the event envelope, assign a sequence number under flock, validate, write atomically, and update per-session metadata. This is the critical path for the capture-event script.

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/event_write.sh` | Create | Event envelope construction, sequence assignment, truncation, write |
| `tests/lib/test_event_write.sh` | Create | Unit and integration tests |

---

## Specification

Function: `gc_write_event(session_id, event_type, data_json) -> 0 or 1`

Pipeline:

```
1. Sanitize session_id (Task 2)
2. Ensure session directory exists (Task 3)
3. Acquire flock on events/{project-id}/{session-id}/.lock (timeout: 5s)
4. Determine next sequence number:
   a. List [0-9]*.json files in session dir (exclude session.json), extract highest number
   b. If no files: next = 1
   c. Else: next = highest + 1
5. Generate event_id (UUID v4)
6. Generate timestamp (ISO 8601 UTC)
7. Construct envelope JSON:
   {
     "event_id": "<uuid>",
     "event_type": "<type>",
     "project_id": "<derived from cwd>",
     "session_id": "<sanitized_id>",
     "sequence": <next>,
     "timestamp": "<iso8601>",
     "data": <data_json>
   }
8. Validate envelope (Task 5)
9. Write atomically to events/{project-id}/{session-id}/{zero-padded-sequence}.json (Task 4)
10. Update session.json (Task 8) within same flock scope
11. Release flock (automatic on fd close)
12. If validation fails: write to events/{project-id}/{session-id}/_rejected/ with error
```

Sequence number formatting:

- 6-digit zero-padded: `printf "%06d" $sequence`
- Range: 000001 to 999999
- If sequence reaches 999999: log error to stderr, skip write, return 1

Note: No write-side truncation -- the capture script stores events as-is without size checks (CQRS principle: write side is fast and dumb). If size management is needed, it belongs on the read side.

Fallback on flock timeout:

- Write event with a UUID-based filename: `orphan-{uuid}.json`
- Log warning to stderr.
- The event is preserved but out of sequence -- reconcilable by projection engine.

---

## Dependencies

- **Task 01**: `/home/meywd/GlobalContext/tasks/03-storage-layer/01-shared-path-resolver.md` (paths.sh)
- **Task 02**: `/home/meywd/GlobalContext/tasks/03-storage-layer/02-session-id-sanitization.md` (sanitize.sh)
- **Task 03**: `/home/meywd/GlobalContext/tasks/03-storage-layer/03-session-directory-and-lock-files.md` (session_dir.sh)
- **Task 04**: `/home/meywd/GlobalContext/tasks/03-storage-layer/04-atomic-write-helper.md` (atomic_write.sh)
- **Task 05**: `/home/meywd/GlobalContext/tasks/03-storage-layer/05-json-validation-helper.md` (json_validate.sh)
- **Task 08**: `/home/meywd/GlobalContext/tasks/03-storage-layer/08-per-session-metadata.md` (session_meta.sh)

---

## Acceptance Tests

1. Write 10 events to a new session -- files 000001.json through 000010.json exist, each with correct 7-field envelope.
2. Verify `sequence` field inside file matches filename.
3. Write an event with invalid JSON data -- file appears in `_rejected/` directory.
4. Concurrent writes (10 parallel) to the same session -- all get unique sequence numbers, no gaps.
5. Verify flock timeout fallback: simulate a locked session, write an event -- orphan file is created.
6. Verify event_id is a valid UUID v4 in each file.
7. Verify timestamp is ISO 8601 UTC.
8. Verify compact JSON (single line, no pretty-printing).
9. Verify `session.json` exists after first event and `event_count` matches after 10 events.
