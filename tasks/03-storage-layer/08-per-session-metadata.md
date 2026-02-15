# Task 08: Per-Session Metadata (session.json) -- Schema and Update Logic

**Story**: 03-storage-layer
**Status**: Pending
**Estimated Complexity**: S (Small) -- 1-2 hours

---

## Description

Define the per-session `session.json` schema and implement the update logic. Each session directory contains its own `session.json` file, updated within the existing per-session flock scope. No global shared state. No additional lock files.

This replaces the original global `sessions.json` design (see Design Amendment 1 and 2).

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/session_meta.sh` | Create | session.json creation and update functions |
| `tests/lib/test_session_meta.sh` | Create | Correctness tests |

---

## Specification

### session.json Schema

Each `events/{project-id}/{session-id}/session.json` contains:

```json
{
  "session_id": "abc-123",
  "project_id": "my-project-a3f7b2",
  "project_dir": "/home/user/my-project",
  "started_at": "2026-02-14T10:30:00Z",
  "source": "manual",
  "model": "claude-opus-4-6",
  "event_count": 247,
  "last_event_at": "2026-02-14T11:45:00Z",
  "last_event_type": "TurnCompleted",
  "last_prompt": "Fix the auth bug in handler.ts",
  "ended_at": null,
  "previous_session_id": null
}
```

### Update Functions

All functions operate on the session's own `session.json` file. They are called **within the existing per-session flock** in `event_write.sh` (Task 6), so no additional locking is needed.

`gc_session_meta_create(session_dir, session_id, project_id, project_dir, source, model, started_at)`:

- Creates `session.json` in the session directory with initial values.
- Sets `event_count` to 1, `last_event_at` to `started_at`, `last_event_type` to `"SessionStarted"`.
- Called when the first event (SessionStarted) for a session is written.

`gc_session_meta_update(session_dir, event_type, timestamp)`:

- Increments `event_count`, updates `last_event_at` and `last_event_type`.
- If `event_type` is `UserPromptReceived`: updates `last_prompt` (extracted from event data by caller).
- If `event_type` is `SessionEnded`: sets `ended_at`.
- Uses `gc_atomic_write` (Task 4) with `fsync=false` (performance).

`gc_session_meta_read(session_dir) -> json`:

- Reads and returns `session.json` content. No lock needed for reads.

### Integration with Event Write (Task 6)

Inside the existing flock scope in `gc_write_event`:

```bash
(
  flock -w 5 200
  # ... assign sequence number, write event file (existing logic) ...

  # Update session.json (within same flock, no extra lock)
  if [ "$next_seq" -eq 1 ]; then
    gc_session_meta_create "$session_dir" "$session_id" "$project_id" ...
  else
    gc_session_meta_update "$session_dir" "$event_type" "$timestamp"
  fi
) 200>"$lock_file"
```

---

## Dependencies

- **Task 01**: `/home/meywd/GlobalContext/tasks/03-storage-layer/01-shared-path-resolver.md` (paths.sh)
- **Task 04**: `/home/meywd/GlobalContext/tasks/03-storage-layer/04-atomic-write-helper.md` (atomic_write.sh)

---

## Acceptance Tests

1. First event creates `session.json` with all fields populated from SessionStarted data.
2. 10th event: `event_count` is 10, `last_event_at` is the 10th event's timestamp.
3. `UserPromptReceived` event updates `last_prompt` field.
4. `SessionEnded` event sets `ended_at` field.
5. `session.json` is always valid JSON after any update.
6. No global lock files exist (no `.sessions.lock`).
7. Two different sessions updating their own `session.json` concurrently: no interference.
8. `session.json` is written atomically (no partial reads).
