# Task 06: Decisions Projection Handler

**Story**: 04-projection-engine
**Estimated Complexity**: L (6-10 hours)
**Status**: Pending

---

## Description

Implement the decisions projection handler. This groups events into decision groups starting at each `UserPromptReceived` and ending at the next `UserPromptReceived`, `TurnCompleted`, or `SessionEnded`. Within each group, tool call requests are paired with their completions using `tool_use_id` (with dedup awareness from G-1, already handled in the replay engine).

---

## Files to Create

| File | Purpose |
|------|---------|
| `/home/meywd/GlobalContext/lib/projections/decisions.js` | Decisions handler + formatters |

---

## Specification / Implementation Details

### Handler State

```javascript
{
  groups: [],
  currentGroup: null,      // The open decision group being built
  pendingToolCalls: {},    // tool_use_id -> { tool_name, input_summary, request_sequence, timestamp }
  groupIdCounter: 0,
  stats: { total_groups: 0, total_actions: 0, failed_actions: 0 }
}
```

### Event Handling Logic

1. **`UserPromptReceived`**:
   - If `currentGroup` is open, close it (finalize pending tool calls, compute `all_succeeded`, push to `groups`).
   - Start a new group with `group_id`, `user_prompt`, empty `actions` and `agents_spawned`.

2. **`ToolCallRequested`**:
   - If no `currentGroup`, skip (events before first prompt are excluded).
   - Store in `pendingToolCalls` keyed by `tool_use_id` (or by sequence if no `tool_use_id`).
   - Add a preliminary action entry to `currentGroup.actions`.

3. **`ToolCallCompleted`**:
   - Look up matching pending tool call by `tool_use_id`.
   - Update the action entry with `output_summary`, `success: true`, `completion_sequence`.
   - Remove from `pendingToolCalls`.

4. **`ToolCallFailed`**:
   - Look up matching pending tool call by `tool_use_id`.
   - Update the action entry with error info, `success: false`, `completion_sequence`.
   - Increment `stats.failed_actions`.
   - Remove from `pendingToolCalls`.

5. **`TurnCompleted` / `SessionEnded`**:
   - Close `currentGroup` (mark any remaining pending tool calls with `success: null`).
   - Set `currentGroup = null`.

6. **`AgentSpawned` / `AgentCompleted`**:
   - If `currentGroup`, add to `agents_spawned` array.

### Tool-Call Pairing by `tool_use_id`

The `tool_use_id` field in the event data is the canonical key for matching requests to completions. If `tool_use_id` is not present (older events or edge cases), fall back to matching by `tool_name` + sequence proximity (the next completion for the same tool name).

### Formatters

- **JSON**: As documented in the schema.
- **Text**: Group headers with prompt text, numbered action list with status `[OK]`/`[FAIL]`/`[?]`.
- **Markdown**: H3 headers per group, blockquoted prompts, numbered action lists.

---

## Dependencies

- Task 01: Base Path Resolution and Shared Utilities (`/home/meywd/GlobalContext/tasks/04-projection-engine/01-base-path-resolution-and-shared-utilities.md`)
- Task 02: Projection Registry (`/home/meywd/GlobalContext/tasks/04-projection-engine/02-projection-registry.md`)
- Task 03: Event Replay Engine (`/home/meywd/GlobalContext/tasks/04-projection-engine/03-event-replay-engine.md`)
- Task 05: Timeline Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/05-timeline-projection-handler.md`) -- for `summary-generators.js`

---

## Acceptance Tests

- A session with 2 user prompts and tool calls between them produces 2 decision groups.
- Events before the first `UserPromptReceived` (e.g., `SessionStarted`) do not create a group.
- `TurnCompleted` closes the current group.
- A `ToolCallRequested` without a matching `ToolCallCompleted` has `success: null` and `output_summary: "(no completion recorded)"`.
- `all_succeeded` is `true` only when every action has `success: true`.
- `action_count` matches the `actions` array length.
- `stats` aggregates are correct.
- The full user prompt is stored, not truncated, in `user_prompt.prompt`.
- `prompt_length` matches the character count.
- Agent events within a group are recorded in `agents_spawned`.
- Tool-call pairing uses `tool_use_id` as the primary key.
