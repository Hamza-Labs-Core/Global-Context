# Task 08: gc-query tail Command

**Story**: 05-context-recovery
**Complexity**: S (Small)
**Status**: Pending

---

## Description

Show the last N events from a session. Thin wrapper around the events command.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_tail` function) |

---

## Specification / Implementation Details

1. Derive project_id from cwd, resolve session ID.
2. Determine total event count (count `[0-9]*.json` files in `$GC_EVENTS_DIR/$project_id/$session_id/`).
3. Compute `--from` as `max(1, total - N + 1)`.
4. Delegate to the events rendering logic.
5. Default N is 20.

---

## Dependencies

- [Task 07: gc-query events Command](/home/meywd/GlobalContext/tasks/05-context-recovery/07-gc-query-events-command.md) (events command, for rendering logic reuse)

---

## Acceptance Tests

1. `gc-query tail <session-id>` shows last 20 events.
2. `gc-query tail <session-id> 5` shows last 5 events.
3. If session has fewer than N events, shows all events.
4. Exit code 3 if session does not exist.

---

## Estimated Complexity: S
