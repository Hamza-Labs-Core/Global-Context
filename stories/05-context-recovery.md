# Story 05: Context Recovery & Retrieval

## Overview

Context Recovery is the payoff of the entire GlobalContext system. Every preceding component -- event capture, storage, projections, session tracking -- exists so that this component can deliver on a single promise: **no context is ever truly lost**.

Context recovery allows an LLM session to restore full context from a previous session, including after compaction, clearing, or starting a new conversation. It provides two primary interfaces:

1. **gc-query CLI** -- a command-line tool for humans and scripts to query the event store, search across sessions, replay events, and extract context.
2. **SessionStart hook integration** -- automatic context loading that injects prior context into a new session without requiring the user to ask for it.

Together, these interfaces make context continuity seamless. A user can close a session, compact, or start fresh, and the next session picks up exactly where the previous one left off.

---

## User Stories

| ID | As a... | I want to... | So that... |
|---|---|---|---|
| CR-01 | User | Start a new Claude session and say "get last context" | The LLM has full awareness of what happened in my previous session |
| CR-02 | User | Have context automatically injected after compaction | I do not lose track of what I was working on when context compacts |
| CR-03 | User | Search across all my sessions for a keyword | I can find when and where I worked on something specific |
| CR-04 | User | List all my sessions with metadata | I can browse my session history and pick one to inspect |
| CR-05 | User | Replay events from a session step by step | I can understand exactly what happened and debug issues |
| CR-06 | Developer | Access event data programmatically via JSON output | I can build tools and integrations on top of the event store |
| CR-07 | User | Follow the chain of related sessions | I can see the full history of a task that spanned multiple compactions |
| CR-08 | User | Check the health of my context store | I know if the system is working and how much data it holds |

---

## Requirement 1: gc-query CLI

### Location and Installation

- Executable located at `~/.claude-context/bin/gc-query`
- Must be a self-contained script (Bash + jq, or Node.js) with no external dependencies beyond what ships with the system
- Must be executable (`chmod +x`)
- Should work on macOS and Linux
- Exit codes: 0 on success, 1 on general error, 2 on invalid arguments, 3 on not-found

### Command: `gc-query last`

Retrieve context from the most recent session.

**Behavior:**
1. Derive `project-id` from the current working directory
2. Read the `~/.claude-context/projections/{project-id}/latest` symlink to determine the most recent session ID for this project
3. Check if `~/.claude-context/projections/{project-id}/{session-id}/context.json` exists and is current (last-modified timestamp >= newest event file in the session directory)
4. If the projection is stale or missing, rebuild it by replaying all events in `~/.claude-context/events/{project-id}/{session-id}/`
4. Format the context snapshot into LLM-friendly markdown (default) or the requested output mode
5. Write output to stdout

**Flags:**
- `--format <json|markdown|text|compact>` -- output format (default: `markdown`)
- `--include-parent` -- follow `previous_session_id` chain and include parent session context
- `--max-events <N>` -- limit the number of events included (default: no limit; summarize if exceeding threshold)

**Acceptance Criteria:**
- [ ] `gc-query last` returns markdown output for the most recent session
- [ ] Returns exit code 3 with message "No sessions found" when no sessions exist
- [ ] `gc-query last --format json` returns valid JSON with all context fields
- [ ] Uses cached projection when available and current; rebuilds only when stale
- [ ] Completes in under 2 seconds for a session with 500 events
- [ ] `gc-query last --include-parent` includes context from the parent session if one exists

### Command: `gc-query session <session-id>`

Retrieve context from a specific session by ID.

**Behavior:**
1. Validate that the session directory exists (searching under `~/.claude-context/events/{project-id}/<session-id>/` or scanning all projects)
2. Load or rebuild the context projection for that session
3. Output in the requested format

**Flags:**
- `--format <json|markdown|text|compact>` -- output format (default: `markdown`)
- `--include-parent` -- include parent session context in output

**Acceptance Criteria:**
- [ ] Returns context for the specified session in the requested format
- [ ] Returns exit code 3 with message "Session not found: <session-id>" when session does not exist
- [ ] Partial session ID matching: if only a prefix is given and it uniquely identifies a session, use it
- [ ] If prefix matches multiple sessions, list the matches and exit with code 2

### Command: `gc-query sessions`

List all sessions with metadata.

**Behavior:**
1. Scan `~/.claude-context/events/{project-id}/` directories for session subdirectories
2. Read each session's `session.json` for metadata (event count, timestamps, state, etc.)
3. For each session, display: session ID, start time, project directory (cwd), event count, session state (active/compacted/ended), duration, and parent session ID if applicable
4. Sort by start time descending (most recent first)
5. By default, scope to the current project (derive project-id from cwd). Use `--all-projects` to list all sessions.

**Flags:**
- `--format <json|markdown|text|compact>` -- output format (default: `text`)
- `--project <path>` -- filter by project directory (derives project-id from path)
- `--all-projects` -- list sessions across all projects (default: current project only)
- `--state <active|compacted|ended|archived>` -- filter by session state
- `--since <date>` -- only sessions started after this date (ISO 8601 or relative like "2d", "1w")
- `--limit <N>` -- maximum number of sessions to return (default: 50)

**Acceptance Criteria:**
- [ ] Lists all sessions sorted by start time descending
- [ ] Each entry shows: session ID (truncated to 8 chars for text mode), start timestamp, project path, event count, state
- [ ] `--project` filter returns only sessions from that working directory
- [ ] `--state compacted` returns only compacted sessions
- [ ] `--since 1w` returns only sessions from the last 7 days
- [ ] Returns exit code 0 with message "No sessions found" and empty list when no sessions exist
- [ ] JSON output includes full session IDs and all metadata fields

### Command: `gc-query search <keyword>`

Search across sessions for prompts or tool calls containing a keyword.

**Behavior:**
1. Iterate through session event directories (current project by default, all projects with `--all-projects`)
2. Search event payloads for the keyword (case-insensitive by default)
3. Search targets: UserPromptReceived `data.prompt`, ToolCallCompleted `data.tool_name`, ToolCallCompleted `data.result` (first 500 chars), SessionStarted `data.cwd`
4. Return matching events grouped by session with surrounding context

**Flags:**
- `--format <json|markdown|text>` -- output format (default: `text`)
- `--case-sensitive` -- enable case-sensitive matching
- `--type <event_type>` -- only search events of this type
- `--limit <N>` -- maximum results (default: 20)
- `--session <session-id>` -- limit search to a specific session
- `--all-projects` -- search across all projects (default: current project only)

**Acceptance Criteria:**
- [ ] Finds events containing the keyword in prompt text, tool names, or tool results
- [ ] Results show: session ID, event sequence number, event type, matching text snippet (80 chars around match)
- [ ] Case-insensitive by default
- [ ] `--type UserPromptReceived` only searches prompt events
- [ ] `--limit 5` returns at most 5 results
- [ ] Returns exit code 0 with "No results found" when nothing matches
- [ ] Handles special characters in search terms (quotes, backslashes) without crashing

### Command: `gc-query events <session-id> [--from N] [--to M]`

Raw event access for a session.

**Behavior:**
1. Read event files from `~/.claude-context/events/{project-id}/<session-id>/`
2. Output raw event JSON, one per line (JSONL) or as a JSON array depending on format
3. Optionally filter by sequence number range

**Flags:**
- `--from <N>` -- start from sequence number N (inclusive, default: 1)
- `--to <M>` -- end at sequence number M (inclusive, default: last event)
- `--type <event_type>` -- filter by event type
- `--format <json|jsonl|text>` -- output format (default: `jsonl`)

**Acceptance Criteria:**
- [ ] Outputs raw event envelopes as stored on disk
- [ ] `--from 10 --to 20` returns only events with sequence 10 through 20
- [ ] `--type ToolCallCompleted` returns only tool completion events
- [ ] Events are output in sequence order
- [ ] Returns exit code 3 if session does not exist
- [ ] Returns empty result (not error) if range is valid but contains no events

### Command: `gc-query replay <session-id> [--from N] [--to M]`

Replay events in human-readable narrative format.

**Behavior:**
1. Read events from the session (optionally filtered by range)
2. Transform each event into a human-readable step description
3. Output as a numbered step-by-step narrative

**Event-to-narrative mapping:**
- `SessionStarted` -> "Session started in /path/to/project (source: manual|compact|resume)"
- `UserPromptReceived` -> "User: <prompt text>"
- `ToolCallRequested` -> "Agent plans to use <tool_name> on <target>"
- `ToolCallCompleted` -> "Executed <tool_name>: <brief result summary>"
- `ToolCallFailed` -> "FAILED: <tool_name> -- <error message>"
- `AgentSpawned` -> "Sub-agent started: <agent description>"
- `AgentCompleted` -> "Sub-agent finished: <result summary>"
- `TurnCompleted` -> "Turn completed (cost: $X.XX)"
- `CompactionTriggered` -> "COMPACTION: Context was compacted (summary saved)"
- `SessionEnded` -> "Session ended"

**Flags:**
- `--from <N>` -- start from sequence number N
- `--to <M>` -- end at sequence number M
- `--verbose` -- include full payloads instead of summaries
- `--format <text|markdown|json>` -- output format (default: `text`)

**Acceptance Criteria:**
- [ ] Each event is rendered as a numbered step: "Step 1: User: fix the login bug"
- [ ] Tool calls show the tool name and a brief description of what was done
- [ ] Failed tool calls are clearly marked with "FAILED"
- [ ] `--verbose` includes full event payloads
- [ ] Replay of a 100-event session completes in under 1 second
- [ ] Handles unknown event types gracefully: "Step N: [Unknown event: <type>]"

### Command: `gc-query tail <session-id> [N]`

Show the last N events from a session (default 20).

**Behavior:**
1. Determine the total event count for the session
2. Read the last N event files
3. Output in the requested format

**Flags:**
- `--format <json|text|markdown>` -- output format (default: `text`)

**Acceptance Criteria:**
- [ ] Default N is 20
- [ ] `gc-query tail abc123 5` shows the last 5 events
- [ ] If the session has fewer than N events, show all events
- [ ] Output uses replay-style formatting for text mode
- [ ] Returns exit code 3 if session does not exist

### Command: `gc-query status`

Show store health and statistics.

**Behavior:**
1. Count total session directories across all project directories in `~/.claude-context/events/`
2. Count total event files across all sessions
3. Calculate total disk usage of `~/.claude-context/`
4. Show the latest session ID and its start time
5. Show projection cache status (how many projections exist, how many are stale)

**Output fields:**
- Total sessions
- Total events
- Disk usage (human-readable: KB, MB, GB)
- Latest session ID and timestamp
- Active projections count
- Stale projections count
- Store path

**Acceptance Criteria:**
- [ ] All statistics are accurate
- [ ] Disk usage is calculated for the entire `~/.claude-context/` directory
- [ ] Handles empty store gracefully: "Store is empty. No sessions recorded."
- [ ] `--format json` returns all fields as JSON
- [ ] Completes in under 3 seconds even with 100+ sessions

### Command: `gc-query doctor`

Run health checks on the event store.

**Behavior:**
1. Validate store directory structure exists and has correct permissions
2. Check that `config.json` is valid JSON
3. Scan event directories for integrity issues (orphan temp files, corrupt JSON, sequence gaps)
4. Verify per-project `latest` symlinks point to valid session directories
5. Check that each session's `session.json` is valid and matches event count
6. Report results as a checklist with pass/fail for each check

**Output fields:**
- Store path and permissions (pass/fail)
- Config validity (pass/fail)
- Total sessions scanned
- Orphan temp files found (count)
- Corrupt event files found (count)
- Sequence gaps found (count)
- Broken symlinks found (count)
- session.json inconsistencies found (count)

**Flags:**
- `--format <json|text>` -- output format (default: `text`)
- `--fix` -- attempt to fix issues (clean orphan temps, rebuild broken symlinks)

**Acceptance Criteria:**
- [ ] All health checks run and report pass/fail
- [ ] Orphan temp files (*.tmp.*) are detected
- [ ] Corrupt event files (invalid JSON) are detected
- [ ] Broken symlinks are detected
- [ ] `--fix` cleans orphan temp files and rebuilds latest symlinks
- [ ] `--format json` returns structured results
- [ ] Completes in under 5 seconds for stores with 100+ sessions

---

## Requirement 2: "Get Last Context" Flow

This is the primary use case for the entire system. A user starts a new Claude Code session and types something like "get last context" or "what was I working on?" and expects the LLM to have full awareness of the previous session.

### Flow Detail

```
User starts new Claude Code session
  |
  v
User types: "get last context" (or similar prompt)
  |
  v
LLM recognizes intent, runs: gc-query last --format markdown
  |
  v
gc-query resolves latest session:
  1. derive project-id from cwd
  2. readlink ~/.claude-context/projections/{project-id}/latest
  3. -> session-id: "abc-123-def"
  |
  v
gc-query checks projection currency:
  4. stat ~/.claude-context/projections/{project-id}/abc-123-def/context.json
  5. stat ~/.claude-context/events/{project-id}/abc-123-def/ (newest file)
  6. If projection.mtime >= newest_event.mtime -> use cached
  7. Else -> rebuild projection from events
  |
  v
gc-query builds markdown output:
  7. Read context.json (or build from events)
  8. Structure into LLM-friendly sections
  9. Write to stdout
  |
  v
LLM reads the output, now has full context of previous session
```

### Projection Rebuild Process

When the cached `context.json` is stale or missing, gc-query rebuilds it:

1. List all event files in `~/.claude-context/events/{project-id}/{session-id}/` sorted by sequence number
2. Initialize empty projection state:
   ```json
   {
     "session_id": "",
     "started_at": "",
     "project_dir": "",
     "prompts": [],
     "tool_calls": [],
     "files_touched": {},
     "decisions": [],
     "last_events": [],
     "event_count": 0,
     "previous_session_id": null
   }
   ```
3. Replay each event in order, updating the projection:
   - `SessionStarted`: set session_id, started_at, project_dir, previous_session_id
   - `UserPromptReceived`: append to prompts array
   - `ToolCallRequested` + `ToolCallCompleted`: pair them and append to tool_calls with name, input, result, duration
   - `ToolCallFailed`: append to tool_calls with error flag
   - `CompactionTriggered`: mark compaction point, capture summary
   - `SessionEnded`: set ended_at, compute duration
4. Populate `last_events` with the final 10 events (for "where we left off")
5. Write projection to `~/.claude-context/projections/{project-id}/{session-id}/context.json`

### Acceptance Criteria

- [ ] "Get last context" returns complete, structured context within 2 seconds
- [ ] Projection is rebuilt correctly from raw events when cache is stale
- [ ] Rebuilt projection is written back to disk for future cache hits
- [ ] Output includes all required sections (see Requirement 4)
- [ ] Works correctly even if the previous session was compacted mid-work
- [ ] Works correctly even if the previous session ended abnormally (no SessionEnded event)

---

## Requirement 3: Automatic Context Recovery via SessionStart Hook

### Overview

When a SessionStart hook fires, the system can automatically inject context from the previous session into the new session. This makes recovery automatic -- the user does not need to type "get last context" because the LLM already has it.

### Hook Trigger Conditions

The SessionStart hook payload includes a `source` field indicating how the session was started. The behavior varies based on the source:

#### Source: "compact"

Context compaction has occurred. This is the most critical case.

**Flow:**
1. SessionStart hook fires with source indicating compaction
2. The capture-event script stores the SessionStarted event (normal capture)
3. Additionally, the hook script detects this is a compaction event
4. It reads the previous session's context (the session that just compacted)
5. It builds a compact summary of what was happening before compaction
6. It returns the summary in the `additionalContext` field of the hook response

**Hook response format (sync hook):**
```json
{
  "additionalContext": "## Context Recovery (Auto)\n\nYour previous context was compacted. Here is what was happening:\n\n### What Was Being Worked On\n...\n\n### Actions Taken\n...\n\n### Files Modified\n...\n\n### Where We Left Off\n..."
}
```

**Constraints:**
- The `additionalContext` value must be a single string (no nested objects)
- Total size should be under 50KB to avoid bloating the new context
- Summary should prioritize recency: last 5 prompts and their results get full detail, older prompts get one-line summaries
- Must complete within the hook timeout (5 seconds)

#### Source: "clear"

User explicitly cleared the conversation. Similar to compact but the user's intent was to start fresh.

**Flow:**
1. Same as compact flow, but summary is labeled as "Context Recovery (Cleared)"
2. Summary is more condensed: focus on what was accomplished, not in-progress work
3. Include a note: "Previous conversation was cleared by user"

#### Source: "resume"

User is resuming a session (e.g., reconnecting). Context may still be largely intact.

**Flow:**
1. Check if the resumed session's context is already available to the LLM
2. If the session has events since last context load, provide a delta summary
3. If no new events, do not inject anything (avoid duplication)
4. This case is optional for initial implementation

#### Source: "manual" (new session)

User started a brand new session. No automatic injection.

**Flow:**
1. No `additionalContext` injected
2. User can manually request context via "get last context"
3. The system silently records the new session start

### Pre-Compaction Snapshot

When a `PreCompact` hook fires (before compaction):

1. Build a complete context snapshot of the current session state
2. Store it as the session's context.json projection immediately
3. This ensures the projection is ready when the post-compaction SessionStart fires
4. The PreCompact handler must be synchronous to guarantee the snapshot is written before compaction occurs

### Acceptance Criteria

- [ ] SessionStart with source "compact" returns `additionalContext` with previous session summary
- [ ] SessionStart with source "clear" returns `additionalContext` with completion summary
- [ ] `additionalContext` is valid markdown, under 50KB
- [ ] Hook response completes within 5 seconds
- [ ] PreCompact handler writes a complete context.json projection before returning
- [ ] The injected context allows the LLM to continue working without asking "what were we doing?"
- [ ] Source "manual" does not inject any additionalContext
- [ ] If building context fails (corrupt events, missing files), the hook still returns successfully with an error note in additionalContext rather than failing the hook entirely

---

## Requirement 4: Context Format for LLM Consumption

### Markdown Template

The context snapshot, when output as markdown, must follow this structure:

```markdown
## Session Context Recovery

### Session Info
- **Session ID**: abc-123-def-456
- **Started**: 2026-02-14 10:30:00 UTC
- **Ended**: 2026-02-14 11:45:00 UTC (duration: 1h 15m)
- **Project**: /home/user/my-project
- **Events Recorded**: 247
- **Continuation Of**: [session xyz-789] (if applicable)

### What Was Being Worked On
The last user prompt was:
> "Fix the authentication bug in the login handler and add rate limiting"

Recent context from the session:
- Working on authentication system in `src/auth/`
- Debugging a JWT validation error
- Adding rate limiting middleware

### Actions Taken
1. Read `src/auth/handler.ts` -- reviewed current auth logic
2. Edited `src/auth/handler.ts` -- fixed JWT expiry check (line 45)
3. Read `src/middleware/rate-limit.ts` -- checked existing middleware
4. Created `src/middleware/rate-limit.ts` -- new token bucket rate limiter
5. Edited `src/routes/auth.ts` -- applied rate limit middleware to login route
6. Ran `npm test` -- 47 passed, 2 failed (rate limit tests)
7. Edited `tests/rate-limit.test.ts` -- fixed test expectations
8. Ran `npm test` -- 49 passed, 0 failed

### Files Modified
| File | Operations | Last Action |
|---|---|---|
| `src/auth/handler.ts` | read, edit | Fixed JWT expiry check |
| `src/middleware/rate-limit.ts` | create, edit | New rate limiter |
| `src/routes/auth.ts` | read, edit | Applied middleware |
| `tests/rate-limit.test.ts` | read, edit | Fixed test expectations |

### Key Decisions
- **JWT fix**: Changed expiry check from `<` to `<=` to handle edge case at exact expiry time
- **Rate limiting approach**: Chose token bucket over sliding window for simplicity
- **Rate limit config**: 10 requests per minute per IP for login endpoint

### Where We Left Off
All tests passing. Rate limiting is implemented and tested. The user had not yet:
- Deployed the changes
- Updated the API documentation
- Added rate limit headers to responses (X-RateLimit-Remaining, etc.)

Last events:
1. Ran tests -- all passing
2. User said: "looks good, let's also add the rate limit headers"
3. Session compacted here
```

### Formatting Rules

1. **Prompt text**: Always quoted with `>` blockquote syntax
2. **File paths**: Always in backtick code formatting
3. **Tool actions**: Summarized as verb + target + brief result
4. **Code snippets**: Not included by default (too large); only include if specifically requested
5. **Decisions**: Stated as "chose X over Y because Z" format
6. **Timestamps**: ISO 8601 with human-readable relative time in parentheses
7. **Session links**: Reference parent sessions by ID with brackets

### Progressive Summarization

For sessions with many events (100+), apply progressive summarization:

| Event Age | Detail Level |
|---|---|
| Last 20 events | Full detail (tool name, target, result) |
| Events 21-50 (from end) | Summary (tool name + target only) |
| Events 51-100 (from end) | Grouped ("Edited 5 files in src/auth/") |
| Events 100+ (from end) | One-line summary ("Earlier: reviewed project structure, set up test framework") |

### Acceptance Criteria

- [ ] Markdown output follows the template structure exactly
- [ ] All six sections are present: Session Info, What Was Being Worked On, Actions Taken, Files Modified, Key Decisions, Where We Left Off
- [ ] File paths use backtick formatting
- [ ] Prompts use blockquote formatting
- [ ] Progressive summarization is applied for sessions with 100+ events
- [ ] Output is valid markdown that renders correctly
- [ ] "Where We Left Off" section accurately reflects the final state of the session
- [ ] JSON output contains the same information in structured format
- [ ] Text output is readable in a terminal without markdown rendering

---

## Requirement 5: Cross-Session Continuity

### Session Chaining

When a session is a continuation of a previous session (e.g., after compaction), the system must track and expose this relationship.

### Per-Session Metadata for Chaining

Session chaining information is stored in each session's `session.json` file (see Story 03, Requirement 4). The `previous_session_id` field links a session to its predecessor. To build a chain, gc-query reads each session's `session.json` and follows the `previous_session_id` links.

Example session.json for a continuation session:
```json
{
  "session_id": "def-456",
  "project_id": "my-project-a3f7b2",
  "project_dir": "/home/user/my-project",
  "started_at": "2026-02-14T11:45:01Z",
  "source": "compact",
  "model": "claude-opus-4-6",
  "event_count": 53,
  "last_event_at": "2026-02-14T12:15:00Z",
  "last_event_type": "TurnCompleted",
  "last_prompt": "also add the rate limit headers",
  "ended_at": null,
  "previous_session_id": "abc-123"
}
```

> **Design Amendment 1 & 2**: There is no global sessions.json. Session metadata is per-session, stored in `events/{project-id}/{session-id}/session.json`. Chain resolution reads individual session.json files by following `previous_session_id` links.

### Chain Resolution

`gc-query` must be able to follow session chains:

```
gc-query session def-456 --include-parent
```

This resolves the chain: `def-456` -> `abc-123` -> (no parent) and outputs the combined context from both sessions, with clear section breaks:

```markdown
## Session Context Recovery (Session Chain)

### Current Session: def-456
[... current session context ...]

---

### Parent Session: abc-123
[... parent session context, progressively summarized ...]
```

### Chain Depth Limits

- Maximum chain depth to follow: 10 sessions
- If chain exceeds 10, show the most recent 10 and note: "N earlier sessions omitted"
- Each parent session in the chain gets progressively more summarized

### Acceptance Criteria

- [ ] Per-session `session.json` tracks `previous_session_id` for chain linking
- [ ] `gc-query session X --include-parent` follows the `previous_session_id` chain and includes parent context
- [ ] Chain resolution stops at depth 10
- [ ] Parent sessions are progressively summarized (parent gets compact summary, grandparent gets one-liner)
- [ ] Circular chains are detected and broken with an error message
- [ ] Chain resolution reads individual session.json files (no global index needed)

---

## Requirement 6: Search and Discovery

### Search by Keyword

```bash
gc-query search "rate limiting"
```

**Output (text mode):**
```
Found 3 matches across 2 sessions:

Session abc-123 (2026-02-14 10:30):
  [#42] UserPromptReceived: "...fix the auth bug and add rate limiting..."
  [#67] ToolCallCompleted: Edit src/middleware/rate-limit.ts

Session def-456 (2026-02-14 11:45):
  [#12] UserPromptReceived: "...also add the rate limit headers..."
```

### Search by File

```bash
gc-query search --file "src/auth/handler.ts"
```

Searches for events that reference a specific file path in tool call inputs or outputs.

**Behavior:**
1. Search `ToolCallRequested` and `ToolCallCompleted` events for the file path
2. Match against common tool input fields: `file_path`, `path`, `glob`, `command` (if it contains the path)
3. Return events grouped by session

### Search by Date Range

```bash
gc-query sessions --since 2026-02-10 --until 2026-02-14
```

Filters the session list by date range using session start times.

### Search by Project Directory

```bash
gc-query sessions --project /home/user/my-project
```

Filters sessions by their working directory, matching on exact path or subdirectory.

### Acceptance Criteria

- [ ] Keyword search finds matches in prompts, tool names, and tool results
- [ ] File search finds all sessions that read, wrote, or edited a given file
- [ ] Date range filtering works with ISO 8601 dates and relative dates
- [ ] Project directory filtering matches exact paths
- [ ] Search results include enough context to understand the match (snippet around keyword)
- [ ] Search across 50 sessions with 200 events each completes in under 5 seconds
- [ ] Results are sorted by relevance (match count) then recency

---

## Requirement 7: Event Replay

### Narrative Replay

Event replay transforms raw events into a human-readable story of what happened.

```bash
gc-query replay abc-123 --from 40 --to 60
```

**Output:**
```
Replaying session abc-123, events 40-60:

Step 40: User: "now fix the rate limit tests"
Step 41: Agent plans to read tests/rate-limit.test.ts
Step 42: Read tests/rate-limit.test.ts (245 lines)
Step 43: Agent plans to edit tests/rate-limit.test.ts
Step 44: Edited tests/rate-limit.test.ts (changed lines 12-18)
Step 45: Agent plans to run command: npm test
Step 46: Ran command: npm test
         Result: 49 passed, 0 failed (exit code 0)
Step 47: Turn completed
Step 48: User: "looks good, let's also add the rate limit headers"
Step 49: Agent plans to read src/routes/auth.ts
Step 50: Read src/routes/auth.ts (89 lines)
...
```

### Verbose Mode

```bash
gc-query replay abc-123 --from 42 --to 42 --verbose
```

Shows the full event payload for each step, including all data fields.

### Event Type Rendering

Each event type has a specific rendering template:

| Event Type | Rendering Template |
|---|---|
| `SessionStarted` | `Session started in {cwd} (source: {source})` |
| `UserPromptReceived` | `User: "{prompt}"` (truncated to 200 chars) |
| `ToolCallRequested` | `Agent plans to use {tool_name} on {primary_input}` |
| `ToolCallCompleted` | `Executed {tool_name}: {result_summary}` (result summarized to 100 chars) |
| `ToolCallFailed` | `FAILED: {tool_name} -- {error}` |
| `AgentSpawned` | `Sub-agent started` |
| `AgentCompleted` | `Sub-agent finished` |
| `TurnCompleted` | `Turn completed` |
| `CompactionTriggered` | `--- COMPACTION ---` (visually distinct separator) |
| `SessionEnded` | `Session ended` |

### Acceptance Criteria

- [ ] Replay produces a numbered step-by-step narrative
- [ ] Each event type has a distinct, readable rendering
- [ ] `--from` and `--to` correctly filter the event range
- [ ] `--verbose` includes full event payloads
- [ ] Compaction events are rendered with visual emphasis
- [ ] User prompts longer than 200 characters are truncated with "..."
- [ ] Tool results longer than 100 characters are summarized
- [ ] Unknown event types render as `[Unknown: {type}] {raw data summary}`
- [ ] Replay handles missing events in sequence (gaps in numbering) gracefully

---

## Requirement 8: Session Lifecycle Metadata

### Session States

| State | Description | Trigger |
|---|---|---|
| `active` | Session is currently in progress | SessionStarted event received |
| `compacted` | Session was compacted, new session continues the work | CompactionTriggered event followed by new SessionStarted |
| `ended` | Session ended normally | SessionEnded event received |
| `archived` | Session was archived (future feature) | Manual or automated archival |
| `orphaned` | Session has no SessionEnded event and is not active | Detected on status check when session has no events for 24h+ |

### Metadata Fields

For each session, the following metadata is tracked in the per-session `session.json` (see Story 03, Requirement 4). Some fields below are computed by gc-query on demand rather than stored:

| Field | Type | Source |
|---|---|---|
| `session_id` | string | SessionStarted event |
| `started_at` | ISO 8601 | SessionStarted timestamp |
| `ended_at` | ISO 8601 or null | SessionEnded timestamp |
| `state` | enum | Derived from events |
| `project_dir` | string | SessionStarted cwd |
| `event_count` | integer | Count of event files |
| `events_by_type` | object | Count per event type |
| `previous_session_id` | string or null | SessionStarted data |
| `continuation_of` | string or null | Same as previous_session_id when source is "compact" |
| `continued_by` | string or null | Updated when a continuation session starts |
| `source` | string | SessionStarted source (manual/compact/clear/resume) |
| `model` | string or null | From SessionStarted data if available |
| `duration_seconds` | integer or null | ended_at - started_at |
| `last_prompt` | string or null | Last UserPromptReceived prompt (truncated to 100 chars) |
| `summary` | string or null | Auto-generated or from CompactionTriggered |

### Metadata Updates

Session metadata in per-session `session.json` is updated by the capture-event script within its existing flock scope:
- On SessionStarted: create `session.json` with initial fields
- On UserPromptReceived: update `last_prompt`
- On SessionEnded: set `ended_at`
- On any event: increment `event_count`, update `last_event_at` and `last_event_type`

Some fields are computed by gc-query on demand:
- `state`: derived from events (active if no SessionEnded, compacted if CompactionTriggered, etc.)
- `events_by_type`: computed by scanning event files
- `duration_seconds`: computed from `started_at` and `ended_at`
- `continued_by`: found by scanning other sessions' `previous_session_id`
- `summary`: computed by projection builder or from CompactionTriggered event
- `orphaned`: detected on status check (active but no events for 24+ hours)

### Acceptance Criteria

- [ ] All metadata fields are populated correctly from events
- [ ] `events_by_type` accurately counts each event type
- [ ] Session state transitions follow the defined state machine
- [ ] `duration_seconds` is computed correctly (null if session has not ended)
- [ ] `last_prompt` is updated on each UserPromptReceived event
- [ ] Per-session `session.json` is updated atomically within the existing flock scope
- [ ] Orphaned sessions are detected when state is `active` but no events for 24+ hours
- [ ] Core metadata (event count, timestamps) can be read from `session.json` without replaying events
- [ ] Computed fields (state, events_by_type, duration) are derived on demand by gc-query

---

## Requirement 9: Output Modes

### JSON Mode (`--format json`)

Full structured output. Used for programmatic consumption, piping to other tools, or integration with scripts.

```json
{
  "session_id": "abc-123",
  "started_at": "2026-02-14T10:30:00Z",
  "ended_at": "2026-02-14T11:45:00Z",
  "project_dir": "/home/user/my-project",
  "event_count": 247,
  "previous_session_id": null,
  "prompts": [
    {"sequence": 1, "text": "Fix the auth bug...", "timestamp": "..."}
  ],
  "tool_calls": [
    {"sequence": 5, "tool": "Read", "target": "src/auth/handler.ts", "result_summary": "245 lines", "success": true}
  ],
  "files_touched": {
    "src/auth/handler.ts": {"operations": ["read", "edit"], "last_action": "Fixed JWT expiry check"},
    "src/middleware/rate-limit.ts": {"operations": ["create", "edit"], "last_action": "New rate limiter"}
  },
  "decisions": [
    {"prompt": "Fix the auth bug...", "actions": ["read handler.ts", "edit handler.ts"], "outcome": "Fixed JWT expiry check"}
  ],
  "last_events": [],
  "summary": "Fixed auth bug, added rate limiting"
}
```

### Markdown Mode (`--format markdown`)

Default for context recovery. Optimized for LLM consumption. Follows the template defined in Requirement 4.

### Text Mode (`--format text`)

Human-readable terminal output with no markdown formatting. Uses indentation and dashes instead of headers and tables.

```
Session: abc-123
Started: 2026-02-14 10:30:00 UTC
Project: /home/user/my-project
Events:  247

What Was Being Worked On:
  Last prompt: "Fix the authentication bug in the login handler"

Actions Taken:
  - Read src/auth/handler.ts (reviewed auth logic)
  - Edited src/auth/handler.ts (fixed JWT expiry)
  ...

Files Modified:
  - src/auth/handler.ts (read, edit)
  - src/middleware/rate-limit.ts (create, edit)
  ...
```

### Compact Mode (`--format compact`)

Minimal summary for quick overview. One or two lines per session.

```
abc-123 | 2026-02-14 10:30 | /home/user/my-project | 247 events | "Fix the auth bug..." | 4 files modified
```

### Acceptance Criteria

- [ ] All four output modes are supported: json, markdown, text, compact
- [ ] `--format json` produces valid, parseable JSON
- [ ] `--format markdown` follows the template from Requirement 4
- [ ] `--format text` is readable without markdown rendering
- [ ] `--format compact` fits on a single line per session
- [ ] Default format for `gc-query last` and `gc-query session` is `markdown`
- [ ] Default format for `gc-query sessions` is `text`
- [ ] Default format for `gc-query events` is `jsonl`
- [ ] Default format for `gc-query replay` is `text`
- [ ] Default format for `gc-query search` is `text`
- [ ] Default format for `gc-query status` is `text`
- [ ] Invalid format values produce a clear error message

---

## Requirement 10: Performance

### Targets

| Operation | Target | Condition |
|---|---|---|
| `gc-query last` (cached) | < 500ms | Projection exists and is current |
| `gc-query last` (rebuild) | < 2s | Session with 500 events |
| `gc-query sessions` | < 1s | 100 sessions |
| `gc-query search` | < 5s | 50 sessions, 200 events each |
| `gc-query replay` | < 1s | 100-event range |
| `gc-query status` | < 3s | 100 sessions |
| SessionStart hook (context injection) | < 5s | Hook timeout constraint |

### Caching Strategy

1. **Projection caching**: Context projections are written to `~/.claude-context/projections/{project-id}/{session-id}/context.json` after first build and reused until invalidated
2. **Cache invalidation**: Compare the modification time of the projection file against the newest event file in the session directory. If any event is newer, the projection is stale
3. **Incremental rebuild**: For active sessions with many events, consider appending to the projection rather than full rebuild. Implementation: store `last_processed_sequence` in the projection and only process events after that sequence
4. **Per-session session.json**: Updated incrementally on each event capture within the existing flock scope — no global index to maintain

### Progressive Summarization for Large Sessions

When a session exceeds 200 events, the context output must be intelligently truncated:

1. **Last 20 events**: Full detail
2. **Events 21-50 from end**: Tool name + target only
3. **Events 51-100 from end**: Grouped by type ("Read 8 files", "Made 3 edits")
4. **Events 100+ from end**: Single paragraph summary
5. **Total output target**: Under 100KB for markdown, under 200KB for JSON

### Large Context Truncation

If the total output exceeds 200KB:

1. Truncate tool call results (keep first 200 chars)
2. Omit the "Actions Taken" detail for old events (keep only files and decisions)
3. Add a note: "Full context truncated. Use `gc-query replay <session-id>` for complete history."

### Acceptance Criteria

- [ ] Cached projection retrieval completes in under 500ms
- [ ] Full projection rebuild for 500 events completes in under 2 seconds
- [ ] Incremental projection update only processes new events
- [ ] Per-session session.json is updated incrementally within flock scope
- [ ] Progressive summarization produces output under 100KB for 500-event sessions
- [ ] Output exceeding 200KB is truncated with a note
- [ ] No file handles are left open after gc-query completes
- [ ] gc-query handles concurrent reads safely (another session writing events while gc-query reads)

---

## Edge Cases

### No Previous Sessions

**Condition:** User runs `gc-query last` or compaction triggers context recovery, but no sessions exist.

**Expected behavior:**
- `gc-query last` returns exit code 3 with message: "No sessions found. This appears to be the first use of GlobalContext."
- SessionStart hook returns empty `additionalContext` (does not fail)

### Empty Session

**Condition:** A session was started but no events were recorded (e.g., user started and immediately quit).

**Expected behavior:**
- `gc-query last` returns a minimal context: "Previous session (abc-123) started at [time] but recorded no events."
- This session is still listed in `gc-query sessions` with event_count: 0

### Long Session Chain

**Condition:** A task has gone through 10+ compactions, creating a chain of 10+ sessions.

**Expected behavior:**
- `gc-query session X --include-parent` follows the chain up to depth 10
- Beyond depth 10, output includes: "10 additional ancestor sessions exist but are omitted. Use `gc-query session <id>` to inspect individually."
- Each parent session in the chain gets progressively less detail

### Very Large Context (> 200KB)

**Condition:** A session has hundreds of events with large tool results, producing a context snapshot over 200KB.

**Expected behavior:**
- Progressive summarization is applied automatically
- Tool results are truncated to 200 characters
- A truncation note is added to the output
- JSON output includes a `truncated: true` field
- The full, untruncated data is always available via `gc-query events` and `gc-query replay`

### Concurrent Access

**Condition:** One Claude session is writing events while gc-query is reading from the same session.

**Expected behavior:**
- gc-query reads a consistent snapshot (events 1-N at the time of the read)
- If a new event is written during the read, it is either fully included or fully excluded (no partial reads)
- Individual event files are atomic (written completely before the file handle is closed)
- No file locking is required for reads; flock is only used for sequence number assignment on writes

### Corrupt or Missing Events

**Condition:** An event file is malformed JSON, missing, or has a gap in sequence numbers.

**Expected behavior:**
- Malformed JSON: Skip the event with a warning in the output: "Warning: Event #42 could not be parsed and was skipped"
- Missing files: If sequence 5 is missing but 4 and 6 exist, note the gap but continue processing
- The projection marks itself as having warnings so future reads know it may be incomplete

### Files No Longer Exist

**Condition:** The context references files that have since been deleted or moved.

**Expected behavior:**
- Files are listed in "Files Modified" regardless of current existence
- No attempt is made to verify file existence during context recovery (it is a historical record)
- If a tool explicitly tries to access a referenced file and it is gone, that is a separate concern handled by the LLM session, not by gc-query

---

## Integration Points

### Integration 1: SessionStart Hook -> Automatic Context Injection

**Trigger:** SessionStart hook fires
**Data flow:**
1. Hook receives SessionStart payload on stdin
2. capture-event stores the event
3. Hook script checks `source` field
4. If "compact" or "clear": run context recovery for previous session
5. Format as markdown summary
6. Return `{"additionalContext": "<markdown summary>"}` on stdout

**Contract:**
- Input: SessionStart JSON payload (stdin)
- Output: JSON with optional `additionalContext` field (stdout)
- Timeout: 5 seconds
- Failure mode: Return `{}` (empty response) on any error; never fail the hook

### Integration 2: User Prompt -> gc-query last

**Trigger:** User types "get last context" (or similar)
**Data flow:**
1. LLM recognizes the intent
2. LLM executes `~/.claude-context/bin/gc-query last --format markdown` via Bash tool
3. gc-query outputs markdown to stdout
4. LLM reads the output and incorporates it into the conversation

**Contract:**
- The LLM must have `~/.claude-context/bin/gc-query` in its tool access (Bash)
- gc-query must output only the context markdown to stdout (no prompts, no interactive elements)
- Errors go to stderr

### Integration 3: User Prompt -> Session Exploration

**Trigger:** User asks about a specific session or wants to explore history
**Data flow:**
1. User: "what happened in my last 5 sessions?"
2. LLM runs: `gc-query sessions --limit 5`
3. LLM presents the list
4. User: "show me session abc-123"
5. LLM runs: `gc-query session abc-123`
6. LLM presents the context

### Integration 4: CLI Direct Usage

**Trigger:** User runs gc-query directly in their terminal (outside of Claude)
**Usage examples:**
```bash
# Quick overview
gc-query status

# Find a session where I worked on auth
gc-query search "authentication"

# Replay what happened
gc-query replay abc-123

# Get raw events for scripting
gc-query events abc-123 --format json | jq '.data.tool_name'
```

---

## Non-Goals

These are explicitly out of scope for this story:

1. **Live/streaming context** -- Context recovery is snapshot-based. There is no live-updating view of an active session. A tail command shows the last N events at the time of execution, not a live feed.

2. **Remote context store access** -- The event store is local to the machine. There is no network protocol, no remote API, no cloud sync. The store lives at `~/.claude-context/` on the local filesystem.

3. **Multi-user context sharing** -- There is no concept of sharing sessions between users. Each user has their own `~/.claude-context/` store.

4. **Context editing** -- Events are immutable. There is no way to modify, delete, or redact events through gc-query. If a user needs to remove sensitive data, they must manually delete event files.

5. **Automatic summarization via LLM** -- The context format is template-based, not LLM-generated. Summaries are mechanical (truncation, grouping), not semantic. LLM-powered summarization could be a future enhancement.

---

## Technical Specifications

### gc-query Script Structure

```
gc-query (entry point)
  |
  +-- parse_args()          # Parse command and flags
  +-- validate()            # Validate session exists, store is healthy
  +-- resolve_session()     # Resolve "last" or prefix to full session ID
  +-- load_projection()     # Load cached or rebuild context projection
  +-- format_output()       # Transform projection into requested format
  +-- output()              # Write to stdout
```

### Key Functions

**resolve_latest_session(project_id)**
```bash
# Read the per-project "latest" symlink
latest=$(readlink ~/.claude-context/projections/$project_id/latest)
if [ -z "$latest" ]; then
  # Fallback: find most recent session by reading session.json timestamps
  latest=$(for d in ~/.claude-context/events/$project_id/*/; do
    jq -r '.started_at' "$d/session.json" 2>/dev/null
  done | sort -r | head -1)
fi
```

**is_projection_current(project_id, session_id)**
```bash
# Compare projection mtime to newest event mtime
proj_mtime=$(stat -c %Y ~/.claude-context/projections/$project_id/$session_id/context.json 2>/dev/null || echo 0)
newest_event=$(ls -1t ~/.claude-context/events/$project_id/$session_id/[0-9]*.json | head -1)
event_mtime=$(stat -c %Y "$newest_event" 2>/dev/null || echo 0)
[ "$proj_mtime" -ge "$event_mtime" ]
```

**build_context_projection(session_id)**
```bash
# Replay all events and build structured context
# Uses jq for JSON processing
# Outputs context.json to projections directory
```

### Dependencies

- **Required**: bash (4.0+), jq (1.6+)
- **Optional**: node (for complex projection building if bash+jq is insufficient)
- **No external network dependencies**
- **No database dependencies**

### File Permissions

- `gc-query`: 755 (executable script)
- Event files: 600 (owner read/write only)
- Projection files: 600 (owner read/write only)
- Store directories: 700 (owner only)

### Error Handling

All errors follow this pattern:
1. Write error message to stderr
2. Set appropriate exit code
3. Never produce partial output to stdout on error (except for warnings embedded in valid output)

Exit codes:
| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | General error (I/O failure, jq error, etc.) |
| 2 | Invalid arguments (bad command, missing required arg, invalid flag) |
| 3 | Not found (session does not exist, no sessions in store) |

---

## Testing Plan

### Unit Tests

| Test | Description |
|---|---|
| T01 | `gc-query last` with no sessions returns exit 3 |
| T02 | `gc-query last` with one session returns markdown context |
| T03 | `gc-query last --format json` returns valid JSON |
| T04 | `gc-query session <id>` with valid ID returns context |
| T05 | `gc-query session <id>` with invalid ID returns exit 3 |
| T06 | `gc-query session <prefix>` with unique prefix resolves correctly |
| T07 | `gc-query sessions` lists all sessions sorted by time |
| T08 | `gc-query sessions --project <path>` filters correctly |
| T09 | `gc-query search <keyword>` finds matches in prompts |
| T10 | `gc-query search <keyword>` finds matches in tool calls |
| T11 | `gc-query events <id>` returns raw events |
| T12 | `gc-query events <id> --from 5 --to 10` returns correct range |
| T13 | `gc-query replay <id>` produces numbered narrative |
| T14 | `gc-query tail <id> 5` returns last 5 events |
| T15 | `gc-query status` returns accurate statistics |
| T16 | Projection cache is used when current |
| T17 | Projection is rebuilt when stale |
| T18 | Progressive summarization activates at 100+ events |
| T19 | Output is truncated at 200KB with note |
| T20 | Corrupt event files are skipped with warning |

### Integration Tests

| Test | Description |
|---|---|
| I01 | Full flow: capture events -> gc-query last -> verify output |
| I02 | Compaction flow: events -> compact -> new session -> auto-recovery |
| I03 | Session chain: 3 sessions linked by compaction -> --include-parent |
| I04 | Concurrent read/write: write events while gc-query reads |
| I05 | Large session: 500 events -> verify < 2s rebuild, < 100KB output |

### Manual Tests

| Test | Description |
|---|---|
| M01 | Start Claude session, do work, compact, verify auto-recovery |
| M02 | Start new session, say "get last context", verify LLM has context |
| M03 | Run `gc-query sessions` in terminal, verify readable output |
| M04 | Run `gc-query search` for a known keyword, verify results |
| M05 | Run `gc-query replay` and verify narrative makes sense |

---

## Implementation Notes

### Implementation Order

1. **gc-query entry point** -- argument parsing, help text, routing to subcommands
2. **`gc-query status`** -- simplest command, validates store access
3. **`gc-query events`** -- raw event access, foundation for other commands
4. **`gc-query tail`** -- thin wrapper on events
5. **Projection builder** -- core logic for building context.json from events
6. **`gc-query session`** -- uses projection builder
7. **`gc-query last`** -- session resolution + session command
8. **`gc-query sessions`** -- session listing from per-session session.json files
9. **`gc-query search`** -- event scanning with keyword matching
10. **`gc-query replay`** -- event-to-narrative transformation
11. **`gc-query doctor`** -- store health validation and repair
12. **Output formatters** -- json, markdown, text, compact renderers
13. **SessionStart hook integration** -- automatic context injection
14. **Performance optimization** -- caching, incremental updates, progressive summarization

### Considerations

- The gc-query script will likely start as Bash + jq but may need to be rewritten in Node.js if the JSON processing becomes too complex for jq
- File system operations (stat, readlink, ls) differ slightly between macOS and Linux; use POSIX-compatible variants where possible
- The `stat` command has different flags on macOS (`-f %m`) vs Linux (`-c %Y`); abstract this into a helper function
- jq is a hard dependency; the install script from Story 01 should verify jq is available and suggest installation if not
- Progressive summarization is the most algorithmically complex part; start with simple truncation and iterate toward smarter grouping

---

## Definition of Done

- [ ] `gc-query` CLI is installed at `~/.claude-context/bin/gc-query` and is executable
- [ ] All 9 subcommands are implemented and return correct output (last, session, sessions, search, events, replay, tail, status, doctor)
- [ ] All 4 output modes (json, markdown, text, compact) work for applicable commands
- [ ] "Get last context" flow works end-to-end: user prompt -> gc-query -> LLM has context
- [ ] SessionStart hook integration automatically injects context on compaction
- [ ] Cross-session chains are tracked and queryable with `--include-parent`
- [ ] Search works across sessions for keywords and file paths
- [ ] Event replay produces readable, accurate narratives
- [ ] Performance targets are met (< 2s rebuild, < 500ms cached read)
- [ ] All edge cases are handled gracefully (no crashes, clear error messages)
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Manual testing confirms the flow works in a real Claude Code session
