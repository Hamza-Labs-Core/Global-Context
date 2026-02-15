# Task 10: Error Handling and Safety

**Story**: 01-event-capture
**Estimated Complexity**: S (Small)
**Status**: Pending

---

## Description

Add comprehensive error handling to ensure the script never exits non-zero and never produces stdout output, regardless of what goes wrong.

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Add trap, error checks, and logging throughout |

---

## Specification/Implementation Details

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

---

## Dependencies

- [Task 09: Main Script Assembly](/home/meywd/GlobalContext/tasks/01-event-capture/09-main-script-assembly.md) -- main script must exist to add error handling to.

---

## Acceptance Tests

1. Remove `jq` from PATH. Run the script. Verify exit code is 0 and stderr contains `[capture-event] ERROR: jq not found`.
2. Run with no arguments. Verify exit code is 0.
3. Pipe empty string. Verify exit code is 0.
4. Pipe malformed JSON. Verify exit code is 0 and an event file is still written (with `data` as string).
5. Make the events directory read-only. Run the script. Verify exit code is 0 and stderr contains an error message.
6. Verify stdout is empty in all error cases (pipe stdout to a file, check size = 0).
7. Kill the script mid-execution with SIGTERM. Verify it exits 0 (trap handles it).
