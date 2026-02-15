# Task 07: Summary Projection Handler

**Story**: 04-projection-engine
**Estimated Complexity**: M (3-5 hours)
**Status**: Pending

---

## Description

Implement the summary projection handler. This produces aggregate metrics and a mechanically generated narrative paragraph. It counts events by type, tools by name, and computes session duration and other high-level stats.

---

## Files to Create

| File | Purpose |
|------|---------|
| `/home/meywd/GlobalContext/lib/projections/summary.js` | Summary handler + formatters |

---

## Specification / Implementation Details

### Handler State

```javascript
{
  sessionId: null,
  startedAt: null,
  endedAt: null,
  eventCount: 0,
  eventBreakdown: {},       // event_type -> count
  toolsUsed: {},            // tool_name -> count
  filesTouchedSet: new Set(),
  filesModifiedSet: new Set(),
  agentsSpawnedCount: 0,
  compactionCount: 0,
  userPromptsCount: 0,
  failedToolCalls: 0,
  firstPrompt: null
}
```

### Event Handling

Increment counters based on event type:
- For `ToolCallRequested`, track tool_name in `toolsUsed`, extract file paths for `filesTouchedSet`/`filesModifiedSet` (Write/Edit go to modified set).
- For `SessionStarted`, capture start time.
- For `SessionEnded`, capture end time.

### Narrative Generation

Assemble from the template defined in the story. No LLM calls. Pure string concatenation.

### Duration Formatting

Use the `formatDuration` utility:
- `"0m"` for < 60s
- `"5m"` for 300s
- `"1h 30m"` for 5400s
- `"2h 0m"` for 7200s

### Formatters

- **JSON**: As documented in the schema.
- **Text**: Multi-line report with labeled metrics and the narrative paragraph.
- **Markdown**: Headers, a metrics table, and the narrative.

---

## Dependencies

- Task 01: Base Path Resolution and Shared Utilities (`/home/meywd/GlobalContext/tasks/04-projection-engine/01-base-path-resolution-and-shared-utilities.md`)
- Task 02: Projection Registry (`/home/meywd/GlobalContext/tasks/04-projection-engine/02-projection-registry.md`)
- Task 03: Event Replay Engine (`/home/meywd/GlobalContext/tasks/04-projection-engine/03-event-replay-engine.md`)

---

## Acceptance Tests

- A session with 14 events produces `event_count: 14`.
- `event_breakdown` has correct counts per event type.
- `tools_used` has correct counts per tool name.
- `duration_human` formats correctly for various durations.
- `narrative` is a complete sentence with no template tokens visible.
- A session with only `SessionStarted` produces `event_count: 1`, zero tool calls, and the narrative `"This session contained no events."` equivalent.
- A session with failed tool calls has the failure clause in the narrative.
- A session with agents has the agents clause in the narrative.
- First user prompt hint appears in the narrative.
