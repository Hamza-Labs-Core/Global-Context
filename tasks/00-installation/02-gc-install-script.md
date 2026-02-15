# Task 02: gc-install Script

**Story**: 00-installation-setup
**Status**: Pending
**Estimated Complexity**: L (Large) -- 4-6 hours

---

## Description

Create the single-entry-point installation script that orchestrates the entire GlobalContext setup. This is the script users run to install or upgrade GlobalContext. It chains together: prerequisites check, source file deployment, `gc-init` (directory structure), hook registration, and first-run verification.

The script must be **idempotent** -- running it again on an already-installed system safely upgrades files without data loss. A `--force` flag overrides version-match skipping to force a full reinstall.

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/bin/gc-install` | Create | Main installer script |
| `tests/bin/test_gc_install.sh` | Create | Installer tests |

All file paths are relative to `/home/meywd/GlobalContext/`.

---

## Specification / Implementation Details

### Invocation

```bash
gc-install [--force] [--skip-hooks] [--dry-run]
```

| Flag | Description |
|---|---|
| `--force` | Overwrite all files even if versions match. Useful for repairing a broken install. |
| `--skip-hooks` | Deploy source files and init store, but do not register hooks in `~/.claude/settings.json`. Useful for development/testing. |
| `--dry-run` | Print what would be done without making changes. |
| (no flags) | Normal install: check prereqs, deploy files, init store, register hooks, verify. |

### Install Flow

```
gc-install [--force] [--skip-hooks] [--dry-run]
  1.  Parse flags
  2.  Resolve GC_BASE from CLAUDE_CONTEXT_PATH or default (~/.claude-context)
  3.  Resolve SRC_DIR (location of source files -- see Task 03)
  4.  Run prerequisites checker (Task 01)
      - If any required prerequisite fails: print report, abort with exit 1
  5.  Print: "Installing GlobalContext to $GC_BASE"
  6.  Check installed version vs available version (Task 06)
      - If versions match and --force not set: print "Already up to date (vX.Y.Z)", exit 0
  7.  Deploy source files to $GC_BASE (Task 03):
      a. Copy bin/ scripts (capture-event, gc-hook, gc-install-hooks, gc-query, project, gc-uninstall, gc-doctor)
      b. Copy lib/ modules (paths.sh, sanitize.sh, atomic_write.sh, etc.)
      c. Set permissions: bin/ scripts get 755, lib/ files get 644
      d. Write VERSION file to $GC_BASE/VERSION
  8.  Run gc-init to create/verify directory structure (delegates to Story 03):
      - $GC_BASE/events/
      - $GC_BASE/projections/
      - $GC_BASE/config.json (created only if missing, preserved on upgrade)
  9.  If not --skip-hooks:
      a. Run gc-install-hooks install (Task 04, delegates to Story 02)
      b. This registers all 10 hooks in ~/.claude/settings.json
 10.  Run first-run verification (Task 07):
      a. gc-doctor checks (quick health check)
      b. Write and read back a test event
 11.  Print install summary:
      - Version installed
      - Files deployed (count)
      - Hooks registered (yes/no)
      - Doctor status (pass/fail)
      - Getting-started instructions
 12.  Exit 0 on success, exit 1 on failure
```

### Idempotency Contract

| Resource | First Install | Repeat Install |
|---|---|---|
| `$GC_BASE/bin/*` scripts | Created | Overwritten (to pick up upgrades) |
| `$GC_BASE/lib/*` modules | Created | Overwritten (to pick up upgrades) |
| `$GC_BASE/VERSION` | Created | Updated |
| `$GC_BASE/config.json` | Created with defaults | Preserved (never overwritten) |
| `$GC_BASE/events/` | Created (mkdir -p) | No-op |
| `$GC_BASE/projections/` | Created (mkdir -p) | No-op |
| `~/.claude/settings.json` hooks | Added | Updated in-place (Story 02 handles idempotency) |
| Event data files | N/A (not touched) | N/A (never touched) |

### Output Format

```
GlobalContext Installer v1.0.0
==============================

Checking prerequisites...
  bash 5.2         ok
  jq 1.7.1         ok
  node 22.1.0      ok
  sha256sum        ok
  flock            ok
  git 2.43.0       ok (optional)
  uuidgen          ok (optional)

Deploying source files to /home/user/.claude-context...
  bin/capture-event       installed
  bin/gc-hook             installed
  bin/gc-install-hooks    installed
  bin/gc-query            installed
  bin/gc-doctor           installed
  bin/gc-uninstall        installed
  lib/ (8 modules)        installed

Initializing store...
  events/                 ok
  projections/            ok
  config.json             ok (preserved existing)

Registering hooks...
  10 hooks registered in ~/.claude/settings.json
  Backup: ~/.claude/settings.json.bak.20260215-143022

Verifying installation...
  Doctor: all checks passed
  Test event: write ok, read ok, cleanup ok

Installation complete!
  Version: 1.0.0
  Store:   /home/user/.claude-context
  Hooks:   registered

To get started:
  Start a Claude Code session -- events will be captured automatically.
  Run: gc-query doctor     -- check system health
  Run: gc-query last       -- view last session context
```

---

## Dependencies

- **Task 01** (`/home/meywd/GlobalContext/tasks/00-installation/01-prerequisites-checker.md`) -- prerequisites checker library.

---

## Acceptance Tests

1. Run `gc-install` on a clean system (no `~/.claude-context/`). Verify all directories, files, hooks, and config are created.
2. Run `gc-install` again. Verify it detects "already up to date" and exits 0 (or upgrades if version differs).
3. Run `gc-install --force`. Verify it overwrites all files even if versions match.
4. Run `gc-install --skip-hooks`. Verify files are deployed but `~/.claude/settings.json` is not modified.
5. Run `gc-install --dry-run`. Verify nothing is created, but the plan is printed.
6. Remove `jq` from PATH. Run `gc-install`. Verify it aborts with a clear error after the prerequisites check.
7. Verify `config.json` is preserved across reinstall (add a custom field, reinstall, verify field persists).
8. Verify event data files are never touched during reinstall.
9. Verify `$GC_BASE` permissions are 700.
10. Run with `CLAUDE_CONTEXT_PATH=/tmp/gc-test`. Verify everything is created under `/tmp/gc-test`.
