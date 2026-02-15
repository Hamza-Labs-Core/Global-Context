# Story 01: Event Capture System

## Overview

The Event Capture System is the **write side** of the CQRS pattern in GlobalContext. It consists of a single Bash script (`capture-event`) that receives JSON payloads from Claude Code hooks on stdin, wraps them in a structured event envelope, and appends them as immutable JSON files to the filesystem event store.

This script is the foundation of the entire system. Every downstream feature -- projections, timeline replay, context recovery, auditing -- depends on events being captured reliably, completely, and quickly. If this script fails or blocks, either data is lost or the Claude Code session is degraded.

**Guiding principle**: The capture script is fast and dumb. It does not interpret, validate, filter, or transform the hook payload beyond wrapping it in an envelope. All intelligence lives on the read side.

---

## Scope

### In Scope

- `capture-event` Bash script (write path)
- Event envelope construction
- Filesystem event store layout
- Per-session sequence numbering with file locking
- Session ID extraction from hook JSON
- Error handling (silent, non-blocking)
- `install.sh` setup script
- Dependency validation

### Out of Scope (Non-Goals)

- Hook configuration in `~/.claude/settings.json` (separate story)
- Projection engine (timeline, files-touched, decisions, context snapshot)
- Query interface (`gc-query`)
- Context recovery flow
- Cleanup, retention, or archival of old events
- Any UI or interactive component

---

## Requirements

### 1. capture-event Script

The core script lives at `~/.claude-context/bin/capture-event`.

#### Specification

- **Language**: Bash (POSIX-compatible where possible, but Bash-specific features like `local` and `[[ ]]` are acceptable)
- **Location**: `~/.claude-context/bin/capture-event`
- **Executable**: Must have `chmod +x` permission
- **Invocation pattern**: Called by Claude Code hook system as:
  ```
  cat <hook-json> | ~/.claude-context/bin/capture-event <EventType>
  ```
- **Arguments**:
  - `$1` (required): Event type string. One of the 10 defined event types.
- **Input**: Full hook JSON payload on stdin
- **Output**: None on stdout. Diagnostic messages only on stderr.
- **Exit code**: Always `0`. Regardless of what happens internally.

#### Acceptance Criteria

- [ ] Script exists at `~/.claude-context/bin/capture-event` and is executable
- [ ] Accepts event type as first positional argument (`$1`)
- [ ] Reads complete JSON payload from stdin into a variable
- [ ] Produces a valid JSON event envelope file in the event store
- [ ] Handles all 10 event types: `SessionStarted`, `UserPromptReceived`, `ToolCallRequested`, `ToolCallCompleted`, `ToolCallFailed`, `AgentSpawned`, `AgentCompleted`, `TurnCompleted`, `CompactionTriggered`, `SessionEnded`
- [ ] Rejects unknown event types with a stderr warning but still exits 0
- [ ] Works when invoked from any working directory (uses absolute paths internally)
- [ ] Does not produce any stdout output (would interfere with Claude Code hook protocol)
- [ ] Always exits 0, regardless of internal errors

---

### 2. Event Envelope

Every captured event is wrapped in a standard envelope before being written to disk.

#### Schema

```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "event_type": "ToolCallCompleted",
  "project_id": "my-project-a3f7b2",
  "session_id": "abc123-def456",
  "sequence": 42,
  "timestamp": "2026-02-14T10:30:00.000Z",
  "data": {
    // raw hook JSON payload, unmodified
  }
}
```

#### Field Definitions

| Field | Type | Description |
|---|---|---|
| `event_id` | string (UUID v4) | Globally unique identifier for this event |
| `event_type` | string | One of the 10 defined event types, taken from `$1` |
| `project_id` | string | Project identifier derived from the working directory (`{basename}-{hash6}`) |
| `session_id` | string | Session identifier extracted from the hook JSON payload |
| `sequence` | integer | Per-session monotonically increasing counter (1-based) |
| `timestamp` | string (ISO 8601) | UTC timestamp of when the event was captured, with millisecond precision |
| `data` | object | The complete, unmodified hook JSON payload |

#### event_id Generation

The script must generate a UUID v4 for each event. Use the following fallback chain:

1. `uuidgen` command (if available, most Linux/macOS systems)
2. Read from `/proc/sys/kernel/random/uuid` (Linux kernel fallback)
3. If both fail, construct a pseudo-UUID from timestamp + PID + random: `$(date +%s%N)-$$-$RANDOM-$RANDOM` (last resort, not a real UUID, but unique enough for our purposes)

#### project_id Derivation

The `project_id` is derived from the working directory at the time the hook fires:

```bash
cwd="$(pwd)"
basename="$(basename "$cwd")"
hash6="$(printf '%s' "$cwd" | sha256sum | cut -c1-6)"
project_id="${basename}-${hash6}"
```

This produces a human-readable identifier like `my-project-a3f7b2`. The hash ensures uniqueness across different paths that share the same directory name (e.g., `/home/user/work/api` and `/home/user/personal/api`).

#### timestamp Generation

```bash
date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
```

If `%3N` is not supported (some minimal environments), fall back to:
```bash
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

#### Envelope Construction

Use `jq` to construct the envelope. The raw payload goes into the `data` field without any transformation:

```bash
jq -n \
  --arg eid "$event_id" \
  --arg etype "$event_type" \
  --arg pid "$project_id" \
  --arg sid "$session_id" \
  --argjson seq "$sequence" \
  --arg ts "$timestamp" \
  --argjson data "$payload" \
  '{
    event_id: $eid,
    event_type: $etype,
    project_id: $pid,
    session_id: $sid,
    sequence: $seq,
    timestamp: $ts,
    data: $data
  }'
```

#### Acceptance Criteria

- [ ] Every written event file contains all 7 envelope fields
- [ ] `event_id` is a valid UUID (or fallback unique ID) and is unique per event
- [ ] `event_type` matches the value passed as `$1` exactly
- [ ] `session_id` is extracted from the hook payload (see Section 4)
- [ ] `sequence` is a positive integer, monotonically increasing per session
- [ ] `timestamp` is ISO 8601 UTC format with at least second precision
- [ ] `data` contains the complete, unmodified hook JSON payload
- [ ] The written file is valid JSON (parseable by `jq .`)
- [ ] `data` preserves all fields from the original hook payload, including nested objects and arrays

---

### 3. Sequence Numbering

Each session has its own sequence counter. Sequence numbers are monotonically increasing integers starting at 1. They serve as both the ordering mechanism and the filename.

#### Storage Layout

```
~/.claude-context/events/{project-id}/{session-id}/
  000001.json     # sequence 1
  000002.json     # sequence 2
  000003.json     # sequence 3
  ...
  .lock           # lock file for sequence coordination
```

The `{project-id}` is derived from the working directory: `{basename}-{hash6}`, where `hash6` is the first 6 hex characters of a SHA-256 hash of the full absolute path. See ARCHITECTURE.md for details.

#### Sequence Assignment Algorithm

```
1. Acquire exclusive lock on {session-dir}/.lock using flock
2. List existing *.json files in {session-dir}, count them
3. Next sequence = count + 1
4. Write event file as {zero-padded sequence}.json
5. Release lock (automatic on fd close)
```

Concretely in Bash:

```bash
SESSION_DIR="$EVENTS_DIR/$project_id/$session_id"
LOCK_FILE="$SESSION_DIR/.lock"

(
  flock -w 5 200 || { echo "Lock timeout" >&2; exit 0; }

  # Count existing event files (only numbered files, exclude session.json)
  existing=$(ls "$SESSION_DIR"/[0-9]*.json 2>/dev/null | wc -l)
  next_seq=$((existing + 1))

  # Zero-pad to 6 digits
  padded=$(printf "%06d" "$next_seq")

  # Write the event file
  echo "$envelope_json" > "$SESSION_DIR/${padded}.json"

) 200>"$LOCK_FILE"
```

#### Zero-Padding

Sequence numbers are zero-padded to 6 digits in filenames:
- `1` becomes `000001.json`
- `42` becomes `000042.json`
- `999999` becomes `999999.json`

This ensures correct lexicographic sorting up to 999,999 events per session, which is far beyond any practical session length.

#### Lock Timeout

The `flock` call must have a timeout (`-w 5` for 5 seconds). If the lock cannot be acquired within the timeout:
- Log a warning to stderr
- Exit 0 (do not block Claude Code)
- The event is lost (acceptable trade-off vs. blocking the session)

#### Acceptance Criteria

- [ ] Sequence numbers start at 1 for each new session
- [ ] Sequence numbers are strictly monotonically increasing within a session
- [ ] Filenames are zero-padded to 6 digits (e.g., `000001.json`)
- [ ] `flock` is used for exclusive locking during sequence assignment and file write
- [ ] Lock file is located at `{session-dir}/.lock`
- [ ] Lock has a timeout of 5 seconds (`flock -w 5`)
- [ ] If lock cannot be acquired, script logs to stderr and exits 0
- [ ] Two concurrent invocations for the same session produce two distinct, sequential event files (no duplicates, no gaps under normal operation)
- [ ] The `sequence` field inside the JSON envelope matches the filename number
- [ ] Sequence determination and file write happen atomically within the lock

---

### 4. Session ID Extraction

The session ID is extracted from the hook JSON payload. Different hook events carry the session ID in different fields.

#### Extraction Logic

Use `jq` to extract the session ID from the hook payload:

```bash
session_id=$(echo "$payload" | jq -r '.session_id // empty')
```

If `session_id` is empty or null after extraction, fall back to `"unknown"`.

#### Session Directory Creation

```bash
SESSION_DIR="$EVENTS_DIR/$project_id/$session_id"
mkdir -p "$SESSION_DIR"
```

#### Session ID Sanitization

Session IDs may contain characters unsafe for filesystem paths. The script must sanitize the session ID for use as a directory name:

- Allow: alphanumeric characters, hyphens (`-`), underscores (`_`)
- Disallow: all other characters including dots (`.`), slashes, spaces, unicode beyond ASCII
- Replace disallowed characters by stripping them
- Truncate to 255 characters maximum (POSIX filesystem limit)
- If the sanitized result is empty, use `"unknown"`

```bash
safe_session_id=$(printf '%s' "$session_id" | tr -cd 'a-zA-Z0-9_-' | cut -c1-255)
if [ -z "$safe_session_id" ]; then
  safe_session_id="unknown"
fi
```

Note: These rules align with Story 03's canonical sanitization rules. Dots are excluded to prevent hidden directories and path traversal attacks.

#### Acceptance Criteria

- [ ] `session_id` is extracted from the hook JSON payload using `jq`
- [ ] If `session_id` is missing, null, or empty, the fallback value `"unknown"` is used
- [ ] Session ID is sanitized for filesystem safety (only alphanumeric, hyphens, underscores — no dots)
- [ ] Session directory is created with `mkdir -p` if it does not exist
- [ ] Session IDs longer than 255 characters are truncated
- [ ] The original (unsanitized) `session_id` is preserved in the event envelope `session_id` field
- [ ] Only the filesystem directory name uses the sanitized version

---

### 5. Error Handling

The capture script **must never block or crash Claude Code**. All failures are silent from Claude Code's perspective: logged to stderr, exit 0.

#### Error Categories and Handling

| Error | Detection | Response |
|---|---|---|
| `jq` not installed | `command -v jq` fails | Log to stderr, exit 0. Event is lost. |
| `flock` not available | `command -v flock` fails | Log to stderr, attempt write without lock (best-effort), exit 0 |
| Empty stdin | `$payload` is empty after read | Log to stderr, exit 0 |
| Malformed JSON on stdin | `jq` parse fails | Store raw text in `data` as a string instead of object, or exit 0 |
| Disk full | Write fails | Log to stderr, exit 0 |
| Permission denied | `mkdir` or write fails | Log to stderr, exit 0 |
| Lock timeout | `flock -w 5` fails | Log to stderr, exit 0 |
| Missing event type arg | `$1` is empty | Log to stderr, exit 0 |
| Unknown event type | `$1` not in known list | Log warning to stderr, but still capture the event (forward compatibility) |

#### Error Logging Format

All error messages written to stderr should follow a consistent format:

```
[capture-event] ERROR: <message>
[capture-event] WARN: <message>
```

Example:
```
[capture-event] ERROR: jq not found. Install jq to enable event capture.
[capture-event] WARN: Could not acquire lock after 5s, dropping event.
[capture-event] ERROR: Failed to write event file: Permission denied
```

#### Trap-Based Safety

The script should use a `trap` to ensure it always exits 0 even if an unexpected error occurs:

```bash
trap 'exit 0' ERR EXIT
set -o pipefail  # but NOT set -e (we handle errors manually)
```

Note: `set -e` must NOT be used because it would cause the script to exit on the first error, potentially before the trap can fire. `set -o pipefail` is used so piped commands propagate errors for our manual handling.

#### Acceptance Criteria

- [ ] Script exits 0 under every possible error condition
- [ ] A `trap` is set to guarantee exit 0 on unexpected errors
- [ ] `set -e` is NOT used
- [ ] Missing `jq` is detected early and script exits gracefully
- [ ] Empty stdin is handled without crashing
- [ ] Malformed JSON on stdin does not crash the script
- [ ] Disk full / permission denied on write is caught and logged
- [ ] Lock timeout is caught and script exits cleanly
- [ ] All error messages go to stderr, never stdout
- [ ] Error messages include the `[capture-event]` prefix for grep-ability in logs

---

### 6. Performance

The capture script is called on every hook event. For async hooks (the majority), it must not noticeably impact session performance. For sync hooks, it must complete within the hook timeout.

#### Performance Budget

| Hook Type | Target Latency | Hard Limit |
|---|---|---|
| Async hooks | < 50ms | 100ms |
| Sync hooks | < 100ms | 5000ms (hook timeout) |

#### Optimization Strategies

1. **Single jq invocation**: Construct the entire envelope JSON in one `jq` call, not multiple piped invocations.
2. **Minimal subprocesses**: The script should spawn at most:
   - 1x `jq` (envelope construction + session_id extraction can be combined)
   - 1x `date` (timestamp)
   - 1x `uuidgen` or 1x read from `/proc/sys/kernel/random/uuid`
   - 1x `flock` (implicit in the subshell redirect)
3. **Read stdin once**: Read the full payload into a variable once with `read` or a `$(cat)` call. Do not re-read stdin.
4. **Avoid unnecessary validation**: Do not validate the payload schema. Do not check field types. Just wrap and write.
5. **Combined extraction**: Extract `session_id` from the payload in the same `jq` call that constructs the envelope, if possible.

#### Measurement

During development, the script should be testable with:

```bash
time echo '{"session_id":"test123"}' | ~/.claude-context/bin/capture-event SessionStarted
```

This must consistently complete in under 100ms on a modern system.

#### Acceptance Criteria

- [ ] Script completes in under 100ms for a typical async hook payload
- [ ] At most 4 subprocess invocations per execution (jq, date, uuidgen, and the implicit flock)
- [ ] stdin is read exactly once into a variable
- [ ] No unnecessary disk reads (e.g., reading back the file just written)
- [ ] No network calls
- [ ] No sleep or busy-wait loops
- [ ] Envelope is constructed in a single `jq` invocation

---

### 7. Dependencies

#### Required

| Dependency | Purpose | Package |
|---|---|---|
| `jq` | JSON parsing and construction | `jq` (apt, brew, etc.) |
| `flock` | File-based exclusive locking | `util-linux` (usually pre-installed on Linux) |
| `bash` | Script interpreter | pre-installed on all target systems |

#### Optional (with fallbacks)

| Dependency | Purpose | Fallback |
|---|---|---|
| `uuidgen` | UUID v4 generation | `/proc/sys/kernel/random/uuid`, then timestamp+PID composite |
| `date` with `%3N` | Millisecond-precision timestamps | `date` without milliseconds |

#### Dependency Validation

The script should validate critical dependencies (`jq`) at the start of every invocation. This must be fast (single `command -v` check). If `jq` is missing, the script logs an error and exits 0 immediately.

```bash
if ! command -v jq &>/dev/null; then
  echo "[capture-event] ERROR: jq not found. Install jq to enable event capture." >&2
  exit 0
fi
```

The `flock` check should be done just before the lock is needed. If `flock` is missing, fall back to writing without locking (acceptable risk of a rare sequence collision vs. losing all events).

#### Acceptance Criteria

- [ ] Script checks for `jq` at startup and exits gracefully if missing
- [ ] Script checks for `flock` before locking and falls back to unlocked write if missing
- [ ] UUID generation works with `uuidgen`, `/proc/sys/kernel/random/uuid`, or the fallback composite
- [ ] Timestamp generation works with or without `%3N` millisecond support
- [ ] No dependencies beyond `bash`, `jq`, `flock`, `date`, and standard coreutils

---

### 8. Event-Type Specific Handling

While the capture script does not transform or validate payloads, this section documents the expected payload shapes for each event type. This serves as a reference for the developer implementing the script and for downstream projection consumers.

The `data` field in the envelope contains the **complete raw hook JSON**. No fields are extracted, renamed, or removed. The descriptions below document what fields are expected to be present, not what the script enforces.

#### 8.1 SessionStarted

**Hook**: `SessionStart` (sync)

Expected payload fields:
```json
{
  "session_id": "string",
  "source": "startup | resume | compact | clear",
  "model": "string (e.g., claude-opus-4-6)"
}
```

Notes:
- `source` indicates why the session started: fresh startup, resuming a previous session, after compaction, or after context clear.
- This is a sync hook. The script must complete before the session proceeds.
- This is typically the first event in a session.

#### 8.2 UserPromptReceived

**Hook**: `UserPromptSubmit` (sync)

Expected payload fields:
```json
{
  "session_id": "string",
  "prompt": "string (the user's message text)"
}
```

Notes:
- `prompt` contains the full text the user typed or pasted.
- This is a sync hook.

#### 8.3 ToolCallRequested

**Hook**: `PreToolUse` (async)

Expected payload fields:
```json
{
  "session_id": "string",
  "tool_name": "string (e.g., Bash, Read, Write, Edit, Grep, Glob)",
  "tool_input": { },
  "tool_use_id": "string"
}
```

Notes:
- `tool_input` is an object whose shape varies per tool. For `Bash`, it contains `{ "command": "..." }`. For `Read`, it contains `{ "file_path": "..." }`. And so on.
- `tool_use_id` is a unique identifier for this specific tool invocation, used to correlate with the corresponding `ToolCallCompleted` or `ToolCallFailed` event.
- This is an async hook. High frequency -- fires for every tool call.

#### 8.4 ToolCallCompleted

**Hook**: `PostToolUse` (async)

Expected payload fields:
```json
{
  "session_id": "string",
  "tool_name": "string",
  "tool_input": { },
  "tool_response": "string (tool output, may be very large)",
  "tool_use_id": "string"
}
```

Notes:
- `tool_response` can be very large (e.g., reading a file returns its entire contents as a string). The script must handle arbitrarily large payloads.
- `tool_use_id` correlates with the preceding `ToolCallRequested` event.
- This is an async hook.

#### 8.5 ToolCallFailed

**Hook**: `PostToolUseFailure` (async)

Expected payload fields:
```json
{
  "session_id": "string",
  "tool_name": "string",
  "tool_input": { },
  "error": "string (error message)",
  "is_interrupt": "boolean (true if user cancelled)",
  "tool_use_id": "string"
}
```

Notes:
- `is_interrupt` distinguishes between tool errors and user cancellations.
- This is an async hook.

#### 8.6 AgentSpawned

**Hook**: `SubagentStart` (async)

Expected payload fields:
```json
{
  "session_id": "string",
  "agent_id": "string",
  "agent_type": "string"
}
```

Notes:
- Tracks when Claude Code spawns sub-agents (e.g., the Task tool).
- `agent_id` uniquely identifies this sub-agent instance.

#### 8.7 AgentCompleted

**Hook**: `SubagentStop` (async)

Expected payload fields:
```json
{
  "session_id": "string",
  "agent_id": "string",
  "agent_type": "string",
  "transcript_path": "string (path to sub-agent transcript file)"
}
```

Notes:
- `transcript_path` points to the file containing the sub-agent's conversation transcript.
- `agent_id` correlates with the preceding `AgentSpawned` event.

#### 8.8 TurnCompleted

**Hook**: `Stop` (async)

Expected payload fields:
```json
{
  "session_id": "string",
  "stop_hook_active": "boolean"
}
```

Notes:
- Marks the end of a turn (the LLM has finished responding).
- `stop_hook_active` indicates whether a stop hook was actively triggered.

#### 8.9 CompactionTriggered

**Hook**: `PreCompact` (sync)

Expected payload fields:
```json
{
  "session_id": "string",
  "trigger": "manual | auto"
}
```

Notes:
- **Critical event**. This is the last chance to capture context before compaction discards conversation history.
- `trigger` indicates whether the user manually compacted or it was automatic.
- This is a sync hook. The script must complete before compaction proceeds.

#### 8.10 SessionEnded

**Hook**: `SessionEnd` (async)

Expected payload fields:
```json
{
  "session_id": "string",
  "reason": "string (e.g., user_exit, timeout, error)"
}
```

Notes:
- This event may not always fire (e.g., if the process is killed).
- Downstream projections should not depend on `SessionEnded` for correctness.

#### Acceptance Criteria

- [ ] All 10 event types are accepted by the script
- [ ] The script does not reject or filter any event type
- [ ] The complete hook JSON payload is stored in the `data` field without modification
- [ ] Unknown event types (forward compatibility) are captured with a stderr warning
- [ ] The script does not validate the shape of the payload against expected fields
- [ ] Large payloads (e.g., tool_response with file contents) are handled without truncation

---

### 9. Installation / Setup

An `install.sh` script provisions the directory structure, installs the capture-event script, and validates dependencies.

#### install.sh Behavior

```bash
#!/usr/bin/env bash
# GlobalContext Event Capture - Installer

BASE_DIR="$HOME/.claude-context"

# 1. Create directory structure
mkdir -p "$BASE_DIR/events"
mkdir -p "$BASE_DIR/projections"
mkdir -p "$BASE_DIR/bin"

# 2. Copy (or symlink) capture-event to bin/
cp capture-event "$BASE_DIR/bin/capture-event"
chmod +x "$BASE_DIR/bin/capture-event"

# 3. Validate dependencies
#    - jq: required, fail if missing
#    - flock: required, warn if missing
#    - uuidgen: optional, inform about fallback

# 4. Create config.json with defaults if it does not exist

# 5. Print summary
```

#### Directory Structure Created

```
~/.claude-context/
  events/            # Event store root
  projections/       # Projection output (for future stories)
  bin/               # Executable scripts
    capture-event    # The capture script
  config.json        # Configuration (future use)
```

#### config.json Defaults

```json
{
  "version": "1.0.0",
  "events_dir": "~/.claude-context/events",
  "created_at": "2026-02-14T00:00:00Z"
}
```

#### Dependency Validation Output

The install script should check dependencies and provide clear, actionable output:

```
[install] Checking dependencies...
[install] OK: jq found at /usr/bin/jq
[install] OK: flock found at /usr/bin/flock
[install] OK: uuidgen found at /usr/bin/uuidgen
[install]
[install] GlobalContext installed successfully.
[install] Event store: ~/.claude-context/events/
[install] Capture script: ~/.claude-context/bin/capture-event
```

Or if a required dependency is missing:

```
[install] Checking dependencies...
[install] FAIL: jq not found. Please install jq:
[install]   Ubuntu/Debian: sudo apt install jq
[install]   macOS: brew install jq
[install]   Fedora: sudo dnf install jq
[install]
[install] Installation aborted. Fix the above issues and re-run.
```

#### Idempotency

The install script must be idempotent. Running it multiple times should not:
- Overwrite existing event files
- Reset sequence counters
- Delete any data
- Duplicate configuration

It should:
- Create directories only if they do not exist (`mkdir -p`)
- Overwrite the capture-event script (to pick up new versions)
- Preserve config.json if it already exists

#### Acceptance Criteria

- [ ] `install.sh` creates the full directory structure under `~/.claude-context/`
- [ ] `capture-event` is copied to `~/.claude-context/bin/` and made executable
- [ ] `jq` is validated as present; install aborts with clear instructions if missing
- [ ] `flock` is validated; warning issued if missing but install continues
- [ ] `uuidgen` is checked; fallback noted if missing
- [ ] `config.json` is created with defaults if it does not exist
- [ ] Running `install.sh` twice does not destroy any existing data
- [ ] Install script provides clear, actionable error messages for missing dependencies
- [ ] Install script prints a summary of what was set up on success

---

## Edge Cases

### Concurrent Hook Fires (Same Millisecond)

**Scenario**: Two async hooks fire simultaneously for the same session (e.g., `PreToolUse` and `PostToolUse` for different tool calls).

**Expected behavior**: The `flock` mechanism serializes writes. One process acquires the lock, writes its event, releases the lock. The second process then acquires the lock and writes its event with the next sequence number. Both events are captured with distinct, sequential sequence numbers.

**Risk**: If `flock` is unavailable, both processes may read the same count of existing files and attempt to write the same filename. One write will overwrite the other, losing an event.

**Mitigation**: When `flock` is unavailable, append a random suffix to avoid collisions: `000042_a3f2.json`. This breaks the clean naming convention but preserves data.

---

### Very Large Payloads

**Scenario**: A `PostToolUse` hook fires with a `tool_response` containing the contents of a large file (e.g., a 1MB source file read via the `Read` tool).

**Expected behavior**: The script reads the full payload from stdin, wraps it in the envelope, and writes it to disk. No truncation. No size limit enforced by the capture script.

**Risk**: Very large payloads slow down the `jq` processing step. A 10MB payload could push the script over the 100ms target for async hooks.

**Mitigation**: This is an acceptable trade-off. The script does not enforce size limits. If performance becomes an issue with very large payloads, a future optimization could stream the payload directly to disk and construct the envelope around it, but this is out of scope for this story.

---

### Disk I/O Contention

**Scenario**: The filesystem is under heavy load from other processes. Write latency spikes.

**Expected behavior**: The script may exceed its performance target but will still complete. The `flock` timeout (5 seconds) provides an upper bound on how long the script will wait.

**Risk**: If the write itself is slow (not the lock), the script could take an unbounded amount of time.

**Mitigation**: Not addressed in this story. Future work could add a total-execution timeout using Bash `SIGALRM` or a wrapper `timeout` command.

---

### Special Characters in Session ID

**Scenario**: The session ID from the hook payload contains characters like `/`, `\0`, spaces, unicode, or shell metacharacters.

**Expected behavior**: The sanitization step (Section 4) strips all characters except `[a-zA-Z0-9_-]` before using the session ID as a directory name. The original session ID is preserved in the event envelope.

**Risk**: Two different session IDs could sanitize to the same directory name. For example, `session/123` and `session_123` would both become `session_123`.

**Mitigation**: This is a known limitation. In practice, Claude Code session IDs are typically UUIDs or hex strings and do not collide. If this becomes an issue, a hash-based directory naming scheme could be introduced.

---

### Empty or Malformed stdin

**Scenario**: The hook fires but stdin is empty, or contains non-JSON data (e.g., a plain string, HTML, or binary data).

**Expected behavior**:
- **Empty stdin**: Script detects empty payload, logs a warning, exits 0.
- **Non-JSON data**: `jq` fails to parse it. Script falls back to storing the raw text as a string value in the `data` field, or logs a warning and exits 0.

**Preferred approach for malformed JSON**: Store the raw input as a string in the `data` field so that no information is lost. The envelope is still valid JSON:

```json
{
  "event_id": "...",
  "event_type": "ToolCallCompleted",
  "session_id": "unknown",
  "sequence": 5,
  "timestamp": "...",
  "data": "this was the raw non-json input"
}
```

This preserves the data for debugging while maintaining a valid event store.

---

### Script Invoked Without Arguments

**Scenario**: `capture-event` is called with no arguments (`$1` is empty).

**Expected behavior**: Log a warning to stderr, exit 0. No event is written.

---

### Session Directory Cannot Be Created

**Scenario**: The parent directory `~/.claude-context/events/` does not exist, or the user does not have write permissions.

**Expected behavior**: `mkdir -p` fails, error is caught, logged to stderr, script exits 0.

---

## Technical Specification Summary

### Script Flow (Pseudocode)

```
1.  Set trap to always exit 0
2.  Validate $1 (event_type) is provided
3.  Check jq is available
4.  Read stdin into $payload variable
5.  Validate $payload is non-empty
6.  Extract session_id from $payload using jq (fallback: "unknown")
7.  Sanitize session_id for filesystem use
8.  Derive project_id from cwd ({basename}-{hash6})
9.  Create session directory: mkdir -p ~/.claude-context/events/{project_id}/{sanitized_session_id}
10. Generate event_id (uuidgen > /proc/sys/kernel/random/uuid > fallback)
11. Generate timestamp (date -u)
12. Acquire flock on {session_dir}/.lock
13.   Count existing [0-9]*.json files in session directory
14.   Compute next sequence number
15.   Construct envelope JSON using jq
16.   Write envelope to {session_dir}/{zero-padded-sequence}.json
17. Release flock (automatic on subshell exit)
18. Exit 0
```

### File Permissions

| Path | Permissions | Notes |
|---|---|---|
| `~/.claude-context/` | 700 | User-only access |
| `~/.claude-context/events/` | 700 | Event store |
| `~/.claude-context/events/{project-id}/` | 700 | Per-project directory |
| `~/.claude-context/events/{project-id}/{session}/` | 700 | Per-session directory |
| `~/.claude-context/events/{project-id}/{session}/*.json` | 600 | Event files (user read/write only) |
| `~/.claude-context/bin/capture-event` | 755 | Executable script |
| `~/.claude-context/events/{project-id}/{session}/.lock` | 600 | Lock file |

### Constants

```bash
BASE_DIR="$HOME/.claude-context"
EVENTS_DIR="$BASE_DIR/events"
MAX_SESSION_ID_LENGTH=255
LOCK_TIMEOUT=5
SEQUENCE_PAD_WIDTH=6
```

---

## Testing Plan

### Unit Tests (manual or scripted)

These tests can be run as a Bash test script or manually:

1. **Happy path**: Pipe valid JSON with a `session_id` to `capture-event SessionStarted`. Verify the event file is created with correct envelope fields.

2. **All event types**: Pipe a payload for each of the 10 event types. Verify all 10 produce valid event files.

3. **Sequence numbering**: Fire 5 events for the same session. Verify files `000001.json` through `000005.json` exist with correct sequence numbers in the envelope.

4. **Missing session_id**: Pipe JSON without a `session_id` field. Verify the event is stored in the `unknown/` directory.

5. **Empty stdin**: Run `echo "" | capture-event SessionStarted`. Verify script exits 0 with no crash.

6. **Malformed JSON**: Run `echo "not json" | capture-event SessionStarted`. Verify script exits 0.

7. **No arguments**: Run `capture-event` with no arguments. Verify script exits 0 with stderr output.

8. **Unknown event type**: Run `echo '{"session_id":"x"}' | capture-event FutureEvent`. Verify event is captured (forward compatibility) with a stderr warning.

9. **Concurrent writes**: Launch 10 concurrent invocations of `capture-event` for the same session using `&` and `wait`. Verify all 10 events are captured with unique sequence numbers.

10. **Large payload**: Pipe a 1MB JSON payload. Verify it is captured completely (file size matches expected).

11. **Special characters in session_id**: Pipe JSON with `session_id` containing slashes, spaces, and unicode. Verify directory name is sanitized and event file is written.

12. **Performance**: Time a single invocation. Verify it completes in under 100ms.

### Verification Commands

```bash
# Verify event store structure
find ~/.claude-context/events/ -type f -name "*.json" | head -20

# Verify a specific event file is valid JSON
jq . ~/.claude-context/events/{project-id}/{session-id}/000001.json

# Verify sequence ordering
ls -1 ~/.claude-context/events/{project-id}/{session-id}/[0-9]*.json

# Verify envelope fields
jq 'keys' ~/.claude-context/events/{project-id}/{session-id}/000001.json
# Expected: ["data", "event_id", "event_type", "project_id", "sequence", "session_id", "timestamp"]

# Count events in a session
ls ~/.claude-context/events/{project-id}/{session-id}/[0-9]*.json | wc -l
```

---

## Definition of Done

- [ ] `capture-event` script exists at `~/.claude-context/bin/capture-event` and is executable
- [ ] `install.sh` script creates directory structure and validates dependencies
- [ ] All 10 event types are handled correctly
- [ ] Event envelope contains all 7 required fields with correct types
- [ ] Sequence numbers are monotonically increasing per session with flock-based coordination
- [ ] Session ID extraction works, with sanitization and "unknown" fallback
- [ ] Script never exits non-zero, regardless of error conditions
- [ ] Script completes in under 100ms for typical async hook payloads
- [ ] Concurrent invocations produce correct, non-conflicting results
- [ ] All 12 test cases from the testing plan pass
- [ ] No stdout output is produced (only stderr for diagnostics)
- [ ] Code is readable, well-commented, and follows the conventions in ARCHITECTURE.md
