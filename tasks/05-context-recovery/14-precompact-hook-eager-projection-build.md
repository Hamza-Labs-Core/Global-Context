# Task 14: PreCompact Hook -- Eager Projection Build (Fix C-4)

**Story**: 05-context-recovery
**Complexity**: M (Medium)
**Status**: Pending

---

## Description

Modify the PreCompact hook handler to eagerly build the context.json projection for the current session BEFORE compaction occurs. This ensures the projection is ready when the post-compaction SessionStart fires, eliminating the need to build it within the tight 5-second SessionStart hook timeout.

This is the first half of the compaction-to-recovery flow (C-4):
```
PreCompact fires -> build context.json projection (this task)
                 -> compaction occurs
SessionStart fires -> read pre-built projection (Task 15)
                   -> return additionalContext
```

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-hook` (or the capture-event handler for PreCompact) |

---

## Specification / Implementation Details

1. When the PreCompact hook fires, after storing the CompactionTriggered event (normal capture):
2. Call `project context <current-session-id>` synchronously to build the context.json projection.
3. This must complete before the hook returns, since PreCompact is synchronous (the story spec says "The PreCompact handler must be synchronous to guarantee the snapshot is written before compaction occurs").
4. If the projection build fails, log the error but do not fail the hook.
5. The projection is now cached at `projections/{project-id}/{session-id}/context.json` and ready for the SessionStart hook.

---

## Dependencies

- [Task 09: Context Projection Builder Integration](/home/meywd/GlobalContext/tasks/05-context-recovery/09-context-projection-builder-integration.md) (context loader / build logic)
- Story 02 (gc-hook wrapper exists)
- Story 04 (project CLI exists)

---

## Acceptance Tests

1. After a PreCompact hook fires, `projections/{project-id}/{session-id}/context.json` exists and is complete.
2. The projection's `_last_sequence` matches the CompactionTriggered event's sequence number.
3. If the projection build fails, the hook still returns successfully (exit 0).
4. The entire PreCompact hook (capture + projection build) completes within 5 seconds for a session with 500 events.

---

## Estimated Complexity: M
