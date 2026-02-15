# Task 07: Implement `gc-install-hooks` -- Validate Command

**Story**: 02-hook-integration
**Status**: Pending
**Estimated Complexity**: M (Medium) -- JSON inspection, smoke test with cleanup

---

## Description

Add the `validate` subcommand to `gc-install-hooks`. This verifies that all 10 hooks are present in `settings.json`, that `gc-hook` is functional, and runs a smoke test that sends a test event through the full pipeline.

---

## Files to Modify

| File | Change |
|------|--------|
| `src/gc-install-hooks` | Add validate subcommand |

---

## Specification / Implementation Details

### Validate Flow

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

---

## Dependencies

- [Task 05: gc-install-hooks install](/home/meywd/GlobalContext/tasks/02-hook-integration/05-gc-install-hooks-install.md) -- install command
- [Task 01: gc-hook wrapper](/home/meywd/GlobalContext/tasks/02-hook-integration/01-gc-hook-wrapper.md) -- gc-hook must be functional for smoke test
- Story 01 (capture-event must be deployed for the smoke test to write an event)

---

## Acceptance Tests

1. Install hooks, run validate. Verify all checks pass.
2. Manually remove one hook from settings.json. Run validate. Verify it detects the missing hook.
3. Remove gc-hook. Run validate. Verify it reports gc-hook missing.
4. After a passing validate, verify no test artifacts remain in the event store.
