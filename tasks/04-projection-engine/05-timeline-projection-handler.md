# Task 05: Timeline Projection Handler

**Story**: 04-projection-engine
**Estimated Complexity**: M (3-5 hours)
**Status**: Pending

---

## Description

Implement the timeline projection handler. This is the simplest projection -- one entry per event, in sequence order, with a generated summary string. The summary follows the per-tool templates defined in the story.

This task also creates the shared summary generators module since Decisions and Context projections reuse the same logic.

---

## Files to Create

| File | Purpose |
|------|---------|
| `/home/meywd/GlobalContext/lib/projections/timeline.js` | Timeline handler + formatters |
| `/home/meywd/GlobalContext/lib/summary-generators.js` | Shared summary generation for tool inputs/outputs (used by timeline, decisions, and context projections) |

---

## Specification / Implementation Details

### Handler State

```javascript
{
  entries: [],
  sessionId: null
}
```

### Timeline Entry Structure

For each event, create a timeline entry:
```javascript
{
  sequence: event.sequence,
  timestamp: event.timestamp,
  event_type: event.event_type,
  summary: generateSummary(event)
}
```

### Summary Generation

Summary generation function dispatches on `event.event_type`:

- `SessionStarted`: `"Session started (model: ${data.model || data.session?.model}, cwd: ${data.cwd || data.session?.cwd})"`
- `UserPromptReceived`: `"User: ${truncate(data.prompt || data.message, 200)}"`
- `ToolCallRequested`: Use per-tool input summary table from the story
- `ToolCallCompleted`: Use per-tool output summary table from the story
- `ToolCallFailed`: `"FAILED ${data.tool_name}: ${truncate(data.error, 150)}"`
- `AgentSpawned`: `"Spawned ${data.agent_type} agent: ${truncate(data.description, 100)}"`
- `AgentCompleted`: `"Agent completed: ${data.agent_type} (status: ${data.status})"`
- `TurnCompleted`: `"Turn completed"`
- `CompactionTriggered`: `"COMPACTION triggered at sequence ${event.sequence}"`
- `SessionEnded`: `"Session ended"`
- Unknown: `"${event.event_type} at sequence ${event.sequence}"`

### Shared Summary Generators (lib/summary-generators.js)

Create shared summary generators in a utility module since Decisions and Context projections reuse the same logic. This module should export functions for:
- Generating input summaries per tool type
- Generating output summaries per tool type
- Generating event-level summaries

### Formatters

- **JSON**: As documented in the schema.
- **Text**: `[{seq}] {timestamp} {event_type}: {summary}` one per line.
- **Markdown**: Table with columns #, Timestamp, Type, Summary.

---

## Dependencies

- Task 01: Base Path Resolution and Shared Utilities (`/home/meywd/GlobalContext/tasks/04-projection-engine/01-base-path-resolution-and-shared-utilities.md`)
- Task 02: Projection Registry (`/home/meywd/GlobalContext/tasks/04-projection-engine/02-projection-registry.md`)
- Task 03: Event Replay Engine (`/home/meywd/GlobalContext/tasks/04-projection-engine/03-event-replay-engine.md`)

---

## Acceptance Tests

- A 14-event test session produces 14 timeline entries.
- Entries are in sequence order.
- A `UserPromptReceived` with a 300-character prompt is truncated to 200 characters with `...`.
- A `ToolCallRequested` for Read includes `file_path=...` in the summary.
- A `ToolCallRequested` for Bash includes the first 100 characters of the command.
- An unknown event type produces `"{event_type} at sequence {n}"`.
- Text format produces exactly one line per entry.
- Markdown format produces a valid markdown table.
- JSON output matches the documented schema.
