# Task 19: gc-query doctor Command (Fix G-3)

**Story**: 05-context-recovery
**Complexity**: M (Medium)
**Status**: Pending

---

## Description

Implement an end-to-end health check command that validates the entire GlobalContext system is functioning correctly.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_doctor` function) |

---

## Specification / Implementation Details

Run the following checks and report pass/fail for each:

1. **Store directory exists**: Check `$GC_ROOT` exists and is a directory.
2. **Store is writable**: Attempt to create and delete a temp file in `$GC_ROOT`.
3. **Required directories exist**: Check `events/`, `projections/`, `bin/`.
4. **config.json exists and is valid**: Parse it with jq, check for required fields.
5. **capture-event is executable**: Check `bin/capture-event` exists and has execute permission.
6. **project is executable**: Check `bin/project` exists and has execute permission.
7. **gc-query is executable**: Check `bin/gc-query` exists (self-check).
8. **Hooks are installed**: Check `~/.claude/settings.json` exists and contains GlobalContext hook entries.
9. **jq is available**: Check `jq --version`.
10. **Disk space**: Check at least 10MB free space.
11. **Per-project latest symlink**: For current project, check if `projections/{project-id}/latest` exists and points to a valid target.
12. **Sample event read**: If any sessions exist, read one event file and verify it parses as valid JSON with all 7 required fields.
13. **Per-session session.json**: Spot-check a sample session's `session.json` is valid JSON.
14. **No stale global files**: Verify no `sessions.json` or `.sessions.lock` exists at store root (leftover from pre-Amendment design).

Output format:
```
GlobalContext Doctor
====================
[PASS] Store directory exists: /home/user/.claude-context
[PASS] Store is writable
[PASS] Required directories exist (events, projections, bin)
[PASS] config.json is valid (version: 1.0.0)
[PASS] capture-event is executable
[PASS] project is executable
[PASS] gc-query is executable
[WARN] Hooks not found in ~/.claude/settings.json
[PASS] jq is available (jq-1.6)
[PASS] Disk space: 2.1GB free
[PASS] Latest symlink (my-project-a3f7b2): -> abc-123
[PASS] Sample event: valid (session abc-123, event 000001.json, 7 fields)
[PASS] Sample session.json: valid (session abc-123, event_count: 142)
[PASS] No stale global files

Result: 13 passed, 1 warning, 0 failed
```

Exit code 0 if all checks pass or only warnings. Exit code 1 if any check fails.

---

## Dependencies

- [Task 03: gc-query Entry Point and Argument Parser](/home/meywd/GlobalContext/tasks/05-context-recovery/03-gc-query-entry-point-and-argument-parser.md) (gc-query entry point)
- [Task 01: Shared Store Path Resolution Helper](/home/meywd/GlobalContext/tasks/05-context-recovery/01-shared-store-path-resolution-helper.md) (store path helper)

---

## Acceptance Tests

1. `gc-query doctor` runs all 14 checks and reports results.
2. On a healthy system, all checks pass and exit code is 0.
3. On a system missing hooks, a warning is shown (not a failure).
4. On a system with a missing `config.json`, a failure is shown and exit code is 1.
5. `gc-query doctor --format json` returns structured results as JSON.
6. `gc-query doctor --fix` attempts to fix issues (e.g., create missing directories).
7. Completes in under 3 seconds.

---

## Estimated Complexity: M
