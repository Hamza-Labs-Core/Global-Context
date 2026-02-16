# Projections

Projections are materialized views built by replaying events from the event store. They transform raw event streams into structured, queryable formats optimized for different use cases.

## Table of Contents

- [What are Projections](#what-are-projections)
- [Projection Types](#projection-types)
- [Building Projections](#building-projections)
- [Incremental Rebuild](#incremental-rebuild)
- [Progressive Summarization](#progressive-summarization)
- [Output Formats](#output-formats)
- [Cache and Invalidation](#cache-and-invalidation)

## What are Projections

### Core Concept

Projections are **derived data** - they contain no information that doesn't exist in the event store. They can always be rebuilt from events by replaying the event stream through projection handlers.

### Why Projections

Without projections, answering questions like "what files did I modify?" would require:
1. Reading every event file
2. Parsing each JSON envelope
3. Inspecting each `data` payload
4. Filtering and aggregating on the fly

Projections pre-compute these answers so queries are instant.

### Rebuilding

Because projections are derived data:
- **Rebuildable**: Can be regenerated from events at any time
- **Disposable**: Can be deleted without data loss
- **Versioned**: Schema changes trigger automatic rebuild
- **Incremental**: Only new events processed by default

### Event Replay Engine

All projections share a common event replay engine:

```
1. Load existing projection (if any) to get _last_sequence
2. Scan event directory for events > _last_sequence
3. Stream events through projection handler
4. Handler processes each event, updating state
5. Finalize projection and write atomically
6. Update _last_sequence metadata
```

**Performance**:
- 1,000 events: < 2 seconds
- 50,000 events: < 60 seconds
- Memory: Bounded by projection size, not event count

## Projection Types

GlobalContext supports five projection types, each optimized for specific query patterns.

### Summary Table

| Projection | File | Purpose | Size | Rebuild Speed |
|------------|------|---------|------|---------------|
| [Timeline](#timeline-projection) | timeline.json | Chronological event log | Small | Fast |
| [Files Touched](#files-touched-projection) | files-touched.json | File interaction tracking | Medium | Fast |
| [Decisions](#decisions-projection) | decisions.json | Intent-to-action chains | Medium | Medium |
| [Summary](#summary-projection) | summary.json | High-level metrics | Tiny | Fast |
| [Context](#context-projection) | context.json | Full session recovery | Large | Slow |

### When to Use Each

| Use Case | Projection |
|----------|------------|
| "What happened in this session?" | Timeline |
| "What files did I touch?" | Files Touched |
| "Why did I make this change?" | Decisions |
| "Quick session overview" | Summary |
| "Resume work from last session" | Context |
| "Debug a specific sequence of events" | Timeline |
| "Find all edits to auth.ts" | Files Touched |

## Timeline Projection

### Purpose

Chronological log of session activity. One-liner summary for each event, suitable for scanning or replaying.

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
      "summary": "User: Fix the failing test in auth.test.js..."
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

| Event Type | Template |
|------------|----------|
| SessionStarted | `"Session started (model: {model}, cwd: {cwd})"` |
| UserPromptReceived | `"User: {first 200 chars of prompt}..."` |
| ToolCallRequested | `"Called {tool_name}: {input_summary}"` |
| ToolCallCompleted | `"Result from {tool_name}: {output_summary}"` |
| ToolCallFailed | `"FAILED {tool_name}: {error message, first 150 chars}"` |
| AgentSpawned | `"Spawned {agent_type} agent"` |
| AgentCompleted | `"Agent completed: {agent_type}"` |
| TurnCompleted | `"Turn completed"` |
| CompactionTriggered | `"COMPACTION triggered ({trigger})"` |
| SessionEnded | `"Session ended ({reason})"` |

### Tool Input Summaries

| Tool | Summary Format |
|------|----------------|
| Read | `"file_path={path}"` |
| Write | `"file_path={path} ({size} chars)"` |
| Edit | `"file_path={path} replacing {old_size} chars"` |
| Bash | `"command={first 100 chars}"` |
| Glob | `"pattern={pattern} path={path}"` |
| Grep | `"pattern={pattern} path={path}"` |

### Tool Output Summaries

| Tool | Summary Format |
|------|----------------|
| Read | `"Read {line_count} lines"` |
| Write | `"Wrote {size} chars"` |
| Edit | `"Edited {path}"` |
| Bash | `"Exit code {code}, output: {first 100 chars}"` |
| Glob | `"{count} files matched"` |
| Grep | `"{count} matches found"` |

### Text Format

```
Timeline for session abc123 (142 events)
=========================================
[001] 2026-02-14T10:00:00Z SessionStarted: Session started (model: claude-opus-4-6)
[002] 2026-02-14T10:00:05Z UserPromptReceived: User: Fix the failing test...
[003] 2026-02-14T10:00:10Z ToolCallRequested: Called Read: file_path=auth.test.js
```

### Markdown Format

```markdown
# Timeline: Session abc123

**Events:** 142 | **Duration:** 1h 30m

| # | Timestamp | Type | Summary |
|---|-----------|------|---------|
| 1 | 10:00:00 | SessionStarted | Session started |
| 2 | 10:00:05 | UserPromptReceived | User: Fix the failing test... |
| 3 | 10:00:10 | ToolCallRequested | Called Read: auth.test.js |
```

### Use Cases

- Replay session activity
- Debug event sequences
- Understand session flow
- Audit what happened

## Files Touched Projection

### Purpose

Comprehensive list of all files read, written, edited, globbed, or grepped. Answers "what files did the LLM interact with?"

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

### File Path Extraction

Paths extracted from tool calls:

| Tool | Source | Operation Type |
|------|--------|----------------|
| Read | `tool_input.file_path` | `read` |
| Write | `tool_input.file_path` | `write` |
| Edit | `tool_input.file_path` | `edit` |
| Glob | Matched files from result | `glob` |
| Grep | `tool_input.path` or matched files | `grep` |
| NotebookEdit | `tool_input.notebook_path` | `edit` |
| Bash | Best-effort extraction from command | varies |

### Deduplication

Files deduplicated by absolute path:
- Same file touched multiple times: all operations listed in `operations` array
- Operations ordered by sequence number
- Summary fields: `first_touched`, `last_touched`, `touch_count`

### Text Format

```
Files Touched in session abc123
================================
15 files touched, 6 modified

/home/user/project/src/auth.ts
  - read at seq 5 (2026-02-14T10:00:15Z)
  - edit at seq 12 (2026-02-14T10:01:30Z)

/home/user/project/auth.test.js
  - read at seq 3 (2026-02-14T10:00:10Z)
```

### Use Cases

- Track file changes
- Identify modified files
- Audit file access
- Generate commit messages

## Decisions Projection

### Purpose

Captures "intent to action" chains by linking user prompts to resulting tool calls. Answers "WHY did things happen?"

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
          "input_summary": "Edit auth.test.js, replacing assertion",
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

1. New group starts on `UserPromptReceived`
2. All subsequent tool calls belong to this group
3. Group ends on:
   - Next `UserPromptReceived`
   - `TurnCompleted`
   - `SessionEnded`
   - End of stream

### Action Pairing

- `ToolCallRequested` matched to `ToolCallCompleted`/`ToolCallFailed`
- Matched by `tool_use_id` or sequence proximity
- Unpaired requests: `success: null`, `output_summary: "(no completion)"`

### Agent Tracking

If `AgentSpawned`/`AgentCompleted` events fall within group:

```json
{
  "agents_spawned": [
    {
      "agent_type": "code-review",
      "spawn_sequence": 10,
      "completion_sequence": 15,
      "status": "completed"
    }
  ]
}
```

### Text Format

```
Decisions in session abc123
============================
Group 1: "Fix the failing test in auth.test.js..."
  1. Read /home/user/project/auth.test.js -> Read 45 lines [OK]
  2. Edit auth.test.js -> File edited [OK]
  3. Bash: npm test -> All 12 tests passed [OK]

Group 2: "Now update the documentation..."
  1. Read README.md -> Read 120 lines [OK]
```

### Use Cases

- Understand decision rationale
- Link prompts to outcomes
- Track successful vs failed actions
- Generate change summaries

## Summary Projection

### Purpose

High-level overview of session metrics and natural language narrative. Quick orientation.

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
    "TurnCompleted": 5,
    "SessionEnded": 1
  },

  "tools_used": {
    "Read": 15,
    "Bash": 12,
    "Edit": 8,
    "Grep": 5,
    "Write": 3,
    "Glob": 2
  },

  "files_touched_count": 15,
  "files_modified_count": 6,
  "user_prompts_count": 5,
  "compaction_count": 1,

  "narrative": "This session lasted 1 hour and 30 minutes. The user made 5 requests, primarily focused on fixing auth token expiry tests. The LLM used 45 tool calls across 6 different tools (Read: 15, Bash: 12, Edit: 8, Grep: 5, Write: 3, Glob: 2). 15 files were touched, 6 were modified. 1 compaction event occurred. 1 tool call failed."
}
```

### Narrative Generation

Narrative is template-based (not LLM-generated):

```
This session lasted {duration}. The user made {prompt_count} request(s){topic_hint}. The LLM used {tool_call_count} tool calls across {tool_type_count} different tools ({tool_list}). {files_touched} files were touched, {files_modified} were modified. {agents_clause}{compaction_clause}{failure_clause}
```

Where:
- `{topic_hint}`: `, starting with "{first 80 chars of first prompt}..."` (if available)
- `{tool_list}`: `"ToolName: count"` sorted by count descending
- `{agents_clause}`: `"{count} sub-agent(s) were spawned. "` (if any)
- `{compaction_clause}`: `"{count} compaction event(s) occurred. "` (if any)
- `{failure_clause}`: `"{count} tool call(s) failed."` (if any)

### Duration Formatting

| Actual | Formatted |
|--------|-----------|
| 30 seconds | `0m` |
| 5 minutes | `5m` |
| 90 minutes | `1h 30m` |
| 2 hours | `2h 0m` |
| 3.5 hours | `3h 30m` |

### Text Format

```
Session Summary: abc123
========================
Duration: 1h 30m
Events: 142
User Prompts: 5
Tool Calls: 45 (1 failed)
Files Touched: 15 (6 modified)
Compactions: 1

This session lasted 1 hour and 30 minutes...
```

### Use Cases

- Quick session overview
- Session listings
- Dashboards
- Session selection

## Context Projection

### Purpose

THE critical projection. Full session context for recovery. Everything needed to resume work in a new session.

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

#### Session Metadata

| Field | Source |
|-------|--------|
| `id` | session_id from envelope |
| `started_at` | SessionStarted timestamp |
| `ended_at` | SessionEnded timestamp (null if active) |
| `model` | SessionStarted data.model |
| `project_directory` | SessionStarted data.cwd |
| `duration_seconds` | Computed from timestamps |
| `event_count` | Total events |

#### All User Prompts

- Every `UserPromptReceived` prompt
- Full text (not truncated)
- Sequence order
- Lets LLM understand conversation flow

#### Key Tool Calls

- All tool request/completion pairs
- Input and output summaries
- Large outputs (>2KB) summarized:
  - Read: `"Read {line_count} lines ({byte_count} bytes)"`
  - Bash: `"Command output: {first 200 chars}... ({total} total)"`
  - Grep: `"{match_count} matches across {file_count} files"`

#### Files Modified

- Derived from files-touched projection
- Simplified: path, operation types, last operation
- Compact reference

#### Last State

| Field | Source |
|-------|--------|
| `last_user_prompt` | Last UserPromptReceived |
| `last_tool_call` | Last ToolCallRequested |
| `last_tool_result` | Last ToolCallCompleted |
| `working_on` | Last prompt (first 100 chars) |

#### Compaction Markers

- Every `CompactionTriggered` event
- Marks where context was compressed
- Critical for understanding completeness

### Size-Aware Summarization

If projection exceeds 100KB, progressive summarization is applied:

**Phase 1** (target: 80KB):
- Truncate `output_summary` in `key_tool_calls` to 100 chars (except last 20)

**Phase 2** (target: 60KB):
- Remove Read-only tool calls (except last 30 events)
- Keep Write, Edit, Bash, and recent entries

**Phase 3** (target: 50KB):
- Collapse consecutive Read calls: `"Read {count} files: {list}"`

**Phase 4** (target: 40KB):
- Truncate user prompts (except last 3) to 500 chars

After each phase, re-measure and stop when below target.

`_summarization_applied` field lists phases used: `["phase1", "phase2"]`

### Markdown Format

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

## Files Modified
- `/home/user/project/src/auth.ts` (read, edit)
- `/home/user/project/auth.test.js` (read, edit)

## Last State
Currently working on: "Now run the tests to make sure everything passes"
Last action: Bash `npm test` -> All 12 tests passed
```

### Use Cases

- Resume work after compaction
- Start new session with full context
- Understand what was accomplished
- LLM context injection

## Building Projections

### Using project Command

```bash
# Build specific projection
project context abc123

# Build for latest session
project timeline latest

# Force rebuild from scratch
project context abc123 --rebuild

# Build partial (sequences 10-50)
project timeline abc123 --from 10 --to 50

# Output to stdout
project context latest --format markdown --output -
```

### Using gc-query

Most gc-query commands automatically build projections:

```bash
# Builds context projection if stale
gc-query last

# Builds timeline projection
gc-query replay abc123

# Does NOT build projections (raw events)
gc-query events abc123
```

### Build Triggers

Projections built or updated when:
- Explicitly requested via `project` command
- gc-query command needs projection and it's stale
- New events exist since `_last_sequence`
- Projection file missing
- `--rebuild` flag used
- Projection version changed

## Incremental Rebuild

### How It Works

1. Load existing projection file
2. Read `_last_sequence` metadata
3. Scan event directory for events > `_last_sequence`
4. If no new events: return existing projection
5. If new events: replay only new events through handler
6. Merge results into existing projection
7. Update `_last_sequence` and `_rebuilt_at`
8. Write atomically

### Merge Strategies

| Projection | Strategy |
|------------|----------|
| Timeline | Append new entries to `entries` array |
| Files Touched | Append operations to existing files or create new entries |
| Decisions | Extend last open group or append new groups |
| Context | Rebuild `last_state`, append to prompts/tool_calls/files |
| Summary | Recompute all metrics from merged data |

### Performance

Incremental rebuild for 10 new events:
- Timeline: < 100ms
- Files Touched: < 100ms
- Decisions: < 200ms
- Summary: < 100ms
- Context: < 200ms

Full rebuild for 1000 events:
- Timeline: < 1s
- Files Touched: < 1s
- Decisions: < 2s
- Summary: < 500ms
- Context: < 2s

### Version Changes

If `_projection_version` doesn't match handler version:
- Automatic full rebuild triggered
- Ensures schema migrations happen transparently

## Progressive Summarization

### Tiers (Context Projection Only)

Context projection uses progressive summarization to keep size manageable:

| Tier | Target Size | Actions |
|------|-------------|---------|
| Full | < 100KB | No summarization |
| Phase 1 | < 80KB | Truncate old tool outputs |
| Phase 2 | < 60KB | Remove Read-only ops |
| Phase 3 | < 50KB | Collapse consecutive Reads |
| Phase 4 | < 40KB | Truncate old prompts |

### Metadata

```json
{
  "_size_bytes": 45230,
  "_summarization_applied": ["phase1", "phase2"]
}
```

## Output Formats

All projections support multiple output formats.

### JSON Format

```bash
project timeline abc123 --format json
```

- Pretty-printed with 2-space indentation
- Machine-readable
- Written to projection file
- Output to stdout

### Text Format

```bash
gc-query replay abc123 --format text
```

- Human-readable plain text
- Tables, lists, sections
- No JSON structures
- Output to stdout

### Markdown Format

```bash
gc-query last --format markdown
```

- Well-structured markdown
- Headers, lists, code blocks, tables
- LLM-friendly
- Output to stdout

### Compact Format

```bash
gc-query last --format compact
```

- Minimal text, no decorations
- Quick context checks
- Output to stdout
- Truncated at 200KB

### Format Support

| Projection | JSON | Text | Markdown | Compact |
|------------|------|------|----------|---------|
| Timeline | Yes | Yes | Yes | No |
| Files Touched | Yes | Yes | Yes | No |
| Decisions | Yes | Yes | Yes | No |
| Summary | Yes | Yes | Yes | No |
| Context | Yes | Yes | Yes | Yes |

## Cache and Invalidation

### Storage Location

```
~/.claude-context/projections/{project-id}/{session-id}/{projection}.json
```

Example:
```
~/.claude-context/projections/my-project-a3f7b2/abc123/context.json
```

### Invalidation Rules

Projection is stale if:
- `_last_sequence` < highest event sequence in session directory
- Projection file doesn't exist
- Projection version doesn't match handler version
- `--rebuild` flag used

### Atomic Writes

All projections written atomically:

```bash
# Write to temp file
{projection}.json.tmp.{pid}

# Atomic rename
mv {projection}.json.tmp.{pid} {projection}.json
```

Ensures partial writes don't corrupt existing projections.

### Manual Cache Management

```bash
# Force rebuild
project context abc123 --rebuild

# Delete projection (will rebuild on next query)
rm ~/.claude-context/projections/my-project-a3f7b2/abc123/context.json

# Delete all projections for session
rm -rf ~/.claude-context/projections/my-project-a3f7b2/abc123/

# Clear all projection cache
rm -rf ~/.claude-context/projections/
```

### Performance Tips

- Let incremental rebuild work (don't use --rebuild unless needed)
- Use --from/--to to query specific ranges
- Delete old projection files if disk space is a concern
- Projections are disposable (safe to delete)

## Related Documentation

- [Event Types](Event-Types.md) - Events that projections consume
- [CLI Reference](CLI-Reference.md) - Commands that build projections
- [Architecture](Architecture.md) - Event replay engine design
- [Development](Development.md) - Adding custom projections
