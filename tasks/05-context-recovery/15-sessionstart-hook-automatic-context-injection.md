# Task 15: SessionStart Hook -- Automatic Context Injection (Fix C-4)

**Story**: 05-context-recovery
**Complexity**: L (Large)
**Status**: Pending

---

## Description

Modify the SessionStart hook handler to detect compaction/clear events and inject context from the previous session as `additionalContext`. This reads the pre-built projection from Task 14.

This is the second half of the compaction-to-recovery flow (C-4):
```
PreCompact fires -> build context.json projection (Task 14)
                 -> compaction occurs
SessionStart fires -> detect source="compact" (this task)
                   -> read pre-built context.json
                   -> format as markdown
                   -> return {"additionalContext": "..."}
```

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-hook` (SessionStart handler) |

---

## Specification / Implementation Details

1. After capturing the SessionStarted event (normal capture), check the `source` field in the hook payload (mapped from the hook's `session_start_type`).
2. **Source "compact"**: Read the previous session's pre-built `context.json` projection. Format as a compact markdown summary. Return `{"additionalContext": "## Context Recovery (Auto)\n\n..."}`.
3. **Source "clear"**: Same as compact but with different heading: "## Context Recovery (Cleared)". Include a note: "Previous conversation was cleared by user." Focus on accomplishments, not in-progress work.
4. **Source "resume"**: Skip for initial implementation (optional per story spec). Return `{}`.
5. **Source "manual"**: Return `{}` (no automatic injection).
6. The `additionalContext` value must be a single string, under 50KB.
7. The previous session ID comes from the hook payload or by reading the `latest` symlink (which still points to the old session at this point).
8. If reading the projection fails, return `{"additionalContext": "## Context Recovery\n\nNote: Unable to load previous session context. Use \`gc-query last\` to retrieve it manually."}` rather than failing the hook.

---

## Dependencies

- [Task 14: PreCompact Hook -- Eager Projection Build](/home/meywd/GlobalContext/tasks/05-context-recovery/14-precompact-hook-eager-projection-build.md) (PreCompact builds the projection that this task reads)
- [Task 10: Output Formatters](/home/meywd/GlobalContext/tasks/05-context-recovery/10-output-formatters.md) (markdown formatter, compact variant for additionalContext)
- [Task 01: Shared Store Path Resolution Helper](/home/meywd/GlobalContext/tasks/05-context-recovery/01-shared-store-path-resolution-helper.md) (store path helper)

---

## Acceptance Tests

1. SessionStart with source "compact" returns `additionalContext` containing previous session summary.
2. SessionStart with source "clear" returns `additionalContext` with "Cleared" label.
3. SessionStart with source "manual" returns `{}` (no additionalContext).
4. `additionalContext` is valid markdown, under 50KB.
5. Hook response completes within 5 seconds.
6. If projection is missing or corrupt, hook returns successfully with an error note.
7. After the hook returns, the LLM has enough context to continue without asking "what were we doing?"

---

## Estimated Complexity: L
