# Event Types

Complete reference for all 10 event types captured by GlobalContext. Each event type corresponds to a specific Claude Code hook and captures different aspects of session activity.

## Table of Contents

- [Event Envelope Schema](#event-envelope-schema)
- [Event File Naming](#event-file-naming)
- [Event Types Overview](#event-types-overview)
- [Detailed Event Schemas](#detailed-event-schemas)
- [Sync vs Async Events](#sync-vs-async-events)

## Event Envelope Schema

Every event, regardless of type, is wrapped in a standard envelope before being stored.

### Envelope Structure

```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "event_type": "ToolCallCompleted",
  "project_id": "my-project-a3f7b2",
  "session_id": "abc123-def456",
  "sequence": 42,
  "timestamp": "2026-02-14T10:30:00.000Z",
  "data": {
    // raw hook payload, event-specific
  }
}
```

### Envelope Fields

| Field | Type | Description |
|-------|------|-------------|
| `event_id` | string (UUID v4) | Globally unique identifier for this event. Generated at capture time. |
| `event_type` | string | Event type name. One of the 10 defined types. |
| `project_id` | string | Project identifier: `{basename}-{hash6}` derived from working directory. |
| `session_id` | string | Session identifier from Claude Code. Extracted from hook payload. |
| `sequence` | integer | Per-session monotonically increasing counter. Starts at 1. |
| `timestamp` | string (ISO 8601) | UTC timestamp with millisecond precision when event was captured. |
| `data` | object | Complete, unmodified hook JSON payload. Shape varies by event type. |

### Notes

- `event_id` is generated using `uuidgen` or equivalent
- `project_id` format: `{basename}-{hash6}` where hash6 = first 6 hex chars of SHA-256(full_path)
- `session_id` is extracted from `data.session_id` in hook payload
- `sequence` is assigned atomically under flock
- `timestamp` format: `YYYY-MM-DDTHH:MM:SS.sssZ`
- `data` contains the raw hook payload with no modifications

## Event File Naming

Events are stored as individual JSON files named by their sequence number.

### Naming Convention

```
{6-digit-zero-padded-sequence}.json
```

Examples:
- Sequence 1: `000001.json`
- Sequence 42: `000042.json`
- Sequence 1000: `001000.json`
- Sequence 100000: `100000.json`

### File Location

```
~/.claude-context/events/{project-id}/{session-id}/{sequence}.json
```

Full example:
```
~/.claude-context/events/my-project-a3f7b2/abc123-def456/000042.json
```

## Event Types Overview

GlobalContext captures 10 event types from Claude Code hooks:

| # | Event Type | Hook Event | Sync | Purpose |
|---|------------|------------|------|---------|
| 1 | [SessionStarted](#1-sessionstarted) | SessionStart | Yes | Session boundary, initialization |
| 2 | [UserPromptReceived](#2-userpromptreceived) | UserPromptSubmit | Yes | User input capture |
| 3 | [ToolCallRequested](#3-toolcallrequested) | PreToolUse | No | Intent before tool execution |
| 4 | [ToolCallCompleted](#4-toolcallcompleted) | PostToolUse | No | Tool execution results |
| 5 | [ToolCallFailed](#5-toolcallfailed) | PostToolUseFailure | No | Tool execution errors |
| 6 | [AgentSpawned](#6-agentspawned) | SubagentStart | No | Sub-agent lifecycle start |
| 7 | [AgentCompleted](#7-agentcompleted) | SubagentStop | No | Sub-agent lifecycle end |
| 8 | [TurnCompleted](#8-turncompleted) | Stop | No | Turn boundary markers |
| 9 | [CompactionTriggered](#9-compactiontriggered) | PreCompact | Yes | Critical pre-compaction event |
| 10 | [SessionEnded](#10-sessionended) | SessionEnd | No | Session closure |

### Frequency

| Event Type | Typical Frequency |
|------------|-------------------|
| SessionStarted | 1 per session |
| SessionEnded | 0-1 per session (may not fire if crashed) |
| UserPromptReceived | 1-20 per session |
| ToolCallRequested | 10-200 per session |
| ToolCallCompleted | 10-200 per session |
| ToolCallFailed | 0-10 per session |
| TurnCompleted | 1-20 per session |
| CompactionTriggered | 0-5 per session |
| AgentSpawned | 0-10 per session |
| AgentCompleted | 0-10 per session |

## Detailed Event Schemas

Each event type has a specific payload structure in the `data` field.

### 1. SessionStarted

**Hook**: `SessionStart` (sync)

**Purpose**: Marks session boundary, captures session metadata, triggers store auto-initialization.

**Data Schema**:
```json
{
  "session_id": "abc123-def456",
  "source": "startup",
  "model": "claude-opus-4-6",
  "cwd": "/home/user/my-project",
  "started_at": "2026-02-14T10:00:00.000Z"
}
```

**Data Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | string | Session identifier from Claude Code |
| `source` | string | Why session started: `startup`, `resume`, `compact`, `clear` |
| `model` | string | LLM model name (e.g., `claude-opus-4-6`) |
| `cwd` | string | Working directory (absolute path) |
| `started_at` | string (ISO 8601) | Session start timestamp |

**Source Values**:

| Value | Meaning |
|-------|---------|
| `startup` | Fresh Claude Code startup |
| `resume` | Resuming a previous session |
| `compact` | New session after compaction |
| `clear` | New session after clearing conversation |

**Notes**:
- This is a sync hook (must complete before session proceeds)
- Always the first event in a session (sequence 1)
- Triggers gc-init if store does not exist
- Used to populate session.json metadata

**Example**:
```json
{
  "event_id": "a1b2c3d4-...",
  "event_type": "SessionStarted",
  "project_id": "my-project-a3f7b2",
  "session_id": "abc123-def456",
  "sequence": 1,
  "timestamp": "2026-02-14T10:00:00.123Z",
  "data": {
    "session_id": "abc123-def456",
    "source": "startup",
    "model": "claude-opus-4-6",
    "cwd": "/home/user/my-project",
    "started_at": "2026-02-14T10:00:00.000Z"
  }
}
```

### 2. UserPromptReceived

**Hook**: `UserPromptSubmit` (sync)

**Purpose**: Captures exact user prompts for decision tracking and context recovery.

**Data Schema**:
```json
{
  "session_id": "abc123-def456",
  "prompt": "Fix the failing test in auth.test.js that checks token expiry"
}
```

**Data Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | string | Session identifier |
| `prompt` | string | Full user message text (not truncated) |

**Notes**:
- This is a sync hook
- Captures the exact text the user typed
- No size limit (large prompts captured in full)
- Used by decisions projection to link prompts to actions
- Used by context projection for session continuity

**Example**:
```json
{
  "event_id": "b2c3d4e5-...",
  "event_type": "UserPromptReceived",
  "project_id": "my-project-a3f7b2",
  "session_id": "abc123-def456",
  "sequence": 2,
  "timestamp": "2026-02-14T10:00:05.456Z",
  "data": {
    "session_id": "abc123-def456",
    "prompt": "Fix the failing test in auth.test.js that checks token expiry"
  }
}
```

### 3. ToolCallRequested

**Hook**: `PreToolUse` (async)

**Purpose**: Captures LLM intent before tool executes. Shows what the LLM wants to do.

**Data Schema**:
```json
{
  "session_id": "abc123-def456",
  "tool_name": "Read",
  "tool_input": {
    "file_path": "/home/user/my-project/auth.test.js"
  },
  "tool_use_id": "toolu_01A2B3C4D5E6F7"
}
```

**Data Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | string | Session identifier |
| `tool_name` | string | Tool name: `Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob`, etc. |
| `tool_input` | object | Tool-specific input parameters (shape varies by tool) |
| `tool_use_id` | string | Unique identifier for this tool invocation |

**Tool Input Shapes**:

| Tool | Input Fields |
|------|--------------|
| `Read` | `{ file_path: string, limit?: number, offset?: number }` |
| `Write` | `{ file_path: string, content: string }` |
| `Edit` | `{ file_path: string, old_string: string, new_string: string, replace_all?: boolean }` |
| `Bash` | `{ command: string, description?: string, timeout?: number }` |
| `Grep` | `{ pattern: string, path?: string, glob?: string, output_mode?: string }` |
| `Glob` | `{ pattern: string, path?: string }` |
| `WebFetch` | `{ url: string, prompt: string }` |
| `WebSearch` | `{ query: string }` |
| `NotebookEdit` | `{ notebook_path: string, new_source: string, cell_id?: string }` |

**Notes**:
- This is an async hook (high frequency)
- Fires for EVERY tool call
- `tool_use_id` correlates with ToolCallCompleted/ToolCallFailed
- Used by files-touched projection to extract file paths
- Used by decisions projection to link intent to results

**Example (Read)**:
```json
{
  "event_id": "c3d4e5f6-...",
  "event_type": "ToolCallRequested",
  "project_id": "my-project-a3f7b2",
  "session_id": "abc123-def456",
  "sequence": 3,
  "timestamp": "2026-02-14T10:00:10.789Z",
  "data": {
    "session_id": "abc123-def456",
    "tool_name": "Read",
    "tool_input": {
      "file_path": "/home/user/my-project/auth.test.js"
    },
    "tool_use_id": "toolu_01A2B3C4D5E6F7"
  }
}
```

**Example (Bash)**:
```json
{
  "event_type": "ToolCallRequested",
  "sequence": 7,
  "data": {
    "tool_name": "Bash",
    "tool_input": {
      "command": "npm test",
      "description": "Run tests to verify fix"
    },
    "tool_use_id": "toolu_02B3C4D5E6F7G8"
  }
}
```

### 4. ToolCallCompleted

**Hook**: `PostToolUse` (async)

**Purpose**: Captures tool execution results. Shows what actually happened.

**Data Schema**:
```json
{
  "session_id": "abc123-def456",
  "tool_name": "Read",
  "tool_input": {
    "file_path": "/home/user/my-project/auth.test.js"
  },
  "tool_response": "1\tconst { verifyToken } = require('./auth');\n2\t...",
  "tool_use_id": "toolu_01A2B3C4D5E6F7"
}
```

**Data Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | string | Session identifier |
| `tool_name` | string | Tool name (same as ToolCallRequested) |
| `tool_input` | object | Tool input (same as ToolCallRequested) |
| `tool_response` | string | Tool output (may be very large) |
| `tool_use_id` | string | Correlates with ToolCallRequested |

**Notes**:
- This is an async hook (high frequency)
- `tool_response` can be very large (e.g., file contents from Read)
- No size limit enforced by capture (write side is dumb)
- Projection engine handles summarization for large responses
- `tool_use_id` matches the preceding ToolCallRequested

**Response Sizes**:

| Tool | Typical Response Size |
|------|----------------------|
| Read | 1KB - 1MB (file contents) |
| Write | <1KB (confirmation) |
| Edit | <1KB (confirmation) |
| Bash | 1KB - 100KB (command output) |
| Grep | 1KB - 100KB (match results) |
| Glob | 1KB - 10KB (file list) |

**Example**:
```json
{
  "event_id": "d4e5f6g7-...",
  "event_type": "ToolCallCompleted",
  "project_id": "my-project-a3f7b2",
  "session_id": "abc123-def456",
  "sequence": 4,
  "timestamp": "2026-02-14T10:00:12.345Z",
  "data": {
    "session_id": "abc123-def456",
    "tool_name": "Read",
    "tool_input": {
      "file_path": "/home/user/my-project/auth.test.js"
    },
    "tool_response": "     1\tconst { verifyToken } = require('./auth');\n     2\t\n     3\tdescribe('verifyToken', () => {\n     4\t  test('should reject expired tokens', () => {\n     5\t    const token = generateExpiredToken();\n     6\t    expect(() => verifyToken(token)).toThrow('Token expired');\n     7\t  });\n     8\t});",
    "tool_use_id": "toolu_01A2B3C4D5E6F7"
  }
}
```

### 5. ToolCallFailed

**Hook**: `PostToolUseFailure` (async)

**Purpose**: Captures tool execution errors for debugging and error tracking.

**Data Schema**:
```json
{
  "session_id": "abc123-def456",
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test"
  },
  "error": "Command failed with exit code 1",
  "is_interrupt": false,
  "tool_use_id": "toolu_02B3C4D5E6F7G8"
}
```

**Data Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | string | Session identifier |
| `tool_name` | string | Tool name that failed |
| `tool_input` | object | Tool input (same as ToolCallRequested) |
| `error` | string | Error message |
| `is_interrupt` | boolean | `true` if user cancelled, `false` if actual error |
| `tool_use_id` | string | Correlates with ToolCallRequested |

**Notes**:
- This is an async hook
- Fires instead of ToolCallCompleted when tool fails
- `is_interrupt` distinguishes user cancellation from errors
- Used by decisions projection to mark failed actions
- Used by timeline projection to highlight errors

**Example**:
```json
{
  "event_id": "e5f6g7h8-...",
  "event_type": "ToolCallFailed",
  "project_id": "my-project-a3f7b2",
  "session_id": "abc123-def456",
  "sequence": 8,
  "timestamp": "2026-02-14T10:01:25.678Z",
  "data": {
    "session_id": "abc123-def456",
    "tool_name": "Bash",
    "tool_input": {
      "command": "npm test"
    },
    "error": "Command failed with exit code 1: FAIL auth.test.js",
    "is_interrupt": false,
    "tool_use_id": "toolu_02B3C4D5E6F7G8"
  }
}
```

### 6. AgentSpawned

**Hook**: `SubagentStart` (async)

**Purpose**: Tracks sub-agent lifecycle for multi-agent sessions.

**Data Schema**:
```json
{
  "session_id": "abc123-def456",
  "agent_id": "agent_01X2Y3Z4",
  "agent_type": "code-review"
}
```

**Data Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | string | Session identifier |
| `agent_id` | string | Unique identifier for this agent instance |
| `agent_type` | string | Agent type or name |

**Notes**:
- This is an async hook
- Fires when Claude Code spawns a sub-agent (e.g., Task tool)
- `agent_id` correlates with AgentCompleted
- Used by decisions projection to track agent usage
- Used by context projection for session completeness

**Example**:
```json
{
  "event_id": "f6g7h8i9-...",
  "event_type": "AgentSpawned",
  "project_id": "my-project-a3f7b2",
  "session_id": "abc123-def456",
  "sequence": 10,
  "timestamp": "2026-02-14T10:02:00.123Z",
  "data": {
    "session_id": "abc123-def456",
    "agent_id": "agent_01X2Y3Z4",
    "agent_type": "code-review"
  }
}
```

### 7. AgentCompleted

**Hook**: `SubagentStop` (async)

**Purpose**: Captures sub-agent results and completion status.

**Data Schema**:
```json
{
  "session_id": "abc123-def456",
  "agent_id": "agent_01X2Y3Z4",
  "agent_type": "code-review",
  "transcript_path": "/tmp/agent_01X2Y3Z4_transcript.json"
}
```

**Data Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | string | Session identifier |
| `agent_id` | string | Agent identifier (matches AgentSpawned) |
| `agent_type` | string | Agent type |
| `transcript_path` | string | Path to agent transcript file (if available) |

**Notes**:
- This is an async hook
- `agent_id` correlates with preceding AgentSpawned
- `transcript_path` points to detailed agent conversation log
- Used by decisions projection to capture agent outcomes

**Example**:
```json
{
  "event_id": "g7h8i9j0-...",
  "event_type": "AgentCompleted",
  "project_id": "my-project-a3f7b2",
  "session_id": "abc123-def456",
  "sequence": 15,
  "timestamp": "2026-02-14T10:03:45.456Z",
  "data": {
    "session_id": "abc123-def456",
    "agent_id": "agent_01X2Y3Z4",
    "agent_type": "code-review",
    "transcript_path": "/tmp/claude-code/agent_01X2Y3Z4_transcript.json"
  }
}
```

### 8. TurnCompleted

**Hook**: `Stop` (async)

**Purpose**: Marks turn boundaries (LLM finished responding).

**Data Schema**:
```json
{
  "session_id": "abc123-def456",
  "stop_hook_active": true
}
```

**Data Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | string | Session identifier |
| `stop_hook_active` | boolean | Whether stop hook was actively triggered |

**Notes**:
- This is an async hook
- Fires when the LLM completes a turn (finishes responding)
- Used by decisions projection as group boundary
- Not critical for context recovery (informational)

**Example**:
```json
{
  "event_id": "h8i9j0k1-...",
  "event_type": "TurnCompleted",
  "project_id": "my-project-a3f7b2",
  "session_id": "abc123-def456",
  "sequence": 9,
  "timestamp": "2026-02-14T10:01:30.789Z",
  "data": {
    "session_id": "abc123-def456",
    "stop_hook_active": true
  }
}
```

### 9. CompactionTriggered

**Hook**: `PreCompact` (sync)

**Purpose**: Critical event marking context compaction. Last chance before information loss.

**Data Schema**:
```json
{
  "session_id": "abc123-def456",
  "trigger": "auto"
}
```

**Data Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | string | Session identifier |
| `trigger` | string | Compaction trigger: `manual` or `auto` |

**Trigger Values**:

| Value | Meaning |
|-------|---------|
| `manual` | User explicitly triggered compaction |
| `auto` | Automatic compaction due to context window limit |

**Notes**:
- This is a sync hook (CRITICAL)
- Fires BEFORE Claude Code compacts context
- After this event, conversation history may be lost
- Marks critical checkpoint in session timeline
- Used by context projection to identify compaction points

**Example**:
```json
{
  "event_id": "i9j0k1l2-...",
  "event_type": "CompactionTriggered",
  "project_id": "my-project-a3f7b2",
  "session_id": "abc123-def456",
  "sequence": 80,
  "timestamp": "2026-02-14T10:45:00.000Z",
  "data": {
    "session_id": "abc123-def456",
    "trigger": "auto"
  }
}
```

### 10. SessionEnded

**Hook**: `SessionEnd` (async)

**Purpose**: Marks session closure for lifecycle tracking.

**Data Schema**:
```json
{
  "session_id": "abc123-def456",
  "reason": "user_exit"
}
```

**Data Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | string | Session identifier |
| `reason` | string | Why session ended |

**Reason Values**:

| Value | Meaning |
|-------|---------|
| `user_exit` | User closed Claude Code normally |
| `timeout` | Session timed out due to inactivity |
| `error` | Session ended due to error |
| `restart` | Session ended for restart |

**Notes**:
- This is an async hook
- May NOT fire if Claude Code crashes or is killed
- Projections should NOT depend on this event for correctness
- Used to update session.json `ended_at` timestamp
- Optional for context recovery (session valid even without SessionEnded)

**Example**:
```json
{
  "event_id": "j0k1l2m3-...",
  "event_type": "SessionEnded",
  "project_id": "my-project-a3f7b2",
  "session_id": "abc123-def456",
  "sequence": 142,
  "timestamp": "2026-02-14T11:30:00.000Z",
  "data": {
    "session_id": "abc123-def456",
    "reason": "user_exit"
  }
}
```

## Sync vs Async Events

Events are captured either synchronously (blocking Claude Code) or asynchronously (non-blocking).

### Synchronous Events

| Event Type | Rationale |
|------------|-----------|
| SessionStarted | Session boundary - must capture before any other events |
| UserPromptReceived | User intent - must capture before LLM processes |
| CompactionTriggered | CRITICAL - last chance before context loss |

**Characteristics**:
- gc-hook runs and completes before Claude Code continues
- Must complete quickly (< 100ms target)
- Failure could block session (but capture script always exits 0)

### Asynchronous Events

| Event Type | Rationale |
|------------|-----------|
| ToolCallRequested | High frequency - cannot block tool execution |
| ToolCallCompleted | High frequency - cannot block LLM response |
| ToolCallFailed | Error path - must not add latency |
| AgentSpawned | Infrequent but non-critical |
| AgentCompleted | Non-critical |
| TurnCompleted | Informational - non-critical |
| SessionEnded | Best-effort - may not fire at all |

**Characteristics**:
- gc-hook runs in background while Claude Code continues
- Can take longer (< 50ms target but not critical)
- Failure does not affect session

## Hook Configuration

Events are captured via hooks configured in `hooks/hooks.json` (plugin) or `~/.claude/settings.json` (manual).

### Hook Mapping

| Claude Code Hook | GlobalContext Event | Matcher | Timeout |
|------------------|---------------------|---------|---------|
| SessionStart | SessionStarted | `""` | 5000ms |
| UserPromptSubmit | UserPromptReceived | (none) | 5000ms |
| PreToolUse | ToolCallRequested | `".*"` | 5000ms |
| PostToolUse | ToolCallCompleted | `".*"` | 5000ms |
| PostToolUseFailure | ToolCallFailed | `".*"` | 5000ms |
| SubagentStart | AgentSpawned | `".*"` | 5000ms |
| SubagentStop | AgentCompleted | `".*"` | 5000ms |
| Stop | TurnCompleted | (none) | 5000ms |
| PreCompact | CompactionTriggered | (none) | 5000ms |
| SessionEnd | SessionEnded | (none) | 5000ms |

**Matcher Notes**:
- `".*"` means "match all tools" (for tool-specific hooks)
- `""` or omitted means "no filter"

## Related Documentation

- [Architecture](Architecture.md) - Event capture flow and storage
- [CLI Reference](CLI-Reference.md) - Querying events
- [Projections](Projections.md) - How events are processed
- [Plugin Guide](Plugin-Guide.md) - Hook installation via plugin
