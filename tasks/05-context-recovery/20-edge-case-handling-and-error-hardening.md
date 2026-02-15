# Task 20: Edge Case Handling and Error Hardening

**Story**: 05-context-recovery
**Complexity**: M (Medium)
**Status**: Pending

---

## Description

Systematic pass through all implemented commands to ensure edge cases from Story 05 are handled: no sessions, empty sessions, corrupt events, abnormal session endings, large contexts, concurrent access.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add error handling throughout) |
| Modify | `~/.claude-context/lib/context-loader.sh` (add degraded mode) |
| Modify | `~/.claude-context/lib/format-context.sh` (add truncation logic) |

---

## Specification / Implementation Details

1. **No sessions**: All commands that require sessions return exit 3 with "No sessions found."
2. **Empty session**: `gc-query last` returns "Previous session (abc-123) started at [time] but recorded no events."
3. **Corrupt events**: Skip with warning "Warning: Event #42 could not be parsed and was skipped."
4. **Sequence gaps**: Note gaps but continue processing.
5. **Abnormal ending**: Sessions without `SessionEnded` event are handled (ended_at is null, duration computed from last_event_at).
6. **Large context (>200KB)**: Truncate tool results to 200 chars, omit old action details, add truncation note.
7. **Concurrent access**: Event reads are atomic (each file is a complete JSON object). No file locking on reads.
8. **jq not found**: Early check at gc-query entry point with clear error message.

---

## Dependencies

- All previous tasks (this is a hardening pass):
  - [Task 01](/home/meywd/GlobalContext/tasks/05-context-recovery/01-shared-store-path-resolution-helper.md)
  - [Task 02](/home/meywd/GlobalContext/tasks/05-context-recovery/02-per-session-session-json-read-model.md)
  - [Task 03](/home/meywd/GlobalContext/tasks/05-context-recovery/03-gc-query-entry-point-and-argument-parser.md)
  - [Task 04](/home/meywd/GlobalContext/tasks/05-context-recovery/04-projection-staleness-check.md)
  - [Task 05](/home/meywd/GlobalContext/tasks/05-context-recovery/05-session-resolution-helpers.md)
  - [Task 06](/home/meywd/GlobalContext/tasks/05-context-recovery/06-gc-query-status-command.md)
  - [Task 07](/home/meywd/GlobalContext/tasks/05-context-recovery/07-gc-query-events-command.md)
  - [Task 08](/home/meywd/GlobalContext/tasks/05-context-recovery/08-gc-query-tail-command.md)
  - [Task 09](/home/meywd/GlobalContext/tasks/05-context-recovery/09-context-projection-builder-integration.md)
  - [Task 10](/home/meywd/GlobalContext/tasks/05-context-recovery/10-output-formatters.md)
  - [Task 11](/home/meywd/GlobalContext/tasks/05-context-recovery/11-gc-query-last-command.md)
  - [Task 12](/home/meywd/GlobalContext/tasks/05-context-recovery/12-gc-query-session-command.md)
  - [Task 13](/home/meywd/GlobalContext/tasks/05-context-recovery/13-cross-session-chaining.md)
  - [Task 14](/home/meywd/GlobalContext/tasks/05-context-recovery/14-precompact-hook-eager-projection-build.md)
  - [Task 15](/home/meywd/GlobalContext/tasks/05-context-recovery/15-sessionstart-hook-automatic-context-injection.md)
  - [Task 16](/home/meywd/GlobalContext/tasks/05-context-recovery/16-gc-query-sessions-command.md)
  - [Task 17](/home/meywd/GlobalContext/tasks/05-context-recovery/17-gc-query-search-command.md)
  - [Task 18](/home/meywd/GlobalContext/tasks/05-context-recovery/18-gc-query-replay-command.md)
  - [Task 19](/home/meywd/GlobalContext/tasks/05-context-recovery/19-gc-query-doctor-command.md)

---

## Acceptance Tests

1. `gc-query last` with empty store: exit 3, clear message.
2. `gc-query session <id>` for an empty session: returns minimal context.
3. `gc-query replay <id>` with a corrupt event at sequence 5: skips it with warning, continues.
4. `gc-query last` for a session with 500+ events producing >200KB: output is truncated with a note.
5. All commands exit cleanly (no partial stdout) on every error condition.
6. Error messages go to stderr, never to stdout.

---

## Estimated Complexity: M
