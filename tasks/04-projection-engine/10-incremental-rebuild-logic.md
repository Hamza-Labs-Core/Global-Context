# Task 10: Incremental Rebuild Logic

**Story**: 04-projection-engine
**Estimated Complexity**: L (6-10 hours)
**Status**: Pending

---

## Description

Add incremental rebuild support to the replay engine and all projection handlers. When a projection file already exists and `--rebuild` is not set, the engine reads the existing projection, extracts `_last_sequence`, and only replays events after that sequence. Each projection handler implements a merge strategy that integrates new events into the existing projection state.

Also implement the version check: if the existing projection's `_projection_version` does not match the current handler's version (defined in the registry per M-1), automatically trigger a full rebuild.

---

## Files to Modify

| File | Modification |
|------|-------------|
| `/home/meywd/GlobalContext/lib/replay-engine.js` | Add `loadExistingProjection`, `shouldRebuild`, sequence range detection |
| `/home/meywd/GlobalContext/lib/projections/timeline.js` | Add merge: append new entries |
| `/home/meywd/GlobalContext/lib/projections/files-touched.js` | Add merge: upsert file entries, recompute stats |
| `/home/meywd/GlobalContext/lib/projections/decisions.js` | Add merge: extend last open group or append new groups |
| `/home/meywd/GlobalContext/lib/projections/context.js` | Add merge: append prompts/tool calls/files, rebuild last_state |
| `/home/meywd/GlobalContext/lib/projections/summary.js` | Add merge: recount all metrics, regenerate narrative |

---

## Specification / Implementation Details

### Replay Engine Changes

```javascript
// In replay-engine.js
async function buildProjection(sessionId, projectionDef, options = {}) {
  const { from, to, rebuild = false } = options;

  let existingProjection = null;
  let startFrom = from || 1;

  if (!rebuild) {
    existingProjection = await loadExistingProjection(sessionId, projectionDef);

    if (existingProjection) {
      // Version check (M-1): mismatch triggers full rebuild
      if (existingProjection._projection_version !== projectionDef.version) {
        warn(`Projection version mismatch (file: ${existingProjection._projection_version}, ` +
             `current: ${projectionDef.version}). Triggering full rebuild.`);
        existingProjection = null;
      } else {
        startFrom = Math.max(startFrom, (existingProjection._last_sequence || 0) + 1);
      }
    }
  }

  // Check if there are new events to process
  const highestSequence = await getHighestSequence(sessionId);
  if (existingProjection && startFrom > highestSequence) {
    // No new events -- return existing projection as-is
    return existingProjection;
  }

  // Build or merge
  if (existingProjection) {
    // Incremental: initialize handler from existing state
    return await replayThrough(sessionId, projectionDef.handler, {
      from: startFrom,
      to,
      existingState: existingProjection
    });
  } else {
    // Full rebuild
    return await replayThrough(sessionId, projectionDef.handler, { from: from || 1, to });
  }
}
```

### Handler Init Changes

Each handler's `init` function gains an optional `existingProjection` parameter:

```javascript
init: (existing) => {
  if (existing) {
    // Reconstitute handler state from existing projection data
    return { entries: existing.entries, sessionId: existing._session_id };
  }
  return { entries: [], sessionId: null };
}
```

### Merge Strategies Per Projection

| Projection | Strategy |
|------------|----------|
| Timeline | Append new entries to `entries` array |
| Files Touched | Upsert into `filesMap`, recompute stats |
| Decisions | Extend last open group if applicable, else append new groups |
| Context | Append to all arrays, fully rebuild `last_state` from tail |
| Summary | Recount all metrics, regenerate narrative |

### Review Issues Addressed

- **M-1**: Version check. The incremental rebuild logic compares the stored `_projection_version` against the registry's `version` and triggers a full rebuild on mismatch.

---

## Dependencies

- Task 03: Event Replay Engine (`/home/meywd/GlobalContext/tasks/04-projection-engine/03-event-replay-engine.md`)
- Task 04: Files Touched Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/04-files-touched-projection-handler.md`)
- Task 05: Timeline Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/05-timeline-projection-handler.md`)
- Task 06: Decisions Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/06-decisions-projection-handler.md`)
- Task 07: Summary Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/07-summary-projection-handler.md`)
- Task 08: Context Snapshot Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/08-context-snapshot-projection-handler.md`)

---

## Acceptance Tests

- Running a projection twice with no new events returns identical output (no unnecessary file write).
- Adding 10 new events and re-projecting only processes those 10 events.
- `_last_sequence` in the output matches the highest event processed.
- `_rebuilt_at` is updated on every successful run.
- `--rebuild` flag causes full reprocessing.
- Projection version mismatch triggers automatic full rebuild with a warning.
- Incremental rebuild produces identical results to a full rebuild for the same event range.
