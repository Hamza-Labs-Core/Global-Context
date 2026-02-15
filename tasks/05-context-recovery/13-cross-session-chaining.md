# Task 13: Cross-Session Chaining (--include-parent)

**Story**: 05-context-recovery
**Complexity**: M (Medium)
**Status**: Pending

---

## Description

Implement the session chain resolution logic that follows `previous_session_id` links to include parent session context. Applies progressive summarization as chain depth increases.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Create | `~/.claude-context/lib/session-chain.sh` |

---

## Specification / Implementation Details

1. Starting from the current session's context, read `previous_session_id`.
2. If non-null, load the parent session's context.
3. Continue following the chain up to a maximum depth of 10.
4. Apply progressive summarization: each level deeper gets more summarized.
   - Current session: full detail
   - Parent (depth 1): compact summary (What Was Being Worked On + Files Modified + Where We Left Off)
   - Grandparent (depth 2+): one-liner summary only
5. Detect circular chains (track visited session IDs) and break with an error message.
6. If chain exceeds depth 10, note: "N additional ancestor sessions exist but are omitted."

Output structure for markdown:
```
## Session Context Recovery (Session Chain)

### Current Session: <current-id>
[full context]

---

### Parent Session: <parent-id>
[compact summary]

---

### Grandparent Session: <grandparent-id>
[one-liner]
```

---

## Dependencies

- [Task 09: Context Projection Builder Integration](/home/meywd/GlobalContext/tasks/05-context-recovery/09-context-projection-builder-integration.md) (context loader, for loading each session in the chain)
- [Task 10: Output Formatters](/home/meywd/GlobalContext/tasks/05-context-recovery/10-output-formatters.md) (formatters, for progressive summarization)

---

## Acceptance Tests

1. A chain of 3 sessions: current gets full detail, parent gets compact, grandparent gets one-liner.
2. Chain of 11 sessions: stops at depth 10, notes omitted sessions.
3. Circular chain (A -> B -> A): detected and broken with error message.
4. Session with no parent: returns only current session context.
5. Parent session with missing events: degraded gracefully with a note.

---

## Estimated Complexity: M
