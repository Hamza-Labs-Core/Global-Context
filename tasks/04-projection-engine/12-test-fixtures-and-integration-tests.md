# Task 12: Test Fixtures and Integration Tests

**Story**: 04-projection-engine
**Estimated Complexity**: L (6-10 hours)
**Status**: Pending

---

## Description

Create the test fixture data and integration test suite that validates the entire projection engine end-to-end. This includes fixture event files for a standard test session, an empty session, and a session with corrupt data. Integration tests run the `project` CLI against these fixtures and verify output schemas, content accuracy, format correctness, incremental rebuild equivalence, and edge case handling.

---

## Files to Create

| File | Purpose |
|------|---------|
| `/home/meywd/GlobalContext/test/fixtures/sessions/test-session-001/000001.json` through `000014.json` | Standard 14-event test session covering all event types |
| `/home/meywd/GlobalContext/test/fixtures/sessions/test-session-empty/` | Empty session directory |
| `/home/meywd/GlobalContext/test/fixtures/sessions/test-session-corrupt/000001.json` | Valid SessionStarted |
| `/home/meywd/GlobalContext/test/fixtures/sessions/test-session-corrupt/000002.json` | Corrupt JSON |
| `/home/meywd/GlobalContext/test/fixtures/sessions/test-session-corrupt/000003.json` | Valid UserPromptReceived |
| `/home/meywd/GlobalContext/test/fixtures/sessions/test-session-duplicate/` | Session with duplicate `tool_use_id` events (for G-1 testing) |
| `/home/meywd/GlobalContext/test/fixtures/sessions/test-session-glob-grep/` | Session with Glob/Grep tool calls that have matched files in `tool_response` (for G-2 testing) |
| `/home/meywd/GlobalContext/test/test-projections.js` | Integration test runner |

---

## Specification / Implementation Details

### Fixture Event Data (test-session-001)

| Sequence | Event Type | Key Data |
|----------|------------|----------|
| 1 | SessionStarted | model: claude-opus-4-6, cwd: /home/user/project |
| 2 | UserPromptReceived | "Fix the failing test in auth.test.js" |
| 3 | ToolCallRequested | Read, file_path: /home/user/project/auth.test.js, tool_use_id: "tu_001" |
| 4 | ToolCallCompleted | Read result, 45 lines, tool_use_id: "tu_001" |
| 5 | ToolCallRequested | Edit, file_path: /home/user/project/auth.test.js, tool_use_id: "tu_002" |
| 6 | ToolCallCompleted | Edit success, tool_use_id: "tu_002" |
| 7 | ToolCallRequested | Bash, command: "npm test", tool_use_id: "tu_003" |
| 8 | ToolCallCompleted | Bash, exit_code: 0, stdout: "All 12 tests passed", tool_use_id: "tu_003" |
| 9 | TurnCompleted | |
| 10 | UserPromptReceived | "Now search for any other expiry-related tests" |
| 11 | ToolCallRequested | Grep, pattern: "expiry", path: /home/user/project, tool_use_id: "tu_004" |
| 12 | ToolCallCompleted | Grep, 3 matches in 2 files, tool_use_id: "tu_004" |
| 13 | TurnCompleted | |
| 14 | SessionEnded | |

### Fixture: test-session-empty

Empty directory (no event files). Used to verify all projections produce valid empty output.

### Fixture: test-session-corrupt

- `000001.json` -- Valid SessionStarted
- `000002.json` -- Corrupt JSON (e.g., `{invalid`)
- `000003.json` -- Valid UserPromptReceived

### Fixture: test-session-duplicate

Session with duplicate `tool_use_id` events for G-1 testing. Two events with the same `tool_use_id` and `event_type` should result in only the first being processed.

### Fixture: test-session-glob-grep

Session with Glob/Grep tool calls that have matched files in `tool_response` for G-2 testing. Verifies that file paths from `tool_response` are recorded in files-touched.

### Test Cases

1. **Schema validation**: Each projection output has all required fields from the documented schema.
2. **Timeline accuracy**: 14 entries, correct summaries, correct order.
3. **Files Touched accuracy**: auth.test.js has read + edit operations; grep results include matched files.
4. **Decisions accuracy**: 2 groups; first group has 3 actions (Read, Edit, Bash); second group has 1 action (Grep).
5. **Summary accuracy**: event_count=14, tools_used includes Read, Edit, Bash, Grep.
6. **Context accuracy**: 2 prompts, tool calls paired, last_state reflects last tool call.
7. **Empty session**: All projections produce valid empty output, exit code 0.
8. **Corrupt session**: Corrupt event skipped with warning, valid events processed.
9. **Duplicate events (G-1)**: Duplicate `tool_use_id` events are deduplicated; only one is processed.
10. **Glob/Grep response extraction (G-2)**: Files from `tool_response` are recorded in files-touched.
11. **Format outputs**: JSON, text, and markdown validated for each projection type.
12. **Incremental rebuild**: Build projection, add 2 events, rebuild incrementally, compare with full rebuild.
13. **Range filtering**: `--from 5 --to 10` produces only events 5-10.
14. **CLAUDE_CONTEXT_PATH**: Setting the env var changes the base path for all operations.
15. **Version mismatch**: Modify `_projection_version` in a saved projection; verify auto-rebuild.
16. **Performance**: 1,000-event session processed in under 2 seconds.

### Test Runner Requirements

- Tests can be run with `node test/test-projections.js` (no npm dependencies).
- Tests report pass/fail with clear messages.

---

## Dependencies

All previous tasks:

- Task 01: Base Path Resolution and Shared Utilities (`/home/meywd/GlobalContext/tasks/04-projection-engine/01-base-path-resolution-and-shared-utilities.md`)
- Task 02: Projection Registry (`/home/meywd/GlobalContext/tasks/04-projection-engine/02-projection-registry.md`)
- Task 03: Event Replay Engine (`/home/meywd/GlobalContext/tasks/04-projection-engine/03-event-replay-engine.md`)
- Task 04: Files Touched Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/04-files-touched-projection-handler.md`)
- Task 05: Timeline Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/05-timeline-projection-handler.md`)
- Task 06: Decisions Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/06-decisions-projection-handler.md`)
- Task 07: Summary Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/07-summary-projection-handler.md`)
- Task 08: Context Snapshot Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/08-context-snapshot-projection-handler.md`)
- Task 09: Output Format System and Shared Formatters (`/home/meywd/GlobalContext/tasks/04-projection-engine/09-output-format-system-and-shared-formatters.md`)
- Task 10: Incremental Rebuild Logic (`/home/meywd/GlobalContext/tasks/04-projection-engine/10-incremental-rebuild-logic.md`)
- Task 11: CLI Entry Point (`/home/meywd/GlobalContext/tasks/04-projection-engine/11-cli-entry-point.md`)

---

## Acceptance Tests

- All 16 test cases pass.
- Fixture data files are valid JSON with correct event envelope schema.
- Tests can be run with `node test/test-projections.js` (no npm dependencies).
- Tests report pass/fail with clear messages.
