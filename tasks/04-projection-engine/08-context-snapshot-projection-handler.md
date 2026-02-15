# Task 08: Context Snapshot Projection Handler

**Story**: 04-projection-engine
**Estimated Complexity**: L (6-10 hours)
**Status**: Pending

---

## Description

Implement the context snapshot projection -- the most complex and most critical projection. This builds the full resumable state: session metadata, all user prompts, summarized tool calls, files modified, agents, last state, and compaction markers. It includes size-aware progressive summarization when the output exceeds 100KB.

---

## Files to Create

| File | Purpose |
|------|---------|
| `/home/meywd/GlobalContext/lib/projections/context.js` | Context snapshot handler + formatters |

---

## Specification / Implementation Details

### Handler State

```javascript
{
  session: { id: null, started_at: null, ended_at: null, model: null, project_directory: null, duration_seconds: null, event_count: 0 },
  prompts: [],
  keyToolCalls: [],
  filesModified: {},        // path -> { operations: Set, last_operation }
  agents: [],               // { agent_type, spawn_sequence, status, outcome_summary }
  pendingAgents: {},         // correlation by type or id
  lastState: { last_user_prompt: null, last_tool_call: null, last_tool_result: null, working_on: null },
  compactionMarkers: [],
  pendingToolCalls: {}       // tool_use_id -> request data, for pairing
}
```

### Event Handling

- **`SessionStarted`**: Populate `session` metadata (model, cwd, started_at).
- **`SessionEnded`**: Set `ended_at`, compute `duration_seconds`.
- **`UserPromptReceived`**: Add to `prompts`, update `lastState.last_user_prompt` and `lastState.working_on`.
- **`ToolCallRequested`**: Create key tool call entry with `input_summary`. Store in `pendingToolCalls`. Update `lastState.last_tool_call`. Track file in `filesModified` if applicable.
- **`ToolCallCompleted`**: Find matching request by `tool_use_id`. Generate `output_summary` with size-aware summarization (> 2KB serialized gets compressed). Update `lastState.last_tool_result`.
- **`ToolCallFailed`**: Similar to completed, but `success: false`.
- **`AgentSpawned` / `AgentCompleted`**: Track in `agents` array.
- **`CompactionTriggered`**: Add to `compactionMarkers`.

### Output Summarization for Large Tool Results (> 2KB serialized)

- Read: `"Read {line_count} lines from {file_path} ({byte_count} bytes)"`
- Bash: `"Command output: {first 200 chars}... ({total_chars} chars total)"`
- Grep: `"{match_count} matches across {file_count} files"`
- Glob: `"{file_count} files matched"`
- Other: `"{first 200 chars}... ({total_chars} chars total)"`

### Progressive Summarization (post-finalization)

1. Serialize projection, measure `_size_bytes`.
2. If > 100KB, apply phases sequentially, re-measuring after each:
   - **Phase 1** (target 80KB): Truncate `output_summary` to 100 chars for all but last 20 tool calls.
   - **Phase 2** (target 60KB): Remove Read-only `key_tool_calls` not in last 30 events.
   - **Phase 3** (target 50KB): Collapse consecutive Read calls into single entries.
   - **Phase 4** (target 40KB): Truncate user prompts (except last 3) to 500 chars.
3. Set `_summarization_applied` array.

### Formatters

- **JSON**: As documented in the schema.
- **Text**: Sections separated by `---` lines: Session Info, User Prompts, Key Tool Calls, Files Modified, Last State.
- **Markdown**: H1/H2 headers, blockquoted prompts, code-formatted tool calls, bullet lists for files.

---

## Dependencies

- Task 01: Base Path Resolution and Shared Utilities (`/home/meywd/GlobalContext/tasks/04-projection-engine/01-base-path-resolution-and-shared-utilities.md`)
- Task 02: Projection Registry (`/home/meywd/GlobalContext/tasks/04-projection-engine/02-projection-registry.md`)
- Task 03: Event Replay Engine (`/home/meywd/GlobalContext/tasks/04-projection-engine/03-event-replay-engine.md`)
- Task 05: Timeline Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/05-timeline-projection-handler.md`) -- for `summary-generators.js`

---

## Acceptance Tests

- Session metadata is correctly extracted from `SessionStarted` and `SessionEnded`.
- All user prompts included in order, full text.
- Tool calls with large outputs (> 2KB) are summarized.
- Tool calls with small outputs (< 2KB) are included in full.
- `files_modified` lists every file with unique operation types and `last_operation`.
- `last_state` reflects the tail of the event stream.
- Compaction markers recorded.
- `_size_bytes` accurately reflects serialized size.
- A projection exceeding 100KB triggers progressive summarization.
- `_summarization_applied` lists applied phases.
- A session with no `SessionEnded` has `ended_at: null`.
- A session with 0 tool calls produces valid output with empty arrays.
- Markdown output is structured for LLM readability.
