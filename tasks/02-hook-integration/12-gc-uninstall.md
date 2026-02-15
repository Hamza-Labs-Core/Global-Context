# Task 12: Create gc-uninstall Command (Review Fix G-5)

**Story**: 02-hook-integration
**Status**: Pending
**Estimated Complexity**: S (Small) -- delegates hook removal to existing script, then rm -rf with safety checks

---

## Description

Create a `gc-uninstall` command that performs a full system teardown: removes hooks from `settings.json`, optionally deletes the entire `~/.claude-context/` store, and prints a summary. This addresses **review issue G-5**: full system uninstall is not defined.

---

## Files to Create

| File | Purpose |
|------|---------|
| `src/bin/gc-uninstall` | Full uninstall script |
| `tests/02-uninstall-tests.sh` | Uninstall tests |

---

## Specification / Implementation Details

### Invocation

```bash
gc-uninstall [--keep-data] [--force] [--dry-run]
```

### Flags

| Flag | Description |
|------|-------------|
| `--keep-data` | Remove hooks from settings.json but preserve `~/.claude-context/` data |
| `--force` | Skip confirmation prompt (for scripted use) |
| `--dry-run` | Print what would be removed without making changes |

### Uninstall Flow

```
gc-uninstall
  1. Source paths.sh to resolve GC_BASE
  2. Print: "GlobalContext Uninstall"
  3. Print: "Store location: $GC_BASE"
  4. If not --force and not --dry-run:
     a. Print: "This will remove all GlobalContext hooks and data."
     b. Read confirmation: "Type 'yes' to confirm: "
     c. If input != "yes": abort
  5. If --dry-run:
     a. Print what would be removed (hooks, store directory, files count, size)
     b. Exit 0
  6. Step 1 -- Remove hooks from settings.json:
     a. Run: gc-install-hooks uninstall
     b. If fails: warn but continue
  7. Step 2 -- Remove store (unless --keep-data):
     a. Count files and compute size for summary
     b. rm -rf "$GC_BASE"
  8. Print summary:
     a. "Hooks removed from ~/.claude/settings.json"
     b. "Store deleted: $GC_BASE (N files, X MB)" or "Store preserved (--keep-data)"
  9. Exit 0
```

### Safety Considerations

- Confirmation prompt by default (no accidental deletions).
- `--keep-data` allows removing hooks while preserving event history for later analysis.
- `--dry-run` for previewing what would happen.
- The script does NOT modify `~/.claude/settings.json` directly -- it delegates to `gc-install-hooks uninstall` (Task 6) for that.
- The script does NOT remove itself from `$GC_BASE/bin/` until the very end (it's running from there).

---

## Dependencies

- [Task 01: gc-hook wrapper](/home/meywd/GlobalContext/tasks/02-hook-integration/01-gc-hook-wrapper.md) -- gc-hook, for path resolution
- [Task 06: gc-install-hooks uninstall](/home/meywd/GlobalContext/tasks/02-hook-integration/06-gc-install-hooks-uninstall.md) -- gc-install-hooks uninstall, for hook removal

---

## Acceptance Tests

1. Full uninstall with confirmation -- hooks removed, store deleted, summary printed.
2. `--keep-data` -- hooks removed, store directory still exists with all data.
3. `--force` -- no confirmation prompt, uninstall proceeds.
4. `--dry-run` -- prints what would be removed, nothing actually deleted.
5. Uninstall when hooks are already removed -- no error, continues to store deletion.
6. Uninstall when store does not exist -- no error, prints "store not found".
7. After full uninstall: `~/.claude/settings.json` has no GC hooks, `~/.claude-context/` does not exist.
8. `gc-uninstall --keep-data && gc-install-hooks install` -- reinstall after partial uninstall works.
