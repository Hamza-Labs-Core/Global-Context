# Task 02: Create `gc-hook` Unit Test Suite

**Story**: 02-hook-integration
**Status**: Pending
**Estimated Complexity**: S (Small) -- test harness with temp directories and mock scripts

---

## Description

Write automated tests for all `gc-hook` guarantees: exit code, stdout silence, stderr silence, stdin passthrough, argument forwarding, and graceful failure when `capture-event` is missing, crashes, or times out.

---

## Files to Create

| File | Purpose |
|------|---------|
| `tests/02-gc-hook-tests.sh` | Executable test script |

---

## Specification / Implementation Details

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

---

## Dependencies

- [Task 01: gc-hook wrapper](/home/meywd/GlobalContext/tasks/02-hook-integration/01-gc-hook-wrapper.md) -- gc-hook script must exist

---

## Acceptance Tests

Run `bash tests/02-gc-hook-tests.sh` and all 8 tests pass with zero failures.
