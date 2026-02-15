# Implementation Plan: Story 04 -- Projection Engine (CQRS Read Side)

**Story**: 04-projection-engine.md
**Status**: Planning
**Date**: 2026-02-14
**Dependencies**: Stories 01 (Event Capture) and 03 (Storage Layer) must be implemented first.

---

## Review Issues Incorporated

This plan incorporates fixes for four review issues that directly affect Story 04:

| Issue | Title | Integration Point |
|-------|-------|-------------------|
| G-1 | Duplicate event detection by `tool_use_id` | Task 5 (Decisions projection tool-call pairing) and Task 4 (Files Touched dedup) |
| G-2 | Extract file paths from `tool_response` too (Glob/Grep) | Task 4 (Files Touched projection) |
| M-1 | Define projection version 1 explicitly | Task 2 (Projection Registry) |
| M-4 | Support `CLAUDE_CONTEXT_PATH` env var | Task 1 (Base path resolution utility) |

**Design Amendments**: 3 (project-id layer). See `docs/DESIGN-AMENDMENTS.md`.

### Amendment Impacts on This Plan

- **Amendment 3**: `lib/paths.js` path functions gain a `projectId` parameter. `getEventsDir(projectId, sessionId)` returns `{base}/events/{projectId}/{sessionId}`. `getProjectionsDir(projectId, sessionId)` returns `{base}/projections/{projectId}/{sessionId}`. The CLI (`bin/project`) accepts `--project` or infers project-id from the event envelope's `project_id` field. Per-project `latest` symlink at `projections/{projectId}/latest`.

---

## Implementation Tasks

### Task 1: Base Path Resolution and Shared Utilities

**Description**:
Create the shared utility module that all other modules depend on. This module provides the base path for the GlobalContext data directory (respecting the `CLAUDE_CONTEXT_PATH` environment variable per review issue M-4), common path builders for events and projections directories, and small helpers used across projection handlers (timestamp formatting, string truncation, safe JSON parsing).

**Files to create**:
- `/home/meywd/GlobalContext/lib/paths.js` -- Base path resolution, directory helpers
- `/home/meywd/GlobalContext/lib/utils.js` -- String truncation, safe JSON parse, atomic file write, duration formatting

**Key implementation details**:

```javascript
// lib/paths.js
function getBasePath() {
  return process.env.CLAUDE_CONTEXT_PATH || path.join(os.homedir(), '.claude-context');
}

function getEventsDir(sessionId) {
  return path.join(getBasePath(), 'events', sessionId);
}

function getProjectionsDir(sessionId) {
  return path.join(getBasePath(), 'projections', sessionId);
}

function getLatestSymlink() {
  return path.join(getBasePath(), 'projections', 'latest');
}
```

```javascript
// lib/utils.js
function truncate(str, maxLen, suffix = '...') { ... }
function safeJsonParse(content, filePath) { ... }  // returns { ok, data, error }
async function atomicWrite(filePath, data) { ... } // temp file + rename pattern
function formatDuration(seconds) { ... }           // "1h 30m", "5m", "0m"
```

**Dependencies**: None (first task).

**Acceptance test**:
- `CLAUDE_CONTEXT_PATH=/tmp/test-gc node -e "require('./lib/paths').getBasePath()"` returns `/tmp/test-gc`.
- Without the env var, returns `~/.claude-context/`.
- `truncate('hello world', 5)` returns `'hello...'`.
- `formatDuration(5400)` returns `'1h 30m'`.
- `atomicWrite` creates a temp file and renames; if interrupted mid-write, the original file remains.

**Estimated complexity**: S

---

### Task 2: Projection Registry

**Description**:
Create the projection registry that maps CLI projection names to their handlers, formatters, version numbers, and output file names. This is the pluggable framework that all five projection types register into. Each registry entry contains the handler interface (`init`, `handle`, `finalize`), three formatters (`json`, `text`, `markdown`), a version number (explicitly set to `1` per review issue M-1), and the output filename.

The registry also exposes a `listProjections()` function for error messages and a `getProjection(name)` function that returns the full entry or null.

**Files to create**:
- `/home/meywd/GlobalContext/lib/projection-registry.js`

**Key implementation details**:

```javascript
// Explicit version 1 definition (M-1)
const CURRENT_PROJECTION_VERSION = 1;

const registry = {};

function register(cliName, definition) {
  // definition: { name, description, version, outputFile, handler, formatters }
  if (!definition.version) {
    definition.version = CURRENT_PROJECTION_VERSION;
  }
  registry[cliName] = definition;
}

function getProjection(cliName) {
  return registry[cliName] || null;
}

function listProjections() {
  return Object.entries(registry).map(([key, val]) => ({
    cliName: key,
    name: val.name,
    description: val.description,
    version: val.version
  }));
}
```

Define version 1 as: the initial schema as documented in Story 04 sections 2-6. When the schema changes in the future, version increments to 2, and existing projections with version 1 trigger an automatic full rebuild.

**Dependencies**: Task 1 (paths/utils).

**Acceptance test**:
- `listProjections()` returns an array (empty initially, populated after handler registration).
- `getProjection('timeline')` returns the timeline entry after registration, or null before.
- `getProjection('bogus')` returns null.
- Every registered projection has `version: 1` explicitly.

**Estimated complexity**: S

---

### Task 3: Event Replay Engine

**Description**:
Build the core replay engine that reads event files from a session directory, validates them, orders them by sequence number, and streams them one at a time through a projection handler. This is the foundation for all projections.

The engine must NOT load all events into memory. It discovers event files, sorts them by numeric sequence, applies range filtering (`from`/`to`), reads each file one at a time, validates the event envelope, and calls `handler.handle(state, event)`.

The engine must also implement duplicate event detection by `tool_use_id` (review issue G-1). When the engine encounters two events with the same `tool_use_id` and same `event_type`, it keeps the first and skips the duplicate, logging a warning to stderr.

**Files to create**:
- `/home/meywd/GlobalContext/lib/replay-engine.js`

**Key implementation details**:

```javascript
async function replayThrough(sessionId, handler, options = {}) {
  const { from = 1, to = Infinity } = options;
  const eventsDir = getEventsDir(sessionId);

  // 1. Discover event files
  const files = await discoverEventFiles(eventsDir);

  // 2. Sort by numeric sequence
  files.sort((a, b) => a.sequence - b.sequence);

  // 3. Detect gaps and log warnings
  detectSequenceGaps(files);

  // 4. Initialize handler state
  let state = handler.init();

  // 5. Track seen tool_use_ids for duplicate detection (G-1)
  const seenToolUseIds = new Map(); // tool_use_id -> { event_type, sequence }

  // 6. Stream through handler
  for (const file of files) {
    if (file.sequence < from || file.sequence > to) continue;

    const result = safeJsonParse(await fs.readFile(file.path, 'utf-8'), file.path);
    if (!result.ok) {
      warn(`Corrupt JSON at ${file.path}: ${result.error}`);
      continue;
    }

    const event = result.data;

    // Validate required fields
    if (!event.event_type || event.sequence == null) {
      warn(`Missing required fields in ${file.path}, skipping`);
      continue;
    }

    // Duplicate detection by tool_use_id (G-1)
    const toolUseId = event.data?.tool_use_id;
    if (toolUseId) {
      const key = `${toolUseId}:${event.event_type}`;
      if (seenToolUseIds.has(key)) {
        warn(`Duplicate event detected: tool_use_id=${toolUseId}, ` +
             `event_type=${event.event_type} at sequence ${event.sequence} ` +
             `(first seen at sequence ${seenToolUseIds.get(key)}). Skipping.`);
        continue;
      }
      seenToolUseIds.set(key, event.sequence);
    }

    state = handler.handle(state, event);
  }

  // 7. Finalize
  return handler.finalize(state);
}
```

Event file discovery: list directory, filter for `*.json` files, extract sequence number from filename (strip `.json`, parse as integer).

Gap detection: iterate sorted sequences; if `seq[i+1] - seq[i] > 1`, log warning.

**Dependencies**: Task 1 (paths/utils).

**Acceptance test**:
- Given a directory with files `000001.json` through `000014.json`, the engine calls `handler.handle` exactly 14 times in order.
- With `from: 5, to: 10`, handler is called exactly 6 times (sequences 5-10).
- A corrupt JSON file (e.g., `{invalid`) logs a warning to stderr and does not halt processing. Remaining events are processed.
- A missing sequence (1, 2, 4 -- missing 3) logs a gap warning and continues.
- An event missing `event_type` is skipped with a warning.
- Two events with the same `tool_use_id` and `event_type`: only the first is passed to the handler (G-1).
- An empty directory produces zero `handle` calls and returns `handler.finalize(handler.init())`.
- 1,000 event files are processed in under 2 seconds.

**Estimated complexity**: M

---

### Task 4: Files Touched Projection Handler

**Description**:
Implement the files-touched projection handler. This handler tracks every file that was read, written, edited, globbed, or grepped during the session. It extracts file paths from both `tool_input` (the request) and `tool_response` (the result) fields -- the latter being critical for Glob and Grep tools per review issue G-2.

This task is placed before Timeline because it exercises the most complex extraction logic and will surface integration issues with the replay engine early.

**Files to create**:
- `/home/meywd/GlobalContext/lib/projections/files-touched.js`

**Key implementation details**:

Handler state structure:
```javascript
{
  filesMap: {},  // path -> { operations: [], first_touched, last_touched, touch_count }
  stats: { total_files: 0, files_read: 0, files_written: 0, files_edited: 0, files_globbed: 0, files_grepped: 0 }
}
```

Event handling per event type:

1. `ToolCallRequested`: Extract paths from `event.data.tool_input` based on tool name:
   - Read: `tool_input.file_path`
   - Write: `tool_input.file_path`
   - Edit: `tool_input.file_path`
   - NotebookEdit: `tool_input.notebook_path`
   - Glob: Record `tool_input.path` + `tool_input.pattern` as a glob entry
   - Grep: If `tool_input.path` looks like a file (has extension), record it
   - Bash: Best-effort regex extraction for `cat`, `less`, `head`, `tail`, `echo >`, `cp`, `mv`, `rm`

2. `ToolCallCompleted`: Extract paths from `event.data.tool_response` (G-2):
   - Glob: Parse the response for file path lines (one path per line in typical output). Record each matched file as operation type `glob`.
   - Grep: Parse the response for file paths. In `files_with_matches` output mode, each line is a file path. Record each as operation type `grep`.

Deduplication: Files are keyed by absolute path in the `filesMap`. Multiple operations on the same file append to the `operations` array.

Tool-call pairing for response extraction: When processing a `ToolCallCompleted` event, use `tool_use_id` to identify the originating tool. If `tool_use_id` is not present, fall back to the tool_name from the event data.

**Formatters**:
- JSON: Direct serialization of the projection schema.
- Text: Header line with stats, then each file with indented operations.
- Markdown: Table of files with operation counts, then detailed operations list.

**Dependencies**: Task 1 (paths/utils), Task 2 (registry), Task 3 (replay engine).

**Acceptance test**:
- A Read event for `/foo/bar.js` records an entry with operation type `read`.
- A Write event records `write`. An Edit event records `edit`.
- A Glob `ToolCallRequested` records the pattern. A subsequent Glob `ToolCallCompleted` with matched files in `tool_response` records each matched file individually (G-2).
- A Grep `ToolCallCompleted` with file paths in `tool_response` records each file with operation type `grep` (G-2).
- Reading the same file twice produces one file entry with two operations.
- `first_touched` is the earliest timestamp; `last_touched` is the latest; `touch_count` equals the operations array length.
- Stats accurately count unique files per operation type.
- A `ToolCallRequested` with missing `tool_input` logs a warning and does not crash.
- Bash command `cat /etc/hosts` extracts `/etc/hosts` as a `read` operation.
- An unknown tool name does not record any file (no false positives).
- All three output formats produce valid output.

**Estimated complexity**: L

---

### Task 5: Timeline Projection Handler

**Description**:
Implement the timeline projection handler. This is the simplest projection -- one entry per event, in sequence order, with a generated summary string. The summary follows the per-tool templates defined in the story.

**Files to create**:
- `/home/meywd/GlobalContext/lib/projections/timeline.js`

**Key implementation details**:

Handler state:
```javascript
{
  entries: [],
  sessionId: null
}
```

For each event, create a timeline entry:
```javascript
{
  sequence: event.sequence,
  timestamp: event.timestamp,
  event_type: event.event_type,
  summary: generateSummary(event)
}
```

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

Create shared summary generators in a utility module since Decisions and Context projections reuse the same logic.

**Files to create (additional)**:
- `/home/meywd/GlobalContext/lib/summary-generators.js` -- Shared input/output summary functions used by timeline, decisions, and context projections.

**Formatters**:
- JSON: As documented in the schema.
- Text: `[{seq}] {timestamp} {event_type}: {summary}` one per line.
- Markdown: Table with columns #, Timestamp, Type, Summary.

**Dependencies**: Task 1 (paths/utils), Task 2 (registry), Task 3 (replay engine).

**Acceptance test**:
- A 14-event test session produces 14 timeline entries.
- Entries are in sequence order.
- A `UserPromptReceived` with a 300-character prompt is truncated to 200 characters with `...`.
- A `ToolCallRequested` for Read includes `file_path=...` in the summary.
- A `ToolCallRequested` for Bash includes the first 100 characters of the command.
- An unknown event type produces `"{event_type} at sequence {n}"`.
- Text format produces exactly one line per entry.
- Markdown format produces a valid markdown table.
- JSON output matches the documented schema.

**Estimated complexity**: M

---

### Task 6: Decisions Projection Handler

**Description**:
Implement the decisions projection handler. This groups events into decision groups starting at each `UserPromptReceived` and ending at the next `UserPromptReceived`, `TurnCompleted`, or `SessionEnded`. Within each group, tool call requests are paired with their completions using `tool_use_id` (with dedup awareness from G-1, already handled in the replay engine).

**Files to create**:
- `/home/meywd/GlobalContext/lib/projections/decisions.js`

**Key implementation details**:

Handler state:
```javascript
{
  groups: [],
  currentGroup: null,      // The open decision group being built
  pendingToolCalls: {},    // tool_use_id -> { tool_name, input_summary, request_sequence, timestamp }
  groupIdCounter: 0,
  stats: { total_groups: 0, total_actions: 0, failed_actions: 0 }
}
```

Event handling logic:

1. `UserPromptReceived`:
   - If `currentGroup` is open, close it (finalize pending tool calls, compute `all_succeeded`, push to `groups`).
   - Start a new group with `group_id`, `user_prompt`, empty `actions` and `agents_spawned`.

2. `ToolCallRequested`:
   - If no `currentGroup`, skip (events before first prompt are excluded).
   - Store in `pendingToolCalls` keyed by `tool_use_id` (or by sequence if no `tool_use_id`).
   - Add a preliminary action entry to `currentGroup.actions`.

3. `ToolCallCompleted`:
   - Look up matching pending tool call by `tool_use_id`.
   - Update the action entry with `output_summary`, `success: true`, `completion_sequence`.
   - Remove from `pendingToolCalls`.

4. `ToolCallFailed`:
   - Look up matching pending tool call by `tool_use_id`.
   - Update the action entry with error info, `success: false`, `completion_sequence`.
   - Increment `stats.failed_actions`.
   - Remove from `pendingToolCalls`.

5. `TurnCompleted` / `SessionEnded`:
   - Close `currentGroup` (mark any remaining pending tool calls with `success: null`).
   - Set `currentGroup = null`.

6. `AgentSpawned` / `AgentCompleted`:
   - If `currentGroup`, add to `agents_spawned` array.

Tool-call pairing by `tool_use_id`: The `tool_use_id` field in the event data is the canonical key for matching requests to completions. If `tool_use_id` is not present (older events or edge cases), fall back to matching by `tool_name` + sequence proximity (the next completion for the same tool name).

**Formatters**:
- JSON: As documented in the schema.
- Text: Group headers with prompt text, numbered action list with status `[OK]`/`[FAIL]`/`[?]`.
- Markdown: H3 headers per group, blockquoted prompts, numbered action lists.

**Dependencies**: Task 1, Task 2, Task 3, Task 5 (summary-generators.js).

**Acceptance test**:
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

**Estimated complexity**: L

---

### Task 7: Summary Projection Handler

**Description**:
Implement the summary projection handler. This produces aggregate metrics and a mechanically generated narrative paragraph. It counts events by type, tools by name, and computes session duration and other high-level stats.

**Files to create**:
- `/home/meywd/GlobalContext/lib/projections/summary.js`

**Key implementation details**:

Handler state:
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

Event handling: Increment counters based on event type. For `ToolCallRequested`, track tool_name in `toolsUsed`, extract file paths for `filesTouchedSet`/`filesModifiedSet` (Write/Edit go to modified set). For `SessionStarted`, capture start time. For `SessionEnded`, capture end time.

Narrative generation: Assemble from the template defined in the story. No LLM calls. Pure string concatenation.

Duration formatting: Use the `formatDuration` utility. `"0m"` for < 60s, `"5m"` for 300s, `"1h 30m"` for 5400s, `"2h 0m"` for 7200s.

**Formatters**:
- JSON: As documented in the schema.
- Text: Multi-line report with labeled metrics and the narrative paragraph.
- Markdown: Headers, a metrics table, and the narrative.

**Dependencies**: Task 1, Task 2, Task 3.

**Acceptance test**:
- A session with 14 events produces `event_count: 14`.
- `event_breakdown` has correct counts per event type.
- `tools_used` has correct counts per tool name.
- `duration_human` formats correctly for various durations.
- `narrative` is a complete sentence with no template tokens visible.
- A session with only `SessionStarted` produces `event_count: 1`, zero tool calls, and the narrative `"This session contained no events."` equivalent.
- A session with failed tool calls has the failure clause in the narrative.
- A session with agents has the agents clause in the narrative.
- First user prompt hint appears in the narrative.

**Estimated complexity**: M

---

### Task 8: Context Snapshot Projection Handler

**Description**:
Implement the context snapshot projection -- the most complex and most critical projection. This builds the full resumable state: session metadata, all user prompts, summarized tool calls, files modified, agents, last state, and compaction markers. It includes size-aware progressive summarization when the output exceeds 100KB.

**Files to create**:
- `/home/meywd/GlobalContext/lib/projections/context.js`

**Key implementation details**:

Handler state:
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

Event handling:
- `SessionStarted`: Populate `session` metadata (model, cwd, started_at).
- `SessionEnded`: Set `ended_at`, compute `duration_seconds`.
- `UserPromptReceived`: Add to `prompts`, update `lastState.last_user_prompt` and `lastState.working_on`.
- `ToolCallRequested`: Create key tool call entry with `input_summary`. Store in `pendingToolCalls`. Update `lastState.last_tool_call`. Track file in `filesModified` if applicable.
- `ToolCallCompleted`: Find matching request by `tool_use_id`. Generate `output_summary` with size-aware summarization (> 2KB serialized gets compressed). Update `lastState.last_tool_result`.
- `ToolCallFailed`: Similar to completed, but `success: false`.
- `AgentSpawned` / `AgentCompleted`: Track in `agents` array.
- `CompactionTriggered`: Add to `compactionMarkers`.

Output summarization for large tool results (> 2KB serialized):
- Read: `"Read {line_count} lines from {file_path} ({byte_count} bytes)"`
- Bash: `"Command output: {first 200 chars}... ({total_chars} chars total)"`
- Grep: `"{match_count} matches across {file_count} files"`
- Glob: `"{file_count} files matched"`
- Other: `"{first 200 chars}... ({total_chars} chars total)"`

Progressive summarization (post-finalization):
1. Serialize projection, measure `_size_bytes`.
2. If > 100KB, apply phases sequentially, re-measuring after each:
   - Phase 1 (target 80KB): Truncate `output_summary` to 100 chars for all but last 20 tool calls.
   - Phase 2 (target 60KB): Remove Read-only `key_tool_calls` not in last 30 events.
   - Phase 3 (target 50KB): Collapse consecutive Read calls into single entries.
   - Phase 4 (target 40KB): Truncate user prompts (except last 3) to 500 chars.
3. Set `_summarization_applied` array.

**Formatters**:
- JSON: As documented in the schema.
- Text: Sections separated by `---` lines: Session Info, User Prompts, Key Tool Calls, Files Modified, Last State.
- Markdown: H1/H2 headers, blockquoted prompts, code-formatted tool calls, bullet lists for files.

**Dependencies**: Task 1, Task 2, Task 3, Task 5 (summary-generators.js).

**Acceptance test**:
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

**Estimated complexity**: L

---

### Task 9: Output Format System and Shared Formatters

**Description**:
Build the output format dispatch system and any shared formatting utilities that are common across multiple projections. This task wires together the `--format` flag with the per-projection formatters and handles the `--output` flag (default file location, `-` for stdout-only).

While individual projection formatters are created in Tasks 4-8, this task creates the shared infrastructure: the format dispatcher, the file writing logic that respects `--output`, and any shared formatting functions (e.g., table rendering for markdown, header rendering for text).

**Files to create**:
- `/home/meywd/GlobalContext/lib/formatters.js` -- Shared formatting utilities and format dispatch

**Key implementation details**:

```javascript
// Format dispatch
async function outputProjection(projection, projectionDef, options) {
  const { format = 'json', output, quiet = false } = options;

  // Always write JSON to the default projection file (unless --output -)
  if (output !== '-') {
    const jsonPath = output || path.join(getProjectionsDir(projection._session_id), projectionDef.outputFile);
    await mkdirp(path.dirname(jsonPath));
    await atomicWrite(jsonPath, JSON.stringify(projection, null, 2));
  }

  // Format for stdout
  const formatter = projectionDef.formatters[format];
  if (!formatter) {
    throw new Error(`Unknown format: ${format}. Supported: json, text, markdown`);
  }

  const output_str = formatter(projection);
  process.stdout.write(output_str);
  if (!output_str.endsWith('\n')) process.stdout.write('\n');
}
```

Shared formatting helpers:
- `renderTextHeader(title, subtitle)` -- Title with `===` underline.
- `renderMarkdownTable(headers, rows)` -- Pipe-delimited table with alignment row.
- `mkdirp(dir)` -- Recursive directory creation for projections dir.

**Dependencies**: Task 1 (paths/utils), Task 2 (registry).

**Acceptance test**:
- `--format json` produces valid, pretty-printed JSON.
- `--format text` produces clean plain text (no JSON structures).
- `--format markdown` produces valid markdown.
- `--output -` does NOT write a file; output goes only to stdout.
- Default output writes the JSON file AND prints formatted output to stdout.
- The projection directory is created if it does not exist.

**Estimated complexity**: M

---

### Task 10: Incremental Rebuild Logic

**Description**:
Add incremental rebuild support to the replay engine and all projection handlers. When a projection file already exists and `--rebuild` is not set, the engine reads the existing projection, extracts `_last_sequence`, and only replays events after that sequence. Each projection handler implements a merge strategy that integrates new events into the existing projection state.

Also implement the version check: if the existing projection's `_projection_version` does not match the current handler's version (defined in the registry per M-1), automatically trigger a full rebuild.

**Files to modify**:
- `/home/meywd/GlobalContext/lib/replay-engine.js` -- Add `loadExistingProjection`, `shouldRebuild`, sequence range detection
- `/home/meywd/GlobalContext/lib/projections/timeline.js` -- Add merge: append new entries
- `/home/meywd/GlobalContext/lib/projections/files-touched.js` -- Add merge: upsert file entries, recompute stats
- `/home/meywd/GlobalContext/lib/projections/decisions.js` -- Add merge: extend last open group or append new groups
- `/home/meywd/GlobalContext/lib/projections/context.js` -- Add merge: append prompts/tool calls/files, rebuild last_state
- `/home/meywd/GlobalContext/lib/projections/summary.js` -- Add merge: recount all metrics, regenerate narrative

**Key implementation details**:

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

Merge strategies per projection (as documented in the story):
| Projection | Strategy |
|------------|----------|
| Timeline | Append new entries to `entries` array |
| Files Touched | Upsert into `filesMap`, recompute stats |
| Decisions | Extend last open group if applicable, else append new groups |
| Context | Append to all arrays, fully rebuild `last_state` from tail |
| Summary | Recount all metrics, regenerate narrative |

**Dependencies**: Task 3 (replay engine), Tasks 4-8 (all projection handlers).

**Acceptance test**:
- Running a projection twice with no new events returns identical output (no unnecessary file write).
- Adding 10 new events and re-projecting only processes those 10 events.
- `_last_sequence` in the output matches the highest event processed.
- `_rebuilt_at` is updated on every successful run.
- `--rebuild` flag causes full reprocessing.
- Projection version mismatch triggers automatic full rebuild with a warning.
- Incremental rebuild produces identical results to a full rebuild for the same event range.

**Estimated complexity**: L

---

### Task 11: CLI Entry Point (`project` Script)

**Description**:
Create the `project` CLI entry point script that parses arguments, resolves the session ID (including `latest` symlink), validates inputs, and orchestrates the replay engine, projection handlers, and output formatters. This is the top-level integration that wires all components together.

**Files to create**:
- `/home/meywd/GlobalContext/bin/project` -- Executable Node.js script with shebang line

**Key implementation details**:

```javascript
#!/usr/bin/env node
'use strict';

const { parseArgs } = require('./lib/cli-parser');  // or inline parsing
const { getProjection, listProjections } = require('./lib/projection-registry');
const { buildProjection } = require('./lib/replay-engine');
const { outputProjection } = require('./lib/formatters');
const { getBasePath, getEventsDir, getLatestSymlink } = require('./lib/paths');
```

Argument parsing (no external dependencies -- use simple argv parsing):
```
project <projection-type> <session-id> [options]

Options:
  --from <n>        Start sequence (default: 1)
  --to <n>          End sequence (default: last)
  --rebuild         Force full rebuild
  --format <fmt>    json | text | markdown (default: json)
  --output <path>   Output path, use - for stdout only
  --quiet           Suppress stderr messages
```

Flow:
1. Parse args. If none provided, print usage and exit 1.
2. Validate `projection-type` against registry. If unknown, print error listing available types and exit 1.
3. Resolve `session-id`. If `latest`, read symlink at `~/.claude-context/projections/latest`. If symlink missing, exit 1 with message.
4. Validate event directory exists. If not, exit 1 with message.
5. Call `buildProjection(sessionId, projectionDef, options)`.
6. Call `outputProjection(projection, projectionDef, options)`.
7. Exit 0 on success, 2 on replay error.

Error output format: `[project] ERROR: {message}` to stderr.
Warning output format: `[project] WARNING: {message}` to stderr.

**Dependencies**: Task 1, Task 2, Task 3, Task 9 (formatters), Task 10 (incremental rebuild), all projection handlers (Tasks 4-8).

**Acceptance test**:
- `project timeline <session-id>` produces a timeline and writes it to the correct path.
- `project files <session-id>` produces a files-touched projection.
- `project decisions <session-id>` produces a decisions projection.
- `project context <session-id>` produces a context snapshot.
- `project summary <session-id>` produces a summary.
- `project timeline latest` resolves the symlink.
- `project timeline <session-id> --from 10 --to 50` limits the event range.
- `project timeline <session-id> --rebuild` forces a full rebuild.
- `project timeline <session-id> --format text` outputs plain text.
- `project timeline <session-id> --format markdown` outputs markdown.
- `project timeline <session-id> --output -` writes only to stdout.
- `project` with no arguments prints usage help and exits 1.
- `project bogus <session-id>` prints error about unknown type and exits 1.
- `project timeline nonexistent-session` prints error and exits 1.
- Exit code 0 on success, 1 on bad args, 2 on replay errors.

**Estimated complexity**: M

---

### Task 12: Test Fixtures and Integration Tests

**Description**:
Create the test fixture data and integration test suite that validates the entire projection engine end-to-end. This includes fixture event files for a standard test session, an empty session, and a session with corrupt data. Integration tests run the `project` CLI against these fixtures and verify output schemas, content accuracy, format correctness, incremental rebuild equivalence, and edge case handling.

**Files to create**:
- `/home/meywd/GlobalContext/test/fixtures/sessions/test-session-001/000001.json` through `000014.json` -- Standard 14-event test session covering all event types
- `/home/meywd/GlobalContext/test/fixtures/sessions/test-session-empty/` -- Empty directory
- `/home/meywd/GlobalContext/test/fixtures/sessions/test-session-corrupt/000001.json` -- Valid SessionStarted
- `/home/meywd/GlobalContext/test/fixtures/sessions/test-session-corrupt/000002.json` -- Corrupt JSON
- `/home/meywd/GlobalContext/test/fixtures/sessions/test-session-corrupt/000003.json` -- Valid UserPromptReceived
- `/home/meywd/GlobalContext/test/fixtures/sessions/test-session-duplicate/` -- Session with duplicate `tool_use_id` events (for G-1 testing)
- `/home/meywd/GlobalContext/test/fixtures/sessions/test-session-glob-grep/` -- Session with Glob/Grep tool calls that have matched files in `tool_response` (for G-2 testing)
- `/home/meywd/GlobalContext/test/test-projections.js` -- Integration test runner

**Fixture event data (test-session-001)**:

| Sequence | Event Type | Key Data |
|----------|------------|----------|
| 1 | SessionStarted | model: claude-opus-4-6, cwd: /home/user/project |
| 2 | UserPromptReceived | "Fix the failing test in auth.test.js" |
| 3 | ToolCallRequested | Read, file_path: /home/user/project/auth.test.js, tool_use_id: "tu_001" |
| 4 | ToolCallCompleted | Read result, 45 lines, tool_use_id: "tu_001" |
| 5 | ToolCallRequested | Edit, file_path: /home/user/project/auth.test.js, tool_use_id: "tu_002" |
| 6 | ToolCallCompleted | Edit success, tool_use_id: "tu_002" |
| 7 | ToolCallRequested | Bash, command: "npm test", tool_use_id: "tu_003" |
| 8 | ToolCallCompleted | Bash, exit_code: 0, stdout: "All 12 tests passed", tool_use_id: "tu_003" |
| 9 | TurnCompleted | |
| 10 | UserPromptReceived | "Now search for any other expiry-related tests" |
| 11 | ToolCallRequested | Grep, pattern: "expiry", path: /home/user/project, tool_use_id: "tu_004" |
| 12 | ToolCallCompleted | Grep, 3 matches in 2 files, tool_use_id: "tu_004" |
| 13 | TurnCompleted | |
| 14 | SessionEnded | |

**Test cases**:

1. **Schema validation**: Each projection output has all required fields from the documented schema.
2. **Timeline accuracy**: 14 entries, correct summaries, correct order.
3. **Files Touched accuracy**: auth.test.js has read + edit operations; grep results include matched files.
4. **Decisions accuracy**: 2 groups; first group has 3 actions (Read, Edit, Bash); second group has 1 action (Grep).
5. **Summary accuracy**: event_count=14, tools_used includes Read, Edit, Bash, Grep.
6. **Context accuracy**: 2 prompts, tool calls paired, last_state reflects last tool call.
7. **Empty session**: All projections produce valid empty output, exit code 0.
8. **Corrupt session**: Corrupt event skipped with warning, valid events processed.
9. **Duplicate events (G-1)**: Duplicate `tool_use_id` events are deduplicated; only one is processed.
10. **Glob/Grep response extraction (G-2)**: Files from `tool_response` are recorded in files-touched.
11. **Format outputs**: JSON, text, and markdown validated for each projection type.
12. **Incremental rebuild**: Build projection, add 2 events, rebuild incrementally, compare with full rebuild.
13. **Range filtering**: `--from 5 --to 10` produces only events 5-10.
14. **CLAUDE_CONTEXT_PATH**: Setting the env var changes the base path for all operations.
15. **Version mismatch**: Modify `_projection_version` in a saved projection; verify auto-rebuild.
16. **Performance**: 1,000-event session processed in under 2 seconds.

**Dependencies**: All previous tasks (1-11).

**Acceptance test**:
- All test cases pass.
- Fixture data files are valid JSON with correct event envelope schema.
- Tests can be run with `node test/test-projections.js` (no npm dependencies).
- Tests report pass/fail with clear messages.

**Estimated complexity**: L

---

## Task Dependency Graph

```
Task 1 (Paths/Utils)
  |
  +---> Task 2 (Registry) --------+
  |                                |
  +---> Task 3 (Replay Engine) ---+---> Task 4  (Files Touched)
                                   |
                                   +---> Task 5  (Timeline + Summary Generators)
                                   |       |
                                   |       +---> Task 6  (Decisions)
                                   |       |
                                   |       +---> Task 8  (Context Snapshot)
                                   |
                                   +---> Task 7  (Summary)
                                   |
                                   +---> Task 9  (Output Format System)
                                   |
                                   +--- All handlers ---+
                                                        |
                                                        v
                                                  Task 10 (Incremental Rebuild)
                                                        |
                                                        v
                                                  Task 11 (CLI Entry Point)
                                                        |
                                                        v
                                                  Task 12 (Test Fixtures + Integration)
```

## Recommended Implementation Order

| Phase | Tasks | Deliverable |
|-------|-------|-------------|
| Phase A: Foundation | 1, 2, 3 | Replay engine and registry ready; can stream events through a handler |
| Phase B: Core Projections | 4, 5 (parallel) | Timeline and Files Touched projections working end-to-end |
| Phase C: Advanced Projections | 6, 7 (parallel) | Decisions and Summary projections working |
| Phase D: Context + Formats | 8, 9 | Context Snapshot with size management; all output formats |
| Phase E: Integration | 10, 11 | Incremental rebuild and CLI wiring |
| Phase F: Validation | 12 | Full test suite with fixtures and edge cases |

## Summary of Review Issue Resolutions

### G-1: Duplicate Event Detection by `tool_use_id`
- **Where**: Task 3 (Replay Engine), lines in the duplicate detection block
- **How**: The replay engine maintains a `Map<string, number>` keyed by `"${tool_use_id}:${event_type}"`. When a duplicate key is encountered, the event is skipped and a warning is logged to stderr.
- **Why at engine level**: Deduplication at the engine level means all projections benefit automatically without each handler implementing its own logic.

### G-2: Extract File Paths from `tool_response` for Glob/Grep
- **Where**: Task 4 (Files Touched projection handler)
- **How**: When processing `ToolCallCompleted` events for Glob and Grep tools, the handler parses `event.data.tool_response` (or `event.data.result`) for file paths and records each as an individual file operation.
- **Glob response parsing**: Split response by newlines, treat each non-empty line as a file path.
- **Grep response parsing**: In `files_with_matches` mode, each line is a file path. In `content` mode, extract file paths from `filename:line:content` format.

### M-1: Define Projection Version 1 Explicitly
- **Where**: Task 2 (Projection Registry)
- **How**: A `CURRENT_PROJECTION_VERSION` constant is set to `1`. Each registry entry explicitly includes `version: 1`. The incremental rebuild logic (Task 10) compares the stored `_projection_version` against the registry's `version` and triggers a full rebuild on mismatch.
- **Version 1 definition**: The initial schema as documented in Story 04, sections 2-6. Future schema changes increment the version.

### M-4: Support `CLAUDE_CONTEXT_PATH` Environment Variable
- **Where**: Task 1 (Base Path Resolution)
- **How**: The `getBasePath()` function checks `process.env.CLAUDE_CONTEXT_PATH` first, falling back to `~/.claude-context/`. All path construction flows through this function.
- **Propagation**: Every module that needs a path imports from `lib/paths.js`, ensuring consistent behavior. The CLI (Task 11) does not need special handling -- it inherits from the shared module.

---

## File Inventory

### Files to Create

| File | Task | Purpose |
|------|------|---------|
| `lib/paths.js` | 1 | Base path resolution, directory helpers |
| `lib/utils.js` | 1 | String truncation, safe JSON, atomic write, duration formatting |
| `lib/projection-registry.js` | 2 | Projection type registry |
| `lib/replay-engine.js` | 3 | Event replay engine with streaming and dedup |
| `lib/projections/files-touched.js` | 4 | Files touched handler + formatters |
| `lib/projections/timeline.js` | 5 | Timeline handler + formatters |
| `lib/summary-generators.js` | 5 | Shared summary generation for tool inputs/outputs |
| `lib/projections/decisions.js` | 6 | Decisions handler + formatters |
| `lib/projections/summary.js` | 7 | Summary handler + formatters |
| `lib/projections/context.js` | 8 | Context snapshot handler + formatters |
| `lib/formatters.js` | 9 | Shared formatting utilities, format dispatch |
| `bin/project` | 11 | CLI entry point (executable) |
| `test/fixtures/sessions/test-session-001/*.json` | 12 | 14-event standard test session |
| `test/fixtures/sessions/test-session-empty/` | 12 | Empty session directory |
| `test/fixtures/sessions/test-session-corrupt/*.json` | 12 | Corrupt data test session |
| `test/fixtures/sessions/test-session-duplicate/*.json` | 12 | Duplicate event test session (G-1) |
| `test/fixtures/sessions/test-session-glob-grep/*.json` | 12 | Glob/Grep response test session (G-2) |
| `test/test-projections.js` | 12 | Integration test runner |

All file paths above are relative to `/home/meywd/GlobalContext/`. The `bin/project` script will be symlinked or copied to `~/.claude-context/bin/project` during installation (handled by a separate install story).

---

## Estimated Total Effort

| Complexity | Count | Estimate per task | Subtotal |
|------------|-------|-------------------|----------|
| S | 2 | 1-2 hours | 2-4 hours |
| M | 5 | 3-5 hours | 15-25 hours |
| L | 5 | 6-10 hours | 30-50 hours |
| **Total** | **12** | | **47-79 hours** |
