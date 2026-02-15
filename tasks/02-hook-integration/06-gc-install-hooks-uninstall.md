# Task 06: Implement `gc-install-hooks` -- Uninstall Command

**Story**: 02-hook-integration
**Status**: Pending
**Estimated Complexity**: M (Medium) -- inverse of install logic, with cleanup of empty structures

---

## Description

Add the `uninstall` subcommand to `gc-install-hooks`. This removes all GlobalContext hooks from `settings.json` while preserving user hooks and other settings.

---

## Files to Modify

| File | Change |
|------|--------|
| `src/gc-install-hooks` | Add uninstall subcommand |

---

## Specification / Implementation Details

### Uninstall Flow

```
gc-install-hooks uninstall
  1. Verify ~/.claude/settings.json exists (abort if not)
  2. Validate it is parseable JSON (abort if malformed)
  3. Create backup
  4. For each hook event key in .hooks:
     a. Filter out entries where .command contains "gc-hook"
     b. If array is now empty, remove the event key
  5. If .hooks is now an empty object, remove the .hooks key
  6. Write cleaned JSON back
  7. Print summary of what was removed
```

---

## Dependencies

- [Task 05: gc-install-hooks install](/home/meywd/GlobalContext/tasks/02-hook-integration/05-gc-install-hooks-install.md) -- install command must exist; uninstall is added to the same script

---

## Acceptance Tests

1. Install hooks, then uninstall. Verify all GC hooks are removed.
2. Verify user hooks survive uninstall.
3. Verify non-hook settings survive uninstall.
4. Verify empty hook arrays are removed.
5. Verify empty `hooks` object is removed.
6. Verify backup was created before uninstall.
7. Run on a file with no hooks. Verify it does not crash (no-op).
