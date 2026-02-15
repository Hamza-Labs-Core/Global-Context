# Hook Payload Structures

Reference documentation for the JSON payloads that Claude Code sends on stdin for each of the 10 hook events captured by GlobalContext.

## Important Notes

- **These payloads are defined by Claude Code, not by GlobalContext.** If Claude Code changes payload formats, GlobalContext captures whatever is sent. This document reflects the payload structures as of the initial implementation.
- **GlobalContext stores the entire payload unmodified** in the event envelope's `data` field. No fields are filtered, renamed, or transformed.
- **Downstream projections should handle missing or unexpected fields gracefully.** New fields may be added by Claude Code at any time.

---

## Hook Events

### 1. SessionStart -> SessionStarted (sync)

Fired when a new Claude Code session begins.

Example payload:
```json
{
  "session_id": "abc-123-def-456",
  "cwd": "/home/user/my-project",
  "model": "claude-sonnet-4-20250514",
  "permissions": ["Bash", "Read", "Write"],
  "timestamp": "2025-01-15T10:30:00Z"
}
```

| Field       | Type     | Description                                      |
|-------------|----------|--------------------------------------------------|
| session_id  | string   | Unique identifier for this session               |
| cwd         | string   | Working directory when session started            |
| model       | string   | Claude model being used                          |
| permissions | string[] | List of tools/permissions granted                |
| timestamp   | string   | ISO 8601 timestamp of session start              |

Notes:
- Low frequency (once per session).
- `cwd` is used by GlobalContext to derive the project-id.
- This is a sync hook -- Claude Code waits for it to complete before proceeding.

---

### 2. UserPromptSubmit -> UserPromptReceived (sync)

Fired when the user submits a prompt.

Example payload:
```json
{
  "session_id": "abc-123-def-456",
  "message": "Fix the bug in auth.ts",
  "timestamp": "2025-01-15T10:31:00Z"
}
```

| Field      | Type   | Description                        |
|------------|--------|------------------------------------|
| session_id | string | Current session identifier         |
| message    | string | The user's prompt text             |
| timestamp  | string | ISO 8601 timestamp                 |

Notes:
- Moderate frequency (once per user turn).
- Message content may be large for complex prompts.
- This is a sync hook.

---

### 3. PreToolUse -> ToolCallRequested (async)

Fired before a tool is invoked by Claude.

Example payload:
```json
{
  "session_id": "abc-123-def-456",
  "tool_name": "Bash",
  "tool_input": {
    "command": "ls -la"
  },
  "tool_use_id": "tu_01ABC"
}
```

| Field       | Type   | Description                                 |
|-------------|--------|---------------------------------------------|
| session_id  | string | Current session identifier                  |
| tool_name   | string | Name of the tool being invoked              |
| tool_input  | object | Tool-specific input parameters              |
| tool_use_id | string | Unique ID for this tool invocation          |

Notes:
- **High frequency event.** Fires for every tool call.
- `tool_input` shape varies per tool (Bash has `command`, Read has `file_path`, Write has `file_path` and `content`, etc.)
- Correlates with PostToolUse/PostToolUseFailure via `tool_use_id`.
- Uses matcher `.*` to capture all tool types.

---

### 4. PostToolUse -> ToolCallCompleted (async)

Fired after a tool invocation succeeds.

Example payload:
```json
{
  "session_id": "abc-123-def-456",
  "tool_name": "Bash",
  "tool_use_id": "tu_01ABC",
  "tool_result": "total 42\ndrwxr-xr-x  5 user staff  160 Jan 15 10:30 .\n...",
  "duration_ms": 150
}
```

| Field       | Type   | Description                                 |
|-------------|--------|---------------------------------------------|
| session_id  | string | Current session identifier                  |
| tool_name   | string | Name of the tool that was invoked           |
| tool_use_id | string | Unique ID matching the PreToolUse event     |
| tool_result | string | Output/result from the tool execution       |
| duration_ms | number | Execution time in milliseconds              |

Notes:
- High frequency, paired with PreToolUse events.
- `tool_result` can be very large (especially for Bash output or file reads).
- Uses matcher `.*` to capture all tool types.

---

### 5. PostToolUseFailure -> ToolCallFailed (async)

Fired when a tool invocation fails.

Example payload:
```json
{
  "session_id": "abc-123-def-456",
  "tool_name": "Bash",
  "tool_use_id": "tu_01ABC",
  "error": "Command failed with exit code 1: npm test",
  "duration_ms": 5200
}
```

| Field       | Type   | Description                                 |
|-------------|--------|---------------------------------------------|
| session_id  | string | Current session identifier                  |
| tool_name   | string | Name of the tool that failed                |
| tool_use_id | string | Unique ID matching the PreToolUse event     |
| error       | string | Error message or description                |
| duration_ms | number | Execution time in milliseconds              |

Notes:
- Lower frequency than PostToolUse (failures are less common).
- Correlates with PreToolUse via `tool_use_id`.
- Uses matcher `.*` to capture all tool types.

---

### 6. SubagentStart -> AgentSpawned (async)

Fired when a sub-agent is spawned.

Example payload:
```json
{
  "session_id": "abc-123-def-456",
  "subagent_id": "sa_01XYZ",
  "task": "Review the test coverage for auth module",
  "model": "claude-sonnet-4-20250514"
}
```

| Field       | Type   | Description                                 |
|-------------|--------|---------------------------------------------|
| session_id  | string | Parent session identifier                   |
| subagent_id | string | Unique ID for this sub-agent                |
| task        | string | Task description assigned to the sub-agent  |
| model       | string | Model used by the sub-agent                 |

Notes:
- Low frequency (only when sub-agents are used).
- Correlates with SubagentStop via `subagent_id`.
- Uses matcher `.*`.

---

### 7. SubagentStop -> AgentCompleted (async)

Fired when a sub-agent completes.

Example payload:
```json
{
  "session_id": "abc-123-def-456",
  "subagent_id": "sa_01XYZ",
  "result": "Found 3 untested functions in auth.ts",
  "duration_ms": 45000
}
```

| Field       | Type   | Description                                 |
|-------------|--------|---------------------------------------------|
| session_id  | string | Parent session identifier                   |
| subagent_id | string | Unique ID matching the SubagentStart event  |
| result      | string | Summary of sub-agent's work                 |
| duration_ms | number | Total execution time in milliseconds        |

Notes:
- Low frequency, paired with SubagentStart events.
- Uses matcher `.*`.

---

### 8. Stop -> TurnCompleted (async)

Fired when Claude stops generating (end of a turn).

Example payload:
```json
{
  "session_id": "abc-123-def-456",
  "stop_reason": "end_turn",
  "usage": {
    "input_tokens": 15000,
    "output_tokens": 3200
  }
}
```

| Field       | Type   | Description                                 |
|-------------|--------|---------------------------------------------|
| session_id  | string | Current session identifier                  |
| stop_reason | string | Why generation stopped (end_turn, etc.)     |
| usage       | object | Token usage statistics for this turn        |

Notes:
- Moderate frequency (once per assistant turn).
- `usage` provides token consumption data useful for cost tracking.

---

### 9. PreCompact -> CompactionTriggered (sync)

Fired before conversation compaction occurs.

Example payload:
```json
{
  "session_id": "abc-123-def-456",
  "message_count": 150,
  "token_count": 180000,
  "threshold": 200000
}
```

| Field         | Type   | Description                                 |
|---------------|--------|---------------------------------------------|
| session_id    | string | Current session identifier                  |
| message_count | number | Number of messages before compaction        |
| token_count   | number | Current token count triggering compaction   |
| threshold     | number | Token threshold that triggered compaction   |

Notes:
- Low frequency (only when conversation gets long enough to trigger compaction).
- This is a sync hook -- Claude Code waits for completion.
- Useful for tracking conversation complexity and context management.

---

### 10. SessionEnd -> SessionEnded (async)

Fired when a Claude Code session ends.

Example payload:
```json
{
  "session_id": "abc-123-def-456",
  "duration_s": 1800,
  "turns": 25,
  "total_tokens": {
    "input": 450000,
    "output": 85000
  }
}
```

| Field        | Type   | Description                                 |
|--------------|--------|---------------------------------------------|
| session_id   | string | Session identifier                          |
| duration_s   | number | Total session duration in seconds           |
| turns        | number | Number of conversation turns                |
| total_tokens | object | Cumulative token usage                      |

Notes:
- Low frequency (once per session).
- Provides session-level summary statistics.
- This is an async hook.

---

## Event Frequency Summary

| Hook Event          | Event Type           | Sync/Async | Relative Frequency |
|---------------------|----------------------|------------|-------------------|
| SessionStart        | SessionStarted       | sync       | Very low (1/session) |
| UserPromptSubmit    | UserPromptReceived   | sync       | Low (1/turn)       |
| PreToolUse          | ToolCallRequested    | async      | High               |
| PostToolUse         | ToolCallCompleted    | async      | High               |
| PostToolUseFailure  | ToolCallFailed       | async      | Medium             |
| SubagentStart       | AgentSpawned         | async      | Very low           |
| SubagentStop        | AgentCompleted       | async      | Very low           |
| Stop                | TurnCompleted        | async      | Low (1/turn)       |
| PreCompact          | CompactionTriggered  | sync       | Very low           |
| SessionEnd          | SessionEnded         | async      | Very low (1/session) |

## Correlation IDs

Events can be correlated using these shared identifiers:

- **session_id**: Present in all events. Links all events within a session.
- **tool_use_id**: Links PreToolUse with PostToolUse/PostToolUseFailure.
- **subagent_id**: Links SubagentStart with SubagentStop.
