# Story 03: Storage Layer

## Overview

The storage layer is the filesystem-based event store at the core of GlobalContext. It defines how events, projections, metadata, and configuration are organized on disk. There are no external database dependencies -- everything is plain JSON files managed through POSIX filesystem primitives (directories, files, symlinks, flock).

This layer must be reliable above all else. Every event written must survive process crashes, concurrent writers, and unexpected conditions. The storage layer sits between the write side (capture-event) and the read side (projections), serving as the single source of truth.

### Relationship to Architecture

Refer to `/docs/ARCHITECTURE.md` for the full system design. The storage layer implements the `EVENT STORE` and supporting structures described in that document. It provides:

- The append-only event log (`events/` directory tree)
- The projection cache (`projections/` directory tree)
- The per-project quick-access symlink (`projections/{project-id}/latest`)
- Per-session metadata (`events/{project-id}/{session-id}/session.json`)
- Store-level configuration (`config.json`)
- Executable entry points (`bin/`)

### Dependencies

- **Upstream**: Capture-event script (Story 02) writes events into this layer.
- **Downstream**: Projection engine (Story 04) reads events from this layer to build read models.
- **External**: None. Filesystem only. Requires POSIX-compatible OS with `flock` support.

---

## Requirement 1: Directory Structure

### Description

The storage layer uses a fixed directory hierarchy rooted at `~/.claude-context/`. Every component of the system has a well-defined location. The structure is deterministic -- given a session ID, the path to any event or projection file can be computed without scanning.

### Specification

```
~/.claude-context/
├── events/
│   ├── {project-id}/
│   │   ├── {session-id}/
│   │   │   ├── session.json        # per-session metadata
│   │   │   ├── .lock               # flock for sequence coordination
│   │   │   ├── 000001.json
│   │   │   ├── 000002.json
│   │   │   └── ...
│   │   └── {another-session-id}/
│   └── {another-project-id}/
├── projections/
│   ├── {project-id}/
│   │   ├── {session-id}/
│   │   │   ├── timeline.json
│   │   │   ├── files-touched.json
│   │   │   ├── decisions.json
│   │   │   └── context.json
│   │   └── latest -> {session-id}  # per-project symlink
│   └── {another-project-id}/
├── bin/
│   ├── capture-event
│   ├── gc-hook
│   ├── project
│   └── gc-query
└── config.json
```

The `{project-id}` is derived from the working directory: `{basename}-{hash6}` where `hash6` is the first 6 hex characters of SHA-256 of the full absolute path. See ARCHITECTURE.md and DESIGN-AMENDMENTS.md (Amendment 3) for details.

#### Directory Purposes

| Path | Type | Purpose |
|------|------|---------|
| `~/.claude-context/` | dir | Root of all storage. Permissions 700. |
| `events/` | dir | Contains all project directories. Append-only event log. |
| `events/{project-id}/` | dir | All session directories for a single project. |
| `events/{project-id}/{session-id}/` | dir | All events for a single session, plus lock and metadata. |
| `events/{project-id}/{session-id}/session.json` | file | Per-session metadata (event count, timestamps, etc.). |
| `events/{project-id}/{session-id}/.lock` | file | flock target for sequence number coordination within this session. |
| `projections/` | dir | Contains all projection outputs (read models). |
| `projections/{project-id}/` | dir | Projection directories for a single project. |
| `projections/{project-id}/{session-id}/` | dir | Projection files for a single session. |
| `projections/{project-id}/latest` | symlink | Points to the most recent session's projection directory within this project. |
| `bin/` | dir | Executable scripts for capture, projection, and querying. |
| `config.json` | file | Store-level configuration. |

### Acceptance Criteria

- [ ] Running the init command creates the top-level directory structure (`events/`, `projections/`, `bin/`). Per-project and per-session directories are created on demand.
- [ ] The root directory `~/.claude-context/` has permissions `700` (owner only).
- [ ] The `events/`, `projections/`, and `bin/` directories exist after initialization.
- [ ] The `bin/` directory contains executable scripts (`capture-event`, `gc-hook`, `project`, `gc-query`) with permissions `755`.
- [ ] A valid `config.json` is created with default values.
- [ ] The directory structure can be created on Linux and macOS without errors.
- [ ] Re-running init on an existing store is safe (idempotent) -- it does not overwrite existing data.

---

## Requirement 2: Event File Format

### Description

Each event is stored as an individual JSON file. One file per event. The filename encodes the sequence number. The file content is a complete, self-describing event envelope.

### Specification

#### Filename Convention

- Pattern: `{6-digit-zero-padded-sequence}.json`
- Examples: `000001.json`, `000042.json`, `999999.json`
- Sequence starts at 1 for each session (not 0).
- Maximum theoretical events per session: 999,999.

#### Event Envelope Schema

```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "event_type": "ToolCallCompleted",
  "project_id": "my-project-a3f7b2",
  "session_id": "session-abc123",
  "sequence": 42,
  "timestamp": "2026-02-14T10:30:00.000Z",
  "data": {
    "tool_name": "Read",
    "tool_input": { "file_path": "/home/user/project/main.py" },
    "tool_result": "...file contents..."
  }
}
```

#### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `event_id` | string (UUID v4) | yes | Globally unique identifier for this event. |
| `event_type` | string | yes | One of the defined event types (see Architecture doc). |
| `project_id` | string | yes | Project identifier derived from working directory (`{basename}-{hash6}`). |
| `session_id` | string | yes | Claude Code session identifier. |
| `sequence` | integer | yes | Monotonically increasing per-session sequence number (1-based). |
| `timestamp` | string (ISO 8601) | yes | UTC timestamp of when the event was captured. |
| `data` | object | yes | The full hook payload. Schema varies by event_type. |

#### Encoding Rules

- UTF-8 encoded.
- Compact JSON (no pretty-print, no trailing newline). This minimizes disk usage.
- No BOM (byte order mark).
- Valid JSON (parseable by `jq` and any JSON parser).

### Acceptance Criteria

- [ ] Each event file contains exactly one JSON object (the event envelope).
- [ ] The filename matches the pattern `/^[0-9]{6}\.json$/`.
- [ ] The `sequence` field inside the envelope matches the filename (e.g., `000042.json` contains `"sequence": 42`).
- [ ] The `event_id` is a valid UUID v4, unique across all events.
- [ ] The `timestamp` is a valid ISO 8601 string in UTC.
- [ ] Files are UTF-8 encoded without BOM.
- [ ] Files are compact JSON (single line, no unnecessary whitespace).
- [ ] Files can be parsed by `jq .` without errors.
- [ ] The `data` field contains the complete hook payload as received from stdin.
- [ ] A session with 1,000 events has files numbered `000001.json` through `001000.json` with no gaps under normal operation.

---

## Requirement 3: Session Directory Management

### Description

Each Claude Code session gets its own directory under `events/`. The directory is created lazily on the first event for that session. It contains the event files and a `.lock` file for concurrency control.

### Specification

#### Directory Naming

- Path: `~/.claude-context/events/{project-id}/{session-id}/`
- The `session_id` comes directly from the Claude Code hook payload.
- The `project_id` is derived from the working directory (see Requirement 1).
- Session IDs from Claude Code are expected to be alphanumeric with possible hyphens (e.g., `abc123`, `session-2026-02-14-a1b2c3`).

#### Session ID Sanitization

Because session IDs come from an external source (Claude Code), they must be sanitized before use as directory names:

- **Allowed characters**: `a-z`, `A-Z`, `0-9`, `-`, `_`
- **Disallowed characters**: all other characters including `.`, `/`, `\`, spaces, null bytes, unicode beyond ASCII
- **Sanitization strategy**: Strip disallowed characters (using `tr -cd 'a-zA-Z0-9_-'`). If the result is empty, use `"unknown"`.
- **Maximum length**: 255 characters (filesystem limit). Truncate if longer.

#### Lifecycle

1. **Creation**: On the first event for a session, `mkdir -p` the session directory and create the `.lock` file.
2. **Active use**: Events are appended as numbered JSON files. The `.lock` file is used for flock coordination.
3. **Completion**: The directory remains after the session ends. No cleanup happens automatically.
4. **Retention**: Session directories are never deleted automatically. Cleanup is deferred (see Amendment 4).

### Acceptance Criteria

- [ ] The session directory is created atomically on the first event for a session.
- [ ] A `.lock` file exists in every session directory.
- [ ] Session IDs with only alphanumeric characters, hyphens, and underscores are used as-is for directory names.
- [ ] Session IDs with disallowed characters (`/`, `.`, spaces, etc.) have those characters stripped.
- [ ] Session IDs longer than 255 characters are truncated.
- [ ] An empty or all-disallowed session ID falls back to `"unknown"`.
- [ ] Session directories are never deleted by the capture or projection code.
- [ ] Two events for the same session always write to the same directory, regardless of timing.
- [ ] The session directory creation is safe under concurrent calls (two events for the same new session arriving simultaneously do not cause errors).

---

## Requirement 4: Per-Session Metadata (session.json)

### Description

Each session directory contains a `session.json` file that tracks metadata about that session. This replaces a global sessions index — there is no shared state between sessions. The `session.json` is updated within the same flock scope used for sequence coordination, adding no new contention.

> **Design Amendment 1 & 2**: The original design had a global `projections/sessions.json` index updated on every event. This violated the CQRS "write side is fast and dumb" principle and introduced flock contention between concurrent sessions. Per-session `session.json` eliminates shared write-side state entirely.

### Specification

#### File Location

`~/.claude-context/events/{project-id}/{session-id}/session.json`

#### Schema

```json
{
  "session_id": "abc-123",
  "project_id": "my-project-a3f7b2",
  "project_dir": "/home/user/my-project",
  "started_at": "2026-02-14T10:00:00Z",
  "source": "manual",
  "model": "claude-opus-4-6",
  "event_count": 142,
  "last_event_at": "2026-02-14T11:30:00Z",
  "last_event_type": "TurnCompleted",
  "last_prompt": "Fix the auth bug in handler.ts",
  "ended_at": null,
  "previous_session_id": null
}
```

#### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | string | yes | The session identifier (matches directory name). |
| `project_id` | string | yes | Project identifier (`{basename}-{hash6}`). |
| `project_dir` | string | yes | The working directory (cwd) of the session. |
| `started_at` | string (ISO 8601) | yes | Timestamp from the SessionStarted event. |
| `source` | string | yes | How the session started: `"manual"`, `"resume"`, `"compact"`, `"clear"`. |
| `model` | string | no | The LLM model used in the session, if available from the hook payload. |
| `event_count` | integer | yes | Total number of events recorded for this session. |
| `last_event_at` | string (ISO 8601) | yes | Timestamp of the most recent event. |
| `last_event_type` | string | yes | Event type of the most recent event. |
| `last_prompt` | string | no | Text of the most recent user prompt (from `UserPromptReceived`). |
| `ended_at` | string (ISO 8601) | no | Timestamp from the `SessionEnded` event, if received. |
| `previous_session_id` | string | no | Session ID of the previous session if this is a resume. |

#### Update Rules

Updates happen within the existing per-session flock scope (no additional lock needed):

- **On SessionStarted** (first event): Create `session.json` with `started_at`, `source`, `model`, `project_dir`, `project_id`. Set `event_count` to 1.
- **On UserPromptReceived**: Update `last_prompt` with the prompt text.
- **On SessionEnded**: Set `ended_at` timestamp.
- **On any event**: Increment `event_count`, update `last_event_at` and `last_event_type`.

#### Querying Sessions

To list all sessions, the query side scans event directories and reads each `session.json`:

```bash
# List all sessions for a project
for dir in ~/.claude-context/events/{project-id}/*/; do
  cat "$dir/session.json" 2>/dev/null
done | jq -s '.'
```

This is O(sessions) not O(events), so it's fast enough for typical usage.

### Acceptance Criteria

- [ ] Each session directory contains a `session.json` file after its first event.
- [ ] `session.json` is a valid JSON object at all times.
- [ ] `session.json` is created from the `SessionStarted` event data.
- [ ] `session.json` is updated on every subsequent event (within the existing flock scope).
- [ ] The `event_count` field accurately reflects the number of event files in the session directory.
- [ ] The `last_event_at` field matches the timestamp of the most recent event.
- [ ] The `source` field is one of: `"manual"`, `"resume"`, `"compact"`, `"clear"`.
- [ ] `last_prompt` is updated when a `UserPromptReceived` event is captured.
- [ ] `ended_at` is set when a `SessionEnded` event is captured.
- [ ] Updates use atomic write (write to temp file, then rename) within the existing lock scope.
- [ ] No global lock or shared file exists for session metadata.
- [ ] Session metadata can be reconstructed by replaying events in the session directory.

---

## Requirement 5: Per-Project Latest Session Symlink

### Description

Each project has a symlink at `projections/{project-id}/latest` that points to the projection directory of the most recently started session within that project. This provides O(1) access to the current/last session's projections without scanning.

> **Design Amendment 3**: The original design had a single global `projections/latest` symlink. This is now per-project, allowing each project to track its own latest session independently.

### Specification

#### Location

`~/.claude-context/projections/{project-id}/latest`

#### Target

Points to the relative path `{session-id}/` within the `projections/{project-id}/` directory.

Example: `projections/my-project-a3f7b2/latest -> abc123/`

#### Update Rule

- Updated whenever a SessionStarted event is processed for that project.
- The symlink is replaced atomically: create a new symlink at a temporary name, then rename it over the existing one (`ln -sfn` behavior).

#### Usage

```bash
# Get the latest session's context projection for the current project
project_id=$(gc_derive_project_id "$(pwd)")
cat ~/.claude-context/projections/$project_id/latest/context.json

# Get the latest session ID from the symlink target
readlink ~/.claude-context/projections/$project_id/latest
```

### Acceptance Criteria

- [ ] Each project has its own `latest` symlink at `projections/{project-id}/latest`.
- [ ] There is no global `projections/latest` symlink.
- [ ] The symlink target is a relative path (not absolute), making the store relocatable.
- [ ] The symlink points to the most recently started session's projection directory within that project.
- [ ] Updating the symlink is atomic (using `ln -sfn` or equivalent temp-symlink-then-rename).
- [ ] If the target projection directory does not yet exist, the symlink is still created (the directory will be created when projections are built).
- [ ] Reading the symlink target (`readlink`) returns the session ID.
- [ ] The symlink works correctly on both Linux and macOS.
- [ ] If the symlink cannot be created (e.g., permissions), the error is logged but does not block event capture.

---

## Requirement 6: Projection Storage

### Description

Projections are pre-computed read models built by replaying events. They live under `projections/{project-id}/{session-id}/` as JSON files. Projections are a cache -- they can be deleted and rebuilt from the event log at any time.

### Specification

#### Directory Structure

```
projections/{project-id}/{session-id}/
├── timeline.json
├── files-touched.json
├── decisions.json
└── context.json
```

#### Projection File Definitions

| File | Purpose | Content Summary |
|------|---------|-----------------|
| `timeline.json` | Ordered chronological summary | Array of event summaries: sequence, timestamp, event_type, brief description. |
| `files-touched.json` | File operation tracking | Map of file paths to operations (read, write, edit, glob) with sequence numbers. |
| `decisions.json` | Intent-to-action chains | Array of user prompts paired with the tool calls that followed. |
| `context.json` | Full reconstructable context | Complete session state: prompts, tool calls with results, decisions, file states. This is the primary recovery artifact. |

#### Metadata in Projection Files

Each projection file includes metadata fields at the top level:

```json
{
  "_projection": "timeline",
  "_session_id": "abc123",
  "_rebuilt_at": "2026-02-14T12:00:00.000Z",
  "_event_count": 142,
  "_last_sequence": 142,
  "data": [ ... ]
}
```

- `_projection`: Name of the projection type.
- `_session_id`: Session this projection belongs to.
- `_rebuilt_at`: Timestamp of when this projection was last computed.
- `_event_count`: Number of events processed to build this projection.
- `_last_sequence`: The highest sequence number included in this projection.
- `data`: The actual projection content (schema varies by projection type).

#### Rebuild Rules

- Projections can be rebuilt at any time by replaying all events in `events/{project-id}/{session-id}/` in sequence order.
- If a projection file exists and `_last_sequence` matches the highest event sequence, the projection is up-to-date.
- If new events exist beyond `_last_sequence`, the projection is stale and should be rebuilt (or incrementally updated).
- Deleting all projection files and directories is safe. They will be rebuilt on next query.

### Acceptance Criteria

- [ ] Projection directories are created per session under `projections/`.
- [ ] Each projection file is valid JSON.
- [ ] Each projection file includes `_projection`, `_session_id`, `_rebuilt_at`, `_event_count`, and `_last_sequence` metadata.
- [ ] Projections can be deleted and rebuilt from events with identical results (deterministic).
- [ ] A stale projection (where events exist beyond `_last_sequence`) is detected and rebuilt on query.
- [ ] An up-to-date projection (where `_last_sequence` matches the latest event) is served without rebuild.
- [ ] Projection writes use atomic write (temp file + rename) to prevent partial reads.
- [ ] The projection directory for a session is created lazily (on first projection build, not on session start).

---

## Requirement 7: Config File (config.json)

### Description

`config.json` stores store-level configuration. It is created during initialization and can be edited by the user or by management commands.

### Specification

#### Location

`~/.claude-context/config.json`

#### Schema

```json
{
  "version": "1.0.0",
  "created_at": "2026-02-14T10:00:00.000Z",
  "storage_path": "~/.claude-context"
}
```

> **Design Amendment 4**: `retention_days` has been removed. The `gc-cleanup` command is deferred — it contradicts the append-only principle. At expected usage levels (~11GB over 90 days of heavy use), disk pressure is unlikely. If cleanup is needed later, it can be added as a separate story.
>
> **CQRS note**: `max_event_size_bytes` has been removed. Truncation on the write side violates the "fast and dumb" principle. The write side captures events as-is. If size management is needed, it belongs on the read side (e.g., projection builders can skip large payloads).

#### Field Definitions

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `version` | string | `"1.0.0"` | Schema version for forward compatibility. Follows semver. |
| `created_at` | string (ISO 8601) | (init time) | When this store was first initialized. |
| `storage_path` | string | `"~/.claude-context"` | The root path of this store. Used for self-reference and validation. |

#### Rules

- Created once during `init`. Not overwritten on subsequent init runs.
- User-editable. The system reads it on each operation.
- Invalid config (unparseable JSON, missing required fields) causes a fatal error with a clear message.
- Future versions may add fields. Unknown fields are ignored (forward-compatible).

### Acceptance Criteria

- [ ] `config.json` is created during initialization with all default values.
- [ ] Re-running init does not overwrite an existing `config.json`.
- [ ] All fields are present and correctly typed after initialization.
- [ ] The `version` field is `"1.0.0"`.
- [ ] The `created_at` field is a valid ISO 8601 timestamp.
- [ ] The `storage_path` field defaults to `"~/.claude-context"` (or the value of `CLAUDE_CONTEXT_PATH`).
- [ ] A missing or corrupt `config.json` produces a clear error message (not a silent failure or cryptic error).
- [ ] Unknown fields in `config.json` are preserved (not stripped) during updates.

---

## Requirement 8: File Locking Strategy

### Description

Multiple Claude Code hooks can fire concurrently (especially async hooks like PreToolUse and PostToolUse). The storage layer must handle concurrent writes safely using POSIX file locking (flock).

### Specification

#### Lock Architecture

There is no global lock. Locking is scoped to the narrowest possible resource — per-session only:

| Lock File | Scope | Protects |
|-----------|-------|----------|
| `events/{project-id}/{session-id}/.lock` | Per-session | Sequence number assignment, event file creation, and `session.json` update within a session. |

> **Design Amendment 1**: The global `projections/.sessions.lock` has been removed along with the global `sessions.json`. All locking is now per-session, eliminating cross-session contention entirely.

#### Locking Protocol

```
1. Open lock file (create if not exists)
2. flock --timeout 5 (exclusive lock, 5-second timeout)
3. If lock acquired:
   a. Perform the protected operation (sequence assignment + event write + session.json update)
   b. Release lock (close file descriptor)
4. If lock NOT acquired (timeout):
   a. Log a warning
   b. Skip the operation OR retry once
   c. Never block indefinitely
```

#### Per-Session Lock (.lock file)

- Protects sequence number assignment and `session.json` update — both happen within the same lock scope.
- The sequence is determined by counting existing `[0-9]*.json` files in the session directory, then incrementing by 1.
- The lock ensures two concurrent events for the same session get different sequence numbers.
- Lock hold time target: under 50ms (just enough for: read dir listing, write event file, update session.json, rename).

#### Failure Behavior

- If a lock cannot be acquired within 5 seconds, the operation fails gracefully.
- For event capture: the event is still written (using a fallback UUID-based filename like `orphan-{uuid}.json`) and flagged for reconciliation.

### Acceptance Criteria

- [ ] Each session directory contains a `.lock` file.
- [ ] No global lock file exists (no `projections/.sessions.lock` or similar).
- [ ] flock is used with a 5-second timeout (never blocks indefinitely).
- [ ] Two concurrent events for the same session receive different, consecutive sequence numbers.
- [ ] If flock times out, the system logs a warning and degrades gracefully (does not crash or lose data).
- [ ] Lock hold times are minimized (under 50ms for event writes including session.json update).
- [ ] No global lock exists that could serialize all sessions.
- [ ] Sessions are fully independent -- a locked session does not block other sessions.
- [ ] Lock files are never deleted during normal operation (they are reused).

---

## Requirement 9: Size Management

### Description

The write side does not enforce size limits on individual events — this would violate the CQRS "fast and dumb" principle. The storage layer provides diagnostic tools for monitoring store size.

> **Design Amendment 4**: The `gc-cleanup` command has been deferred. It contradicts the append-only principle. At expected usage levels (~11GB over 90 days of heavy use), disk pressure is unlikely. If cleanup is needed later, it can be added as a separate story.
>
> **CQRS note**: Per-event truncation has been removed from the write side. The capture script stores events as-is without size checks. If size management is needed, it belongs on the read side (e.g., projection builders can summarize large payloads).

### Specification

#### No Write-Side Size Limits

- The capture script writes events without checking payload size.
- Very large payloads (e.g., reading a 10MB file) are stored in full.
- This is a deliberate trade-off: data completeness over disk efficiency.

#### Store Size Tracking

- No real-time size tracking (too expensive).
- The `gc-query` command can report store size on demand: `gc-query store-size`.
- Reports total event count, total size in bytes, oldest session, newest session.

#### Future: gc-cleanup (Deferred)

When implemented in a future story, `gc-cleanup` would:
- Support `--dry-run` to report what would be deleted
- Support `--older-than DAYS` for age-based cleanup
- Support `--session SESSION_ID` for targeted cleanup
- Remove corresponding projection directories during cleanup

### Acceptance Criteria

- [ ] The capture script does not check or limit event payload size.
- [ ] Very large payloads (>1MB) are stored without truncation.
- [ ] The `gc-query store-size` command reports total events, total bytes, and session date range.
- [ ] No `gc-cleanup` command exists in this version (deferred to future story).

---

## Requirement 10: Initialization

### Description

The `init` command sets up the full directory structure, creates configuration files, and validates the filesystem. It must be idempotent -- safe to run multiple times without data loss.

### Specification

#### Init Process

```
1. Determine storage path (default: ~/.claude-context, or from env var CLAUDE_CONTEXT_PATH)
2. Create root directory with permissions 700
3. Create subdirectories: events/, projections/, bin/
4. Create config.json with defaults (if not exists)
5. Copy/install bin/ scripts (capture-event, gc-hook, project, gc-query) with permissions 755
6. Validate: directory is writable, at least 10MB free space
7. Print summary of what was created/verified
```

Note: Per-project directories (`events/{project-id}/`, `projections/{project-id}/`) and per-session directories are created on demand by the capture-event script, not during init.

#### Permissions

| Path | Permission | Rationale |
|------|-----------|-----------|
| `~/.claude-context/` | `700` | Owner-only access to the store root. |
| `events/` | `700` | Owner-only access to event data. |
| `events/{project-id}/` | `700` | Per-project directory. |
| `events/{project-id}/{session-id}/` | `700` | Per-session directory. |
| `projections/` | `700` | Owner-only access to projections. |
| `bin/` | `755` | Scripts need to be executable. |
| `bin/*` | `755` | Executable scripts. |
| Event files (`*.json`) | `600` | Owner read/write only. |
| `session.json` | `600` | Owner read/write only. Per-session metadata. |
| `config.json` | `600` | Owner read/write only. Sensitive configuration. |

#### Environment Variable Override

- `CLAUDE_CONTEXT_PATH`: If set, use this path instead of `~/.claude-context`.
- This allows testing, custom installations, and multi-store setups.

#### Idempotency Rules

- Directories: `mkdir -p` (safe if exists).
- `config.json`: Skip if exists (print "config.json already exists, skipping").
- `bin/` scripts: Always overwrite (to support upgrades).

### Acceptance Criteria

- [ ] Running `init` on a clean system creates the full directory structure.
- [ ] Running `init` on an existing store does not delete or overwrite any event or projection data.
- [ ] Running `init` on an existing store does not overwrite `config.json`.
- [ ] Running `init` on an existing store updates `bin/` scripts (to support upgrades).
- [ ] The root directory has permissions `700`.
- [ ] Event files created by the capture script have permissions `600`.
- [ ] The `CLAUDE_CONTEXT_PATH` environment variable overrides the default storage path.
- [ ] Init validates that the filesystem is writable (writes and deletes a test file).
- [ ] Init validates that at least 10MB of free disk space is available.
- [ ] Init prints a summary of what it created (directories, files) and what it skipped (already existing).
- [ ] Init exits with code 0 on success and non-zero on failure, with a clear error message.

---

## Requirement 11: Data Integrity

### Description

Events are the source of truth. A corrupt or partially written event file can cause data loss or projection errors. The storage layer must use defensive writing strategies to ensure every file on disk is either complete and valid, or not present at all.

### Specification

#### Atomic Writes

All file writes (events, projections, sessions.json) use the atomic write pattern:

```
1. Generate temp filename: {target}.tmp.{pid} (e.g., 000042.json.tmp.12345)
2. Write complete content to temp file
3. fsync the temp file (flush to disk)
4. Rename temp file to target filename (atomic on POSIX filesystems)
```

- If the process crashes during step 2, only the temp file is left (easily cleaned up).
- If the process crashes during step 4, either the old file or the new file is present (never a partial file).
- Temp files matching `*.tmp.*` in event directories can be safely deleted on startup.

#### JSON Validation

Before writing an event file:

```
1. Serialize the event envelope to JSON
2. Validate the JSON is parseable (pipe through jq or JSON.parse)
3. Verify required fields are present (event_id, event_type, session_id, sequence, timestamp, data)
4. Only then proceed with atomic write
```

If validation fails, the event is written to a `_rejected/` subdirectory with the validation error appended, for debugging.

#### Orphan Temp File Cleanup

- On init, scan for and delete any `*.tmp.*` files in the `events/` tree.
- These are artifacts of interrupted writes and are always safe to delete.

#### Optional Checksum

- If enabled in config (`"checksum": true`), each event file gets an additional `_checksum` field in the envelope.
- The checksum is a SHA-256 hash of the `data` field (serialized JSON).
- This allows verification that event data has not been corrupted on disk.
- Disabled by default (adds overhead).

```json
{
  "event_id": "...",
  "event_type": "...",
  "session_id": "...",
  "sequence": 42,
  "timestamp": "...",
  "data": { ... },
  "_checksum": "sha256:a1b2c3d4..."
}
```

### Acceptance Criteria

- [ ] All file writes use the atomic write pattern (write to temp, then rename).
- [ ] A process crash during write never leaves a partially written target file.
- [ ] Temp files use the pattern `{target}.tmp.{pid}` for uniqueness.
- [ ] JSON is validated before writing (unparseable JSON is never written to an event file).
- [ ] Events missing required fields are rejected and written to a `_rejected/` directory.
- [ ] The init command cleans up any orphan temp files from previous interrupted runs.
- [ ] When checksum is enabled, the `_checksum` field is present and correct in event files.
- [ ] When checksum is disabled (default), no `_checksum` field is added.
- [ ] Checksums can be verified after the fact by replaying the data field through SHA-256.
- [ ] Rename-based atomic writes work correctly on the target filesystem (ext4, APFS, etc.).

---

## Edge Cases

### Session ID with Special Characters

| Input | Sanitized | Notes |
|-------|-----------|-------|
| `abc123` | `abc123` | No change needed. |
| `session/with/slashes` | `sessionwithslashes` | Slashes stripped. |
| `has spaces` | `hasspaces` | Spaces stripped. |
| `unicode-café` | `unicode-caf` | Non-ASCII stripped. |
| `../../../etc/passwd` | `etcpasswd` | Path traversal neutralized (dots and slashes stripped). |
| (empty string) | `unknown` | Fallback to fixed name. |
| `.hidden` | `hidden` | Dot stripped. |
| 300-char string | (first 255 chars) | Truncated to filesystem limit. |

The capture-event script must sanitize session IDs before any filesystem operation. Path traversal attacks must be impossible.

### Disk Full During Write

1. The atomic write detects the failure during temp file write (write returns error or short write).
2. The temp file is deleted (best-effort cleanup).
3. The capture-event script logs the error to stderr and exits 0 (never blocks Claude Code).
4. The event is lost (this is acceptable -- the system is best-effort for individual events, not transactional).
5. The hook system in Claude Code will see the non-zero exit but continue operation (hooks do not block the LLM).

### Concurrent Events for Same Session

Handled by flock on the per-session `.lock` file. Worst case with timeout:
- Writer A acquires lock, writes event + updates session.json.
- Writer B waits up to 5 seconds.
- If Writer A finishes within 5 seconds (expected: under 50ms), Writer B proceeds.
- If Writer A is stuck (extremely unlikely for a file write), Writer B times out and drops the event.
- Per-session metadata (session.json) is always consistent within its own lock scope.

### Very Long-Running Sessions (100K+ Events)

- 100,000 event files in a single directory may cause performance issues on some filesystems.
- **Mitigation (future)**: For sessions exceeding 10,000 events, consider subdirectory bucketing (e.g., `events/{session-id}/000/000001.json`). This is not implemented in v1.0 but the architecture allows for it.
- **Current approach**: Rely on modern filesystem capabilities (ext4 with dir_index, APFS). Most sessions are expected to have under 5,000 events.
- **Sequence number ceiling**: 999,999 events per session. If reached, the capture script logs an error and stops recording for that session.

### Symlink Permissions on Different Filesystems

- Symlinks do not have independent permissions on most POSIX systems (they inherit the target's permissions).
- On NFS or some mounted filesystems, symlink creation may fail. The capture script must handle this gracefully (log and continue).
- The per-project `latest` symlink is a convenience, not a critical feature. Its absence does not break any functionality — session directories can be scanned directly.

### Store on NFS or Network Filesystems

- flock may not work reliably on NFS (depends on NFS version and server configuration).
- **Recommendation**: Store should be on a local filesystem. The init command should warn if the target path is on a network mount.
- **Fallback**: If flock fails, the system still functions but with a small risk of sequence number conflicts. These can be detected and resolved by the projection engine (gaps or duplicates in sequence numbers).

---

## Non-Goals

The following are explicitly out of scope for this story:

- **Database storage**: This story is filesystem-only. No SQLite, no PostgreSQL, no embedded databases.
- **Encryption at rest**: Event files are stored as plaintext JSON. Encryption may be added in a future story.
- **Remote/cloud storage**: No S3, no GCS, no Azure Blob. Storage is local filesystem only.
- **Real-time file watching**: The projection engine polls or is triggered explicitly, not via inotify/fswatch.
- **Compression**: Event files are not compressed. Compression may be added as part of a future archival story.
- **Multi-user access**: The store is single-user (the owner of `~/.claude-context`). No multi-tenancy.

---

## Technical Notes

### Why One File Per Event (Not One File Per Session)?

- **Atomic appends**: Each event is a complete, independent file. No risk of corrupting a shared file.
- **Concurrent safety**: Multiple hooks writing to the same session only need sequence coordination, not file-level locking of a shared log.
- **Replay flexibility**: Can replay from any point by reading files from sequence N onward.
- **Failure isolation**: A corrupt event file affects only that one event, not the entire session log.
- **Filesystem as index**: The directory listing IS the event index. `ls events/{project-id}/{session-id}/[0-9]*.json` gives you the event list. `wc -l` gives you the count.

### Why Compact JSON (Not Pretty-Printed)?

- **Space savings**: Pretty-printed JSON is typically 2-3x larger. For a session with 1,000 events averaging 2KB each, this is the difference between 2MB and 6MB.
- **Read performance**: Smaller files are faster to read and parse.
- **Debuggability**: Use `jq .` to pretty-print any event file for inspection. The data is not opaque.

### Performance Characteristics

| Operation | Expected Latency | Notes |
|-----------|-----------------|-------|
| Write single event | < 10ms | Includes flock acquire + event write + session.json update + rename. |
| Read single event | < 5ms | Single file read + JSON parse. |
| List session events | < 50ms | Directory listing (even with 10K files). |
| Read session metadata | < 5ms | Single session.json file read. |
| Rebuild projection | < 5s per 1K events | Depends on projection complexity. |

---

## Implementation Checklist

This section provides a suggested implementation order:

1. [ ] Implement the `init` command (directory creation, config.json, permissions).
2. [ ] Implement project and session directory creation and `.lock` file management.
3. [ ] Implement atomic write helper (temp file + rename pattern).
4. [ ] Implement JSON validation helper (validate envelope, reject invalid).
5. [ ] Implement flock-based sequence number assignment.
6. [ ] Implement event file writing (envelope creation, atomic write).
7. [ ] Implement per-session session.json creation and update (within flock scope).
8. [ ] Implement per-project latest symlink management.
9. [ ] Implement projection directory and file scaffolding.
10. [ ] Implement gc-query store-size command.
11. [ ] Implement orphan temp file cleanup during init.
12. [ ] Add session ID and project ID sanitization with full edge case handling.
13. [ ] Add disk space validation during init.
14. [ ] Write integration tests for concurrent write scenarios.
15. [ ] Write integration tests for crash recovery (interrupted writes).

---

## Testing Strategy

### Unit Tests

- Session ID sanitization: all edge cases from the table above.
- Project ID derivation: basename extraction, hash computation, edge cases.
- Sequence number formatting: verify zero-padding for 1, 42, 999999.
- Event envelope construction: all required fields present and correctly typed (including project_id).
- Config parsing: valid config, missing fields, corrupt JSON, unknown fields.

### Integration Tests

- **Write and read back**: Write 100 events to a session, read them all back, verify order and content.
- **Concurrent writes**: Spawn 10 parallel writers to the same session, verify all events are written with unique sequence numbers and no gaps.
- **Per-session session.json updates**: Write 20 events to a session, verify session.json has correct event_count and last_event_at.
- **Atomic write crash simulation**: Kill the write process mid-write, verify no corrupt target files exist.
- **Init idempotency**: Run init twice, verify no data loss and correct output messages.
- **Disk full simulation**: Fill the filesystem, attempt a write, verify graceful failure.
- **Large session**: Write 10,000 events, verify directory listing performance and sequence correctness.
- **Per-project symlink update**: Start 5 sessions for the same project in sequence, verify the per-project `latest` symlink points to the last one.

### Filesystem Compatibility Tests

- Test on ext4 (Linux default).
- Test on APFS (macOS default).
- Test on tmpfs (for CI/CD environments).
- Verify flock behavior on each filesystem.
- Verify symlink behavior on each filesystem.
