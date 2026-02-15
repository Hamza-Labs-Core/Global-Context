# Implementation Plan: Story 01 -- Event Capture System

**Date**: 2026-02-14
**Story**: 01-event-capture
**Estimated Total Effort**: ~3 days (12-16 hours)
**Review Issues Incorporated**: C-1, C-5, M-2, M-3, M-4
**Design Amendments**: 2, 3 (per-session session.json, project-id layer). See `docs/DESIGN-AMENDMENTS.md`.

### Amendment Impacts on This Plan

- **Amendment 2**: `capture-event` creates/updates `session.json` in the session directory within the existing flock scope. On first event (SessionStarted), creates the file. On subsequent events, increments `event_count` and updates `last_event_at`.
- **Amendment 3**: Paths gain a project-id layer: `events/{project-id}/{session-id}/`. `capture-event` extracts `cwd` from the hook payload, derives `project_id` via `gc_derive_project_id(cwd)`, and uses it in all paths. A new function `derive_project_id()` is added alongside `sanitize_session_id()` (Task 3). The event envelope gains a `project_id` field.

---

## Review Issue Resolutions Applied

Before listing tasks, this section documents how each review issue is addressed in the plan.

| Issue | Summary | Resolution in This Plan |
|-------|---------|------------------------|
| C-1 | Lock file naming: Story 01 uses `_seq.lock`, Story 03 uses `.lock` | Standardize on `.lock` throughout. All references to `_seq.lock` are replaced with `.lock`. |
| C-5 | UUID fallback generates non-standard IDs | Use a bash-native UUID v4 generator as the final fallback (`printf` with `$RANDOM` producing RFC 4122-compliant format). |
| M-2 | Sanitization rules differ between Story 01 and Story 03 | Adopt Story 03's stricter rules: disallow leading dots, prevent path traversal, max 255 chars, empty falls back to `unknown-{uuid}`. Story 01 references Story 03's canonical rules. |
| M-3 | Atomic write pattern inconsistency | Use temp file + rename pattern (Story 03). Skip `fsync` for async hooks by default to stay within the 50ms latency target; include `fsync` for sync hooks (CompactionTriggered, SessionStarted, UserPromptReceived). |
| M-4 | `CLAUDE_CONTEXT_PATH` env var not supported | All scripts resolve the base directory via `CLAUDE_CONTEXT_PATH` with fallback to `~/.claude-context`. Extracted as a shared pattern at the top of every script. |

---

## Task Dependency Graph

```
Task 1 (Base Dir Resolution)
  |
  v
Task 2 (Directory Structure + install.sh)
  |
  v
Task 3 (Session ID Sanitization)
  |
  +---> Task 4 (UUID Generation)
  |       |
  |       v
  +---> Task 5 (Timestamp Generation)
  |       |
  |       v
  +---> Task 6 (Sequence Numbering + Locking)
          |
          v
        Task 7 (Atomic Write Helper)
          |
          v
        Task 8 (Envelope Construction)
          |
          v
        Task 9 (Main Script Assembly)
          |
          v
        Task 10 (Error Handling + Safety)
          |
          v
        Task 11 (Performance Validation)
          |
          v
        Task 12 (Integration Test Suite)
```

---

## Tasks

### Task 1: Base Directory Resolution with CLAUDE_CONTEXT_PATH Support

**Description**

Create a shared shell snippet (and document the pattern) that resolves the GlobalContext storage root. Every script in the system must use this pattern at the top. This addresses review issue M-4.

The pattern:

```bash
BASE_DIR="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"
EVENTS_DIR="$BASE_DIR/events"
```

This is not a separate file (to avoid adding a sourcing dependency), but a documented inline pattern that must appear at the top of both `capture-event` and `install.sh`.

**Files to Create/Modify**

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Create -- add base dir resolution block at top |
| `/home/meywd/GlobalContext/src/install.sh` | Create -- add base dir resolution block at top |
| `/home/meywd/GlobalContext/docs/CONVENTIONS.md` | Create -- document the `CLAUDE_CONTEXT_PATH` pattern for all scripts to follow |

**Dependencies**: None (first task).

**Acceptance Test**

1. Set `CLAUDE_CONTEXT_PATH=/tmp/gc-test` and source the snippet. Verify `BASE_DIR` equals `/tmp/gc-test`.
2. Unset `CLAUDE_CONTEXT_PATH` and source the snippet. Verify `BASE_DIR` equals `$HOME/.claude-context`.
3. Set `CLAUDE_CONTEXT_PATH` to a path with a trailing slash. Verify the script handles it (strip trailing slash or works regardless).

**Estimated Complexity**: S

---

### Task 2: Directory Structure and install.sh

**Description**

Implement the `install.sh` script that provisions the full directory structure, validates dependencies, and creates `config.json`. The script must be idempotent -- safe to run multiple times.

The directory structure created:

```
$BASE_DIR/
  events/            # Event store root
  projections/       # Projection output (future stories)
  bin/               # Executable scripts
    capture-event    # The capture script (copied from source)
  config.json        # Configuration with defaults
```

Dependency validation:
- `jq`: required -- abort with install instructions if missing.
- `flock`: required -- warn if missing, continue.
- `uuidgen`: optional -- note fallback if missing.

`config.json` defaults (created only if file does not exist):

```json
{
  "version": "1.0.0",
  "events_dir": "events",
  "created_at": "<ISO 8601 timestamp>"
}
```

Note: `events_dir` is a relative path (relative to `BASE_DIR`), not absolute, to keep the store relocatable.

**Files to Create/Modify**

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/install.sh` | Create |

**Dependencies**: Task 1 (base dir resolution pattern).

**Acceptance Test**

1. Run `install.sh` on a clean system. Verify all directories exist under `$BASE_DIR`.
2. Verify `config.json` contains `version`, `events_dir`, and `created_at`.
3. Verify `capture-event` is in `$BASE_DIR/bin/` and has execute permission (`755`).
4. Run `install.sh` a second time. Verify no existing data is overwritten. Verify `config.json` is preserved.
5. Remove `jq` from `PATH` and run `install.sh`. Verify it aborts with clear instructions.
6. Run with `CLAUDE_CONTEXT_PATH=/tmp/gc-install-test`. Verify directories are created at that path.
7. Verify root directory has permissions `700`.

**Estimated Complexity**: M

---

### Task 3: Session ID Sanitization Function

**Description**

Implement a Bash function that sanitizes a session ID for safe use as a filesystem directory name. This follows Story 03's canonical sanitization rules (review issue M-2).

Rules (from Story 03):
- **Allowed characters**: `a-z`, `A-Z`, `0-9`, `-`, `_`
- **Disallowed characters**: `/`, `\`, spaces, null bytes, `.` (including leading dots), unicode beyond ASCII
- **Replacement**: Disallowed characters are replaced with `_`
- **Leading dot handling**: Leading dots are stripped (prevents hidden directories and `.`/`..` traversal)
- **Path traversal prevention**: After sanitization, verify the result does not equal `.` or `..`
- **Maximum length**: 255 characters (POSIX filesystem limit per Story 03, not 128 as in original Story 01)
- **Empty fallback**: If the sanitized result is empty, use `unknown-{uuid}` (where `{uuid}` comes from the UUID generation function, Task 4)

Note: The original (unsanitized) `session_id` is preserved in the event envelope's `session_id` field. Only the filesystem directory name uses the sanitized version.

**Implementation**:

```bash
sanitize_session_id() {
  local raw="$1"
  # Strip characters outside allowed set
  local safe
  safe=$(printf '%s' "$raw" | tr -cd 'a-zA-Z0-9_-')
  # Truncate to 255 characters
  safe="${safe:0:255}"
  # Prevent path traversal
  if [ -z "$safe" ] || [ "$safe" = "." ] || [ "$safe" = ".." ]; then
    safe="unknown-$(generate_uuid)"
  fi
  printf '%s' "$safe"
}
```

Note: dots are excluded from the `tr` character class entirely (unlike Story 01's original which allowed dots). This aligns with Story 03's rule that dots are disallowed, preventing hidden directories.

**Files to Create/Modify**

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Add `sanitize_session_id` function |

**Dependencies**: Task 1. Soft dependency on Task 4 (UUID generation) for the empty fallback case.

**Acceptance Test**

1. Input `abc-123` produces `abc-123` (no change).
2. Input `session/with/slashes` produces `sessionwithslashes`.
3. Input `has spaces here` produces `hasspaceshere`.
4. Input `..` produces `unknown-{uuid}`.
5. Input `.hidden` produces `hidden` (leading dot stripped by character class exclusion).
6. Input empty string `""` produces `unknown-{uuid}`.
7. Input a 300-character alphanumeric string is truncated to 255 characters.
8. Input `hello.world` produces `helloworld` (dots removed per Story 03 rules).
9. Verify the original session_id (before sanitization) is preserved in the event envelope.

**Estimated Complexity**: S

---

### Task 4: UUID v4 Generation Function

**Description**

Implement a Bash function that generates a UUID v4 using a three-tier fallback chain. This addresses review issue C-5 by using a bash-native RFC 4122-compliant UUID as the final fallback instead of a non-standard timestamp+PID composite.

Fallback chain:
1. `uuidgen` command (most Linux/macOS systems) -- convert to lowercase
2. Read from `/proc/sys/kernel/random/uuid` (Linux kernel fallback)
3. Bash-native UUID v4 using `$RANDOM` and `printf` (RFC 4122 compliant):

```bash
printf '%04x%04x-%04x-%04x-%04x-%04x%04x%04x' \
  $RANDOM $RANDOM \
  $RANDOM \
  $(( (RANDOM & 0x0FFF) | 0x4000 )) \
  $(( (RANDOM & 0x3FFF) | 0x8000 )) \
  $RANDOM $RANDOM $RANDOM
```

This final fallback produces a valid UUID v4 format string. The version nibble is set to `4` and the variant bits are set to `10`, per RFC 4122. The entropy source (`$RANDOM`) is 15-bit, so uniqueness is weaker than a true UUID, but sufficient for event IDs in a single-user filesystem store.

**Files to Create/Modify**

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Add `generate_uuid` function |

**Dependencies**: Task 1.

**Acceptance Test**

1. With `uuidgen` available: verify output matches UUID v4 regex `^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`.
2. With `uuidgen` removed from PATH but `/proc/sys/kernel/random/uuid` available: verify output is a valid UUID.
3. With both unavailable: verify the bash-native fallback produces a string matching UUID v4 regex (version nibble = 4, variant = 8/9/a/b).
4. Call the function 100 times. Verify no duplicates.

**Estimated Complexity**: S

---

### Task 5: Timestamp Generation Function

**Description**

Implement a Bash function that generates an ISO 8601 UTC timestamp with millisecond precision. Include a fallback for environments where `%3N` (milliseconds) is not supported by `date`.

Primary:
```bash
date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
```

Fallback (detects `%3N` not supported):
```bash
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Detection strategy: call `date -u +"%3N"` once and check if the output is a 3-digit number. If it outputs the literal `%3N`, the feature is not supported.

**Files to Create/Modify**

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Add `generate_timestamp` function |

**Dependencies**: Task 1.

**Acceptance Test**

1. On a system with `%3N` support: verify output matches `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$`.
2. On a system without `%3N` support (or mocked): verify output matches `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$`.
3. Verify the timestamp is in UTC (ends with `Z`).

**Estimated Complexity**: S

---

### Task 6: Sequence Numbering with flock-Based Locking

**Description**

Implement the per-session sequence number assignment using `flock` for exclusive locking. This addresses review issue C-1 by using `.lock` (not `_seq.lock`) as the lock file name.

The sequence assignment runs inside a flock-guarded subshell:

```bash
SESSION_DIR="$EVENTS_DIR/$project_id/$safe_session_id"
LOCK_FILE="$SESSION_DIR/.lock"
mkdir -p "$SESSION_DIR"

(
  flock -w 5 200 || { echo "[capture-event] WARN: Lock timeout after 5s, dropping event." >&2; exit 0; }

  # Count existing event files (only numbered files, exclude session.json)
  existing=$(ls "$SESSION_DIR"/[0-9]*.json 2>/dev/null | wc -l)
  next_seq=$((existing + 1))
  padded=$(printf "%06d" "$next_seq")

  # ... (write event file here, see Task 7/8)

) 200>"$LOCK_FILE"
```

If `flock` is not available:
- Log a warning to stderr.
- Attempt write without locking (best-effort).
- To mitigate collision risk, append a random suffix to the filename: `{padded}_{random4hex}.json`. This breaks the clean naming convention but preserves data. Document this as a known degradation mode.

Lock file:
- Located at `$SESSION_DIR/.lock` (not `_seq.lock` -- per C-1 resolution).
- Created implicitly by the flock redirect (`200>"$LOCK_FILE"`).
- Never deleted by the capture script.

**Files to Create/Modify**

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Add sequence assignment logic inside flock subshell |

**Dependencies**: Task 1, Task 3 (sanitized session dir path).

**Acceptance Test**

1. Fire 5 events sequentially for the same session. Verify files `000001.json` through `000005.json` exist.
2. Verify the `sequence` field inside each JSON envelope matches its filename number.
3. Fire 10 events concurrently (`&` + `wait`) for the same session. Verify all 10 files exist with unique, sequential numbers (no gaps, no duplicates).
4. Simulate lock timeout (hold the lock with a separate process for > 5s). Verify the capture script logs a warning and exits 0.
5. Verify the lock file is at `$SESSION_DIR/.lock`, not `_seq.lock`.
6. Verify `flock` availability check works: temporarily rename `flock` binary and verify the fallback path is taken with a warning.

**Estimated Complexity**: M

---

### Task 7: Atomic Write Helper

**Description**

Implement an atomic write function that writes event data to a temporary file and then renames it to the target path. This addresses review issue M-3 by aligning with Story 03's atomic write pattern.

Pattern:
```
1. Generate temp filename: {target}.tmp.{pid}
2. Write complete content to temp file
3. (Optional) fsync the temp file for sync hooks
4. Rename temp file to target filename (atomic on POSIX)
```

For performance, `fsync` is applied selectively:
- **Sync hooks** (SessionStarted, UserPromptReceived, CompactionTriggered): include `fsync` because data integrity on these critical events is worth the ~10ms cost.
- **Async hooks** (all others): skip `fsync` to stay within the 50ms latency target.

The event type is passed as a parameter to the write function so it can decide whether to fsync.

```bash
SYNC_EVENT_TYPES="SessionStarted UserPromptReceived CompactionTriggered"

atomic_write() {
  local target="$1"
  local content="$2"
  local event_type="$3"
  local tmp="${target}.tmp.$$"

  printf '%s\n' "$content" > "$tmp" || { rm -f "$tmp"; return 1; }

  # fsync for sync/critical event types
  if [[ " $SYNC_EVENT_TYPES " == *" $event_type "* ]]; then
    if command -v sync &>/dev/null; then
      sync "$tmp" 2>/dev/null || true
    fi
  fi

  mv "$tmp" "$target" || { rm -f "$tmp"; return 1; }
}
```

On failure (disk full, permission denied), the temp file is cleaned up and the error propagates to the caller for logging.

**Files to Create/Modify**

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Add `atomic_write` function |

**Dependencies**: Task 1.

**Acceptance Test**

1. Call `atomic_write` with valid args. Verify the target file exists with correct content.
2. Verify no `.tmp.*` files remain after a successful write.
3. Simulate disk full (write to a full tmpfs). Verify the temp file is cleaned up and the function returns non-zero.
4. Verify that for a `SessionStarted` event, `sync` is called (if available).
5. Verify that for a `ToolCallCompleted` event, `sync` is not called.
6. Verify the written file has permissions `600` (set by umask or explicit chmod).

**Estimated Complexity**: S

---

### Task 8: Event Envelope Construction

**Description**

Implement the JSON envelope construction using a single `jq` invocation. This combines session_id extraction, envelope wrapping, and JSON output into one call for performance.

The envelope contains all 7 required fields:

```json
{
  "event_id": "<uuid>",
  "event_type": "<from $1>",
  "project_id": "<derived from cwd>",
  "session_id": "<from payload>",
  "sequence": <integer>,
  "timestamp": "<ISO 8601>",
  "data": { <raw payload> }
}
```

Combined `jq` invocation (extracts session_id AND builds envelope):

```bash
envelope_json=$(printf '%s' "$payload" | jq -c \
  --arg eid "$event_id" \
  --arg etype "$event_type" \
  --arg pid "$project_id" \
  --argjson seq "$next_seq" \
  --arg ts "$timestamp" \
  '{
    event_id: $eid,
    event_type: $etype,
    project_id: $pid,
    session_id: (.session_id // "unknown"),
    sequence: $seq,
    timestamp: $ts,
    data: .
  }')
```

For the session_id extraction (needed before the envelope for the directory path), extract it in a separate, fast `jq` call:

```bash
session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty')
```

This means two `jq` invocations total: one for session_id extraction (needed for directory), one for envelope construction. This is acceptable -- combining them into one call would require restructuring the flow since the session directory must exist before the envelope can be written.

For malformed JSON input: if `jq` fails to parse the payload, wrap the raw text as a string in the `data` field:

```bash
if ! session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null); then
  session_id="unknown"
  # Build envelope with raw string data
  envelope_json=$(jq -cn \
    --arg eid "$event_id" \
    --arg etype "$event_type" \
    --arg pid "$project_id" \
    --arg sid "unknown" \
    --argjson seq "$next_seq" \
    --arg ts "$timestamp" \
    --arg data "$payload" \
    '{event_id:$eid, event_type:$etype, project_id:$pid, session_id:$sid, sequence:$seq, timestamp:$ts, data:$data}')
fi
```

Output format: compact JSON (`jq -c`) per Story 03's encoding rules (no pretty-print, minimizes disk usage).

**Files to Create/Modify**

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Add envelope construction logic |

**Dependencies**: Task 4 (UUID), Task 5 (timestamp), Task 6 (sequence number).

**Acceptance Test**

1. Pipe `{"session_id":"test-abc","tool_name":"Read"}` and verify the envelope contains all 7 fields (including project_id).
2. Verify `data` contains the original payload unmodified (including `session_id` field).
3. Verify `event_type` matches the `$1` argument.
4. Verify `event_id` is a valid UUID.
5. Verify `sequence` is an integer (not a string).
6. Verify `timestamp` is ISO 8601 UTC.
7. Pipe malformed input `"not json"` and verify the envelope is still valid JSON with `data` as a string.
8. Pipe JSON without `session_id` and verify `session_id` defaults to `"unknown"`.
9. Verify output is compact JSON (single line, no extra whitespace).
10. Pipe a 1MB JSON payload and verify it is captured completely in the `data` field.

**Estimated Complexity**: M

---

### Task 9: Main Script Assembly (capture-event)

**Description**

Assemble the complete `capture-event` script by combining all the functions and logic from Tasks 1-8 into a single, well-structured Bash script. This is the integration task.

Script flow (pseudocode):

```
1.  #!/usr/bin/env bash
2.  Set trap to always exit 0 (see Task 10)
3.  Resolve BASE_DIR via CLAUDE_CONTEXT_PATH (Task 1)
4.  Validate $1 (event_type) is provided; warn on unknown types
5.  Check jq is available; exit 0 if missing
6.  Read stdin into $payload variable (single read)
7.  Validate $payload is non-empty
8.  Extract session_id from $payload using jq (fallback: "unknown")
9.  Sanitize session_id for filesystem use (Task 3)
10. Derive project_id from cwd (basename + hash6 of full path)
11. mkdir -p session directory ($EVENTS_DIR/$project_id/$safe_session_id)
12. Generate event_id via generate_uuid (Task 4)
13. Generate timestamp via generate_timestamp (Task 5)
14. Acquire flock on {session_dir}/.lock (Task 6)
15.   Count existing [0-9]*.json files for next sequence number
15.   Construct envelope JSON using jq (Task 8)
16.   Atomic write envelope to {session_dir}/{padded}.json (Task 7)
17. Release flock (automatic on subshell exit)
18. Exit 0
```

Known event types list (for warning on unknown types):

```bash
KNOWN_TYPES="SessionStarted UserPromptReceived ToolCallRequested ToolCallCompleted ToolCallFailed AgentSpawned AgentCompleted TurnCompleted CompactionTriggered SessionEnded"
```

Unknown event types produce a stderr warning but the event is still captured (forward compatibility).

Constants:

```bash
MAX_SESSION_ID_LENGTH=255
LOCK_TIMEOUT=5
SEQUENCE_PAD_WIDTH=6
SYNC_EVENT_TYPES="SessionStarted UserPromptReceived CompactionTriggered"
```

Stdin reading:

```bash
payload=$(cat)
```

This reads all of stdin into a variable. Using `cat` is simpler and handles large payloads better than `read` with IFS manipulation.

**Files to Create/Modify**

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Assemble complete script |

**Dependencies**: Tasks 1-8 (all component tasks).

**Acceptance Test**

1. Run `echo '{"session_id":"s1"}' | capture-event SessionStarted`. Verify `$BASE_DIR/events/{project-id}/s1/000001.json` exists with correct envelope (including `project_id` field).
2. Run all 10 event types. Verify each produces a valid event file.
3. Run with unknown event type `FutureEvent`. Verify event is captured and stderr contains a warning.
4. Run with no arguments. Verify stderr warning and exit 0.
5. Run with empty stdin. Verify stderr warning and exit 0.
6. Run from `/tmp` (different working directory). Verify it still works (absolute paths).
7. Verify no stdout output at all (redirect stdout to a file and check it is empty).
8. Verify `CLAUDE_CONTEXT_PATH` is respected.

**Estimated Complexity**: M

---

### Task 10: Error Handling and Safety

**Description**

Add comprehensive error handling to ensure the script never exits non-zero and never produces stdout output, regardless of what goes wrong.

Key safety mechanisms:

1. **Trap**: `trap 'exit 0' ERR EXIT` at the top of the script, after `#!/usr/bin/env bash`.
2. **No `set -e`**: Explicitly avoided. Errors are handled manually.
3. **`set -o pipefail`**: Enabled so piped command failures are detectable, but handled by the script rather than causing an exit.
4. **All error output to stderr**: Every `echo` in error paths uses `>&2`.
5. **Consistent error format**: `[capture-event] ERROR: <message>` or `[capture-event] WARN: <message>`.

Error categories:

| Condition | Detection | Response |
|-----------|-----------|----------|
| `jq` not installed | `command -v jq` fails | Log ERROR, exit 0 |
| `flock` not available | `command -v flock` fails | Log WARN, write without lock |
| Empty stdin | `$payload` is empty | Log WARN, exit 0 |
| Malformed JSON on stdin | `jq` parse fails | Store raw text as string in `data` |
| Disk full / permission denied | Write/mkdir fails | Log ERROR, exit 0 |
| Lock timeout | `flock -w 5` fails | Log WARN, exit 0 (event dropped) |
| Missing event type `$1` | `-z "$1"` | Log ERROR, exit 0 |
| Unknown event type | Not in `KNOWN_TYPES` | Log WARN, capture anyway |

**Files to Create/Modify**

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Add trap, error checks, and logging throughout |

**Dependencies**: Task 9 (main script must exist to add error handling to).

**Acceptance Test**

1. Remove `jq` from PATH. Run the script. Verify exit code is 0 and stderr contains `[capture-event] ERROR: jq not found`.
2. Run with no arguments. Verify exit code is 0.
3. Pipe empty string. Verify exit code is 0.
4. Pipe malformed JSON. Verify exit code is 0 and an event file is still written (with `data` as string).
5. Make the events directory read-only. Run the script. Verify exit code is 0 and stderr contains an error message.
6. Verify stdout is empty in all error cases (pipe stdout to a file, check size = 0).
7. Kill the script mid-execution with SIGTERM. Verify it exits 0 (trap handles it).

**Estimated Complexity**: S

---

### Task 11: Performance Validation

**Description**

Validate that the capture script meets the performance budget: under 100ms for typical async hook payloads, under 50ms target.

Verification approach:

```bash
# Measure single invocation
time echo '{"session_id":"perf-test","tool_name":"Read","tool_input":{"file_path":"/tmp/test"}}' \
  | $BASE_DIR/bin/capture-event ToolCallCompleted
```

Performance budget:

| Hook Type | Target | Hard Limit |
|-----------|--------|------------|
| Async hooks | < 50ms | 100ms |
| Sync hooks | < 100ms | 5000ms |

If performance exceeds targets, optimize:
- Verify at most 4 subprocesses: `jq` (x2 -- session_id + envelope), `date` (x1), `uuidgen` (x1), implicit `flock`.
- Verify stdin is read exactly once.
- Verify no unnecessary disk reads.
- Consider caching the `%3N` support check in a variable.
- Consider combining the two `jq` calls if the flow can be restructured.

**Files to Create/Modify**

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/tests/perf-test.sh` | Create performance benchmark script |

**Dependencies**: Task 9, Task 10 (complete script needed for perf testing).

**Acceptance Test**

1. Run the performance benchmark 20 times. Verify median execution time is under 100ms.
2. Run with a 1MB payload. Verify it completes (may exceed 100ms -- that is acceptable per the edge case documentation).
3. Count subprocess invocations using `strace -f -e trace=execve` (Linux). Verify at most 5 exec calls (bash itself + jq x2 + date + uuidgen).

**Estimated Complexity**: S

---

### Task 12: Integration Test Suite

**Description**

Create a comprehensive test script that validates all acceptance criteria from Story 01. This script should be runnable as a standalone Bash script and report pass/fail for each test case.

Test cases (mapped from Story 01's testing plan):

| # | Test Case | Validates |
|---|-----------|-----------|
| 1 | Happy path: pipe valid JSON, verify envelope | Sections 1, 2 |
| 2 | All 10 event types: verify each produces a valid file | Section 8 |
| 3 | Sequence numbering: 5 sequential events, verify 000001-000005 | Section 3 |
| 4 | Missing session_id: verify `unknown` directory used | Section 4 |
| 5 | Empty stdin: verify exit 0 with no crash | Section 5 |
| 6 | Malformed JSON: verify exit 0, event still stored as string | Section 5 |
| 7 | No arguments: verify exit 0 with stderr output | Section 5 |
| 8 | Unknown event type: verify captured with stderr warning | Section 8 |
| 9 | Concurrent writes: 10 parallel invocations, verify unique sequences | Section 3 |
| 10 | Large payload: 1MB JSON, verify complete capture | Edge case |
| 11 | Special chars in session_id: sanitization works, original preserved | Section 4, M-2 |
| 12 | Performance: single invocation under 100ms | Section 6 |
| 13 | Lock file is `.lock` not `_seq.lock` | C-1 |
| 14 | UUID fallback produces valid UUID format | C-5 |
| 15 | CLAUDE_CONTEXT_PATH override works | M-4 |
| 16 | Atomic write: no partial files on disk | M-3 |
| 17 | Sanitization follows Story 03 rules (no dots, max 255, traversal prevention) | M-2 |
| 18 | Idempotent install: run install.sh twice, no data loss | Section 9 |

The test script uses a temporary directory as `CLAUDE_CONTEXT_PATH` so tests do not pollute the real event store. Cleanup happens in a trap on exit.

**Files to Create/Modify**

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/tests/01-event-capture-test.sh` | Create integration test suite |

**Dependencies**: Task 9, Task 10 (complete, error-handled script), Task 2 (install.sh).

**Acceptance Test**

1. Run `bash tests/01-event-capture-test.sh`. All 18 test cases pass.
2. Run on a clean system (no prior install). All tests pass (test script runs install.sh first).
3. Run with `CLAUDE_CONTEXT_PATH=/tmp/gc-test-run`. Verify all events are written to that path and the default `~/.claude-context` is untouched.

**Estimated Complexity**: L

---

## File Summary

All file paths are relative to `/home/meywd/GlobalContext/`.

| File | Action | Task(s) |
|------|--------|---------|
| `src/capture-event` | Create | 1, 3, 4, 5, 6, 7, 8, 9, 10 |
| `src/install.sh` | Create | 1, 2 |
| `tests/01-event-capture-test.sh` | Create | 12 |
| `tests/perf-test.sh` | Create | 11 |
| `docs/CONVENTIONS.md` | Create | 1 |

---

## Implementation Order (Recommended)

The tasks are ordered to allow incremental development and testing. Each task builds on the previous ones, and the script can be tested partially after each step.

| Phase | Tasks | Milestone |
|-------|-------|-----------|
| **Phase 1: Foundation** | 1, 2 | Directory structure exists, install works |
| **Phase 2: Core Functions** | 3, 4, 5 | Utility functions implemented and testable in isolation |
| **Phase 3: Write Path** | 6, 7, 8 | Sequence numbering, atomic writes, envelope construction |
| **Phase 4: Integration** | 9, 10 | Complete script assembled with error handling |
| **Phase 5: Validation** | 11, 12 | Performance verified, all acceptance criteria pass |

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `jq` not available on target systems | Low | High (no events captured) | install.sh checks and provides install instructions; fail-fast with clear error |
| `flock` not available (macOS without coreutils) | Medium | Medium (potential sequence collisions) | Fallback to unlocked write with random suffix; document in install output |
| Large payloads (>1MB) exceed latency target | Low | Low (only affects that single event) | Documented as acceptable trade-off; no truncation |
| Concurrent writes cause sequence gaps | Low | Low (gaps are harmless for projections) | flock serialization prevents this under normal operation |
| Temp files left behind on crash | Low | Low (small files, easily cleaned) | Naming convention `*.tmp.*` allows cleanup during init (Story 03 handles this) |
| macOS `date` does not support `%3N` | Medium | Low (falls back to second precision) | Detected at runtime with fallback |

---

## Notes for Implementation

1. **Do not add `set -e`** -- this is explicitly prohibited by the story. Use manual error checking.
2. **The script must produce zero stdout output** -- any stdout would interfere with the Claude Code hook protocol.
3. **All paths must be absolute internally** -- the script may be called from any working directory.
4. **The `data` field is sacred** -- the raw hook payload goes in unmodified. No field extraction, renaming, or filtering.
5. **Forward compatibility** -- unknown event types are captured, not rejected. This allows Claude Code to add new hook events without breaking the capture system.
6. **Story 03 is the authority on sanitization** -- when Story 01's rules conflict with Story 03, use Story 03's rules (no dots in directory names, max 255 chars, path traversal prevention).
7. **The lock file is `.lock`** -- not `_seq.lock`. This is the canonical name per Story 03 and review issue C-1.
