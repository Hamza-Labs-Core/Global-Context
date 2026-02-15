# Task 16: gc-query sessions Command

**Story**: 05-context-recovery
**Complexity**: M (Medium)
**Status**: Pending

---

## Description

List all sessions with metadata. Scans per-session `session.json` files across the project (or all projects with `--all-projects`).

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_sessions` function) |

---

## Specification / Implementation Details

1. Derive project_id from cwd. Scan `$GC_EVENTS_DIR/$project_id/*/session.json` to collect session metadata.
2. If a session directory has no `session.json`, fall back to reading its `SessionStarted` event (first `[0-9]*.json` file).
3. With `--all-projects`, scan `$GC_EVENTS_DIR/*/*/session.json` across all projects.
4. Compute derived fields not present in session.json:
   - `state`: Derive from events (has SessionEnded? -> "ended". Has CompactionTriggered? -> "compacted". Active with no events for 24h+ -> "orphaned". Otherwise -> "active").
   - `duration_seconds`: Compute from `started_at` and `ended_at` or `last_event_at`.
5. Apply filters: `--project`, `--state`, `--since`, `--limit`.
6. Sort by `started_at` descending.
7. Output in text format (default), or JSON/compact as requested.

For text mode, each row shows: session ID (truncated to 8 chars), start timestamp, project path, event count, state.

---

## Dependencies

- [Task 02: Per-Session session.json Read Model](/home/meywd/GlobalContext/tasks/05-context-recovery/02-per-session-session-json-read-model.md) (session read model with derived fields)
- [Task 03: gc-query Entry Point and Argument Parser](/home/meywd/GlobalContext/tasks/05-context-recovery/03-gc-query-entry-point-and-argument-parser.md) (gc-query entry point)

---

## Acceptance Tests

1. `gc-query sessions` lists sessions for the current project, sorted by start time descending.
2. `gc-query sessions --all-projects` lists sessions across all projects.
3. `gc-query sessions --state compacted` filters by state.
4. `gc-query sessions --since 1w` returns only sessions from the last 7 days.
5. `gc-query sessions --limit 5` returns at most 5 sessions.
6. Exit code 0 with "No sessions found" when store is empty.
7. JSON output includes full session IDs and all metadata fields.
8. Completes in under 1 second with 100 sessions.

---

## Estimated Complexity: M
