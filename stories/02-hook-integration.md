# Story 02: Hook Integration Layer

## Overview

The Hook Integration Layer is the bridge between Claude Code and GlobalContext. It configures Claude Code's hook system to pipe all lifecycle events into the event capture system. Without this layer, no events flow into the event store -- nothing else in GlobalContext works.

Claude Code exposes a hook system via `~/.claude/settings.json` that allows external scripts to run on specific lifecycle events. Each hook receives a JSON payload on stdin describing the event. This story covers the generation, installation, merging, validation, and maintenance of those hook configurations, as well as the shell wrapper scripts that invoke `capture-event`.

### Relationship to Other Components

- **Depends on**: Story 01 (Event Capture -- the `capture-event` script must exist and be executable)
- **Enables**: All downstream stories (projections, querying, context recovery)
- **Touches**: `~/.claude/settings.json` (shared with user and other tools)

---

## 1. Hook Configuration File

### Description

GlobalContext hooks live in `~/.claude/settings.json` under the `hooks` key. The installation process must read any existing configuration, merge GlobalContext hooks into it without disturbing the user's other settings or hooks, and write the result back.

### Settings File Structure

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "~/.claude-context/bin/gc-hook SessionStarted",
        "async": false,
        "timeout": 5000,
        "matcher": ""
      }
    ],
    "PreToolUse": [
      {
        "type": "command",
        "command": "~/.claude-context/bin/gc-hook ToolCallRequested",
        "async": true,
        "timeout": 5000,
        "matcher": ".*"
      }
    ]
  }
}
```

### Acceptance Criteria

- **AC-1.1**: The installer reads `~/.claude/settings.json` if it exists, parses it, and preserves all existing keys and values outside of GlobalContext hooks.
- **AC-1.2**: If `~/.claude/settings.json` does not exist, the installer creates it with only the GlobalContext hooks section plus an empty object for any required top-level structure.
- **AC-1.3**: If `~/.claude/` directory does not exist, the installer creates it with mode `0700`.
- **AC-1.4**: The installer creates a timestamped backup of the existing `settings.json` at `~/.claude/settings.json.bak.{timestamp}` before any modification.
- **AC-1.5**: All 10 hook events are registered (see Section 2 for the complete mapping).
- **AC-1.6**: The written JSON is valid, properly formatted (2-space indentation), and parseable by `jq` and Node.js `JSON.parse`.
- **AC-1.7**: Hook commands reference `~/.claude-context/bin/gc-hook` using the tilde path (Claude Code expands `~` in hook commands).

---

## 2. Hook Event Mapping

### Description

Each Claude Code hook event maps to exactly one GlobalContext event type. The `gc-hook` wrapper script receives the event type as its first argument and passes stdin through to `capture-event`.

### Complete Mapping Table

| Hook Event           | GlobalContext Event Type | Sync  | Matcher | Rationale |
|----------------------|--------------------------|-------|---------|-----------|
| SessionStart         | SessionStarted           | sync  | ""      | Session boundary; must capture before any other events fire |
| UserPromptSubmit     | UserPromptReceived       | sync  | (none)  | Exact user prompts; must capture before LLM processes them |
| PreToolUse           | ToolCallRequested        | async | ".*"    | High frequency; captures intent before tool runs |
| PostToolUse          | ToolCallCompleted        | async | ".*"    | High frequency; captures results after tool runs |
| PostToolUseFailure   | ToolCallFailed           | async | ".*"    | Error tracking; captures tool failures |
| SubagentStart        | AgentSpawned             | async | ".*"    | Sub-agent lifecycle tracking |
| SubagentStop         | AgentCompleted           | async | ".*"    | Sub-agent result capture |
| Stop                 | TurnCompleted            | async | (none)  | Turn boundary markers |
| PreCompact           | CompactionTriggered      | sync  | (none)  | Critical -- last chance to capture context before loss |
| SessionEnd           | SessionEnded             | async | (none)  | Session lifecycle closure |

### gc-hook Wrapper Script

The `gc-hook` script at `~/.claude-context/bin/gc-hook` is a thin shell wrapper:

```bash
#!/usr/bin/env bash
# GlobalContext hook wrapper v1
# Usage: gc-hook <EventType>
# Reads JSON from stdin, passes to capture-event, always exits 0

EVENT_TYPE="${1:?Missing event type}"

~/.claude-context/bin/capture-event "$EVENT_TYPE" 2>/dev/null

exit 0
```

This wrapper exists to guarantee exit code 0 regardless of what happens in `capture-event`. The `2>/dev/null` suppresses any stderr output that could leak into Claude Code's processing.

### Acceptance Criteria

- **AC-2.1**: All 10 hook events are mapped to their corresponding GlobalContext event types exactly as specified in the table above.
- **AC-2.2**: The `gc-hook` wrapper script exists at `~/.claude-context/bin/gc-hook` and is executable (`chmod +x`).
- **AC-2.3**: The `gc-hook` wrapper always exits with code 0, even if `capture-event` fails, is missing, or times out.
- **AC-2.4**: The `gc-hook` wrapper passes stdin through to `capture-event` without modification.
- **AC-2.5**: The `gc-hook` wrapper passes the event type as the first positional argument to `capture-event`.
- **AC-2.6**: The `gc-hook` wrapper suppresses all stderr output (`2>/dev/null`).

---

## 3. Async vs Sync Strategy

### Description

Claude Code hooks support an `async` flag. When `async: false`, Claude Code waits for the hook to complete before continuing. When `async: true`, the hook runs in the background and Claude Code proceeds immediately.

### Sync Events (async: false)

These three events MUST complete before Claude Code continues:

| Event             | Reason |
|-------------------|--------|
| **SessionStart**      | The session boundary event must be the first event recorded. If it runs async, tool events could arrive before the session is registered, breaking the event ordering guarantee. |
| **UserPromptSubmit**  | The user's exact prompt must be captured before the LLM begins processing. This is the canonical record of user intent. If lost, subsequent tool calls lack context. |
| **PreCompact**        | This is the last chance to capture context before Claude Code compresses the conversation. If this runs async, the compaction may complete before the event is written, and the pre-compaction state is lost forever. This is the single most critical sync point in the system. |

### Async Events (async: true)

These seven events run in the background:

| Event                | Reason |
|----------------------|--------|
| **PreToolUse**           | High frequency. Blocking on every tool call would add measurable latency to the session. The event is observational -- capturing intent, not gating execution. |
| **PostToolUse**          | High frequency. Same rationale as PreToolUse. Results are already committed by the time this fires. |
| **PostToolUseFailure**   | Error tracking is important but not blocking. The failure has already occurred. |
| **SubagentStart**        | Agent spawning should not be delayed by event capture. |
| **SubagentStop**         | Agent completion results are already finalized. |
| **Stop**                 | Turn boundaries are informational markers. |
| **SessionEnd**           | The session is ending -- there is nothing left to gate. Best-effort capture is acceptable. |

### Acceptance Criteria

- **AC-3.1**: SessionStart, UserPromptSubmit, and PreCompact hooks have `"async": false` in the settings configuration.
- **AC-3.2**: PreToolUse, PostToolUse, PostToolUseFailure, SubagentStart, SubagentStop, Stop, and SessionEnd hooks have `"async": true` in the settings configuration.
- **AC-3.3**: Even sync hooks complete within the 5-second timeout under normal conditions (file append should take <100ms).
- **AC-3.4**: The async/sync classification is documented in the generated configuration as inline comments (or in a companion doc) so future maintainers understand the rationale.

---

## 4. Matcher Configuration

### Description

Claude Code hooks support a `matcher` field -- a regex that filters which events trigger the hook. Tool-related hooks use matchers to specify which tools to observe. Non-tool hooks either use an empty string or omit the field.

### Matcher Rules

| Hook Event           | Matcher Value | Explanation |
|----------------------|---------------|-------------|
| SessionStart         | `""`          | No tool filtering; fires on session start |
| UserPromptSubmit     | (omitted)     | Does not support matcher; fires on every user prompt |
| PreToolUse           | `".*"`        | Captures ALL tool invocations without exception |
| PostToolUse          | `".*"`        | Captures ALL tool completions without exception |
| PostToolUseFailure   | `".*"`        | Captures ALL tool failures without exception |
| SubagentStart        | `".*"`        | Captures ALL agent types |
| SubagentStop         | `".*"`        | Captures ALL agent types |
| Stop                 | (omitted)     | Does not support matcher; fires on every turn stop |
| PreCompact           | (omitted)     | Does not support matcher; fires on every compaction |
| SessionEnd           | (omitted)     | Does not support matcher; fires on every session end |

### Why ".*" Instead of Selective Matching

GlobalContext captures everything. Selective tool matching would create blind spots in the event store, making projections incomplete and context recovery unreliable. The append-only event store is cheap (small JSON files), so the cost of capturing all events is negligible compared to the cost of missing one.

### Acceptance Criteria

- **AC-4.1**: PreToolUse, PostToolUse, PostToolUseFailure, SubagentStart, and SubagentStop hooks have `"matcher": ".*"` in their configuration.
- **AC-4.2**: SessionStart has `"matcher": ""` in its configuration.
- **AC-4.3**: UserPromptSubmit, Stop, PreCompact, and SessionEnd hooks either omit the `matcher` field or set it to `""` if the schema requires the field to be present.
- **AC-4.4**: No hook uses a selective matcher that would exclude any tool or agent type.

---

## 5. Timeout Configuration

### Description

Every hook has a `timeout` field specified in milliseconds. This is Claude Code's kill timer -- if the hook process does not exit within this duration, Claude Code terminates it.

### Timeout Value: 5000ms (5 seconds)

All 10 hooks use the same timeout: **5000 milliseconds**.

### Rationale

- The `capture-event` script performs a single operation: read stdin, write a JSON file to disk. Under normal conditions this completes in under 100ms.
- The 5-second timeout provides a 50x safety margin for edge cases: slow disk I/O, flock contention under heavy parallel tool use, or filesystem hiccups.
- A timeout shorter than 1 second risks false kills under I/O pressure.
- A timeout longer than 10 seconds would risk blocking the session unacceptably for sync hooks (SessionStart, UserPromptSubmit, PreCompact).
- 5 seconds is the sweet spot: safe for sync hooks, generous for async hooks, and short enough that a truly stuck process gets cleaned up promptly.

### Acceptance Criteria

- **AC-5.1**: All 10 hooks have `"timeout": 5000` in their configuration.
- **AC-5.2**: No hook has a timeout greater than 10000ms or less than 1000ms.
- **AC-5.3**: The timeout value is defined as a constant in the installation script (not hardcoded in 10 places) so it can be adjusted in one place if needed.

---

## 6. Non-Blocking Guarantee

### Description

GlobalContext hooks are pure observers. They must never influence Claude Code's behavior, alter tool execution, block user interaction, or produce output that Claude Code interprets as a directive.

### Rules

1. **Always exit 0**: The `gc-hook` wrapper script unconditionally exits with code 0. A non-zero exit code from a sync hook could cause Claude Code to abort or retry the operation.

2. **Never produce stdout JSON**: Claude Code hooks can return JSON on stdout to influence behavior (e.g., `{"decision": "block"}` on PreToolUse to prevent a tool from running). GlobalContext hooks must NEVER produce any stdout output. The `gc-hook` wrapper ensures this by not echoing anything.

3. **Suppress stderr**: Any error messages from `capture-event` are redirected to `/dev/null` in the wrapper. Leaked stderr could appear in Claude Code's output or logs.

4. **No side effects on the session**: Hooks must not modify files in the working directory, alter environment variables visible to Claude Code, or create lock files that could interfere with other processes.

5. **Graceful failure**: If `capture-event` is missing, not executable, or crashes, the wrapper absorbs the failure silently. The user's Claude Code session is unaffected. Event loss is acceptable; session disruption is not.

### gc-hook Wrapper Guarantees

```bash
#!/usr/bin/env bash
# GlobalContext hook wrapper v1
EVENT_TYPE="${1:?Missing event type}"

# Capture event in a subshell to isolate all side effects
# - stdout is suppressed (no output to Claude Code)
# - stderr is suppressed (no error leaks)
# - exit code is ignored (always exit 0)
(~/.claude-context/bin/capture-event "$EVENT_TYPE" </dev/stdin >/dev/null 2>/dev/null) || true

exit 0
```

### Acceptance Criteria

- **AC-6.1**: The `gc-hook` wrapper script always exits with code 0 under all conditions: missing `capture-event`, `capture-event` crash, `capture-event` timeout, invalid stdin, empty stdin.
- **AC-6.2**: The `gc-hook` wrapper produces zero bytes on stdout under all conditions.
- **AC-6.3**: The `gc-hook` wrapper produces zero bytes on stderr under all conditions.
- **AC-6.4**: The `gc-hook` wrapper does not modify any files outside of `~/.claude-context/`.
- **AC-6.5**: If `capture-event` is missing or not executable, the wrapper exits 0 silently within 1ms (no hang waiting for a missing process).
- **AC-6.6**: Manual verification: running `echo '{}' | gc-hook TestEvent` produces no output and returns exit code 0.

---

## 7. Installation Script

### Description

The installation script (`gc-install-hooks`) manages the lifecycle of GlobalContext hooks in `~/.claude/settings.json`. It handles first-time installation, updates, and uninstallation. It is the only component that writes to `settings.json`.

### Installation Flow

```
gc-install-hooks install
  1. Verify prerequisites (capture-event exists, ~/.claude/ exists)
  2. Read existing ~/.claude/settings.json (or start with {})
  3. Backup existing file to ~/.claude/settings.json.bak.{YYYYMMDD-HHMMSS}
  4. Parse existing JSON
  5. If "hooks" key missing, create it as empty object
  6. For each of the 10 hook events:
     a. If event key missing in hooks, create it as empty array
     b. Check if a GlobalContext hook already exists in the array
        (identified by command containing "gc-hook")
     c. If exists: update it in-place with current config
     d. If not exists: append to the array
  7. Write merged JSON back to settings.json
  8. Validate written file is parseable
  9. Print summary of changes
```

### Uninstallation Flow

```
gc-install-hooks uninstall
  1. Read existing ~/.claude/settings.json
  2. Backup existing file
  3. For each hook event in "hooks":
     a. Filter out entries where command contains "gc-hook"
     b. If array is now empty, remove the event key
  4. If "hooks" object is now empty, remove the "hooks" key
  5. Write cleaned JSON back to settings.json
  6. Print summary of removals
```

### Identification Strategy

GlobalContext hooks are identified by the presence of `gc-hook` in the `command` field. This is the sole marker used to distinguish GlobalContext hooks from user-defined hooks. The installation script never touches hook entries that do not contain `gc-hook` in their command.

### Acceptance Criteria

- **AC-7.1**: `gc-install-hooks install` adds all 10 hooks to `~/.claude/settings.json` with correct event types, async flags, matchers, and timeouts.
- **AC-7.2**: Running `gc-install-hooks install` twice produces the same result as running it once (idempotent). No duplicate hooks are created.
- **AC-7.3**: Existing user hooks (hooks whose command does not contain `gc-hook`) are preserved exactly as-is after install and uninstall.
- **AC-7.4**: Existing non-hook settings in `settings.json` (e.g., `"model"`, `"permissions"`, custom keys) are preserved exactly as-is.
- **AC-7.5**: A backup file is created at `~/.claude/settings.json.bak.{timestamp}` before every modification.
- **AC-7.6**: `gc-install-hooks uninstall` removes all and only GlobalContext hooks, leaving user hooks and other settings intact.
- **AC-7.7**: After uninstall, if a hook event array is empty, the event key is removed from `hooks`. If `hooks` is empty, the `hooks` key is removed.
- **AC-7.8**: If `~/.claude/settings.json` does not exist, `gc-install-hooks install` creates it.
- **AC-7.9**: If `~/.claude/` does not exist, `gc-install-hooks install` creates it with mode `0700`.
- **AC-7.10**: The installation script is located at `~/.claude-context/bin/gc-install-hooks` and is executable.
- **AC-7.11**: The installation script uses `jq` for JSON manipulation (available on most systems, explicit dependency).

---

## 8. Hook Validation

### Description

Before installing hooks, and optionally on-demand, the system validates that the hook infrastructure is functional. This catches configuration errors early rather than silently losing events.

### Pre-Installation Checks

| Check | Action on Failure |
|-------|-------------------|
| `~/.claude-context/bin/capture-event` exists | Abort install with error message |
| `capture-event` is executable | Abort install with error message |
| `~/.claude/` directory exists or can be created | Abort install with error message |
| `jq` is available on PATH | Abort install with error message |
| `~/.claude/settings.json` is valid JSON (if exists) | Abort install with error message and recovery instructions |

### Post-Installation Validation

After writing the hooks, the installer runs a smoke test:

```bash
gc-install-hooks validate
  1. Parse ~/.claude/settings.json and verify all 10 hooks are present
  2. Verify gc-hook wrapper is executable
  3. Run: echo '{"test": true}' | ~/.claude-context/bin/gc-hook TestValidation
     - Verify exit code is 0
     - Verify no stdout output
  4. Check if a TestValidation event was written to the event store
  5. Clean up the test event
  6. Report pass/fail for each check
```

### Handling Malformed settings.json

If `~/.claude/settings.json` exists but contains malformed JSON:

1. The installer does NOT attempt to fix it.
2. It prints a clear error message: `"ERROR: ~/.claude/settings.json contains invalid JSON. Please fix it manually or delete it to start fresh."`
3. It suggests: `"Run: jq . ~/.claude/settings.json to see the parse error."`
4. It exits with code 1.
5. It does NOT create a backup of a malformed file (the malformed file IS the state to preserve until the user fixes it).

### Acceptance Criteria

- **AC-8.1**: `gc-install-hooks install` aborts with a clear error if `capture-event` does not exist or is not executable.
- **AC-8.2**: `gc-install-hooks install` aborts with a clear error if `jq` is not available on PATH.
- **AC-8.3**: `gc-install-hooks install` aborts with a clear error and recovery instructions if `settings.json` contains malformed JSON.
- **AC-8.4**: `gc-install-hooks validate` verifies all 10 hooks are present in `settings.json` and reports any missing hooks.
- **AC-8.5**: `gc-install-hooks validate` runs a smoke test that sends a test event through `gc-hook` and verifies it reaches the event store.
- **AC-8.6**: The smoke test cleans up after itself (removes test event file).
- **AC-8.7**: All validation errors produce human-readable messages on stderr with actionable remediation steps.

---

## 9. Update/Upgrade Path

### Description

When GlobalContext changes its hook configuration (new event types, different async settings, updated timeouts), the installation script must update existing hooks in-place without duplicating them or losing user hooks.

### Versioning Strategy

Each GlobalContext hook command embeds a version identifier:

```json
{
  "type": "command",
  "command": "~/.claude-context/bin/gc-hook ToolCallCompleted",
  "async": true,
  "timeout": 5000,
  "matcher": ".*"
}
```

Identification is by the `gc-hook` substring in the command field. The event type argument (`ToolCallCompleted`) serves as a secondary identifier to match the hook to its event.

### Upgrade Scenarios

| Scenario | Behavior |
|----------|----------|
| Hook exists with same config | No change (idempotent) |
| Hook exists with outdated timeout | Update timeout in-place |
| Hook exists with changed async flag | Update async in-place |
| Hook exists but new matcher pattern needed | Update matcher in-place |
| New hook event added in future version | Append new hook |
| Hook event removed in future version | Remove obsolete hook |
| User modified a GlobalContext hook manually | Overwrite with canonical config (user customizations of GC hooks are not preserved) |

### Acceptance Criteria

- **AC-9.1**: Running `gc-install-hooks install` on a system with an older version of GlobalContext hooks updates all hooks to the current configuration.
- **AC-9.2**: No duplicate GlobalContext hooks exist after an upgrade (at most one `gc-hook` entry per event array).
- **AC-9.3**: User-defined hooks in the same event arrays are never modified or removed during upgrade.
- **AC-9.4**: If a future version of GlobalContext removes support for a hook event, the upgrade removes the obsolete hook entry.
- **AC-9.5**: The upgrade creates a backup of `settings.json` before making changes (same as fresh install).

---

## 10. Complete Hook Configuration

### Reference Configuration

This is the full `hooks` section that `gc-install-hooks` produces when installed into an empty `settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "~/.claude-context/bin/gc-hook SessionStarted",
        "async": false,
        "timeout": 5000,
        "matcher": ""
      }
    ],
    "UserPromptSubmit": [
      {
        "type": "command",
        "command": "~/.claude-context/bin/gc-hook UserPromptReceived",
        "async": false,
        "timeout": 5000
      }
    ],
    "PreToolUse": [
      {
        "type": "command",
        "command": "~/.claude-context/bin/gc-hook ToolCallRequested",
        "async": true,
        "timeout": 5000,
        "matcher": ".*"
      }
    ],
    "PostToolUse": [
      {
        "type": "command",
        "command": "~/.claude-context/bin/gc-hook ToolCallCompleted",
        "async": true,
        "timeout": 5000,
        "matcher": ".*"
      }
    ],
    "PostToolUseFailure": [
      {
        "type": "command",
        "command": "~/.claude-context/bin/gc-hook ToolCallFailed",
        "async": true,
        "timeout": 5000,
        "matcher": ".*"
      }
    ],
    "SubagentStart": [
      {
        "type": "command",
        "command": "~/.claude-context/bin/gc-hook AgentSpawned",
        "async": true,
        "timeout": 5000,
        "matcher": ".*"
      }
    ],
    "SubagentStop": [
      {
        "type": "command",
        "command": "~/.claude-context/bin/gc-hook AgentCompleted",
        "async": true,
        "timeout": 5000,
        "matcher": ".*"
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "~/.claude-context/bin/gc-hook TurnCompleted",
        "async": true,
        "timeout": 5000
      }
    ],
    "PreCompact": [
      {
        "type": "command",
        "command": "~/.claude-context/bin/gc-hook CompactionTriggered",
        "async": false,
        "timeout": 5000
      }
    ],
    "SessionEnd": [
      {
        "type": "command",
        "command": "~/.claude-context/bin/gc-hook SessionEnded",
        "async": true,
        "timeout": 5000
      }
    ]
  }
}
```

---

## Edge Cases

### E-1: User Already Has Hooks for the Same Events

**Scenario**: The user has a custom hook on `PreToolUse` that logs to their own system.

**Behavior**: GlobalContext appends its hook to the existing array. Both hooks run in parallel (Claude Code fires all matching hooks). The user's hook is never modified or removed.

**Example -- before install**:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "type": "command",
        "command": "/home/user/my-logger.sh",
        "async": true,
        "timeout": 3000,
        "matcher": "Bash"
      }
    ]
  }
}
```

**Example -- after install**:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "type": "command",
        "command": "/home/user/my-logger.sh",
        "async": true,
        "timeout": 3000,
        "matcher": "Bash"
      },
      {
        "type": "command",
        "command": "~/.claude-context/bin/gc-hook ToolCallRequested",
        "async": true,
        "timeout": 5000,
        "matcher": ".*"
      }
    ]
  }
}
```

### E-2: settings.json Does Not Exist

**Behavior**: The installer creates `~/.claude/settings.json` with only the GlobalContext hooks. No backup is created (there is nothing to back up).

### E-3: settings.json Has Malformed JSON

**Behavior**: The installer aborts with a clear error message and does not modify the file. See Section 8 for details.

### E-4: User Hooks Use the Same Matchers

**Behavior**: No conflict. Claude Code runs all matching hooks in parallel. A user hook with `"matcher": ".*"` and a GlobalContext hook with `"matcher": ".*"` both fire on every tool call. They are independent processes.

### E-5: Hook Script Path Contains Spaces

**Behavior**: The `gc-hook` wrapper is at a fixed path (`~/.claude-context/bin/gc-hook`) that does not contain spaces. If a user's home directory contains spaces (rare on Linux, possible on macOS), the tilde expansion in Claude Code handles this. The command string in the hook configuration uses `~` not the expanded path, which avoids space issues.

If the expanded path does contain spaces, Claude Code's hook executor must handle this. This is outside GlobalContext's control. The mitigation is documented: if tilde expansion fails due to spaces, the user should symlink `~/.claude-context` to a space-free path.

### E-6: capture-event Is Slow or Hangs

**Behavior**: The 5-second timeout in the hook configuration causes Claude Code to kill the hook process. For async hooks, this is invisible to the user. For sync hooks (SessionStart, UserPromptSubmit, PreCompact), the user experiences up to a 5-second delay, then Claude Code continues normally. The event may be lost, but the session is not broken.

### E-7: Concurrent Installation

**Behavior**: If two processes run `gc-install-hooks install` simultaneously, the last writer wins. Both create backups, so no data is permanently lost. This is an unlikely edge case (manual install is a one-time operation) and does not warrant file locking complexity.

### E-8: Reinstall After Partial Failure

**Behavior**: If the installer crashes mid-write and leaves a corrupt `settings.json`, the backup file preserves the previous state. The user can restore from backup: `cp ~/.claude/settings.json.bak.{timestamp} ~/.claude/settings.json`. The installer will then detect malformed JSON on the next run and guide the user to fix it.

---

## Non-Goals

This story explicitly does NOT cover:

- **The `capture-event` script itself** -- that is Story 01 (Event Capture). This story assumes it exists and is executable.
- **Projections or read models** -- those are downstream stories that consume events from the store.
- **Querying or context recovery** -- those are downstream stories that read projections.
- **The event envelope schema** -- that is defined in Story 01 and the architecture doc.
- **Hook payload schemas** -- the JSON that Claude Code sends on stdin is defined by Claude Code, not by GlobalContext. We capture it as-is.
- **Performance optimization of capture** -- the hook layer's job is to invoke `capture-event` and get out of the way. Capture performance is Story 01's concern.

---

## Technical Specifications

### File Locations

| File | Path | Purpose |
|------|------|---------|
| Hook wrapper | `~/.claude-context/bin/gc-hook` | Thin shell script that invokes capture-event |
| Installer | `~/.claude-context/bin/gc-install-hooks` | Manages hook lifecycle in settings.json |
| Settings file | `~/.claude/settings.json` | Claude Code configuration (shared) |
| Backup files | `~/.claude/settings.json.bak.{timestamp}` | Pre-modification backups |

### Dependencies

| Dependency | Required By | Fallback |
|------------|-------------|----------|
| `bash` | gc-hook, gc-install-hooks | None (hard requirement) |
| `jq` | gc-install-hooks | None (hard requirement, checked at install time) |
| `capture-event` | gc-hook | Silent failure (exit 0) |

### Exit Codes

| Script | Exit Code | Meaning |
|--------|-----------|---------|
| gc-hook | 0 | Always (success or failure) |
| gc-install-hooks install | 0 | Hooks installed/updated successfully |
| gc-install-hooks install | 1 | Prerequisites not met (missing capture-event, bad JSON, no jq) |
| gc-install-hooks uninstall | 0 | Hooks removed successfully |
| gc-install-hooks uninstall | 1 | settings.json not found or not parseable |
| gc-install-hooks validate | 0 | All checks passed |
| gc-install-hooks validate | 1 | One or more checks failed |

---

## Testing Plan

### Unit Tests

| Test | Description |
|------|-------------|
| T-1 | gc-hook exits 0 when capture-event is missing |
| T-2 | gc-hook exits 0 when capture-event crashes |
| T-3 | gc-hook produces no stdout |
| T-4 | gc-hook produces no stderr |
| T-5 | gc-hook passes stdin through to capture-event |
| T-6 | gc-hook passes event type argument correctly |

### Integration Tests

| Test | Description |
|------|-------------|
| T-7 | Install into empty settings.json creates correct config |
| T-8 | Install into settings.json with existing hooks preserves them |
| T-9 | Install into settings.json with existing non-hook settings preserves them |
| T-10 | Reinstall does not duplicate hooks (idempotency) |
| T-11 | Uninstall removes only GlobalContext hooks |
| T-12 | Uninstall cleans up empty hook arrays and empty hooks object |
| T-13 | Install creates backup file |
| T-14 | Install creates ~/.claude/ directory if missing |
| T-15 | Install aborts on malformed JSON with clear error |
| T-16 | Install aborts if capture-event is missing |
| T-17 | Install aborts if jq is missing |
| T-18 | Validate detects missing hooks |
| T-19 | Validate smoke test writes and cleans up test event |
| T-20 | Upgrade from older config updates hooks in-place |

### Manual Verification

| Test | Description |
|------|-------------|
| M-1 | Install hooks, start a Claude Code session, verify SessionStarted event appears in event store |
| M-2 | Send a prompt, verify UserPromptReceived event appears |
| M-3 | Trigger a tool call, verify ToolCallRequested and ToolCallCompleted events appear |
| M-4 | Trigger compaction, verify CompactionTriggered event appears |
| M-5 | End session, verify SessionEnded event appears |
| M-6 | Verify no visible impact on Claude Code session performance or behavior |

---

## Implementation Notes

1. **jq is the JSON manipulation tool**: Do not attempt to manipulate JSON with `sed`, `awk`, or string concatenation. Use `jq` for all reads, merges, and writes. It handles escaping, formatting, and edge cases correctly.

2. **Tilde in command paths**: Use `~/.claude-context/bin/gc-hook` (with tilde) in the hook command, not an expanded absolute path. Claude Code handles tilde expansion, and this makes the config portable across users.

3. **Backup naming**: Use `settings.json.bak.YYYYMMDD-HHMMSS` format. This sorts chronologically by filename and avoids overwriting previous backups within the same second.

4. **gc-hook stdin handling**: The wrapper must pass stdin from Claude Code directly to `capture-event`. Use piping or redirection, not variable capture -- the payload can be large (PostToolUse includes full tool output) and must not be truncated by shell variable limits.

5. **Subshell isolation**: Run `capture-event` in a subshell `( ... )` within `gc-hook` to isolate any environment side effects (directory changes, signal handlers, traps) from the hook executor.

6. **No cleanup of old backups**: The installer does not delete old backup files. They are small (a few KB each) and serve as an audit trail. Users can clean them up manually if desired.
