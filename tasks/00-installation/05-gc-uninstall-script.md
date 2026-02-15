# Task 05: gc-uninstall Script

**Story**: 00-installation-setup
**Status**: Pending
**Estimated Complexity**: M (Medium) -- 2-3 hours

---

## Description

Enhance the `gc-uninstall` command (initially defined in Story 02, Plan 02 Task 12) with the full installation-aware uninstall flow. The enhanced version understands the complete file distribution from Task 03 and provides a `--purge` flag for full data removal.

The key distinction from Story 02's `gc-uninstall`:
- Story 02 focuses on hook removal from `settings.json` and basic store deletion.
- This task adds awareness of `bin/` and `lib/` scripts, the `VERSION` file, and a two-tier removal strategy (soft uninstall vs purge).

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/bin/gc-uninstall` | Create (or enhance from Story 02) | Full uninstall script |
| `tests/bin/test_gc_uninstall.sh` | Create | Uninstall tests |

All file paths are relative to `/home/meywd/GlobalContext/`.

---

## Specification / Implementation Details

### Invocation

```bash
gc-uninstall [--purge] [--force] [--dry-run]
```

| Flag | Description |
|---|---|
| (no flags) | **Soft uninstall**: Remove hooks from `settings.json`, remove `bin/` scripts and `lib/` modules. Preserve `events/`, `projections/`, and `config.json`. |
| `--purge` | **Full uninstall**: Remove everything including event data. Requires confirmation. |
| `--force` | Skip confirmation prompt (for scripted use). |
| `--dry-run` | Print what would be removed without making changes. |

### Uninstall Flow

```
gc-uninstall [--purge] [--force] [--dry-run]
  1.  Parse flags
  2.  Resolve GC_BASE from CLAUDE_CONTEXT_PATH or default
  3.  If GC_BASE does not exist: print "GlobalContext is not installed.", exit 0
  4.  Compute summary stats:
      a. Count event files
      b. Total size of $GC_BASE
      c. Number of sessions
  5.  Print what will be removed:
      a. Always: "Hooks in ~/.claude/settings.json"
      b. Always: "Scripts in $GC_BASE/bin/ and $GC_BASE/lib/"
      c. If --purge: "ALL DATA in $GC_BASE/events/ and $GC_BASE/projections/"
      d. If --purge: "$GC_BASE/config.json"
      e. If not --purge: "Preserved: events/, projections/, config.json"
  6.  If --dry-run: print summary, exit 0
  7.  If --purge and not --force:
      a. Print: "WARNING: This will permanently delete all captured event data."
      b. Print: "  Sessions: N, Events: N, Size: X MB"
      c. Read confirmation: "Type 'yes' to confirm: "
      d. If input != "yes": abort
  8.  Step 1 -- Remove hooks from settings.json:
      a. If $GC_BASE/bin/gc-install-hooks exists: run gc-install-hooks uninstall
      b. Else: attempt jq-based removal directly
      c. If fails: warn but continue
  9.  Step 2 -- Remove scripts:
      a. rm -rf "$GC_BASE/bin/"
      b. rm -rf "$GC_BASE/lib/"
      c. rm -f "$GC_BASE/VERSION"
 10.  Step 3 -- If --purge:
      a. rm -rf "$GC_BASE/events/"
      b. rm -rf "$GC_BASE/projections/"
      c. rm -f "$GC_BASE/config.json"
      d. rm -rf "$GC_BASE/logs/"
      e. rmdir "$GC_BASE" 2>/dev/null  # Remove root if now empty
 11.  Print summary:
      a. "Hooks removed from ~/.claude/settings.json"
      b. "Scripts removed from $GC_BASE/bin/ and lib/"
      c. If --purge: "Data deleted: N sessions, N events, X MB"
      d. If not --purge: "Data preserved at $GC_BASE/ (events/, projections/, config.json)"
      e. If not --purge: "To completely remove all data: gc-uninstall --purge"
 12.  Exit 0
```

---

## Dependencies

- **Task 01** (`/home/meywd/GlobalContext/tasks/00-installation/01-prerequisites-checker.md`) -- for prerequisite awareness.
- **Task 04** (`/home/meywd/GlobalContext/tasks/00-installation/04-hook-registration-automation.md`) -- gc-install-hooks uninstall.

---

## Acceptance Tests

1. Install, then `gc-uninstall` (soft). Verify hooks removed, `bin/` and `lib/` removed, `events/` and `config.json` preserved.
2. Install, write some events, then `gc-uninstall --purge --force`. Verify everything is deleted, `$GC_BASE` does not exist.
3. `gc-uninstall --purge` (without `--force`). Verify confirmation prompt appears. Type "no" -- verify nothing is deleted.
4. `gc-uninstall --dry-run`. Verify nothing is removed but the plan is printed.
5. `gc-uninstall` on a system where GlobalContext is not installed. Verify "not installed" message and exit 0.
6. `gc-uninstall` when `settings.json` has user hooks. Verify only GC hooks are removed.
7. After soft uninstall, `gc-install` can reinstall cleanly using the preserved data.
8. After purge, `gc-install` can perform a fresh install.
