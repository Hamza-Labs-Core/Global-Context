# Task 13: gc-query store-size Command

**Story**: 03-storage-layer
**Status**: Pending
**Estimated Complexity**: S (Small) -- 2-3 hours

---

## Description

Implement the `gc-query store-size` subcommand that reports total event count, total size in bytes, oldest session, and newest session.

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/bin/gc-query` | Create (stub) | Query command with `store-size` subcommand |
| `tests/bin/test_gc_query_store_size.sh` | Create | Store size reporting tests |

---

## Specification

Invocation: `gc-query store-size [--format json|text]`

Output (text mode):

```
GlobalContext Store: /home/user/.claude-context
Sessions:      15
Total events:  3,247
Total size:    12.4 MB
Oldest:        2026-01-15 (session abc-123)
Newest:        2026-02-14 (session xyz-789)
```

Output (JSON mode):

```json
{
  "store_path": "/home/user/.claude-context",
  "session_count": 15,
  "total_events": 3247,
  "total_size_bytes": 13002752,
  "oldest_session": {"session_id": "abc-123", "started_at": "2026-01-15T08:00:00Z"},
  "newest_session": {"session_id": "xyz-789", "started_at": "2026-02-14T10:00:00Z"}
}
```

Implementation:

1. Scan project directories in `$GC_EVENTS_DIR/` (the project-id layer).
2. For each project, count session directories.
3. Count all `[0-9]*.json` files across all session directories (excludes session.json, lock files, rejected, tmp).
4. Sum file sizes using `du` or `stat`.
5. Read per-session `session.json` files to find oldest/newest `started_at` timestamps.

---

## Dependencies

- **Task 01**: `/home/meywd/GlobalContext/tasks/03-storage-layer/01-shared-path-resolver.md` (paths.sh)
- **Task 08**: `/home/meywd/GlobalContext/tasks/03-storage-layer/08-per-session-metadata.md` (session_meta.sh, for reading per-session session.json)
- **Task 09**: `/home/meywd/GlobalContext/tasks/03-storage-layer/09-config-file.md` (config.sh)

---

## Acceptance Tests

1. Empty store -- reports 0 sessions, 0 events, 0 bytes.
2. Store with 3 sessions and 50 events -- correct counts and size.
3. `--format json` produces valid JSON.
4. `--format text` (default) produces human-readable output.
5. Oldest and newest session IDs are correct.
