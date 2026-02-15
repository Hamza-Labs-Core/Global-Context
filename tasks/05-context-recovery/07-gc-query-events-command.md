# Task 07: gc-query events Command

**Story**: 05-context-recovery
**Complexity**: S (Small)
**Status**: Pending

---

## Description

Implement raw event access. Read event files from a session directory and output them as JSONL (default) or JSON array. Support sequence range filtering and event type filtering.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_events` function) |

---

## Specification / Implementation Details

1. Derive project_id from cwd, then resolve the session ID (using `resolve_session_id`).
2. List all `[0-9]*.json` files in the session's events directory (`$GC_EVENTS_DIR/$project_id/$session_id/`), sorted numerically.
3. Apply `--from` and `--to` filters on sequence numbers.
4. Apply `--type` filter by reading each event's `event_type` field.
5. Output in the requested format (jsonl: one event per line; json: JSON array).

---

## Dependencies

- [Task 03: gc-query Entry Point and Argument Parser](/home/meywd/GlobalContext/tasks/05-context-recovery/03-gc-query-entry-point-and-argument-parser.md) (gc-query entry point)
- [Task 05: Session Resolution Helpers](/home/meywd/GlobalContext/tasks/05-context-recovery/05-session-resolution-helpers.md) (session resolution)

---

## Acceptance Tests

1. `gc-query events <session-id>` outputs all events as JSONL.
2. `gc-query events <session-id> --from 10 --to 20` outputs only events 10-20.
3. `gc-query events <session-id> --type ToolCallCompleted` filters by type.
4. Events are in strict sequence order.
5. Exit code 3 if session does not exist.
6. Empty result (not error) if range contains no events.

---

## Estimated Complexity: S
