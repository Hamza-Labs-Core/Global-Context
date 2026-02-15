# Story 04: Projection Engine (CQRS Read Side)

## Overview

The projection engine is the read side of the CQRS pattern in GlobalContext. It replays events from the event store and builds structured views (projections) optimized for different query patterns. Projections are derived data -- always rebuildable from the underlying event stream. They never contain information that does not originate from stored events.

The engine is invoked through the `project` CLI command and supports five projection types: **timeline**, **files**, **decisions**, **context**, and **summary**. Each projection addresses a distinct query pattern and is stored as a standalone JSON file under `~/.claude-context/projections/{project-id}/{session-id}/`.

### Why This Matters

Without projections, answering questions like "what files did I modify?" or "resume where I left off" would require reading every individual event file, parsing each one, and assembling the answer on the fly. Projections pre-compute these answers so they are available instantly. Because they are derived from events, they can always be rebuilt from scratch if corrupted, lost, or if the projection logic itself changes.

### Dependencies

- **Stories 01/03 (Event Capture + Storage Layer)**: The projection engine reads events produced by `capture-event`. The event envelope schema (event_id, event_type, project_id, session_id, sequence, timestamp, data) and the storage layout (`~/.claude-context/events/{project-id}/{session-id}/{sequence}.json`) must be in place.
- **Architecture**: Follows the CQRS read side as defined in `/home/meywd/GlobalContext/docs/ARCHITECTURE.md`.

---

## 1. The `project` CLI Command

### Location

```
~/.claude-context/bin/project
```

The script must be executable (`chmod +x`) and should work as a standalone command when added to `PATH` or invoked by absolute path.

### Usage

```
project <projection-type> <session-id> [options]
```

### Arguments

| Argument | Required | Description |
|---|---|---|
| `projection-type` | Yes | One of: `timeline`, `files`, `decisions`, `context`, `summary` |
| `session-id` | Yes | The session ID whose events to project. Use `latest` as an alias to resolve the `~/.claude-context/projections/latest` symlink. |

### Options

| Option | Default | Description |
|---|---|---|
| `--from <sequence>` | 1 | Start projecting from this sequence number (inclusive) |
| `--to <sequence>` | (last) | Stop projecting at this sequence number (inclusive) |
| `--rebuild` | false | Force a full rebuild, ignoring any existing projection state |
| `--format <format>` | `json` | Output format: `json`, `text`, or `markdown` |
| `--output <path>` | (default location) | Override the output file path. Use `-` for stdout. |
| `--quiet` | false | Suppress progress/info messages to stderr |

### Behavior

1. Validate that `projection-type` is one of the five supported types. Exit with code 1 and a usage message if not.
2. Resolve `session-id`. If `latest`, follow the symlink at `~/.claude-context/projections/latest`. If no symlink exists, exit with code 1 and a clear error message.
3. Validate that the session event directory exists at `~/.claude-context/events/{session-id}/`. Exit with code 1 if missing.
4. Load the existing projection file if present and `--rebuild` is not set. Read `_last_sequence` from projection metadata.
5. Determine the event range to replay: from `max(--from, _last_sequence + 1)` to `--to` (or the highest sequence in the event directory).
6. If no new events exist and `--rebuild` is not set, output the existing projection in the requested format and exit with code 0.
7. Replay events through the appropriate projection handler.
8. Write the updated projection to `~/.claude-context/projections/{session-id}/{projection-name}.json`.
9. Output the projection to stdout in the requested `--format`.
10. Exit with code 0 on success.

### Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Invalid arguments, missing session, or missing event directory |
| 2 | Event replay error (corrupt event file, I/O error) |

### Acceptance Criteria

- [ ] `project timeline <session-id>` produces a timeline projection and writes it to the correct path.
- [ ] `project files <session-id>` produces a files-touched projection.
- [ ] `project decisions <session-id>` produces a decisions projection.
- [ ] `project context <session-id>` produces a context snapshot projection.
- [ ] `project summary <session-id>` produces a summary projection.
- [ ] `project timeline latest` resolves the symlink and projects the most recent session.
- [ ] `project timeline <session-id> --from 10 --to 50` only processes events in that range.
- [ ] `project timeline <session-id> --rebuild` ignores cached state and rebuilds from scratch.
- [ ] `project timeline <session-id> --format text` outputs human-readable text to stdout.
- [ ] `project timeline <session-id> --format markdown` outputs markdown to stdout.
- [ ] `project timeline <session-id> --output -` writes only to stdout, does not write a file.
- [ ] Running `project` with no arguments prints usage help and exits with code 1.
- [ ] Running `project bogus <session-id>` prints an error about unknown projection type and exits with code 1.
- [ ] Running `project timeline nonexistent-session` prints an error and exits with code 1.

---

## 2. Timeline Projection

### Purpose

An ordered sequence of what happened in the session, presented as a concise log. Each entry is a one-liner summary suitable for scanning.

### Output Schema

```json
{
  "_projection_type": "timeline",
  "_projection_version": 1,
  "_last_sequence": 142,
  "_rebuilt_at": "2026-02-14T10:45:00.000Z",
  "_session_id": "abc123",
  "entries": [
    {
      "sequence": 1,
      "timestamp": "2026-02-14T10:00:00.000Z",
      "event_type": "SessionStarted",
      "summary": "Session started (model: claude-opus-4-6, cwd: /home/user/project)"
    },
    {
      "sequence": 2,
      "timestamp": "2026-02-14T10:00:05.000Z",
      "event_type": "UserPromptReceived",
      "summary": "User: Fix the failing test in auth.test.js that checks token expiry..."
    },
    {
      "sequence": 3,
      "timestamp": "2026-02-14T10:00:10.000Z",
      "event_type": "ToolCallRequested",
      "summary": "Called Read: file_path=/home/user/project/auth.test.js"
    }
  ]
}
```

### Summary Generation Rules

Each event type maps to a specific summary template:

| Event Type | Summary Template |
|---|---|
| `SessionStarted` | `"Session started (model: {model}, cwd: {working_directory})"` |
| `UserPromptReceived` | `"User: {first 200 characters of prompt}"` -- truncate with `...` if longer |
| `ToolCallRequested` | `"Called {tool_name}: {brief description of input}"` -- see below for per-tool rules |
| `ToolCallCompleted` | `"Result from {tool_name}: {brief summary of output}"` -- see below |
| `ToolCallFailed` | `"FAILED {tool_name}: {error message, first 150 chars}"` |
| `AgentSpawned` | `"Spawned {agent_type} agent: {brief description}"` |
| `AgentCompleted` | `"Agent completed: {agent_type} (status: {status})"` |
| `TurnCompleted` | `"Turn completed"` |
| `CompactionTriggered` | `"COMPACTION triggered at sequence {sequence}"` |
| `SessionEnded` | `"Session ended"` |

#### ToolCallRequested Input Summaries

The summary for a tool call request should be derived from the tool_input in the event data. Per-tool extraction:

| Tool | Input Summary |
|---|---|
| `Read` | `"file_path={file_path}"` |
| `Write` | `"file_path={file_path} ({content length} chars)"` |
| `Edit` | `"file_path={file_path} replacing {old_string length} chars"` |
| `Bash` | `"command={first 100 chars of command}"` |
| `Glob` | `"pattern={pattern} path={path or cwd}"` |
| `Grep` | `"pattern={pattern} path={path or cwd}"` |
| `WebFetch` | `"url={url}"` |
| `WebSearch` | `"query={query}"` |
| `NotebookEdit` | `"notebook_path={notebook_path} cell={cell_number}"` |
| (other) | `"{first 100 chars of JSON-stringified tool_input}"` |

#### ToolCallCompleted Output Summaries

| Tool | Output Summary |
|---|---|
| `Read` | `"Read {line count} lines from {file_path}"` |
| `Write` | `"Wrote {content length} chars to {file_path}"` |
| `Edit` | `"Edited {file_path}"` |
| `Bash` | `"Exit code {exit_code}, output: {first 100 chars of stdout}"` |
| `Glob` | `"{match count} files matched"` |
| `Grep` | `"{match count} matches found"` |
| (other) | `"{first 100 chars of JSON-stringified result}"` |

### Filtering

When `--from` and `--to` are specified, only include entries within that sequence range. Additionally, support future extension for event_type filtering (not required for initial implementation, but the data structure should not prevent it).

### Storage

```
~/.claude-context/projections/{session-id}/timeline.json
```

### Acceptance Criteria

- [ ] Timeline contains one entry per event in sequence order.
- [ ] Each entry has `sequence`, `timestamp`, `event_type`, and `summary` fields.
- [ ] UserPromptReceived summaries are truncated at 200 characters with `...` appended.
- [ ] ToolCallRequested summaries include the tool name and a meaningful description of the input.
- [ ] ToolCallCompleted summaries include the tool name and a brief result description.
- [ ] ToolCallFailed summaries include the error message.
- [ ] Unknown event types produce a generic summary: `"{event_type} at sequence {sequence}"`.
- [ ] Timeline entries respect `--from` and `--to` sequence range options.
- [ ] Output JSON matches the documented schema.
- [ ] Text format output shows one line per entry: `[{sequence}] {timestamp} {event_type}: {summary}`.
- [ ] Markdown format output shows entries as a numbered list with bold event types.

---

## 3. Files Touched Projection

### Purpose

A comprehensive list of every file that was read, written, edited, globbed, or grepped during the session. This answers the question: "What files did the LLM interact with?"

### Output Schema

```json
{
  "_projection_type": "files-touched",
  "_projection_version": 1,
  "_last_sequence": 142,
  "_rebuilt_at": "2026-02-14T10:45:00.000Z",
  "_session_id": "abc123",
  "files": [
    {
      "path": "/home/user/project/src/auth.ts",
      "operations": [
        {
          "type": "read",
          "sequence": 5,
          "timestamp": "2026-02-14T10:00:15.000Z",
          "tool": "Read"
        },
        {
          "type": "edit",
          "sequence": 12,
          "timestamp": "2026-02-14T10:01:30.000Z",
          "tool": "Edit"
        }
      ],
      "first_touched": "2026-02-14T10:00:15.000Z",
      "last_touched": "2026-02-14T10:01:30.000Z",
      "touch_count": 2
    }
  ],
  "stats": {
    "total_files": 15,
    "files_read": 12,
    "files_written": 3,
    "files_edited": 5,
    "files_globbed": 8,
    "files_grepped": 4
  }
}
```

### File Path Extraction Rules

File paths must be extracted from the `tool_input` field in event data. The extraction depends on the event type and the tool:

| Source Event Type | Tool | Fields to Extract | Operation Type |
|---|---|---|---|
| `ToolCallRequested` | `Read` | `tool_input.file_path` | `read` |
| `ToolCallRequested` | `Write` | `tool_input.file_path` | `write` |
| `ToolCallRequested` | `Edit` | `tool_input.file_path` | `edit` |
| `ToolCallRequested` | `Glob` | Resolved from `tool_input.pattern` + `tool_input.path` | `glob` |
| `ToolCallRequested` | `Grep` | `tool_input.path` (if a file, not a directory) | `grep` |
| `ToolCallRequested` | `NotebookEdit` | `tool_input.notebook_path` | `edit` |
| `ToolCallRequested` | `Bash` | Best-effort extraction from `tool_input.command` (see below) | varies |

**Glob handling**: For Glob tool calls, the `pattern` field contains a glob expression and the `path` field contains the base directory. Record the `path` + `pattern` as a single entry with operation type `glob`. If the ToolCallCompleted event for the same tool call contains matched file paths in the result, record each matched file individually as `glob` operations.

**Grep handling**: If `tool_input.path` points to a specific file (not a directory), record it. If it points to a directory, do not record the directory itself. If the ToolCallCompleted result lists matched files, record each file with operation type `grep`.

**Bash handling**: Best-effort extraction only. Look for common patterns in the command string:
- `cat <path>`, `less <path>`, `head <path>`, `tail <path>` -> `read`
- `echo ... > <path>`, `cp ... <path>`, `mv ... <path>` -> `write`
- `rm <path>` -> `write` (destructive write)
- Do not attempt to parse complex piped commands. This is best-effort and missing files from Bash commands is acceptable.

### Deduplication

Files are deduplicated by their absolute path. If the same file is touched multiple times, all operations are listed in the `operations` array, ordered by sequence number. The `first_touched` and `last_touched` timestamps and `touch_count` are maintained as summary fields.

### Storage

```
~/.claude-context/projections/{session-id}/files-touched.json
```

### Acceptance Criteria

- [ ] Every Read, Write, and Edit tool call results in the file path being recorded.
- [ ] Glob tool calls record matched files from the result when available.
- [ ] Grep tool calls record the target file or matched files from the result.
- [ ] Files are deduplicated by absolute path.
- [ ] Multiple operations on the same file are all recorded in the `operations` array.
- [ ] Operations are ordered by sequence number within each file entry.
- [ ] `first_touched`, `last_touched`, and `touch_count` are accurate.
- [ ] The `stats` object contains correct aggregate counts.
- [ ] Files from unknown tools are not recorded (no false positives from guessing).
- [ ] Missing `tool_input` fields do not cause errors -- the event is skipped with a warning to stderr.
- [ ] Incremental rebuild correctly merges new operations into existing file entries.

---

## 4. Decisions Projection

### Purpose

Captures the "intent to action" chain by grouping user prompts with the tool calls that followed. This projection answers: "WHY did things happen, not just WHAT happened." It reveals the causal relationship between a user's request and the actions the LLM took.

### Output Schema

```json
{
  "_projection_type": "decisions",
  "_projection_version": 1,
  "_last_sequence": 142,
  "_rebuilt_at": "2026-02-14T10:45:00.000Z",
  "_session_id": "abc123",
  "decision_groups": [
    {
      "group_id": 1,
      "user_prompt": {
        "sequence": 2,
        "timestamp": "2026-02-14T10:00:05.000Z",
        "prompt": "Fix the failing test in auth.test.js that checks token expiry",
        "prompt_length": 62
      },
      "actions": [
        {
          "tool_name": "Read",
          "input_summary": "Read file /home/user/project/auth.test.js",
          "output_summary": "Read 45 lines",
          "success": true,
          "request_sequence": 3,
          "completion_sequence": 4,
          "timestamp": "2026-02-14T10:00:10.000Z"
        },
        {
          "tool_name": "Edit",
          "input_summary": "Edit /home/user/project/auth.test.js, replacing assertion",
          "output_summary": "File edited successfully",
          "success": true,
          "request_sequence": 5,
          "completion_sequence": 6,
          "timestamp": "2026-02-14T10:00:20.000Z"
        }
      ],
      "action_count": 2,
      "all_succeeded": true,
      "agents_spawned": []
    }
  ],
  "stats": {
    "total_groups": 5,
    "total_actions": 23,
    "failed_actions": 1
  }
}
```

### Grouping Logic

1. Start a new decision group whenever a `UserPromptReceived` event is encountered.
2. All subsequent `ToolCallRequested`, `ToolCallCompleted`, `ToolCallFailed`, `AgentSpawned`, and `AgentCompleted` events belong to this group.
3. The group ends when one of the following is encountered:
   - Another `UserPromptReceived` event (which starts a new group)
   - A `TurnCompleted` event
   - A `SessionEnded` event
   - End of event stream
4. `TurnCompleted` events are NOT included as actions in the group; they only serve as group boundaries.
5. Tool call pairing: Match `ToolCallRequested` to its corresponding `ToolCallCompleted` or `ToolCallFailed` by matching on the tool call identifier in the event data (typically the tool_use_id or a combination of tool_name + sequence proximity). If no completion event is found, mark the action with `"success": null` and `"output_summary": "(no completion recorded)"`.

### Action Summaries

**input_summary**: A one-line description of what the tool was asked to do. Follow the same per-tool rules as the Timeline projection's ToolCallRequested summaries, but with slightly more context (up to 150 characters).

**output_summary**: A one-line description of the result. Follow the Timeline projection's ToolCallCompleted rules. For failures, include the error message (first 150 characters).

### Agent Tracking

If `AgentSpawned` or `AgentCompleted` events fall within a decision group, record them in the `agents_spawned` array:

```json
{
  "agent_type": "code-review",
  "spawn_sequence": 10,
  "completion_sequence": 15,
  "status": "completed"
}
```

### Storage

```
~/.claude-context/projections/{session-id}/decisions.json
```

### Acceptance Criteria

- [ ] Each `UserPromptReceived` starts a new decision group.
- [ ] All tool call events between two `UserPromptReceived` events (or until `TurnCompleted`/`SessionEnded`) are grouped together.
- [ ] Tool call requests are paired with their completions or failures.
- [ ] Unpaired tool call requests (no completion found) are marked with `"success": null`.
- [ ] `all_succeeded` is `true` only if every action in the group has `"success": true`.
- [ ] The full user prompt is stored (not truncated) in `user_prompt.prompt`.
- [ ] `prompt_length` accurately reflects the character count of the full prompt.
- [ ] `action_count` matches the length of the `actions` array.
- [ ] `stats` aggregates are correct across all groups.
- [ ] Events before the first `UserPromptReceived` (such as `SessionStarted`) do not create a decision group; they are excluded.
- [ ] Agent events within a group are recorded in `agents_spawned`.
- [ ] Incremental rebuild correctly appends new groups or extends the last open group.

---

## 5. Context Snapshot Projection

### Purpose

This is THE critical projection. It contains everything needed to resume work in a new session. When a user says "get last context," this projection is what gets loaded. It must provide the LLM with enough information to continue seamlessly.

### Output Schema

```json
{
  "_projection_type": "context",
  "_projection_version": 1,
  "_last_sequence": 142,
  "_rebuilt_at": "2026-02-14T10:45:00.000Z",
  "_session_id": "abc123",
  "_size_bytes": 45230,

  "session": {
    "id": "abc123",
    "started_at": "2026-02-14T10:00:00.000Z",
    "ended_at": "2026-02-14T11:30:00.000Z",
    "model": "claude-opus-4-6",
    "project_directory": "/home/user/project",
    "duration_seconds": 5400,
    "event_count": 142
  },

  "prompts": [
    {
      "sequence": 2,
      "timestamp": "2026-02-14T10:00:05.000Z",
      "prompt": "Fix the failing test in auth.test.js that checks token expiry"
    }
  ],

  "key_tool_calls": [
    {
      "sequence": 3,
      "tool_name": "Read",
      "input_summary": "Read /home/user/project/auth.test.js",
      "output_summary": "45 lines, test file with 3 test cases",
      "success": true,
      "timestamp": "2026-02-14T10:00:10.000Z"
    }
  ],

  "files_modified": [
    {
      "path": "/home/user/project/src/auth.ts",
      "operations": ["read", "edit"],
      "last_operation": "edit"
    }
  ],

  "agents": [
    {
      "agent_type": "code-review",
      "spawn_sequence": 10,
      "status": "completed",
      "outcome_summary": "Reviewed auth module, found 2 issues"
    }
  ],

  "last_state": {
    "last_user_prompt": "Now run the tests to make sure everything passes",
    "last_tool_call": "Bash: npm test",
    "last_tool_result": "All 12 tests passed",
    "working_on": "Fixing auth token expiry test and verifying the fix"
  },

  "compaction_markers": [
    {
      "sequence": 80,
      "timestamp": "2026-02-14T10:45:00.000Z",
      "pre_compaction_event_count": 80
    }
  ]
}
```

### Section Details

#### a. Session Metadata

Extracted from the `SessionStarted` event:

| Field | Source |
|---|---|
| `id` | `session_id` from event envelope |
| `started_at` | `timestamp` from `SessionStarted` event |
| `ended_at` | `timestamp` from `SessionEnded` event (null if session still active) |
| `model` | `data.model` or `data.session.model` from `SessionStarted` event |
| `project_directory` | `data.cwd` or `data.session.cwd` from `SessionStarted` event |
| `duration_seconds` | Computed from `started_at` to `ended_at` (or current time if active) |
| `event_count` | Total events in the session |

#### b. All User Prompts in Order

Every `UserPromptReceived` event's prompt text, in sequence order. Full text, not truncated. This lets the resuming LLM understand the conversation flow.

#### c. Key Tool Calls and Results

All `ToolCallRequested`/`ToolCallCompleted` pairs, summarized. For tool calls with very large outputs (result data > 2KB when serialized), the `output_summary` should be a compressed description rather than raw data. Summarization rules:

- Read results > 2KB: `"Read {line_count} lines from {file_path} ({byte_count} bytes)"`
- Bash results > 2KB: `"Command output: {first 200 chars}... ({total_chars} chars total)"`
- Grep results > 2KB: `"{match_count} matches across {file_count} files"`
- Glob results > 2KB: `"{file_count} files matched"`
- All other results > 2KB: `"{first 200 chars}... ({total_chars} chars total)"`

Results under 2KB are included in full in `output_summary`.

#### d. Files Modified

Derived from the same logic as the Files Touched projection, but simplified to just path, unique operation types, and last operation. This is a compact reference, not the full operation log.

#### e. Agents Spawned

Every `AgentSpawned`/`AgentCompleted` pair with outcome summary.

#### f. Last Known State

Constructed from the tail of the event stream:

| Field | Source |
|---|---|
| `last_user_prompt` | The prompt text from the last `UserPromptReceived` event |
| `last_tool_call` | `"{tool_name}: {input_summary}"` from the last `ToolCallRequested` event |
| `last_tool_result` | `output_summary` from the last `ToolCallCompleted` event |
| `working_on` | Inferred from the last user prompt combined with the last few tool calls. This is a best-effort string assembled as: `"{last_user_prompt, first 100 chars}"`. No LLM inference is used; it is a simple extraction. |

#### g. Compaction Markers

Every `CompactionTriggered` event is recorded. These mark points where Claude Code's internal context was compressed. They are critical metadata for understanding the completeness of the session context.

### Size-Aware Summarization

The context projection must remain usable by an LLM, which means it cannot grow unboundedly. Size management rules:

1. After building the full projection, measure `_size_bytes` (JSON serialized size).
2. If `_size_bytes` exceeds **100KB** (102,400 bytes), apply progressive summarization:
   - **Phase 1** (target: 80KB): Truncate `output_summary` fields in `key_tool_calls` to 100 characters max for all tool calls except the last 20.
   - **Phase 2** (target: 60KB): Remove `key_tool_calls` entries for Read-only operations that are not in the last 30 events. Keep Write, Edit, Bash, and all entries from the last 30 events.
   - **Phase 3** (target: 50KB): Collapse consecutive Read tool calls into a single entry: `"Read {count} files: {file1}, {file2}, ..."`.
   - **Phase 4** (target: 40KB): Truncate user prompts (except the last 3) to 500 characters.
3. After each phase, re-measure. Stop summarizing once size is below the phase target.
4. Add a `_summarization_applied` field indicating which phases were applied: `[]`, `["phase1"]`, `["phase1", "phase2"]`, etc.

### Storage

```
~/.claude-context/projections/{session-id}/context.json
```

### Acceptance Criteria

- [ ] Session metadata is correctly extracted from `SessionStarted` and `SessionEnded` events.
- [ ] All user prompts are included in order, with full text.
- [ ] All tool calls are represented with input and output summaries.
- [ ] Large tool outputs (> 2KB) are summarized, not included raw.
- [ ] `files_modified` lists every file that was read, written, or edited with unique operation types.
- [ ] Agent spawn/completion pairs are recorded with status.
- [ ] `last_state` correctly reflects the tail of the event stream.
- [ ] Compaction markers are recorded from `CompactionTriggered` events.
- [ ] `_size_bytes` accurately reflects the serialized JSON size.
- [ ] When projection exceeds 100KB, progressive summarization is applied.
- [ ] Summarization phases are applied incrementally, stopping as soon as size is within target.
- [ ] `_summarization_applied` correctly lists which phases were used.
- [ ] A session with 0 tool calls produces a valid context projection with empty arrays.
- [ ] A session with no `SessionEnded` event has `ended_at: null` and computes duration from current time.
- [ ] The markdown output format is structured for LLM readability: clear sections, indentation, and labeled fields.

---

## 6. Summary Projection

### Purpose

A brief overview of the entire session -- high-level metrics and a natural language summary. Useful for session listings, dashboards, and quick orientation.

### Output Schema

```json
{
  "_projection_type": "summary",
  "_projection_version": 1,
  "_last_sequence": 142,
  "_rebuilt_at": "2026-02-14T10:45:00.000Z",
  "_session_id": "abc123",

  "session_id": "abc123",
  "started_at": "2026-02-14T10:00:00.000Z",
  "ended_at": "2026-02-14T11:30:00.000Z",
  "duration_seconds": 5400,
  "duration_human": "1h 30m",

  "event_count": 142,
  "event_breakdown": {
    "SessionStarted": 1,
    "UserPromptReceived": 5,
    "ToolCallRequested": 45,
    "ToolCallCompleted": 44,
    "ToolCallFailed": 1,
    "AgentSpawned": 2,
    "AgentCompleted": 2,
    "TurnCompleted": 5,
    "CompactionTriggered": 1,
    "SessionEnded": 1
  },

  "tools_used": {
    "Read": 15,
    "Write": 3,
    "Edit": 8,
    "Bash": 12,
    "Grep": 5,
    "Glob": 2
  },

  "files_touched_count": 15,
  "files_modified_count": 6,
  "agents_spawned_count": 2,
  "compaction_count": 1,
  "user_prompts_count": 5,

  "narrative": "This session lasted 1 hour and 30 minutes. The user made 5 requests, primarily focused on fixing auth token expiry tests. The LLM used 45 tool calls across 6 different tools (Read: 15, Bash: 12, Edit: 8, Grep: 5, Write: 3, Glob: 2). 15 files were touched, 6 were modified. 2 sub-agents were spawned. 1 compaction event occurred. 1 tool call failed."
}
```

### Narrative Generation

The `narrative` field is a single-paragraph natural language summary built from templates. It is NOT generated by an LLM; it is assembled mechanically from the metrics. Template:

```
This session lasted {duration_human}. The user made {user_prompts_count} request(s){prompt_topic_hint}. The LLM used {tool_call_count} tool calls across {tool_type_count} different tools ({top_tools_list}). {files_touched_count} files were touched, {files_modified_count} were modified. {agents_clause}{compaction_clause}{failure_clause}
```

Where:
- `{prompt_topic_hint}`: If the first user prompt is available, append `, starting with "{first 80 chars of first prompt}..."`. Otherwise, omit.
- `{top_tools_list}`: Top tools listed as `"ToolName: count"`, sorted by count descending, all tools included.
- `{agents_clause}`: If agents were spawned: `"{count} sub-agent(s) were spawned. "`. Otherwise, omit.
- `{compaction_clause}`: If compactions occurred: `"{count} compaction event(s) occurred. "`. Otherwise, omit.
- `{failure_clause}`: If failures occurred: `"{count} tool call(s) failed."`. Otherwise, omit.

### Storage

```
~/.claude-context/projections/{session-id}/summary.json
```

### Acceptance Criteria

- [ ] All metric counts are accurate.
- [ ] `event_breakdown` contains a count for every event type present in the session.
- [ ] `tools_used` contains a count for every tool name that appears in `ToolCallRequested` events.
- [ ] `duration_human` formats correctly: `"0m"` for under 1 minute, `"5m"` for 5 minutes, `"1h 30m"` for 90 minutes, `"2h 0m"` for exactly 2 hours.
- [ ] `narrative` is a grammatically correct, single-paragraph summary.
- [ ] The narrative does not contain placeholder tokens or template syntax.
- [ ] A session with only a `SessionStarted` event produces valid output with zero counts.
- [ ] Text format output is a clean multi-line report.
- [ ] Markdown format output uses headers and a table for metrics.

---

## 7. Incremental Rebuild

### Purpose

Avoid reprocessing the entire event stream on every projection request. Instead, track the last-projected sequence number and only process new events.

### Mechanism

1. Every projection JSON file contains metadata fields:
   - `_last_sequence`: The highest event sequence number that has been incorporated into this projection.
   - `_rebuilt_at`: ISO 8601 timestamp of when the projection was last updated.
   - `_projection_version`: Schema version of the projection format (integer, starting at 1).

2. On invocation (without `--rebuild`):
   - Read the existing projection file if present.
   - Extract `_last_sequence`.
   - Scan the event directory for events with sequence > `_last_sequence`.
   - Process only those events through the projection handler.
   - Merge the new results into the existing projection data.
   - Update `_last_sequence` and `_rebuilt_at`.
   - Write the updated projection.

3. On invocation with `--rebuild`:
   - Ignore any existing projection file.
   - Process all events from sequence 1 (or `--from`).
   - Write a fresh projection file.

4. **Version check**: If the existing projection's `_projection_version` does not match the current handler's version, automatically trigger a full rebuild. This ensures schema migrations happen transparently.

### Merging Strategies per Projection

| Projection | Merge Strategy |
|---|---|
| `timeline` | Append new entries to the `entries` array. |
| `files-touched` | For each new file operation, either append to an existing file's `operations` array or create a new file entry. Update `stats`. |
| `decisions` | If the last group was still open (no `TurnCompleted` or next `UserPromptReceived`), new events extend it. Otherwise, new groups are appended. |
| `context` | Rebuild the `last_state` section entirely from the last few events. Append new prompts, tool calls, and file operations to their respective arrays. |
| `summary` | Recount all metrics from the merged data. Regenerate the narrative. |

### Acceptance Criteria

- [ ] Running `project timeline <session-id>` twice in a row with no new events does NOT rewrite the file (or writes an identical file).
- [ ] Adding 10 new events and running `project timeline <session-id>` only processes those 10 new events.
- [ ] `_last_sequence` in the output matches the highest event sequence processed.
- [ ] `_rebuilt_at` is updated on every successful run.
- [ ] `--rebuild` flag causes a full reprocessing regardless of existing state.
- [ ] If `_projection_version` in the existing file does not match the handler's version, a full rebuild is triggered automatically.
- [ ] Incremental rebuild produces identical results to a full rebuild (for the same event range).
- [ ] A file written by incremental rebuild and one written by full rebuild are semantically equivalent (field order may differ, content must match).

---

## 8. Event Replay Engine

### Purpose

The core mechanism that reads events from the session directory, orders them, and streams them through projection handlers. All projections depend on this component.

### Design

```
EventReplayEngine
  .loadEvents(sessionId, { from, to }) -> EventIterator
  .replayThrough(sessionId, handler, { from, to }) -> projectionData
```

### Behavior

1. **Event Discovery**: List all `.json` files in `~/.claude-context/events/{session-id}/`. File names are zero-padded sequence numbers (e.g., `000001.json`, `000042.json`).

2. **Ordering**: Sort files numerically by sequence number (not lexicographically, though zero-padding makes them equivalent for 6-digit numbers).

3. **Range Filtering**: If `from` is specified, skip events with sequence < `from`. If `to` is specified, skip events with sequence > `to`.

4. **Streaming**: Events are read one at a time and passed to the handler function. The engine must NOT load all events into memory simultaneously. For a session with 50,000 events, memory usage should remain bounded (proportional to projection size, not event count).

5. **Event Parsing**: Each event file is parsed as JSON. Fields validated:
   - `event_id` (string, required)
   - `event_type` (string, required)
   - `session_id` (string, required)
   - `sequence` (number, required)
   - `timestamp` (string, required)
   - `data` (object, required)

6. **Error Handling**:
   - **Corrupt JSON file**: Log a warning to stderr with the file path and sequence number. Skip the event. Continue processing.
   - **Missing sequence number**: If expected sequence 5 but next file is 7, log a warning: `"Warning: missing event(s) at sequence 5-6"`. Continue processing from sequence 7.
   - **Missing required fields**: Log a warning. Skip the event if `event_type` or `sequence` is missing. Proceed with partial data if only non-critical fields are missing.
   - **I/O error reading file**: Log an error. If a single file fails, skip it and continue. If the entire directory is unreadable, exit with code 2.

7. **Handler Interface**: Projection handlers implement a simple interface:

```javascript
{
  init: () -> state,              // Initialize projection state
  handle: (state, event) -> state, // Process one event, return updated state
  finalize: (state) -> projection  // Finalize and return the projection data
}
```

### Performance Requirements

- Process 1,000 events in under 2 seconds on standard hardware.
- Process 50,000 events in under 60 seconds.
- Memory usage should not exceed 100MB for any session size (projection data in memory is bounded by the projection itself, not the event count).

### Acceptance Criteria

- [ ] Events are read in strict sequence order.
- [ ] `--from 10 --to 50` only processes events 10 through 50 inclusive.
- [ ] A corrupt JSON file logs a warning and does not halt processing.
- [ ] A missing sequence number logs a warning and continues.
- [ ] Events missing `event_type` or `sequence` are skipped with a warning.
- [ ] The engine does not load all event files into memory at once.
- [ ] A directory with 0 event files produces an empty projection (no error).
- [ ] A directory with 1 event file produces a valid projection.
- [ ] Performance: 1,000 events processed in under 2 seconds.
- [ ] Performance: 50,000 events processed in under 60 seconds.
- [ ] I/O errors on individual files are isolated; the engine continues with remaining files.

---

## 9. Output Formats

### Purpose

Projections are consumed by different clients: machines (JSON), humans (text), and LLMs (markdown). Each format serves a different purpose.

### JSON Format (default)

- Standard JSON output as described in each projection's schema.
- Pretty-printed with 2-space indentation for readability.
- Written to the projection file AND stdout (unless `--output` overrides).

### Text Format (`--format text`)

Human-readable plain text. Each projection has its own text template:

**Timeline (text)**:
```
Timeline for session abc123 (142 events)
=========================================
[001] 2026-02-14T10:00:00.000Z SessionStarted: Session started (model: claude-opus-4-6)
[002] 2026-02-14T10:00:05.000Z UserPromptReceived: User: Fix the failing test...
[003] 2026-02-14T10:00:10.000Z ToolCallRequested: Called Read: file_path=/home/user/project/auth.test.js
...
```

**Files Touched (text)**:
```
Files Touched in session abc123
================================
15 files touched, 6 modified

/home/user/project/src/auth.ts
  - read at seq 5 (2026-02-14T10:00:15.000Z)
  - edit at seq 12 (2026-02-14T10:01:30.000Z)

/home/user/project/auth.test.js
  - read at seq 3 (2026-02-14T10:00:10.000Z)
...
```

**Decisions (text)**:
```
Decisions in session abc123
============================
Group 1: "Fix the failing test in auth.test.js..."
  1. Read /home/user/project/auth.test.js -> Read 45 lines [OK]
  2. Edit /home/user/project/auth.test.js -> File edited [OK]
  3. Bash: npm test -> All 12 tests passed [OK]

Group 2: "Now update the documentation..."
  1. Read /home/user/project/README.md -> Read 120 lines [OK]
  ...
```

**Context (text)**:
```
Context Snapshot for session abc123
====================================
Session: abc123
Started: 2026-02-14T10:00:00.000Z
Model: claude-opus-4-6
Project: /home/user/project

--- User Prompts ---
1. Fix the failing test in auth.test.js that checks token expiry
2. Now run the tests to make sure everything passes

--- Key Tool Calls ---
[3] Read /home/user/project/auth.test.js -> 45 lines
[5] Edit /home/user/project/auth.test.js -> edited
[7] Bash: npm test -> All 12 tests passed

--- Files Modified ---
/home/user/project/src/auth.ts (read, edit)
/home/user/project/auth.test.js (read, edit)

--- Last State ---
Working on: Now run the tests to make sure everything passes
Last tool: Bash: npm test
Last result: All 12 tests passed
```

**Summary (text)**:
```
Session Summary: abc123
========================
Duration: 1h 30m
Events: 142
User Prompts: 5
Tool Calls: 45 (1 failed)
Files Touched: 15 (6 modified)
Agents Spawned: 2
Compactions: 1

This session lasted 1 hour and 30 minutes. The user made 5 requests...
```

### Markdown Format (`--format markdown`)

Formatted for LLM consumption. Uses headers, lists, code blocks, and tables.

**Timeline (markdown)**:
```markdown
# Timeline: Session abc123

**Events:** 142 | **Duration:** 1h 30m

| # | Timestamp | Type | Summary |
|---|-----------|------|---------|
| 1 | 10:00:00 | SessionStarted | Session started (model: claude-opus-4-6) |
| 2 | 10:00:05 | UserPromptReceived | User: Fix the failing test... |
| 3 | 10:00:10 | ToolCallRequested | Called Read: auth.test.js |
```

**Context (markdown)**:
```markdown
# Context: Session abc123

## Session Info
- **ID:** abc123
- **Model:** claude-opus-4-6
- **Project:** /home/user/project
- **Duration:** 1h 30m
- **Events:** 142

## Conversation
### Prompt 1
> Fix the failing test in auth.test.js that checks token expiry

**Actions taken:**
1. Read `auth.test.js` (45 lines)
2. Edit `auth.test.js` (replaced assertion)
3. Bash: `npm test` -> All 12 tests passed

### Prompt 2
> Now update the documentation
...

## Files Modified
- `/home/user/project/src/auth.ts` (read, edit)
- `/home/user/project/auth.test.js` (read, edit)

## Last State
Currently working on: "Now run the tests to make sure everything passes"
Last action: Bash `npm test` -> All 12 tests passed
```

### Acceptance Criteria

- [ ] `--format json` produces valid, pretty-printed JSON to stdout.
- [ ] `--format text` produces clean, readable plain text.
- [ ] `--format markdown` produces well-structured markdown suitable for LLM consumption.
- [ ] All five projection types support all three output formats.
- [ ] JSON is always written to the projection file regardless of `--format`.
- [ ] When `--output -` is used, no file is written; output goes only to stdout.
- [ ] Text and markdown formats do not contain raw JSON structures.
- [ ] Markdown format uses proper markdown syntax (headers, tables, lists, code blocks, blockquotes).

---

## 10. Projection Registry

### Purpose

A pluggable system that makes it straightforward to add new projection types without modifying the core engine. Each projection is a self-contained handler registered in a central registry.

### Design

```javascript
// Registry structure
const projectionRegistry = {
  timeline: {
    name: "timeline",
    description: "Ordered sequence of session events with summaries",
    version: 1,
    outputFile: "timeline.json",
    handler: timelineHandler,   // { init, handle, finalize }
    formatters: {
      json: timelineJsonFormatter,
      text: timelineTextFormatter,
      markdown: timelineMarkdownFormatter
    }
  },
  files: {
    name: "files-touched",
    description: "All files read, written, edited, or searched",
    version: 1,
    outputFile: "files-touched.json",
    handler: filesTouchedHandler,
    formatters: { ... }
  },
  // ... etc
};
```

### Registration Interface

New projections are added by:

1. Creating a handler object with `init`, `handle`, and `finalize` methods.
2. Creating formatter functions for each output format.
3. Registering in the registry with a name, description, version, and output file name.

### Built-in Projections

| CLI Name | Registry Name | Output File |
|---|---|---|
| `timeline` | `timeline` | `timeline.json` |
| `files` | `files-touched` | `files-touched.json` |
| `decisions` | `decisions` | `decisions.json` |
| `context` | `context` | `context.json` |
| `summary` | `summary` | `summary.json` |

### Future Extension Points

The registry is designed to support (but does not need to implement now):

- Custom projections loaded from a user-defined directory (e.g., `~/.claude-context/custom-projections/`).
- A `project --list` command that prints all registered projections.
- Projection dependencies (e.g., summary depends on files-touched counts).

### Acceptance Criteria

- [ ] All five projection types are registered in the projection registry.
- [ ] The `project` CLI command looks up the handler from the registry by name.
- [ ] An unregistered projection name produces a clear error listing available projections.
- [ ] Adding a new projection requires only: creating a handler, creating formatters, and adding one registry entry.
- [ ] The registry contains `name`, `description`, `version`, `outputFile`, `handler`, and `formatters` for each projection.
- [ ] Registry version is used for incremental rebuild version checking.

---

## Edge Cases

### Session with 0 Events

- The event directory exists but contains no `.json` files.
- All projections produce valid output with empty arrays/zero counts.
- Timeline: `{ entries: [] }`
- Files: `{ files: [], stats: { total_files: 0, ... } }`
- Decisions: `{ decision_groups: [], stats: { total_groups: 0, ... } }`
- Context: `{ session: { event_count: 0, ... }, prompts: [], key_tool_calls: [], ... }`
- Summary: `{ event_count: 0, narrative: "This session contained no events." }`
- Exit code: 0 (not an error).

### Very Large Sessions (50K+ Events)

- The event replay engine MUST stream events, not load all into memory.
- File handles must be opened and closed promptly (not held open for the duration).
- Projection state in memory grows with the projection output, not with the event count.
- For the files-touched projection with 10,000 unique files, the projection JSON itself may be large -- this is acceptable.
- For the context projection, the size-aware summarization (Section 5) handles unbounded growth.

### Events with Missing Fields

- If `data` is an empty object `{}`, the handler should not crash.
- If `data.tool_input` is missing from a `ToolCallRequested` event, record the tool call with `input_summary: "(no input data)"`.
- If `data.tool_name` is missing, use `"unknown_tool"`.
- If `timestamp` is missing, use `null` and log a warning.
- Missing fields should never cause the projection to fail entirely.

### Projection Rebuild Interrupted Mid-Way

- Projections are written atomically: write to a temporary file first, then rename to the final path. This ensures a partial write does not corrupt the existing projection.
- If the process is killed mid-rebuild, the old projection file remains intact.
- The next run will detect the stale `_last_sequence` and process events from that point.

### Multiple Projections Requested Simultaneously

- Running `project timeline <session-id>` and `project files <session-id>` in parallel is safe because they write to different files.
- Each projection file is written atomically (temp file + rename).
- No shared mutable state between projection handlers.

### tool_response Containing Binary or Non-JSON Data

- If a tool result contains binary data or is not valid JSON, the output_summary should be: `"(binary or non-JSON data, {byte_count} bytes)"`.
- The projection handler must not attempt to JSON.stringify binary data.
- Check for non-UTF-8 content and handle gracefully.

### Session Directory Missing

- If `~/.claude-context/events/{session-id}/` does not exist, exit with code 1 and message: `"Error: No events found for session {session-id}"`.
- Do not create the directory.

### Projections Directory Does Not Exist

- If `~/.claude-context/projections/{session-id}/` does not exist, create it (including parent directories).
- This is normal for the first projection of a session.

---

## Non-Goals

These are explicitly out of scope for this story:

- **Real-time streaming projections**: Projections are batch-rebuilt on demand. There is no file watcher, no live-updating projection, no event subscription model. This may be added in a future story.
- **Cross-session projections**: This story only handles single-session projections. Projections that span multiple sessions (e.g., "all files I modified this week across all sessions") are a future story.
- **Full-text search over events**: There is no search index, no query language, no grep-over-events capability in the projection engine. A separate `gc-query` tool may provide this in the future.
- **LLM-powered summarization**: All summaries are mechanically generated from templates. No LLM calls are made during projection building. This keeps the projection engine fast, deterministic, and free of external dependencies.
- **Projection deletion or cleanup**: There is no garbage collection for old projection files. This is a future operational concern.
- **Projection diffing**: There is no mechanism to diff two versions of a projection. Future story.

---

## Technical Specifications

### Technology Stack

- **Language**: Node.js (primary) or Bash + jq (fallback for environments without Node)
- **No external dependencies**: Use only Node.js built-in modules (fs, path, crypto, etc.). No npm packages required.
- **JSON processing**: Native `JSON.parse`/`JSON.stringify` in Node.js.
- **File system**: Use `fs.promises` for async file operations in Node.js.

### File Naming Conventions

| File | Purpose |
|---|---|
| `~/.claude-context/bin/project` | CLI entry point (executable) |
| `~/.claude-context/lib/replay-engine.js` | Event replay engine |
| `~/.claude-context/lib/projection-registry.js` | Projection registry |
| `~/.claude-context/lib/projections/timeline.js` | Timeline handler + formatters |
| `~/.claude-context/lib/projections/files-touched.js` | Files touched handler + formatters |
| `~/.claude-context/lib/projections/decisions.js` | Decisions handler + formatters |
| `~/.claude-context/lib/projections/context.js` | Context snapshot handler + formatters |
| `~/.claude-context/lib/projections/summary.js` | Summary handler + formatters |
| `~/.claude-context/lib/formatters.js` | Shared formatting utilities |

### Atomic File Writes

All projection writes must be atomic:

```javascript
const tmpPath = outputPath + '.tmp.' + process.pid;
await fs.writeFile(tmpPath, JSON.stringify(projection, null, 2));
await fs.rename(tmpPath, outputPath);
```

This ensures that a crash during write does not corrupt the existing projection.

### Error Reporting

- Warnings go to stderr (e.g., missing fields, skipped events).
- Projection output goes to stdout.
- Error messages include the session ID and the specific event sequence number when applicable.
- Format: `"[project] WARNING: {message}"` or `"[project] ERROR: {message}"`.

### Testing Strategy

Each component should be testable in isolation:

1. **Event Replay Engine**: Test with a fixture directory containing known event files. Verify ordering, range filtering, error handling.
2. **Individual Projection Handlers**: Test `init -> handle(event1) -> handle(event2) -> finalize` with mock events. Verify output schema.
3. **Formatters**: Test each formatter with known projection data. Verify text and markdown output.
4. **CLI Integration**: Test the full `project` command with a fixture session directory. Verify file output and stdout output for each format.
5. **Incremental Rebuild**: Create a projection, add events, rebuild incrementally, then compare with a full rebuild.
6. **Size-Aware Summarization**: Create a context projection that exceeds 100KB and verify progressive summarization is applied.
7. **Edge Cases**: Test 0-event sessions, missing fields, corrupt files, large sessions.

### Fixture Data

Create a test fixtures directory with:

```
test/fixtures/sessions/
  test-session-001/
    000001.json  # SessionStarted
    000002.json  # UserPromptReceived
    000003.json  # ToolCallRequested (Read)
    000004.json  # ToolCallCompleted (Read)
    000005.json  # ToolCallRequested (Edit)
    000006.json  # ToolCallCompleted (Edit)
    000007.json  # ToolCallRequested (Bash)
    000008.json  # ToolCallCompleted (Bash)
    000009.json  # TurnCompleted
    000010.json  # UserPromptReceived
    000011.json  # ToolCallRequested (Grep)
    000012.json  # ToolCallCompleted (Grep)
    000013.json  # TurnCompleted
    000014.json  # SessionEnded
  test-session-empty/
    (no files)
  test-session-corrupt/
    000001.json  # Valid SessionStarted
    000002.json  # Corrupt JSON (invalid syntax)
    000003.json  # Valid UserPromptReceived
```

---

## Implementation Sequence

The recommended order of implementation:

1. **Event Replay Engine** (Section 8) -- the foundation everything else builds on.
2. **Projection Registry** (Section 10) -- the framework for plugging in handlers.
3. **Timeline Projection** (Section 2) -- the simplest projection, good for validating the engine.
4. **Files Touched Projection** (Section 3) -- exercises file path extraction logic.
5. **Decisions Projection** (Section 4) -- exercises event grouping logic.
6. **Summary Projection** (Section 6) -- exercises aggregation logic.
7. **Context Snapshot Projection** (Section 5) -- the most complex, benefits from patterns established in earlier projections.
8. **Output Formats** (Section 9) -- add text and markdown formatters to all projections.
9. **Incremental Rebuild** (Section 7) -- add incremental support to all projections.
10. **CLI Command** (Section 1) -- wire everything together into the `project` script.

Steps 1-3 can be implemented and tested together as a first deliverable. Steps 4-6 are independent and can be parallelized. Steps 7-10 integrate everything.

---

## Definition of Done

This story is complete when:

- [ ] The `project` CLI command is executable and handles all five projection types.
- [ ] All five projections produce correct output for a test session with at least 14 events covering all event types.
- [ ] All three output formats (json, text, markdown) work for all five projection types.
- [ ] Incremental rebuild works correctly -- adding events and re-projecting produces the same result as a full rebuild.
- [ ] The context projection applies size-aware summarization when exceeding 100KB.
- [ ] Edge cases are handled: 0 events, missing fields, corrupt files, large sessions.
- [ ] Atomic file writes are used for all projection output.
- [ ] Warnings and errors go to stderr; projection output goes to stdout.
- [ ] Test fixtures exist and all handlers pass unit tests.
- [ ] The projection engine processes 1,000 events in under 2 seconds.
- [ ] No external npm dependencies are required.
