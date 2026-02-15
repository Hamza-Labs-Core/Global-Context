# Task 08: Create Integration Test Suite

**Story**: 02-hook-integration
**Status**: Pending
**Estimated Complexity**: L (Large) -- many test cases, each requiring setup/teardown of temp directories and mock files

---

## Description

Write automated integration tests that verify the full installation lifecycle: fresh install, idempotent reinstall, upgrade, uninstall, and edge cases (malformed JSON, missing dependencies, existing user hooks).

---

## Files to Create

| File | Purpose |
|------|---------|
| `tests/02-integration-tests.sh` | Executable test script |

---

## Specification / Implementation Details

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

---

## Dependencies

- [Task 01: gc-hook wrapper](/home/meywd/GlobalContext/tasks/02-hook-integration/01-gc-hook-wrapper.md)
- [Task 05: gc-install-hooks install](/home/meywd/GlobalContext/tasks/02-hook-integration/05-gc-install-hooks-install.md)
- [Task 06: gc-install-hooks uninstall](/home/meywd/GlobalContext/tasks/02-hook-integration/06-gc-install-hooks-uninstall.md)
- [Task 07: gc-install-hooks validate](/home/meywd/GlobalContext/tasks/02-hook-integration/07-gc-install-hooks-validate.md)

---

## Acceptance Tests

Run `bash tests/02-integration-tests.sh` and all tests pass. Each test sets up a clean environment, runs the operation, asserts the result, and tears down.
