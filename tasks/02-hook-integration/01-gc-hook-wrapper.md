# Task 01: Create the `gc-hook` Wrapper Script

**Story**: 02-hook-integration
**Status**: Pending
**Estimated Complexity**: S (Small) -- approximately 15 lines of Bash

---

## Description

Build the thin shell wrapper that Claude Code hook commands invoke. This script receives an event type as its first argument, reads JSON from stdin, passes both to `capture-event`, and guarantees exit code 0 with zero stdout/stderr output regardless of what happens internally. This is the script referenced by every hook command in `settings.json`.

This task directly addresses **review issue C-3**: the `gc-hook` wrapper is owned by Story 02 and must be created here.

---

## Files to Create

| File | Purpose |
|------|---------|
| `src/gc-hook` | Source file for the wrapper script (installed to `~/.claude-context/bin/gc-hook`) |

---

## Specification / Implementation Details

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

---

## Dependencies

- None (first task)

---

## Acceptance Tests

1. Place a mock `capture-event` at `~/.claude-context/bin/capture-event` that writes stdin to a temp file.
2. Run: `echo '{"session_id":"test"}' | src/gc-hook SessionStarted`
3. Verify exit code is 0.
4. Verify stdout is empty (capture with `$()` and assert empty string).
5. Verify stderr is empty (redirect 2>&1 to a file, assert empty).
6. Verify the mock received the JSON and the event type argument.
7. Remove `capture-event`, run `gc-hook` again. Verify exit 0, no output.
8. Make `capture-event` a script that exits 1. Run `gc-hook`. Verify exit 0.
