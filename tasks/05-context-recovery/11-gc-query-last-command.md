# Task 11: gc-query last Command

**Story**: 05-context-recovery
**Complexity**: M (Medium)
**Status**: Pending

---

## Description

Implement the primary "get last context" command. Resolves the latest session, loads or rebuilds its context projection, and outputs it in the requested format.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_last` function) |

---

## Specification / Implementation Details

1. Resolve latest session using `resolve_latest_session()`.
2. Load context using `load_context(session_id)`.
3. If `--include-parent` is set, follow the `previous_session_id` chain (Task 13).
4. Format output using the appropriate formatter (default: markdown).
5. Write to stdout.

---

## Dependencies

- [Task 05: Session Resolution Helpers](/home/meywd/GlobalContext/tasks/05-context-recovery/05-session-resolution-helpers.md) (session resolution)
- [Task 09: Context Projection Builder Integration](/home/meywd/GlobalContext/tasks/05-context-recovery/09-context-projection-builder-integration.md) (context loader)
- [Task 10: Output Formatters](/home/meywd/GlobalContext/tasks/05-context-recovery/10-output-formatters.md) (output formatters)

---

## Acceptance Tests

1. `gc-query last` returns markdown for the most recent session.
2. `gc-query last --format json` returns valid JSON.
3. Exit code 3 with "No sessions found" when no sessions exist.
4. Uses cached projection when current; rebuilds only when stale.
5. Completes in under 500ms (cached) or under 2 seconds (rebuild of 500 events).
6. `gc-query last --include-parent` includes parent session context.

---

## Estimated Complexity: M
