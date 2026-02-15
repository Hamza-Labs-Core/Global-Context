# Task 09: Context Projection Builder Integration

**Story**: 05-context-recovery
**Complexity**: M (Medium)
**Status**: Pending

---

## Description

Implement the function that loads or rebuilds a session's `context.json` projection. This is the core logic that powers `gc-query last` and `gc-query session`. It calls the `project` CLI from Story 04 to build/rebuild projections and reads the output.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Create | `~/.claude-context/lib/context-loader.sh` |

---

## Specification / Implementation Details

1. **load_context(project_id, session_id)**: Check if the context projection is current using `is_projection_current`. If current, read and return the cached projection. If stale or missing, call `project context <project-id> <session-id>` to rebuild, then read and return the result.

2. **build_context_if_needed(project_id, session_id)**: Same as load_context but only builds -- does not output. Used by the PreCompact hook (Task 14) to eagerly build the projection.

3. Handle errors gracefully: if the projection engine fails, output a degraded context by reading raw events directly and assembling a minimal context.

---

## Dependencies

- [Task 04: Projection Staleness Check](/home/meywd/GlobalContext/tasks/05-context-recovery/04-projection-staleness-check.md) (staleness check)
- Story 04 (the `project` CLI must exist and produce `context.json`)

---

## Acceptance Tests

1. When projection is current, `load_context` reads from cache without calling `project`.
2. When projection is stale, `load_context` calls `project context <session-id>` and reads the result.
3. When projection is missing, `load_context` triggers a full build.
4. When `project` fails, `load_context` returns a degraded context with an error note instead of crashing.
5. Rebuild completes in under 2 seconds for a session with 500 events.

---

## Estimated Complexity: M
