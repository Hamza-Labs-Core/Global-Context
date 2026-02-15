# Implementation Plan: Story 02 -- Hook Integration Layer

**Story**: 02-hook-integration
**Date**: 2026-02-14
**Status**: Ready for implementation
**Depends on**: Story 01 (Event Capture -- `capture-event` must exist and be executable)
**Review fixes incorporated**: C-3, M-4, M-5, G-4, G-5
**Design Amendments**: 3 (project-id layer). See `docs/DESIGN-AMENDMENTS.md`.

### Amendment Impacts on This Plan

- **Amendment 3**: `gc-hook` extracts the project directory from the hook payload's `cwd` field and passes it to `capture-event`. The hook command string does not change — project detection happens at runtime inside `gc-hook`, not in settings.json.

---

## Overview

This plan breaks Story 02 into 12 ordered implementation tasks. The story produces two executable scripts (`gc-hook`, `gc-install-hooks`) and their tests. It also installs the complete hook configuration into `~/.claude/settings.json` so that all Claude Code lifecycle events flow into the GlobalContext event store.

### Review Fixes Addressed

- **C-3** (gc-hook wrapper must be clearly defined and created in this story): Tasks 1 and 2 explicitly create `gc-hook` as a Story 02 artifact. The wrapper is fully specified, tested, and deployed by `gc-install-hooks`.
- **M-4** (Support `CLAUDE_CONTEXT_PATH` env var in gc-hook): Task 3 adds a shared path-resolution helper used by `gc-hook` and `gc-install-hooks`, respecting the env var defined in Story 03.
- **M-5** (Document hook payload structures): Task 10 adds a reference document for all hook payload structures, linking back to Story 01 Section 8.
- **G-4** (No log file for async hook stderr): Task 11 adds optional debug logging to `gc-hook` when `GC_DEBUG=1` is set, writing to `~/.claude-context/logs/hook.log` with rotation.
- **G-5** (Full system uninstall not defined): Task 12 creates `gc-uninstall` that removes hooks from settings.json, deletes the store, and prints a cleanup summary.

---

## Task 1: Create the `gc-hook` Wrapper Script

### Description

Build the thin shell wrapper that Claude Code hook commands invoke. This script receives an event type as its first argument, reads JSON from stdin, passes both to `capture-event`, and guarantees exit code 0 with zero stdout/stderr output regardless of what happens internally. This is the script referenced by every hook command in `settings.json`.

This task directly addresses **review issue C-3**: the `gc-hook` wrapper is owned by Story 02 and must be created here.

### Files to Create

- `src/gc-hook` -- source file for the wrapper script (installed to `~/.claude-context/bin/gc-hook`)

### Script Specification

```bash
#!/usr/bin/env bash
# GlobalContext hook wrapper v1
# Usage: gc-hook <EventType>
# Called by Claude Code hooks. Reads JSON from stdin, passes to capture-event.
# GUARANTEES: exit 0, zero stdout, zero stderr.

EVENT_TYPE="${1:?Missing event type}"

# Resolve storage path: CLAUDE_CONTEXT_PATH env var, or default
GC_BASE="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"

# Run capture-event in a subshell to isolate all side effects.
# - stdin is piped through from Claude Code
# - stdout is suppressed (no output that Claude Code could interpret)
# - stderr is suppressed (no error leaks)
# - exit code is ignored (|| true)
("$GC_BASE/bin/capture-event" "$EVENT_TYPE" </dev/stdin >/dev/null 2>/dev/null) || true

exit 0
```

### Dependencies

- None (first task)

### Acceptance Test

1. Place a mock `capture-event` at `~/.claude-context/bin/capture-event` that writes stdin to a temp file.
2. Run: `echo '{"session_id":"test"}' | src/gc-hook SessionStarted`
3. Verify exit code is 0.
4. Verify stdout is empty (capture with `$()` and assert empty string).
5. Verify stderr is empty (redirect 2>&1 to a file, assert empty).
6. Verify the mock received the JSON and the event type argument.
7. Remove `capture-event`, run `gc-hook` again. Verify exit 0, no output.
8. Make `capture-event` a script that exits 1. Run `gc-hook`. Verify exit 0.

### Estimated Complexity

**S** (Small) -- approximately 15 lines of Bash.

---

## Task 2: Create `gc-hook` Unit Test Suite

### Description

Write automated tests for all `gc-hook` guarantees: exit code, stdout silence, stderr silence, stdin passthrough, argument forwarding, and graceful failure when `capture-event` is missing, crashes, or times out.

### Files to Create

- `tests/02-gc-hook-tests.sh` -- executable test script

### Test Cases

| ID | Test | Method |
|----|------|--------|
| T-1 | gc-hook exits 0 when capture-event is missing | Remove capture-event, run gc-hook, assert `$? == 0` |
| T-2 | gc-hook exits 0 when capture-event crashes (exit 1) | Mock capture-event as `exit 1`, run gc-hook, assert `$? == 0` |
| T-3 | gc-hook produces zero bytes on stdout | Capture stdout to variable, assert empty |
| T-4 | gc-hook produces zero bytes on stderr | Redirect stderr to file, assert file is empty |
| T-5 | gc-hook passes stdin through to capture-event | Mock capture-event to write stdin to file, compare input to file |
| T-6 | gc-hook passes event type as $1 to capture-event | Mock capture-event to write $1 to file, verify value |
| T-7 | gc-hook respects CLAUDE_CONTEXT_PATH env var | Set env var to temp dir, place mock there, verify it is invoked |
| T-8 | gc-hook handles large payloads (1MB) without truncation | Generate 1MB JSON, pipe through gc-hook, verify capture-event received full payload |

### Dependencies

- Task 1 (gc-hook script must exist)

### Acceptance Test

Run `bash tests/02-gc-hook-tests.sh` and all 8 tests pass with zero failures.

### Estimated Complexity

**S** (Small) -- test harness with temp directories and mock scripts.

---

## Task 3: Add `CLAUDE_CONTEXT_PATH` Support (Review Fix M-4)

### Description

Ensure both `gc-hook` and `gc-install-hooks` respect the `CLAUDE_CONTEXT_PATH` environment variable for the storage root path, rather than hardcoding `~/.claude-context/`. This addresses **review issue M-4**.

The pattern is simple: at the top of each script, resolve the base directory:

```bash
GC_BASE="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"
```

All subsequent path references use `$GC_BASE` instead of a hardcoded path.

For hook commands written to `settings.json`, the command string must remain `~/.claude-context/bin/gc-hook ...` (Claude Code expands `~`). The env var override is resolved at runtime inside `gc-hook`, not in the hook command string. This means:
- The `settings.json` hook commands always reference `~/.claude-context/bin/gc-hook` (the entry point).
- When `gc-hook` executes, it reads `CLAUDE_CONTEXT_PATH` and invokes `capture-event` from the correct location.
- Users who set `CLAUDE_CONTEXT_PATH` in their shell profile get the override applied to all hook invocations.

### Files to Modify

- `src/gc-hook` (from Task 1) -- already includes `GC_BASE` resolution; verify it is correct
- `src/gc-install-hooks` (created in Task 5) -- must use `GC_BASE` for all path references during install/validate

### Files to Create

None. The resolution is inline (a single variable assignment), not a separate helper file.

### Dependencies

- Task 1 (gc-hook exists)

### Acceptance Test

1. Set `CLAUDE_CONTEXT_PATH=/tmp/test-gc-store`.
2. Create `/tmp/test-gc-store/bin/capture-event` as a mock.
3. Run `echo '{"session_id":"x"}' | CLAUDE_CONTEXT_PATH=/tmp/test-gc-store src/gc-hook SessionStarted`.
4. Verify the mock at the custom path was invoked (not the default path).
5. Unset `CLAUDE_CONTEXT_PATH`, verify it falls back to `~/.claude-context`.

### Estimated Complexity

**S** (Small) -- one-line change per script, plus verification tests.

---

## Task 4: Define Hook Configuration Data Structure

### Description

Create the canonical hook configuration as a structured data definition that the installation script reads. This is the single source of truth for all 10 hook entries: event names, event types, async flags, timeouts, and matchers. Defining it as data (not inline code) satisfies AC-5.3 (timeout as a constant, not hardcoded in 10 places) and makes it easy to add/remove hooks in future versions.

### Files to Create

- `src/hook-config.json` -- the complete reference configuration as valid JSON

### Data Structure

```json
{
  "_comment": "GlobalContext hook configuration v1. Do not edit -- generated by gc-install-hooks.",
  "_timeout_ms": 5000,
  "hooks": {
    "SessionStart": {
      "event_type": "SessionStarted",
      "async": false,
      "timeout": 5000,
      "matcher": ""
    },
    "UserPromptSubmit": {
      "event_type": "UserPromptReceived",
      "async": false,
      "timeout": 5000,
      "matcher": null
    },
    "PreToolUse": {
      "event_type": "ToolCallRequested",
      "async": true,
      "timeout": 5000,
      "matcher": ".*"
    },
    "PostToolUse": {
      "event_type": "ToolCallCompleted",
      "async": true,
      "timeout": 5000,
      "matcher": ".*"
    },
    "PostToolUseFailure": {
      "event_type": "ToolCallFailed",
      "async": true,
      "timeout": 5000,
      "matcher": ".*"
    },
    "SubagentStart": {
      "event_type": "AgentSpawned",
      "async": true,
      "timeout": 5000,
      "matcher": ".*"
    },
    "SubagentStop": {
      "event_type": "AgentCompleted",
      "async": true,
      "timeout": 5000,
      "matcher": ".*"
    },
    "Stop": {
      "event_type": "TurnCompleted",
      "async": true,
      "timeout": 5000,
      "matcher": null
    },
    "PreCompact": {
      "event_type": "CompactionTriggered",
      "async": false,
      "timeout": 5000,
      "matcher": null
    },
    "SessionEnd": {
      "event_type": "SessionEnded",
      "async": true,
      "timeout": 5000,
      "matcher": null
    }
  }
}
```

Where `matcher: null` means the field is omitted from the `settings.json` output.

### Dependencies

- None (data definition only)

### Acceptance Test

1. `jq . src/hook-config.json` parses without error.
2. `jq '.hooks | keys | length' src/hook-config.json` returns `10`.
3. Sync events (SessionStart, UserPromptSubmit, PreCompact) have `"async": false`.
4. All timeouts are 5000.
5. Tool-related hooks (PreToolUse, PostToolUse, PostToolUseFailure, SubagentStart, SubagentStop) have `"matcher": ".*"`.

### Estimated Complexity

**S** (Small) -- pure data, no logic.

---

## Task 5: Implement `gc-install-hooks` -- Install Command

### Description

Build the core installation logic: read existing `settings.json`, merge GlobalContext hooks into it (preserving user hooks and non-hook settings), and write the result back. This is the most complex script in Story 02.

### Files to Create

- `src/gc-install-hooks` -- executable Bash script

### Implementation Details

The script supports three subcommands: `install`, `uninstall`, `validate`. This task covers `install`.

**Install flow**:

```
gc-install-hooks install
  1. Resolve GC_BASE from CLAUDE_CONTEXT_PATH or default
  2. Pre-installation checks:
     a. Verify jq is on PATH (abort if missing)
     b. Verify $GC_BASE/bin/capture-event exists and is executable (abort if missing)
     c. Verify $GC_BASE/bin/gc-hook exists and is executable (abort if missing)
  3. Ensure ~/.claude/ directory exists (create with mode 0700 if missing)
  4. If ~/.claude/settings.json exists:
     a. Validate it is parseable JSON (abort with clear error if malformed)
     b. Create backup at ~/.claude/settings.json.bak.{YYYYMMDD-HHMMSS}
     c. Read content into variable
  5. If ~/.claude/settings.json does not exist:
     a. Start with empty object: '{}'
  6. Use jq to merge hooks:
     For each of the 10 hook events:
       a. Build the hook entry JSON object (type, command, async, timeout, matcher)
       b. If hooks.{EventName} array exists, filter out any entry containing "gc-hook"
          in its command, then append the new entry
       c. If hooks.{EventName} does not exist, create it with [new entry]
  7. Write merged JSON to ~/.claude/settings.json (2-space indentation)
  8. Validate written file is parseable by jq
  9. Print summary: "Installed 10 GlobalContext hooks. Backup: <path>"
```

**Key jq operations**:

For each hook event, the merge can be done with a single jq pipeline:

```bash
# Remove existing GC hook from array (if any), then append new one
jq --argjson new_hook "$hook_json" \
   '.hooks.PreToolUse = ([.hooks.PreToolUse // [] | .[] | select(.command | contains("gc-hook") | not)] + [$new_hook])' \
   "$settings_file"
```

The entire merge should be done in as few jq invocations as possible (ideally one pass that handles all 10 events).

**Constants** (defined once at the top of the script):

```bash
HOOK_TIMEOUT=5000
HOOK_IDENTIFIER="gc-hook"
GC_HOOK_PATH="~/.claude-context/bin/gc-hook"
```

### Dependencies

- Task 1 (gc-hook must exist for prerequisite check)
- Task 4 (hook-config.json for the canonical configuration)

### Acceptance Test

1. Start with no `~/.claude/settings.json`. Run `gc-install-hooks install`. Verify file is created with all 10 hooks.
2. Run again. Verify no duplicates (idempotent).
3. Add a user hook to PreToolUse manually. Run install. Verify user hook is preserved alongside GC hook.
4. Add a non-hook setting (`"model": "opus"`) to settings.json. Run install. Verify it is preserved.
5. Verify backup file exists at `~/.claude/settings.json.bak.*`.
6. Verify all 10 hooks have correct async flags, timeouts, and matchers per the mapping table.
7. Run `jq . ~/.claude/settings.json` to verify valid JSON with 2-space indentation.

### Estimated Complexity

**L** (Large) -- JSON merging with jq, backup logic, prerequisite checks, idempotency.

---

## Task 6: Implement `gc-install-hooks` -- Uninstall Command

### Description

Add the `uninstall` subcommand to `gc-install-hooks`. This removes all GlobalContext hooks from `settings.json` while preserving user hooks and other settings.

### Files to Modify

- `src/gc-install-hooks` -- add uninstall subcommand

### Implementation Details

```
gc-install-hooks uninstall
  1. Verify ~/.claude/settings.json exists (abort if not)
  2. Validate it is parseable JSON (abort if malformed)
  3. Create backup
  4. For each hook event key in .hooks:
     a. Filter out entries where .command contains "gc-hook"
     b. If array is now empty, remove the event key
  5. If .hooks is now an empty object, remove the .hooks key
  6. Write cleaned JSON back
  7. Print summary of what was removed
```

### Dependencies

- Task 5 (install command must exist; uninstall is added to the same script)

### Acceptance Test

1. Install hooks, then uninstall. Verify all GC hooks are removed.
2. Verify user hooks survive uninstall.
3. Verify non-hook settings survive uninstall.
4. Verify empty hook arrays are removed.
5. Verify empty `hooks` object is removed.
6. Verify backup was created before uninstall.
7. Run on a file with no hooks. Verify it does not crash (no-op).

### Estimated Complexity

**M** (Medium) -- inverse of install logic, with cleanup of empty structures.

---

## Task 7: Implement `gc-install-hooks` -- Validate Command

### Description

Add the `validate` subcommand to `gc-install-hooks`. This verifies that all 10 hooks are present in `settings.json`, that `gc-hook` is functional, and runs a smoke test that sends a test event through the full pipeline.

### Files to Modify

- `src/gc-install-hooks` -- add validate subcommand

### Implementation Details

```
gc-install-hooks validate
  1. Parse ~/.claude/settings.json
  2. For each of the 10 expected hook events:
     a. Check that the event key exists in .hooks
     b. Check that at least one entry contains "gc-hook" in its command
     c. Verify async, timeout, and matcher values match expected
     d. Report PASS or FAIL for each
  3. Verify gc-hook is executable
  4. Smoke test:
     a. echo '{"session_id":"__gc_validation_test__","test":true}' | gc-hook TestValidation
     b. Verify exit code 0
     c. Verify no stdout output
     d. Check if event file was written to the event store under __gc_validation_test__ session
     e. Clean up: remove the test session directory
  5. Report overall PASS/FAIL
  6. Exit 0 if all checks pass, exit 1 if any fail
```

### Dependencies

- Task 5 (install command)
- Task 1 (gc-hook must be functional for smoke test)
- Story 01 (capture-event must be deployed for the smoke test to write an event)

### Acceptance Test

1. Install hooks, run validate. Verify all checks pass.
2. Manually remove one hook from settings.json. Run validate. Verify it detects the missing hook.
3. Remove gc-hook. Run validate. Verify it reports gc-hook missing.
4. After a passing validate, verify no test artifacts remain in the event store.

### Estimated Complexity

**M** (Medium) -- JSON inspection, smoke test with cleanup.

---

## Task 8: Create Integration Test Suite

### Description

Write automated integration tests that verify the full installation lifecycle: fresh install, idempotent reinstall, upgrade, uninstall, and edge cases (malformed JSON, missing dependencies, existing user hooks).

### Files to Create

- `tests/02-integration-tests.sh` -- executable test script

### Test Cases

| ID | Test | Description |
|----|------|-------------|
| T-7 | Fresh install on empty settings | Install with no prior settings.json; verify all 10 hooks present |
| T-8 | Install preserves existing user hooks | Add user hook, install, verify both hooks coexist |
| T-9 | Install preserves non-hook settings | Add `"model":"opus"` to settings.json, install, verify it survives |
| T-10 | Idempotent reinstall | Run install twice, verify no duplicate hooks |
| T-11 | Uninstall removes only GC hooks | Install, add user hook, uninstall, verify user hook remains |
| T-12 | Uninstall cleans empty structures | Uninstall from a file where GC hooks are the only hooks; verify `hooks` key is removed |
| T-13 | Backup created on install | Verify `settings.json.bak.*` file exists after install |
| T-14 | Creates ~/.claude/ if missing | Remove ~/.claude/, install, verify it is created with mode 0700 |
| T-15 | Aborts on malformed JSON | Write invalid JSON to settings.json, install, verify abort with error message |
| T-16 | Aborts if capture-event missing | Remove capture-event, install, verify abort with error message |
| T-17 | Aborts if jq missing | (Skip if impractical to hide jq; test by checking the error path logic) |
| T-18 | Validate detects missing hooks | Remove a hook entry, run validate, verify it reports the missing hook |
| T-19 | Validate smoke test succeeds | Run validate after clean install, verify all checks pass |
| T-20 | Upgrade from older config | Modify timeout of existing GC hook to 3000, reinstall, verify it is updated to 5000 |
| T-21 | CLAUDE_CONTEXT_PATH override | Set env var to temp dir, install, verify scripts resolve correctly |

All tests use an isolated temp directory as both `HOME` and `CLAUDE_CONTEXT_PATH` to avoid touching the real user environment.

### Dependencies

- Task 1 (gc-hook)
- Task 5 (install)
- Task 6 (uninstall)
- Task 7 (validate)

### Acceptance Test

Run `bash tests/02-integration-tests.sh` and all tests pass. Each test sets up a clean environment, runs the operation, asserts the result, and tears down.

### Estimated Complexity

**L** (Large) -- many test cases, each requiring setup/teardown of temp directories and mock files.

---

## Task 9: Deployment Integration with Story 01 Installer

### Description

Ensure that `gc-hook` and `gc-install-hooks` are deployed alongside `capture-event` during the Story 01 installation process. Update Story 01's `install.sh` (or create a top-level installer) to:

1. Copy `gc-hook` to `~/.claude-context/bin/gc-hook` and `chmod +x`.
2. Copy `gc-install-hooks` to `~/.claude-context/bin/gc-install-hooks` and `chmod +x`.
3. Run `gc-install-hooks install` to register the hooks in `settings.json`.

This task wires the two stories together.

### Files to Modify

- `src/install.sh` (or create `src/install-hooks.sh` if Story 01's installer is separate)

### Implementation Details

After Story 01's `install.sh` deploys `capture-event`, add:

```bash
# Deploy hook wrapper (Story 02)
cp src/gc-hook "$GC_BASE/bin/gc-hook"
chmod +x "$GC_BASE/bin/gc-hook"

# Deploy hook installer (Story 02)
cp src/gc-install-hooks "$GC_BASE/bin/gc-install-hooks"
chmod +x "$GC_BASE/bin/gc-install-hooks"

# Register hooks in Claude Code settings
"$GC_BASE/bin/gc-install-hooks" install
```

### Dependencies

- Task 1 (gc-hook)
- Task 5 (gc-install-hooks install)
- Story 01 (install.sh must exist)

### Acceptance Test

1. Run the full `install.sh` from a clean state.
2. Verify `~/.claude-context/bin/gc-hook` exists and is executable.
3. Verify `~/.claude-context/bin/gc-install-hooks` exists and is executable.
4. Verify `~/.claude/settings.json` contains all 10 hooks.
5. Run `echo '{"session_id":"test"}' | ~/.claude-context/bin/gc-hook SessionStarted` and verify it succeeds.

### Estimated Complexity

**S** (Small) -- a few lines added to the installer.

---

## Task 10: Document Hook Payload Structures (Review Fix M-5)

### Description

Create a reference document that describes the JSON payload structure for each of the 10 hook events that Claude Code sends on stdin. This addresses **review issue M-5**.

The payloads are defined by Claude Code (not by GlobalContext), so this document serves as a reference for developers and for downstream projection consumers. It links to Story 01 Section 8 where the expected fields are first described.

### Files to Create

- `docs/HOOK-PAYLOADS.md` -- reference documentation

### Content Structure

For each of the 10 hook events:

1. **Hook event name** (the Claude Code hook name, e.g., `PreToolUse`)
2. **GlobalContext event type** (e.g., `ToolCallRequested`)
3. **Sync/Async** designation
4. **Example JSON payload** (what arrives on stdin)
5. **Field descriptions** table
6. **Notes** on size, frequency, and downstream usage

Example entry:

```
### PreToolUse -> ToolCallRequested (async)

Example payload:
{
  "session_id": "abc-123",
  "tool_name": "Bash",
  "tool_input": { "command": "ls -la" },
  "tool_use_id": "tu_01ABC"
}

| Field       | Type   | Description                          |
|-------------|--------|--------------------------------------|
| session_id  | string | Current session identifier           |
| tool_name   | string | Name of the tool being invoked       |
| tool_input  | object | Tool-specific input parameters       |
| tool_use_id | string | Unique ID for this tool invocation   |

Notes:
- High frequency event. Fires for every tool call.
- tool_input shape varies per tool (Bash has "command", Read has "file_path", etc.)
- Correlates with PostToolUse/PostToolUseFailure via tool_use_id.
```

Also include a section noting:
- These payloads are Claude Code's contract, not GlobalContext's. If Claude Code changes payload formats, GlobalContext captures whatever is sent.
- GlobalContext stores the entire payload unmodified in the event envelope's `data` field.
- Downstream projections should handle missing or unexpected fields gracefully.

### Dependencies

- None (documentation only; can be written at any time)

### Acceptance Test

1. Document exists and is well-formatted Markdown.
2. All 10 hook events are documented with example payloads.
3. Field descriptions match Story 01 Section 8.
4. The document includes a disclaimer about Claude Code owning the payload contract.

### Estimated Complexity

**M** (Medium) -- 10 payload structures to document with examples and field tables.

---

## Task 11: Add Debug Logging to gc-hook (Review Fix G-4)

### Description

Add optional debug logging to `gc-hook` so that stderr from async hook invocations is not silently lost. By default, stderr remains suppressed (production safety). When the `GC_DEBUG=1` environment variable is set, `gc-hook` writes diagnostic output to a log file instead.

This addresses **review issue G-4**: async hooks run with stderr suppressed (`2>/dev/null`), so if `capture-event` fails, there is no trace.

### Files to Modify

- `src/gc-hook` (from Task 1) -- add conditional debug logging

### Files to Create

- `src/lib/debug_log.sh` -- shared debug logging helper (log rotation, file creation)
- `tests/02-debug-log-tests.sh` -- tests for debug logging behavior

### Implementation Details

**Debug logging helper** (`src/lib/debug_log.sh`):

```bash
#!/usr/bin/env bash
# Debug logging for GlobalContext hooks
# Only active when GC_DEBUG=1

GC_LOG_DIR="${GC_BASE:-$HOME/.claude-context}/logs"
GC_LOG_FILE="$GC_LOG_DIR/hook.log"
GC_LOG_MAX_BYTES=1048576  # 1MB

gc_debug_log() {
  [ "${GC_DEBUG:-0}" != "1" ] && return 0
  mkdir -p "$GC_LOG_DIR" 2>/dev/null || return 0

  # Rotate if over 1MB
  if [ -f "$GC_LOG_FILE" ]; then
    local size
    size=$(stat -c%s "$GC_LOG_FILE" 2>/dev/null || stat -f%z "$GC_LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt "$GC_LOG_MAX_BYTES" ]; then
      mv "$GC_LOG_FILE" "$GC_LOG_FILE.old" 2>/dev/null
    fi
  fi

  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$GC_LOG_FILE" 2>/dev/null
}
```

**Modified gc-hook** (Task 1 update):

```bash
# In gc-hook, replace the capture-event invocation:
if [ "${GC_DEBUG:-0}" = "1" ]; then
  source "$GC_BASE/lib/debug_log.sh" 2>/dev/null
  gc_debug_log "gc-hook invoked: event_type=$EVENT_TYPE"
  ("$GC_BASE/bin/capture-event" "$EVENT_TYPE" </dev/stdin >/dev/null 2>>"$GC_LOG_FILE") || {
    gc_debug_log "capture-event failed: exit=$?"
    true
  }
else
  ("$GC_BASE/bin/capture-event" "$EVENT_TYPE" </dev/stdin >/dev/null 2>/dev/null) || true
fi
```

Key design decisions:

- **Default off**: No performance impact in production. Zero filesystem writes when `GC_DEBUG` is unset.
- **1MB rotation**: Keeps a single `.old` backup. No unbounded growth.
- **Best-effort**: All logging operations fail silently (logging must never break the exit-0 guarantee).
- **Platform-compatible stat**: Tries Linux (`-c%s`) then macOS (`-f%z`) syntax.

### Dependencies

- Task 1 (gc-hook must exist)

### Acceptance Test

1. Run gc-hook with `GC_DEBUG` unset -- no log file created, no log directory created.
2. Run gc-hook with `GC_DEBUG=1` -- log file created at `$GC_BASE/logs/hook.log`.
3. Log entry contains timestamp, event type, and outcome.
4. When capture-event fails with `GC_DEBUG=1` -- failure is logged with exit code.
5. Write 1.5MB of log entries -- file is rotated, `hook.log.old` exists, `hook.log` is small.
6. `GC_DEBUG=1` gc-hook still exits 0, still produces zero stdout/stderr.
7. Corrupt or read-only log directory -- gc-hook still exits 0 (logging failure is silent).

### Estimated Complexity

**S** (Small) -- conditional wrapper around existing invocation, plus a small helper.

---

## Task 12: Create gc-uninstall Command (Review Fix G-5)

### Description

Create a `gc-uninstall` command that performs a full system teardown: removes hooks from `settings.json`, optionally deletes the entire `~/.claude-context/` store, and prints a summary. This addresses **review issue G-5**: full system uninstall is not defined.

### Files to Create

- `src/bin/gc-uninstall` -- full uninstall script
- `tests/02-uninstall-tests.sh` -- uninstall tests

### Implementation Details

**Invocation**:

```bash
gc-uninstall [--keep-data] [--force] [--dry-run]
```

**Flags**:

| Flag | Description |
|------|-------------|
| `--keep-data` | Remove hooks from settings.json but preserve `~/.claude-context/` data |
| `--force` | Skip confirmation prompt (for scripted use) |
| `--dry-run` | Print what would be removed without making changes |

**Uninstall flow**:

```
gc-uninstall
  1. Source paths.sh to resolve GC_BASE
  2. Print: "GlobalContext Uninstall"
  3. Print: "Store location: $GC_BASE"
  4. If not --force and not --dry-run:
     a. Print: "This will remove all GlobalContext hooks and data."
     b. Read confirmation: "Type 'yes' to confirm: "
     c. If input != "yes": abort
  5. If --dry-run:
     a. Print what would be removed (hooks, store directory, files count, size)
     b. Exit 0
  6. Step 1 -- Remove hooks from settings.json:
     a. Run: gc-install-hooks uninstall
     b. If fails: warn but continue
  7. Step 2 -- Remove store (unless --keep-data):
     a. Count files and compute size for summary
     b. rm -rf "$GC_BASE"
  8. Print summary:
     a. "Hooks removed from ~/.claude/settings.json"
     b. "Store deleted: $GC_BASE (N files, X MB)" or "Store preserved (--keep-data)"
  9. Exit 0
```

**Safety considerations**:

- Confirmation prompt by default (no accidental deletions).
- `--keep-data` allows removing hooks while preserving event history for later analysis.
- `--dry-run` for previewing what would happen.
- The script does NOT modify `~/.claude/settings.json` directly -- it delegates to `gc-install-hooks uninstall` (Task 6) for that.
- The script does NOT remove itself from `$GC_BASE/bin/` until the very end (it's running from there).

### Dependencies

- Task 1 (gc-hook, for path resolution)
- Task 6 (gc-install-hooks uninstall, for hook removal)

### Acceptance Test

1. Full uninstall with confirmation -- hooks removed, store deleted, summary printed.
2. `--keep-data` -- hooks removed, store directory still exists with all data.
3. `--force` -- no confirmation prompt, uninstall proceeds.
4. `--dry-run` -- prints what would be removed, nothing actually deleted.
5. Uninstall when hooks are already removed -- no error, continues to store deletion.
6. Uninstall when store does not exist -- no error, prints "store not found".
7. After full uninstall: `~/.claude/settings.json` has no GC hooks, `~/.claude-context/` does not exist.
8. `gc-uninstall --keep-data && gc-install-hooks install` -- reinstall after partial uninstall works.

### Estimated Complexity

**S** (Small) -- delegates hook removal to existing script, then rm -rf with safety checks.

---

## Task Dependency Graph

```
Task 1: gc-hook wrapper
  |
  +---> Task 2: gc-hook unit tests
  |
  +---> Task 3: CLAUDE_CONTEXT_PATH support (M-4)
  |
  +---> Task 5: gc-install-hooks install
  |       |
  |       +---> Task 6: gc-install-hooks uninstall
  |       |       |
  |       |       +---> Task 12: gc-uninstall [G-5] (needs 6)
  |       |
  |       +---> Task 7: gc-install-hooks validate
  |       |
  |       +---> Task 8: Integration tests (needs 5, 6, 7, 11, 12)
  |       |
  |       +---> Task 9: Deployment integration (needs 1, 5)
  |
  +---> Task 11: Debug logging [G-4] (needs 1)
  |
  Task 4: Hook config data structure (independent)
  |
  +---> Task 5 (consumed by install logic)

  Task 10: Payload documentation (independent, can run in parallel)
```

### Suggested Implementation Order

| Phase | Tasks | Rationale |
|-------|-------|-----------|
| 1 | Task 1, Task 4, Task 10 | Independent foundations: wrapper script, config data, docs |
| 2 | Task 2, Task 3, Task 11 | Test and harden gc-hook, add debug logging |
| 3 | Task 5 | Core install logic (depends on Task 1 and Task 4) |
| 4 | Task 6, Task 7 | Uninstall and validate (depend on Task 5) |
| 5 | Task 12 | Full uninstall command (depends on Task 6) |
| 6 | Task 8 | Integration tests (depend on Tasks 5, 6, 7, 11, 12) |
| 7 | Task 9 | Deployment wiring (final step, depends on everything) |

---

## Files Summary

### Files Created by This Story

| File | Task | Purpose |
|------|------|---------|
| `src/gc-hook` | 1, 11 | Hook wrapper script (deployed to `~/.claude-context/bin/gc-hook`) |
| `src/hook-config.json` | 4 | Canonical hook configuration data |
| `src/gc-install-hooks` | 5, 6, 7 | Hook lifecycle manager (deployed to `~/.claude-context/bin/gc-install-hooks`) |
| `src/lib/debug_log.sh` | 11 | Debug logging helper (deployed to `~/.claude-context/lib/debug_log.sh`) |
| `src/bin/gc-uninstall` | 12 | Full system uninstall (deployed to `~/.claude-context/bin/gc-uninstall`) |
| `tests/02-gc-hook-tests.sh` | 2 | Unit tests for gc-hook |
| `tests/02-debug-log-tests.sh` | 11 | Debug logging tests |
| `tests/02-uninstall-tests.sh` | 12 | Uninstall tests |
| `tests/02-integration-tests.sh` | 8 | Integration tests for full install lifecycle |
| `docs/HOOK-PAYLOADS.md` | 10 | Hook payload reference documentation |

### Files Modified by This Story

| File | Task | Change |
|------|------|--------|
| `src/install.sh` | 9 | Add gc-hook and gc-install-hooks deployment steps |
| `~/.claude/settings.json` | 5 (at runtime) | Hooks section added/merged by gc-install-hooks |

### Files Deployed at Runtime

| Deployed Path | Source | Permissions |
|---------------|--------|-------------|
| `~/.claude-context/bin/gc-hook` | `src/gc-hook` | `755` |
| `~/.claude-context/bin/gc-install-hooks` | `src/gc-install-hooks` | `755` |
| `~/.claude-context/bin/gc-uninstall` | `src/bin/gc-uninstall` | `755` |
| `~/.claude-context/lib/debug_log.sh` | `src/lib/debug_log.sh` | `644` |

---

## Acceptance Criteria Traceability

This table maps each acceptance criterion from the story to the task that implements it.

| AC | Task | Description |
|----|------|-------------|
| AC-1.1 | 5 | Installer reads and preserves existing settings.json |
| AC-1.2 | 5 | Installer creates settings.json if missing |
| AC-1.3 | 5 | Installer creates ~/.claude/ with mode 0700 if missing |
| AC-1.4 | 5 | Timestamped backup before modification |
| AC-1.5 | 5 | All 10 hook events registered |
| AC-1.6 | 5 | Valid JSON with 2-space indentation |
| AC-1.7 | 5 | Commands use tilde path |
| AC-2.1 | 4, 5 | All 10 event mappings correct |
| AC-2.2 | 1, 9 | gc-hook exists and is executable |
| AC-2.3 | 1 | gc-hook always exits 0 |
| AC-2.4 | 1 | gc-hook passes stdin through |
| AC-2.5 | 1 | gc-hook passes event type argument |
| AC-2.6 | 1 | gc-hook suppresses stderr |
| AC-3.1 | 4, 5 | Sync hooks have async: false |
| AC-3.2 | 4, 5 | Async hooks have async: true |
| AC-3.3 | 1 | Sync hooks complete within timeout |
| AC-3.4 | 10 | Async/sync rationale documented |
| AC-4.1 | 4, 5 | Tool hooks have matcher: ".*" |
| AC-4.2 | 4, 5 | SessionStart has matcher: "" |
| AC-4.3 | 4, 5 | Non-tool hooks omit matcher or use "" |
| AC-4.4 | 4 | No selective matchers |
| AC-5.1 | 4, 5 | All hooks have timeout: 5000 |
| AC-5.2 | 4 | Timeout within bounds |
| AC-5.3 | 5 | Timeout defined as constant |
| AC-6.1 | 1, 2 | gc-hook always exits 0 |
| AC-6.2 | 1, 2 | gc-hook zero stdout |
| AC-6.3 | 1, 2 | gc-hook zero stderr |
| AC-6.4 | 1 | gc-hook no side effects outside ~/.claude-context/ |
| AC-6.5 | 1, 2 | gc-hook handles missing capture-event silently |
| AC-6.6 | 2 | Manual verification test |
| AC-7.1 | 5 | install adds all 10 hooks correctly |
| AC-7.2 | 5, 8 | Idempotent install |
| AC-7.3 | 5, 8 | User hooks preserved |
| AC-7.4 | 5, 8 | Non-hook settings preserved |
| AC-7.5 | 5 | Backup file created |
| AC-7.6 | 6, 8 | Uninstall removes only GC hooks |
| AC-7.7 | 6 | Empty arrays/objects cleaned up |
| AC-7.8 | 5 | Install creates settings.json if missing |
| AC-7.9 | 5 | Install creates ~/.claude/ if missing |
| AC-7.10 | 9 | gc-install-hooks at correct path and executable |
| AC-7.11 | 5 | Uses jq for JSON manipulation |
| AC-8.1 | 5 | Aborts if capture-event missing |
| AC-8.2 | 5 | Aborts if jq missing |
| AC-8.3 | 5 | Aborts on malformed JSON with error message |
| AC-8.4 | 7 | Validate checks all 10 hooks present |
| AC-8.5 | 7 | Validate runs smoke test |
| AC-8.6 | 7 | Smoke test cleans up |
| AC-8.7 | 5, 6, 7 | Human-readable error messages on stderr |
| AC-9.1 | 5 | Upgrade updates outdated hooks |
| AC-9.2 | 5, 8 | No duplicate GC hooks after upgrade |
| AC-9.3 | 5, 8 | User hooks untouched during upgrade |
| AC-9.4 | 5 | Obsolete hooks removed |
| AC-9.5 | 5 | Backup before upgrade |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| jq not installed on target system | Medium | High (install fails) | Clear error message with platform-specific install instructions |
| User has complex existing settings.json | Medium | Medium (merge bug) | Thorough integration tests with diverse existing configs |
| Claude Code changes hook payload format | Low | Low (we store as-is) | Document that payloads are Claude Code's contract |
| Concurrent gc-install-hooks runs | Very Low | Low (last writer wins) | Backups preserve previous state; documented edge case |
| Home directory path contains spaces | Low | Medium (command parsing) | Tilde path in hook commands avoids expansion issues |

---

## Definition of Done

- [ ] `gc-hook` wrapper script passes all unit tests (Task 2)
- [ ] `gc-install-hooks install` correctly merges hooks into settings.json
- [ ] `gc-install-hooks uninstall` cleanly removes only GC hooks
- [ ] `gc-install-hooks validate` detects missing/incorrect hooks and runs smoke test
- [ ] `CLAUDE_CONTEXT_PATH` env var is respected by both scripts
- [ ] All integration tests pass (Task 8)
- [ ] Hook payload structures are documented (Task 10)
- [ ] Scripts are deployed via installer (Task 9)
- [ ] No stdout output from gc-hook under any condition
- [ ] gc-hook always exits 0 under any condition
- [ ] Idempotent: running install multiple times produces same result
- [ ] User hooks and non-hook settings are never modified or removed
- [ ] Debug logging writes to log file only when `GC_DEBUG=1` (Task 11)
- [ ] Log rotation at 1MB prevents unbounded growth (Task 11)
- [ ] `gc-uninstall` removes hooks and store with confirmation (Task 12)
- [ ] `gc-uninstall --keep-data` preserves store while removing hooks (Task 12)
- [ ] `gc-uninstall --dry-run` previews changes without modifying anything (Task 12)
