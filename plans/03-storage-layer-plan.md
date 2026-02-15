# Implementation Plan: Story 03 -- Storage Layer

**Date**: 2026-02-14
**Story**: 03-storage-layer
**Status**: Planning
**Estimated Total Effort**: ~5 days (assuming one engineer)

---

## Overview

This plan breaks Story 03 (Storage Layer) into concrete, ordered implementation tasks. It incorporates fixes for the following review issues from `/docs/REVIEW.md`:

| Review Issue | Summary | How Addressed |
|---|---|---|
| C-1 | Lock file naming conflict (`.lock` vs `_seq.lock`) | Task 3 canonicalizes on `.lock` |
| C-2 | sessions.json schema mismatch between Story 03 and Story 05 | ~~Task 8 defines the merged canonical schema~~ **Superseded by Amendment 2**: global sessions.json removed, replaced by per-session session.json |
| M-2 | Session ID sanitization discrepancy between stories | Task 2 owns the canonical rules |
| M-3 | Atomic write pattern inconsistency across stories | Task 4 defines the canonical pattern |
| M-4 | CLAUDE_CONTEXT_PATH env var not propagated | Task 1 defines the shared path resolver |

**Design Amendments**: 1, 2, 3, 4. See `docs/DESIGN-AMENDMENTS.md`.

### Amendment Impacts on This Plan

- **Amendment 1** (Remove global sessions.json): Task 8 scope is reduced — no global sessions.json, no `.sessions.lock`, no `gc_sessions_*` write-path CRUD functions. Task 8 now defines only the per-session `session.json` schema and the update logic within the existing per-session flock.
- **Amendment 2** (Per-session session.json): `session.json` is created/updated inside the per-session flock scope in `event_write.sh` (Task 6). No new lock required.
- **Amendment 3** (Project-ID layer): All path functions in Task 1 gain a `project_id` parameter. Task 2 adds a `gc_derive_project_id()` function. Directory structure becomes `events/{project-id}/{session-id}/`.
- **Amendment 4** (Remove gc-cleanup): Task 12 (gc-cleanup) is deferred. Removed from this plan.

---

## Task 1: Shared Path Resolver and Constants Module

### Description

Create a shared shell library that every script in the project sources. It resolves the storage root path (respecting `CLAUDE_CONTEXT_PATH`), defines directory constants, and provides common utility functions. This is the single place where the base path is determined -- no script should hardcode `~/.claude-context`.

This directly addresses review issue **M-4** (CLAUDE_CONTEXT_PATH env var support).

### Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/paths.sh` | Create | Shared shell library: path resolution, constants, common helpers |
| `tests/lib/test_paths.sh` | Create | Unit tests for path resolution logic |

### Specification

`paths.sh` must export the following:

```bash
# Resolve storage root
GC_ROOT="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"

# Directory constants
GC_EVENTS_DIR="$GC_ROOT/events"
GC_PROJECTIONS_DIR="$GC_ROOT/projections"
GC_BIN_DIR="$GC_ROOT/bin"
GC_CONFIG_FILE="$GC_ROOT/config.json"
# Note: No global sessions.json or .sessions.lock — per-session metadata only (Amendment 1)
```

It must also provide helper functions:

- `gc_session_events_dir(project_id, session_id)` -- returns `$GC_EVENTS_DIR/{project_id}/{sanitized-session-id}`
- `gc_session_lock_file(project_id, session_id)` -- returns `$GC_EVENTS_DIR/{project_id}/{sanitized-session-id}/.lock`
- `gc_session_projections_dir(project_id, session_id)` -- returns `$GC_PROJECTIONS_DIR/{project_id}/{sanitized-session-id}`
- `gc_project_latest(project_id)` -- returns `$GC_PROJECTIONS_DIR/{project_id}/latest`
- `gc_resolve_root()` -- validates and returns the root path, printing an error if the store is not initialized
- `gc_derive_project_id(project_dir)` -- returns `{basename}-{hash6}` (see Amendment 3)

### Dependencies

None. This is the foundation.

### Acceptance Test

1. Source `paths.sh` with `CLAUDE_CONTEXT_PATH` unset -- `GC_ROOT` equals `$HOME/.claude-context`.
2. Source `paths.sh` with `CLAUDE_CONTEXT_PATH=/tmp/test-store` -- `GC_ROOT` equals `/tmp/test-store`.
3. All path constants are derived from `GC_ROOT` (grep shows no hardcoded `~/.claude-context`).
4. Run `tests/lib/test_paths.sh` -- all assertions pass.

### Estimated Complexity

**S** (Small)

---

## Task 2: Session ID Sanitization Function

### Description

Implement the canonical session ID sanitization rules in a dedicated, testable function within the shared library. This function is the single authoritative implementation -- Story 01 and all other stories must call it, not re-implement it.

This directly addresses review issue **M-2** (canonical session ID sanitization).

### Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/sanitize.sh` | Create | Session ID sanitization function |
| `tests/lib/test_sanitize.sh` | Create | Unit tests for all edge cases |

### Specification

Function: `gc_sanitize_session_id(raw_id) -> sanitized_id`

Rules (canonical, all other stories reference these):

1. **Allowed characters**: `a-z`, `A-Z`, `0-9`, `-`, `_`
2. **Disallowed characters stripped**: All characters not in `[a-zA-Z0-9_-]` are removed (using `tr -cd`). This includes `/`, `\`, spaces, null bytes, dots, non-ASCII.
3. **Path traversal prevention**: Dots are stripped by the character class, so `..` and `.hidden` are neutralized automatically.
4. **Empty result**: If after sanitization the string is empty, use `"unknown"`.
5. **Maximum length**: Truncate to 255 characters after sanitization.
6. The mapping is deterministic — the same input always yields the same output.

Edge case table (canonical reference):

| Input | Output | Reason |
|---|---|---|
| `abc123` | `abc123` | Already valid |
| `session-2026` | `session-2026` | Hyphens allowed |
| `session/with/slashes` | `sessionwithslashes` | Slashes stripped |
| `has spaces` | `hasspaces` | Spaces stripped |
| `../../../etc/passwd` | `etcpasswd` | Dots and slashes stripped |
| (empty string) | `unknown` | Fallback |
| `.hidden` | `hidden` | Dot stripped |
| 300-char string | first 255 chars | Truncated |
| `UPPER-case` | `UPPER-case` | Case preserved |
| `with.dots.inside` | `withdotsinside` | Dots stripped |

### Dependencies

- Task 1 (paths.sh for UUID generation helper, if shared; otherwise standalone)

### Acceptance Test

1. Run `tests/lib/test_sanitize.sh` -- all 10+ edge cases from the table above pass.
2. Call `gc_sanitize_session_id ""` -- returns `"unknown"`.
3. Call `gc_sanitize_session_id "$(python3 -c "print('a'*300))"` -- returns a 255-char string.
4. Verify determinism: calling twice with the same input returns identical output (except the empty-string fallback which generates a new UUID each time).

### Estimated Complexity

**S** (Small)

---

## Task 3: Session Directory Creation and Lock File Management

### Description

Implement the logic for creating per-session directories under `events/` on demand. Each directory contains event files and a `.lock` file for flock coordination. The directory is created lazily on the first event for a session.

This directly addresses review issue **C-1** by canonicalizing on `.lock` (not `_seq.lock`).

### Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/session_dir.sh` | Create | Session directory creation, lock file creation, existence check |
| `tests/lib/test_session_dir.sh` | Create | Unit and integration tests |

### Specification

Function: `gc_ensure_session_dir(project_id, session_id)`

1. Sanitize the session ID using `gc_sanitize_session_id` (Task 2).
2. Compute path: `$GC_EVENTS_DIR/{project_id}/{sanitized_id}/`.
3. Create directory: `mkdir -p "$dir"`.
4. Create lock file: `touch "$dir/.lock"` (idempotent).
5. Return the directory path on stdout.

The function must be safe under concurrent invocation -- `mkdir -p` is inherently safe, and `touch` is idempotent.

Lock file naming convention (canonical, C-1 resolution):

| Lock File | Location | Purpose |
|---|---|---|
| `.lock` | `events/{project-id}/{session-id}/.lock` | Per-session sequence number coordination and session.json update |

> **Amendment 1**: The global `.sessions.lock` has been removed. All locking is per-session only.

### Dependencies

- Task 1 (paths.sh)
- Task 2 (sanitize.sh)

### Acceptance Test

1. Call `gc_ensure_session_dir "proj-abc123" "test-session-1"` -- directory `$GC_EVENTS_DIR/proj-abc123/test-session-1/` exists with `.lock` file.
2. Call again -- no error, no duplication, same result.
3. Call with `"proj-abc123" "session/bad"` -- directory is `$GC_EVENTS_DIR/proj-abc123/sessionbad/` (slashes stripped, not replaced).
4. Two parallel invocations with the same session ID complete without error.
5. Verify `.lock` file exists (not `_seq.lock`, not `lock`).

### Estimated Complexity

**S** (Small)

---

## Task 4: Atomic Write Helper

### Description

Implement the canonical atomic write function used by all file writes in the system (events, projections, session.json, config.json). This is a shared utility that writes to a temp file, optionally fsyncs, then renames atomically.

This directly addresses review issue **M-3** (canonical atomic write pattern).

### Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/atomic_write.sh` | Create | Atomic write function |
| `tests/lib/test_atomic_write.sh` | Create | Tests including crash simulation |

### Specification

Function: `gc_atomic_write(target_path, content, [fsync])`

Canonical pattern (all stories must use this):

```
1. Generate temp filename: {target}.tmp.{$$}
   Example: 000042.json.tmp.12345
2. Write complete content to temp file
3. If fsync=true: sync the temp file (using dd or python -c 'import os; os.fsync(...)')
4. mv (rename) temp file to target filename
5. If any step fails: remove temp file (best-effort), return non-zero
```

Parameters:

- `target_path` (required): The final destination file path.
- `content` (required): The content to write. Passed via stdin or as a variable.
- `fsync` (optional, default: `false`): Whether to fsync before rename. Set to `true` for sync hooks and critical writes (session.json). Set to `false` for async hooks where latency matters.

Design decisions:

- Temp file name includes PID (`$$`) for uniqueness across concurrent processes.
- The rename (`mv`) is atomic on POSIX-compliant filesystems (ext4, APFS, tmpfs).
- If the write fails (e.g., disk full), only the temp file is left -- the target file is untouched.
- Temp files matching `*.tmp.*` are orphans from interrupted writes and can be safely deleted.

### Dependencies

- Task 1 (paths.sh, for any shared constants)

### Acceptance Test

1. Write a file using `gc_atomic_write` -- target file exists with correct content.
2. Write to a non-existent directory -- function returns non-zero, no partial file.
3. Simulate crash (kill -9 during write of large content) -- target file is either absent or contains previous content, never partial.
4. Two concurrent `gc_atomic_write` calls to the same target -- last writer wins, file is valid.
5. Verify temp file is cleaned up on success (no `*.tmp.*` files remain).
6. Test with `fsync=true` -- function still works (may be slightly slower).

### Estimated Complexity

**S** (Small)

---

## Task 5: JSON Validation Helper

### Description

Implement a function that validates a JSON string before it is written to disk. This ensures no corrupt or invalid JSON is ever persisted to the event store.

### Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/json_validate.sh` | Create | JSON validation and required-field checking |
| `tests/lib/test_json_validate.sh` | Create | Validation tests |

### Specification

Function: `gc_validate_event_json(json_string) -> 0 (valid) or 1 (invalid)`

Validation steps:

1. Parse JSON using `jq empty` -- if this fails, the JSON is malformed.
2. Check required fields: `event_id`, `event_type`, `project_id`, `session_id`, `sequence`, `timestamp`, `data` (7 fields).
3. Verify `sequence` is a positive integer.
4. Verify `timestamp` is a non-empty string (full ISO 8601 validation is out of scope for bash).
5. Verify `data` is an object (not null, not a string).

On failure:

- Print error reason to stderr.
- Return exit code 1.
- The caller is responsible for writing to `_rejected/` if desired.

Function: `gc_validate_json(json_string) -> 0 or 1`

- Simpler variant: just checks if the string is valid JSON (for non-event files like session.json, config.json).

### Dependencies

- External: `jq` must be installed (validated during init, Task 7).

### Acceptance Test

1. Valid event JSON -- returns 0.
2. Malformed JSON (missing closing brace) -- returns 1.
3. JSON missing `event_id` -- returns 1.
4. JSON with `sequence: "not_a_number"` -- returns 1.
5. JSON with `data: null` -- returns 1.
6. Valid non-event JSON via `gc_validate_json` -- returns 0.

### Estimated Complexity

**S** (Small)

---

## Task 6: Event File Writing (Envelope, Sequence, Session Metadata)

### Description

Implement the core event writing pipeline: construct the event envelope, assign a sequence number under flock, validate, write atomically, and update per-session metadata. This is the critical path for the capture-event script.

### Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/event_write.sh` | Create | Event envelope construction, sequence assignment, truncation, write |
| `tests/lib/test_event_write.sh` | Create | Unit and integration tests |

### Specification

Function: `gc_write_event(session_id, event_type, data_json) -> 0 or 1`

Pipeline:

```
1. Sanitize session_id (Task 2)
2. Ensure session directory exists (Task 3)
3. Acquire flock on events/{project-id}/{session-id}/.lock (timeout: 5s)
4. Determine next sequence number:
   a. List [0-9]*.json files in session dir (exclude session.json), extract highest number
   b. If no files: next = 1
   c. Else: next = highest + 1
5. Generate event_id (UUID v4)
6. Generate timestamp (ISO 8601 UTC)
7. Construct envelope JSON:
   {
     "event_id": "<uuid>",
     "event_type": "<type>",
     "project_id": "<derived from cwd>",
     "session_id": "<sanitized_id>",
     "sequence": <next>,
     "timestamp": "<iso8601>",
     "data": <data_json>
   }
8. Validate envelope (Task 5)
9. Write atomically to events/{project-id}/{session-id}/{zero-padded-sequence}.json (Task 4)
10. Update session.json (Task 8) within same flock scope
11. Release flock (automatic on fd close)
12. If validation fails: write to events/{project-id}/{session-id}/_rejected/ with error
```

Sequence number formatting:

- 6-digit zero-padded: `printf "%06d" $sequence`
- Range: 000001 to 999999
- If sequence reaches 999999: log error to stderr, skip write, return 1

Note: No write-side truncation — the capture script stores events as-is without size checks (CQRS principle: write side is fast and dumb). If size management is needed, it belongs on the read side.

Fallback on flock timeout:

- Write event with a UUID-based filename: `orphan-{uuid}.json`
- Log warning to stderr.
- The event is preserved but out of sequence -- reconcilable by projection engine.

### Dependencies

- Task 1 (paths.sh)
- Task 2 (sanitize.sh)
- Task 3 (session_dir.sh)
- Task 4 (atomic_write.sh)
- Task 5 (json_validate.sh)

### Acceptance Test

1. Write 10 events to a new session -- files 000001.json through 000010.json exist, each with correct 7-field envelope.
2. Verify `sequence` field inside file matches filename.
3. Write an event with invalid JSON data -- file appears in `_rejected/` directory.
4. Concurrent writes (10 parallel) to the same session -- all get unique sequence numbers, no gaps.
5. Verify flock timeout fallback: simulate a locked session, write an event -- orphan file is created.
6. Verify event_id is a valid UUID v4 in each file.
7. Verify timestamp is ISO 8601 UTC.
8. Verify compact JSON (single line, no pretty-printing).
9. Verify `session.json` exists after first event and `event_count` matches after 10 events.

### Estimated Complexity

**L** (Large)

---

## Task 7: Init Command

### Description

Implement the `init` command that creates the full directory structure, configuration files, lock files, and validates the filesystem. Must be idempotent -- safe to run repeatedly without data loss.

This incorporates review issue **M-4** by using the shared path resolver from Task 1.

### Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/bin/gc-init` | Create | Init command script |
| `tests/bin/test_gc_init.sh` | Create | Init idempotency and correctness tests |

### Specification

Invocation: `gc-init` (no arguments)

Process:

```
 1. Source paths.sh to resolve GC_ROOT
 2. Print: "Initializing GlobalContext store at $GC_ROOT"
 3. Create root directory:    mkdir -p "$GC_ROOT" && chmod 700 "$GC_ROOT"
 4. Create events/:           mkdir -p "$GC_EVENTS_DIR" && chmod 700 "$GC_EVENTS_DIR"
 5. Create projections/:      mkdir -p "$GC_PROJECTIONS_DIR" && chmod 700 "$GC_PROJECTIONS_DIR"
 6. Create bin/:              mkdir -p "$GC_BIN_DIR" && chmod 755 "$GC_BIN_DIR"
 7. Create config.json:       if [ ! -f "$GC_CONFIG_FILE" ]; then
                                  write default config (see Task 9)
                                  chmod 600 "$GC_CONFIG_FILE"
                               fi
 8. Install bin/ scripts:     copy capture-event, project, gc-query to bin/
                               chmod 755 on each (always overwrite for upgrades)
 9. Clean orphan temp files:  find "$GC_EVENTS_DIR" -name '*.tmp.*' -delete
10. Validate writability:     write and delete a test file in GC_ROOT
11. Validate disk space:      check >= 10MB free (df -P or similar)
12. Print summary:            list what was created vs what was skipped
13. Exit 0 on success, non-zero on failure
```

> **Amendment 1**: No global `sessions.json` or `.sessions.lock` is created. Per-session metadata is created lazily when the first event is written (Task 6/8).

Idempotency rules:

| Resource | If Exists | If Not Exists |
|---|---|---|
| Directories | Skip (mkdir -p handles this) | Create |
| `config.json` | Skip, print "already exists" | Create with defaults |
| `bin/*` scripts | Overwrite (to support upgrades) | Create |

### Dependencies

- Task 1 (paths.sh)
- Task 4 (atomic_write.sh, used for config.json initial write)

### Acceptance Test

1. Run `gc-init` on clean system -- all directories and files created with correct permissions.
2. Verify `$GC_ROOT` has permission 700.
3. Verify `config.json` exists with all default fields.
4. Verify no `sessions.json` or `.sessions.lock` files exist (Amendment 1).
5. Verify `bin/` scripts are executable (755).
6. Run `gc-init` again -- output says "already exists" for config.json, no data overwritten.
7. Set `CLAUDE_CONTEXT_PATH=/tmp/gc-test` and run `gc-init` -- store created at `/tmp/gc-test/`.
8. Create a `*.tmp.*` file in events/ before init -- verify it is cleaned up.
9. Verify disk space check (test on a nearly full tmpfs if feasible).
10. Exit code is 0 on success.

### Estimated Complexity

**M** (Medium)

---

## Task 8: Per-Session Metadata (session.json) -- Schema and Update Logic

### Description

Define the per-session `session.json` schema and implement the update logic. Each session directory contains its own `session.json` file, updated within the existing per-session flock scope. No global shared state. No additional lock files.

This replaces the original global `sessions.json` design (see Design Amendment 1 and 2).

### Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/session_meta.sh` | Create | session.json creation and update functions |
| `tests/lib/test_session_meta.sh` | Create | Correctness tests |

### Specification

#### session.json Schema

Each `events/{project-id}/{session-id}/session.json` contains:

```json
{
  "session_id": "abc-123",
  "project_id": "my-project-a3f7b2",
  "project_dir": "/home/user/my-project",
  "started_at": "2026-02-14T10:30:00Z",
  "source": "manual",
  "model": "claude-opus-4-6",
  "event_count": 247,
  "last_event_at": "2026-02-14T11:45:00Z",
  "last_event_type": "TurnCompleted",
  "last_prompt": "Fix the auth bug in handler.ts",
  "ended_at": null,
  "previous_session_id": null
}
```

#### Update Functions

All functions operate on the session's own `session.json` file. They are called **within the existing per-session flock** in `event_write.sh` (Task 6), so no additional locking is needed.

`gc_session_meta_create(session_dir, session_id, project_id, project_dir, source, model, started_at)`:

- Creates `session.json` in the session directory with initial values.
- Sets `event_count` to 1, `last_event_at` to `started_at`, `last_event_type` to `"SessionStarted"`.
- Called when the first event (SessionStarted) for a session is written.

`gc_session_meta_update(session_dir, event_type, timestamp)`:

- Increments `event_count`, updates `last_event_at` and `last_event_type`.
- If `event_type` is `UserPromptReceived`: updates `last_prompt` (extracted from event data by caller).
- If `event_type` is `SessionEnded`: sets `ended_at`.
- Uses `gc_atomic_write` (Task 4) with `fsync=false` (performance).

`gc_session_meta_read(session_dir) -> json`:

- Reads and returns `session.json` content. No lock needed for reads.

#### Integration with Event Write (Task 6)

Inside the existing flock scope in `gc_write_event`:

```bash
(
  flock -w 5 200
  # ... assign sequence number, write event file (existing logic) ...

  # Update session.json (within same flock, no extra lock)
  if [ "$next_seq" -eq 1 ]; then
    gc_session_meta_create "$session_dir" "$session_id" "$project_id" ...
  else
    gc_session_meta_update "$session_dir" "$event_type" "$timestamp"
  fi
) 200>"$lock_file"
```

### Dependencies

- Task 1 (paths.sh)
- Task 4 (atomic_write.sh)

### Acceptance Test

1. First event creates `session.json` with all fields populated from SessionStarted data.
2. 10th event: `event_count` is 10, `last_event_at` is the 10th event's timestamp.
3. `UserPromptReceived` event updates `last_prompt` field.
4. `SessionEnded` event sets `ended_at` field.
5. `session.json` is always valid JSON after any update.
6. No global lock files exist (no `.sessions.lock`).
7. Two different sessions updating their own `session.json` concurrently: no interference.
8. `session.json` is written atomically (no partial reads).

### Estimated Complexity

**S** (Small)

---

## Task 9: Config File (config.json) Management

### Description

Implement config.json creation with defaults and a reader that scripts use to load configuration values. Config is created once during init and never overwritten.

### Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/config.sh` | Create | Config creation, reading, validation |
| `tests/lib/test_config.sh` | Create | Config tests |

### Specification

Function: `gc_config_create()`:

Writes default config.json (via atomic write) if the file does not exist:

```json
{
  "version": "1.0.0",
  "created_at": "<ISO 8601 now>",
  "storage_path": "<$GC_ROOT>",
  "checksum": false
}
```

> **Amendment 4**: `retention_days` removed — gc-cleanup is deferred, so retention config is meaningless.
> **CQRS note**: `max_event_size_bytes` removed — the write side stores events as-is without size checks. If size management is needed, it belongs on the read side.

Function: `gc_config_read(field) -> value`:

- Reads a single field from config.json using jq.
- Example: `gc_config_read version` returns `"1.0.0"`.
- If config.json does not exist: print error "GlobalContext store not initialized. Run gc-init." and exit 1.
- If config.json is unparseable: print error "config.json is corrupt" and exit 1.
- If the requested field is missing: return the default value (hardcoded fallbacks).

Function: `gc_config_validate() -> 0 or 1`:

- Checks that config.json exists, is valid JSON, and contains all required fields.
- Returns 0 if valid, 1 if not.

Unknown fields are preserved -- the config reader ignores them, and no operation strips them.

### Dependencies

- Task 1 (paths.sh)
- Task 4 (atomic_write.sh)

### Acceptance Test

1. Call `gc_config_create` -- file exists with all default fields.
2. Call again -- file is not overwritten (check `created_at` is unchanged).
3. `gc_config_read version` returns `"1.0.0"`.
4. `gc_config_read storage_path` returns the store root path.
5. Delete config.json, call `gc_config_read` -- error message printed, exit code 1.
6. Write `{invalid json` to config.json, call `gc_config_read` -- error message, exit code 1.
7. Add `"custom_field": "value"` to config.json, call `gc_config_create` -- custom field preserved (file not overwritten).
8. `gc_config_validate` returns 0 for valid config, 1 for corrupt config.

### Estimated Complexity

**S** (Small)

---

## Task 10: Latest Session Symlink Management

### Description

Implement atomic symlink update for the per-project `latest` symlink at `projections/{project-id}/latest`, which points to the most recently started session's projection directory within that project.

### Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/latest_symlink.sh` | Create | Symlink creation and update |
| `tests/lib/test_latest_symlink.sh` | Create | Symlink tests |

### Specification

Function: `gc_update_latest_symlink(project_id, session_id)`:

```
1. Compute target: the session_id string (relative path within projections/{project-id}/)
2. Ensure project projection dir: mkdir -p "$GC_PROJECTIONS_DIR/$project_id"
3. Compute symlink path: $GC_PROJECTIONS_DIR/$project_id/latest
4. Create temp symlink: ln -s "$session_id" "$GC_PROJECTIONS_DIR/$project_id/.latest.tmp.$$"
5. Rename over existing: mv -fT "$GC_PROJECTIONS_DIR/$project_id/.latest.tmp.$$" "$GC_PROJECTIONS_DIR/$project_id/latest"
   (On macOS where mv -T is not available, use: ln -sfn "$session_id" "$GC_PROJECTIONS_DIR/$project_id/latest")
6. If symlink creation fails: log warning to stderr, do not block event capture
```

Platform considerations:

- Linux: `mv -fT` for atomic rename of symlink.
- macOS: `ln -sfn` which atomically replaces the symlink.
- Detect platform and use the appropriate method.

Function: `gc_read_latest_session_id(project_id) -> session_id`:

- `readlink "$GC_PROJECTIONS_DIR/$project_id/latest"` -- returns the session ID.
- If symlink does not exist: return empty string.

### Dependencies

- Task 1 (paths.sh)

### Acceptance Test

1. Call `gc_update_latest_symlink "proj-abc123" "session-1"` -- symlink at `projections/proj-abc123/latest` points to `session-1`.
2. Call `gc_update_latest_symlink "proj-abc123" "session-2"` -- symlink now points to `session-2`.
3. `gc_read_latest_session_id "proj-abc123"` returns `"session-2"`.
4. Symlink target is a relative path (not absolute).
5. Two different projects have independent `latest` symlinks.
6. Works on both Linux and macOS (test on CI or both platforms).
7. If projections directory does not exist -- error logged, no crash.
8. Target projection directory does not need to exist for symlink creation.

### Estimated Complexity

**S** (Small)

---

## Task 11: Projection Directory and File Scaffolding

### Description

Implement the projection storage structure: per-session projection directories, projection file metadata format, staleness detection, and the atomic write pattern for projection files. This task creates the scaffolding -- the actual projection logic (timeline, files-touched, etc.) is Story 04's responsibility.

### Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/projection_store.sh` | Create | Projection directory creation, staleness check, metadata handling |
| `tests/lib/test_projection_store.sh` | Create | Tests |

### Specification

Function: `gc_ensure_projection_dir(project_id, session_id)`:

- Creates `$GC_PROJECTIONS_DIR/{project_id}/{session_id}/` if it does not exist.
- Returns the directory path.

Function: `gc_write_projection(project_id, session_id, projection_name, data_json, event_count, last_sequence)`:

- Wraps data in metadata envelope:
  ```json
  {
    "_projection": "<projection_name>",
    "_project_id": "<project_id>",
    "_session_id": "<session_id>",
    "_rebuilt_at": "<ISO 8601 now>",
    "_event_count": <event_count>,
    "_last_sequence": <last_sequence>,
    "data": <data_json>
  }
  ```
- Writes atomically to `$GC_PROJECTIONS_DIR/{project_id}/{session_id}/{projection_name}.json`.

Function: `gc_is_projection_stale(project_id, session_id, projection_name) -> 0 (stale) or 1 (current)`:

- Read `_last_sequence` from the projection file.
- Count `[0-9]*.json` files in `$GC_EVENTS_DIR/{project_id}/{session_id}/` (excludes session.json, lock files, rejected).
- If event count > `_last_sequence`: projection is stale (return 0).
- If projection file does not exist: stale (return 0).
- Otherwise: current (return 1).

Function: `gc_read_projection(project_id, session_id, projection_name) -> json`:

- Reads and returns the projection file content.
- Returns empty string if file does not exist.

Projection file definitions (schema owned by Story 04, listed here for reference):

| File | Purpose |
|---|---|
| `timeline.json` | Ordered chronological summary |
| `files-touched.json` | File operation tracking |
| `decisions.json` | Intent-to-action chains |
| `context.json` | Full reconstructable context |

### Dependencies

- Task 1 (paths.sh)
- Task 4 (atomic_write.sh)

### Acceptance Test

1. `gc_ensure_projection_dir "proj-abc123" "s1"` creates `projections/proj-abc123/s1/`.
2. `gc_write_projection "proj-abc123" "s1" "timeline" '[]' 10 10` creates `timeline.json` with metadata.
3. Verify metadata fields: `_projection` is `"timeline"`, `_project_id` is `"proj-abc123"`, `_session_id` is `"s1"`, `_event_count` is 10, `_last_sequence` is 10.
4. `gc_is_projection_stale "proj-abc123" "s1" "timeline"` returns 1 (current) when event count matches.
5. Add an event file to the session, call `gc_is_projection_stale` -- returns 0 (stale).
6. Projection writes are atomic (verified by concurrent read during write).
7. Deleting all projection files is safe -- `gc_is_projection_stale` returns 0 for all.

### Estimated Complexity

**M** (Medium)

---

## ~~Task 12: gc-cleanup Command~~ [DEFERRED — See Amendment 4]

This task is deferred per Design Amendment 4. Retention-based deletion contradicts the append-only principle. Disk usage is monitored by `gc-query store-size` (Task 13) and `gc-query doctor` (Plan 05). If cleanup is needed in the future, it will be added as a separate story.

---

## Task 13: gc-query store-size Command

### Description

Implement the `gc-query store-size` subcommand that reports total event count, total size in bytes, oldest session, and newest session.

### Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/bin/gc-query` | Create (stub) | Query command with `store-size` subcommand |
| `tests/bin/test_gc_query_store_size.sh` | Create | Store size reporting tests |

### Specification

Invocation: `gc-query store-size [--format json|text]`

Output (text mode):

```
GlobalContext Store: /home/user/.claude-context
Sessions:      15
Total events:  3,247
Total size:    12.4 MB
Oldest:        2026-01-15 (session abc-123)
Newest:        2026-02-14 (session xyz-789)
```

Output (JSON mode):

```json
{
  "store_path": "/home/user/.claude-context",
  "session_count": 15,
  "total_events": 3247,
  "total_size_bytes": 13002752,
  "oldest_session": {"session_id": "abc-123", "started_at": "2026-01-15T08:00:00Z"},
  "newest_session": {"session_id": "xyz-789", "started_at": "2026-02-14T10:00:00Z"}
}
```

Implementation:

1. Scan project directories in `$GC_EVENTS_DIR/` (the project-id layer).
2. For each project, count session directories.
3. Count all `[0-9]*.json` files across all session directories (excludes session.json, lock files, rejected, tmp).
4. Sum file sizes using `du` or `stat`.
5. Read per-session `session.json` files to find oldest/newest `started_at` timestamps.

### Dependencies

- Task 1 (paths.sh)
- Task 8 (session_meta.sh, for reading per-session session.json)
- Task 9 (config.sh)

### Acceptance Test

1. Empty store -- reports 0 sessions, 0 events, 0 bytes.
2. Store with 3 sessions and 50 events -- correct counts and size.
3. `--format json` produces valid JSON.
4. `--format text` (default) produces human-readable output.
5. Oldest and newest session IDs are correct.

### Estimated Complexity

**S** (Small)

---

## Task 14: Rejected Event Handling

### Description

Implement the `_rejected/` directory mechanism for events that fail validation. These are events that cannot be written to the main event log but should be preserved for debugging.

### Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/rejected.sh` | Create | Rejected event writing |
| `tests/lib/test_rejected.sh` | Create | Tests |

### Specification

Function: `gc_write_rejected_event(project_id, session_id, content, error_reason)`:

1. Create `$GC_EVENTS_DIR/{project_id}/{session_id}/_rejected/` if it does not exist.
2. Write a file named `{timestamp}-{uuid}.json` containing:
   ```json
   {
     "_rejected_at": "<ISO 8601>",
     "_reason": "<error_reason>",
     "_original_content": "<content or truncated preview>"
   }
   ```
3. This does not need flock (rejected files do not participate in sequencing).
4. Uses atomic write (Task 4).

### Dependencies

- Task 1 (paths.sh)
- Task 3 (session_dir.sh)
- Task 4 (atomic_write.sh)

### Acceptance Test

1. Write a rejected event -- file appears in `_rejected/` with correct structure.
2. Rejected files do not interfere with sequence numbering (not counted as events).
3. Multiple rejected events create separate files (no overwrites).
4. The `_reason` field explains why the event was rejected.

### Estimated Complexity

**S** (Small)

---

## Task 15: Integration Test Suite

### Description

Write end-to-end integration tests that exercise the full storage layer: init, write events, update per-session session.json, manage projections, and handle concurrent operations.

### Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `tests/integration/test_storage_layer.sh` | Create | Full integration test suite |
| `tests/integration/test_concurrent_writes.sh` | Create | Concurrency stress tests |
| `tests/integration/test_crash_recovery.sh` | Create | Crash recovery and orphan cleanup |

### Specification

#### test_storage_layer.sh

1. **Init and verify**: Run gc-init, verify all directories and files. Verify no sessions.json or .sessions.lock.
2. **Write and read back**: Write 100 events across 3 sessions (2 projects), verify all files with project-id paths.
3. **Per-session metadata**: Verify each session has its own `session.json` with correct `event_count`.
4. **Latest symlink**: Verify per-project symlinks point to the last session started in each project.
5. **Projection scaffolding**: Write a projection, verify metadata (including `_project_id`), check staleness.
6. **Config**: Verify config.json, test read operations, verify no `retention_days` or `max_event_size_bytes`.
7. **Store size**: Run gc-query store-size, verify counts across projects.
8. **Idempotent init**: Run gc-init again, verify no data loss.
9. **CLAUDE_CONTEXT_PATH**: Run entire suite against a custom path.

#### test_concurrent_writes.sh

1. Spawn 20 parallel `gc_write_event` calls for the same session.
2. Verify: 20 event files exist, sequence numbers 1-20, no gaps, no duplicates.
3. Verify: `session.json` `event_count` is 20 after all writes complete.
4. Repeat with 5 different sessions concurrently (across 2 projects).
5. Verify: each session's `session.json` has correct independent `event_count`.

#### test_crash_recovery.sh

1. Create orphan temp files (`*.tmp.*`) in event directories.
2. Run gc-init -- verify orphan files are deleted.
3. Write an event to `_rejected/` -- verify it does not affect normal operations.
4. Simulate flock timeout -- verify orphan event file is created.

### Dependencies

- All previous tasks (1-14)

### Acceptance Test

All test scripts exit with code 0. Specific pass/fail output for each test case.

### Estimated Complexity

**L** (Large)

---

## Dependency Graph

```
Task 1: Shared Path Resolver + Project ID Derivation
  |
  +---> Task 2: Session ID Sanitization
  |       |
  |       +---> Task 3: Session Directory + Lock Files [C-1]
  |               |
  |               +---> Task 6: Event File Writing + session.json update
  |               |
  |               +---> Task 14: Rejected Event Handling
  |
  +---> Task 4: Atomic Write Helper [M-3]
  |       |
  |       +---> Task 6: Event File Writing
  |       +---> Task 7: Init Command [M-4]
  |       +---> Task 8: Per-Session Metadata (session.json)
  |       +---> Task 9: Config File
  |       +---> Task 11: Projection Scaffolding
  |       +---> Task 14: Rejected Event Handling
  |
  +---> Task 5: JSON Validation
  |       |
  |       +---> Task 6: Event File Writing
  |
  +---> Task 10: Latest Symlink (per-project)
  |
  +---> Task 9: Config File
          |
          +---> Task 7: Init Command
          +---> Task 13: gc-query store-size

Task 15: Integration Tests (depends on all active tasks)
```

## Implementation Order

| Order | Task | Depends On | Review Issue |
|---|---|---|---|
| 1 | Task 1: Shared Path Resolver + Project ID | -- | M-4, Amend 3 |
| 2 | Task 2: Session ID Sanitization | Task 1 | M-2 |
| 3 | Task 4: Atomic Write Helper | Task 1 | M-3 |
| 4 | Task 5: JSON Validation | (jq) | -- |
| 5 | Task 3: Session Directory + Lock Files | Tasks 1, 2 | C-1 |
| 6 | Task 9: Config File | Tasks 1, 4 | -- |
| 7 | Task 8: Per-Session Metadata | Tasks 1, 4 | Amend 2 |
| 8 | Task 14: Rejected Event Handling | Tasks 1, 3, 4 | -- |
| 9 | Task 6: Event File Writing | Tasks 1-5, 8 | -- |
| 10 | Task 10: Latest Symlink (per-project) | Task 1 | Amend 3 |
| 11 | Task 11: Projection Scaffolding | Tasks 1, 4 | -- |
| 12 | Task 7: Init Command | Tasks 1, 4, 9 | M-4 |
| 13 | Task 13: gc-query store-size | Tasks 1, 9 | -- |
| 14 | Task 15: Integration Tests | All | -- |

Tasks 4 and 5 can be implemented in parallel. Tasks 10 and 11 can be implemented in parallel.

---

## Review Issue Resolution Summary

| Issue | Resolution | Owner Task |
|---|---|---|
| **C-1**: Lock file naming | Canonicalized on `.lock` (not `_seq.lock`). Story 01 must be updated to reference this. | Task 3 |
| **C-2**: sessions.json schema | ~~Merged schema defined.~~ **Superseded by Amendment 2**: global sessions.json removed. Per-session `session.json` with focused schema. | Task 8 |
| **M-2**: Session ID sanitization | Canonical rules defined in Task 2. Only `[a-zA-Z0-9_-]` allowed. All other characters stripped (using `tr -cd`). Story 01 must call this function, not re-implement. | Task 2 |
| **M-3**: Atomic write pattern | Canonical pattern defined: temp file (`{target}.tmp.{pid}`) + optional fsync + rename. All stories must use `gc_atomic_write()`. | Task 4 |
| **M-4**: CLAUDE_CONTEXT_PATH env var | All path resolution goes through `paths.sh` which respects `CLAUDE_CONTEXT_PATH`. No script hardcodes `~/.claude-context`. | Task 1 |

---

## File Inventory

All files created by this story:

### Source Files

| File | Task | Purpose |
|---|---|---|
| `src/lib/paths.sh` | 1 | Shared path resolver and constants |
| `src/lib/sanitize.sh` | 2 | Session ID sanitization |
| `src/lib/session_dir.sh` | 3 | Session directory management |
| `src/lib/atomic_write.sh` | 4 | Atomic write helper |
| `src/lib/json_validate.sh` | 5 | JSON validation |
| `src/lib/event_write.sh` | 6 | Event writing pipeline |
| `src/lib/session_meta.sh` | 8 | Per-session session.json creation and update |
| `src/lib/config.sh` | 9 | Config file management |
| `src/lib/latest_symlink.sh` | 10 | Latest symlink management |
| `src/lib/projection_store.sh` | 11 | Projection directory and file management |
| `src/lib/rejected.sh` | 14 | Rejected event handling |
| `src/bin/gc-init` | 7 | Init command |
| ~~`src/bin/gc-cleanup`~~ | ~~12~~ | ~~Cleanup command~~ [DEFERRED] |
| `src/bin/gc-query` | 13 | Query command (store-size subcommand) |

### Documentation

| File | Task | Purpose |
|---|---|---|
| `docs/schemas/session.json.schema.md` | 8 | Per-session session.json schema |

### Test Files

| File | Task | Purpose |
|---|---|---|
| `tests/lib/test_paths.sh` | 1 | Path resolver tests |
| `tests/lib/test_sanitize.sh` | 2 | Sanitization edge case tests |
| `tests/lib/test_session_dir.sh` | 3 | Session directory tests |
| `tests/lib/test_atomic_write.sh` | 4 | Atomic write tests |
| `tests/lib/test_json_validate.sh` | 5 | JSON validation tests |
| `tests/lib/test_event_write.sh` | 6 | Event write tests |
| `tests/lib/test_session_meta.sh` | 8 | Per-session metadata tests |
| `tests/lib/test_config.sh` | 9 | Config tests |
| `tests/lib/test_latest_symlink.sh` | 10 | Symlink tests |
| `tests/lib/test_projection_store.sh` | 11 | Projection store tests |
| `tests/lib/test_rejected.sh` | 14 | Rejected event tests |
| `tests/bin/test_gc_init.sh` | 7 | Init command tests |
| ~~`tests/bin/test_gc_cleanup.sh`~~ | ~~12~~ | ~~Cleanup command tests~~ [DEFERRED] |
| `tests/bin/test_gc_query_store_size.sh` | 13 | Store size query tests |
| `tests/integration/test_storage_layer.sh` | 15 | Full integration tests |
| `tests/integration/test_concurrent_writes.sh` | 15 | Concurrency tests |
| `tests/integration/test_crash_recovery.sh` | 15 | Crash recovery tests |

---

## Effort Estimates

| Task | Complexity | Estimate |
|---|---|---|
| Task 1: Shared Path Resolver | S | 1-2 hours |
| Task 2: Session ID Sanitization | S | 1-2 hours |
| Task 3: Session Directory + Lock Files | S | 1-2 hours |
| Task 4: Atomic Write Helper | S | 2-3 hours |
| Task 5: JSON Validation | S | 1-2 hours |
| Task 6: Event File Writing | L | 4-6 hours |
| Task 7: Init Command | M | 3-4 hours |
| Task 8: Per-Session Metadata | S | 1-2 hours |
| Task 9: Config File | S | 1-2 hours |
| Task 10: Latest Symlink | S | 1-2 hours |
| Task 11: Projection Scaffolding | M | 2-3 hours |
| ~~Task 12: gc-cleanup~~ | ~~M~~ | ~~DEFERRED~~ |
| Task 13: gc-query store-size | S | 2-3 hours |
| Task 14: Rejected Event Handling | S | 1-2 hours |
| Task 15: Integration Tests | L | 6-8 hours |
| **Total** | | **~24-38 hours (~3-4 working days)** |
