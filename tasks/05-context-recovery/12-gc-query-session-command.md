# Task 12: gc-query session Command

**Story**: 05-context-recovery
**Complexity**: S (Small)
**Status**: Pending

---

## Description

Retrieve context from a specific session by ID. Supports partial session ID matching.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_session` function) |

---

## Specification / Implementation Details

1. Resolve session ID using `resolve_session_id(partial_id)`.
2. Load or rebuild the context projection.
3. Format and output.

---

## Dependencies

- [Task 05: Session Resolution Helpers](/home/meywd/GlobalContext/tasks/05-context-recovery/05-session-resolution-helpers.md) (session resolution with prefix matching)
- [Task 09: Context Projection Builder Integration](/home/meywd/GlobalContext/tasks/05-context-recovery/09-context-projection-builder-integration.md) (context loader)
- [Task 10: Output Formatters](/home/meywd/GlobalContext/tasks/05-context-recovery/10-output-formatters.md) (output formatters)

---

## Acceptance Tests

1. `gc-query session <full-id>` returns context for that session.
2. `gc-query session <prefix>` resolves unique prefix and returns context.
3. Ambiguous prefix lists matches and exits with code 2.
4. Nonexistent session exits with code 3.
5. `--include-parent` follows the session chain.

---

## Estimated Complexity: S
