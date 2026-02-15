# Task 02: Per-Session session.json Read Model (Fix C-2)

**Story**: 05-context-recovery
**Complexity**: S (Small)
**Status**: Pending

---

## Description

Define the read model that `gc-query` uses when reading per-session `session.json` files. Story 03 writes a base set of fields; Story 05's `gc-query` computes derived fields (`state`, `duration_seconds`, etc.) at read time. No global `sessions.json` exists (Amendment 1).

> **Amendment 2**: This task was originally about merging a global `sessions.json` schema. Now it documents how `gc-query` reads per-session `session.json` files and computes derived fields on the fly.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Create | `src/lib/session_read.sh` | Read helper that loads session.json and computes derived fields |

---

## Specification / Implementation Details

### Per-Session session.json (Written by Story 03)

Each `events/{project-id}/{session-id}/session.json` contains these fields (written by `event_write.sh`):

```json
{
  "session_id": "abc-123",
  "project_id": "my-project-a3f7b2",
  "project_dir": "/home/user/my-project",
  "started_at": "2026-02-14T10:00:00Z",
  "source": "manual",
  "model": "claude-opus-4-6",
  "event_count": 142,
  "last_event_at": "2026-02-14T11:30:00Z",
  "last_event_type": "TurnCompleted",
  "last_prompt": "Fix the auth bug in handler.ts",
  "ended_at": null,
  "previous_session_id": null
}
```

### Derived Fields (Computed at Read Time by gc-query)

`gc-query` computes these additional fields when reading `session.json`:

- **`state`**: Derived from events -- `"ended"` (has `ended_at`), `"compacted"` (has CompactionTriggered), `"orphaned"` (no events for 24h+), `"active"` (otherwise).
- **`duration_seconds`**: Computed from `started_at` and `ended_at` (or `last_event_at` if `ended_at` is null).

**Key decisions:**
- `source` canonical values: `"manual"`, `"compact"`, `"clear"`, `"resume"`.
- Derived fields are never written back to `session.json` -- they are computed each time (CQRS: read side computes).
- Scanning `events/{project-id}/*/session.json` replaces reading a global index.

---

## Dependencies

- [Task 01: Shared Store Path Resolution Helper](/home/meywd/GlobalContext/tasks/05-context-recovery/01-shared-store-path-resolution-helper.md) (paths.sh for path resolution)

---

## Acceptance Tests

1. `gc_read_session_with_derived(project_id, session_id)` returns all base fields plus computed `state` and `duration_seconds`.
2. Session with `ended_at` set: `state` is `"ended"`.
3. Session with no events for 24h+: `state` is `"orphaned"`.
4. Missing `session.json`: returns error gracefully, does not crash.

---

## Estimated Complexity: S
