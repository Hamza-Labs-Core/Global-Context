# Task 12: Integration Test Suite

**Story**: 01-event-capture
**Estimated Complexity**: L (Large)
**Status**: Pending

---

## Description

Create a comprehensive test script that validates all acceptance criteria from Story 01. This script should be runnable as a standalone Bash script and report pass/fail for each test case.

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/tests/01-event-capture-test.sh` | Create integration test suite |

---

## Specification/Implementation Details

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

---

## Dependencies

- [Task 09: Main Script Assembly](/home/meywd/GlobalContext/tasks/01-event-capture/09-main-script-assembly.md) -- complete script needed.
- [Task 10: Error Handling and Safety](/home/meywd/GlobalContext/tasks/01-event-capture/10-error-handling-and-safety.md) -- error handling must be in place.
- [Task 02: Directory Structure and install.sh](/home/meywd/GlobalContext/tasks/01-event-capture/02-directory-structure-and-install.md) -- install.sh needed for test 18.

---

## Acceptance Tests

1. Run `bash tests/01-event-capture-test.sh`. All 18 test cases pass.
2. Run on a clean system (no prior install). All tests pass (test script runs install.sh first).
3. Run with `CLAUDE_CONTEXT_PATH=/tmp/gc-test-run`. Verify all events are written to that path and the default `~/.claude-context` is untouched.
