# Implementation Plan: Story 00 -- Installation & Setup

**Date**: 2026-02-15
**Story**: 00-installation-setup
**Status**: Planning
**Estimated Total Effort**: ~4 days (16-24 hours)
**Prerequisites**: All source files from Stories 01-05 must be implementation-ready (not necessarily implemented -- this plan defines the framework that deploys them).
**Design Amendments**: 1, 2, 3, 4. See `docs/DESIGN-AMENDMENTS.md`.

### Relationship to Other Stories

This is the **bootstrapping story**. It produces the entry-point scripts (`gc-install`, `gc-uninstall`, `gc-doctor`) that users interact with directly. It orchestrates the outputs of all other stories:

- **Story 01** (Event Capture): `capture-event` is deployed to `bin/`
- **Story 02** (Hook Integration): `gc-hook`, `gc-install-hooks` are deployed to `bin/`, hooks are registered in `~/.claude/settings.json`
- **Story 03** (Storage Layer): `gc-init` creates directory structure and `config.json`
- **Story 04** (Projection Engine): `project` is deployed to `bin/`
- **Story 05** (Context Recovery): `gc-query` is deployed to `bin/`

### Amendment Impacts on This Plan

- **Amendment 3** (Project-ID layer): `gc-init` creates `events/` and `projections/` without pre-creating project subdirectories (those are created lazily by `capture-event`). The `gc-doctor` health check verifies the project-id directory structure.
- **Amendment 4** (Remove gc-cleanup): No cleanup step in install or uninstall. The `gc-doctor` command reports disk usage as a diagnostic, not an actionable cleanup.

---

## Task Dependency Graph

```
Task 1: Prerequisites Checker
  |
  +---> Task 2: gc-install Script
  |       |
  |       +---> Task 3: Source File Distribution
  |       |       |
  |       |       +---> Task 6: Upgrade Logic (needs 2, 3)
  |       |
  |       +---> Task 4: Hook Registration Automation (needs 2)
  |       |
  |       +---> Task 7: First-Run Verification (needs 2, 4)
  |
  +---> Task 5: gc-uninstall Script (needs 1, 4)
  |
  +---> Task 8: Integration Tests (needs all)
```

---

## Tasks

### Task 1: Prerequisites Checker

**Description**

Create a reusable function library that verifies the system has all required dependencies for GlobalContext. This library is called by both `gc-install` (to gate installation) and `gc-doctor` (to report health). It checks for each prerequisite independently and returns structured results so callers can decide how to proceed.

The checker does not abort on failure -- it reports what is missing and lets the caller decide. This design allows `gc-install` to abort early while `gc-doctor` can report partial health.

**Prerequisites to Check**

| Prerequisite | Required | Check Method | Minimum Version | Fallback Behavior |
|---|---|---|---|---|
| `bash` | Yes | `${BASH_VERSINFO[0]}` | 4+ | Abort (the scripts themselves require bash 4+ for associative arrays) |
| `jq` | Yes | `command -v jq` + `jq --version` | 1.5+ | Abort (JSON manipulation is impossible without jq) |
| `node` | Yes | `command -v node` + `node --version` | 18+ | Abort (projection engine and gc-query require Node.js) |
| `git` | No | `command -v git` | Any | Warn (version tracking via git is optional; project-id derivation works without it) |
| `flock` | No | `command -v flock` | Any | Warn (capture-event falls back to unlocked writes with random suffix) |
| `uuidgen` | No | `command -v uuidgen` | Any | Info (bash-native UUID fallback is used) |
| `sha256sum` or `shasum` | Yes | `command -v sha256sum` or `command -v shasum` | Any | Abort (project-id derivation requires hashing) |

**Result Structure**

The checker populates associative arrays and prints a human-readable summary:

```bash
# Each prerequisite sets:
#   PREREQ_STATUS[name]="ok|missing|outdated|optional_missing"
#   PREREQ_VERSION[name]="detected version string"
#   PREREQ_MESSAGE[name]="human-readable status message"

gc_check_prerequisites()  # populates arrays, returns 0 if all required pass, 1 otherwise
gc_print_prereq_report()  # prints formatted report to stdout
gc_prereq_ok()            # returns 0 if all required prerequisites are met
```

**Version Extraction**

```bash
# bash version: already available as BASH_VERSINFO[0]
# jq version:   jq --version | sed 's/jq-//'     -> "1.7.1"
# node version: node --version | sed 's/^v//'     -> "22.1.0"
# git version:  git --version | awk '{print $3}'  -> "2.43.0"
```

**Error Messages**

Each missing prerequisite produces a specific, actionable message:

| Missing | Message |
|---|---|
| bash 4+ | `ERROR: bash 4+ required (found: X.Y). On macOS: brew install bash` |
| jq | `ERROR: jq is required but not found. Install: sudo apt install jq (Debian/Ubuntu) or brew install jq (macOS)` |
| node 18+ | `ERROR: Node.js 18+ required (found: X.Y). Install from https://nodejs.org/` |
| sha256sum/shasum | `ERROR: sha256sum or shasum required for project-id hashing. Install coreutils.` |
| flock (optional) | `WARN: flock not found. Concurrent event writes will use best-effort mode (no locking).` |
| git (optional) | `INFO: git not found. Version tracking will be limited.` |
| uuidgen (optional) | `INFO: uuidgen not found. Using bash-native UUID generation (slightly weaker entropy).` |

**Files to Create/Modify**

| File | Action | Purpose |
|---|---|---|
| `src/lib/prerequisites.sh` | Create | Prerequisite checker library |
| `tests/lib/test_prerequisites.sh` | Create | Unit tests for prerequisite detection |

**Dependencies**: None (first task).

**Acceptance Test**

1. On a system with all prerequisites met: `gc_check_prerequisites` returns 0, report shows all "ok".
2. Remove `jq` from PATH: `gc_check_prerequisites` returns 1, `PREREQ_STATUS[jq]` is `"missing"`, message includes install instructions.
3. Mock bash version to 3: checker detects "outdated" and reports the specific version found.
4. Mock node version to 16: checker detects "outdated" with `"found: 16"` in the message.
5. Remove `flock` from PATH: checker returns 0 (flock is optional), but `PREREQ_STATUS[flock]` is `"optional_missing"`.
6. Remove `git` from PATH: checker returns 0 (git is optional), report shows INFO message.
7. `gc_print_prereq_report` output is human-readable with aligned columns and clear pass/fail indicators.

**Estimated Complexity**: M (Medium)

---

### Task 2: gc-install Script

**Description**

Create the single-entry-point installation script that orchestrates the entire GlobalContext setup. This is the script users run to install or upgrade GlobalContext. It chains together: prerequisites check, source file deployment, `gc-init` (directory structure), hook registration, and first-run verification.

The script must be **idempotent** -- running it again on an already-installed system safely upgrades files without data loss. A `--force` flag overrides version-match skipping to force a full reinstall.

**Invocation**

```bash
gc-install [--force] [--skip-hooks] [--dry-run]
```

| Flag | Description |
|---|---|
| `--force` | Overwrite all files even if versions match. Useful for repairing a broken install. |
| `--skip-hooks` | Deploy source files and init store, but do not register hooks in `~/.claude/settings.json`. Useful for development/testing. |
| `--dry-run` | Print what would be done without making changes. |
| (no flags) | Normal install: check prereqs, deploy files, init store, register hooks, verify. |

**Install Flow**

```
gc-install [--force] [--skip-hooks] [--dry-run]
  1.  Parse flags
  2.  Resolve GC_BASE from CLAUDE_CONTEXT_PATH or default (~/.claude-context)
  3.  Resolve SRC_DIR (location of source files -- see Task 3)
  4.  Run prerequisites checker (Task 1)
      - If any required prerequisite fails: print report, abort with exit 1
  5.  Print: "Installing GlobalContext to $GC_BASE"
  6.  Check installed version vs available version (Task 6)
      - If versions match and --force not set: print "Already up to date (vX.Y.Z)", exit 0
  7.  Deploy source files to $GC_BASE (Task 3):
      a. Copy bin/ scripts (capture-event, gc-hook, gc-install-hooks, gc-query, project, gc-uninstall, gc-doctor)
      b. Copy lib/ modules (paths.sh, sanitize.sh, atomic_write.sh, etc.)
      c. Set permissions: bin/ scripts get 755, lib/ files get 644
      d. Write VERSION file to $GC_BASE/VERSION
  8.  Run gc-init to create/verify directory structure (delegates to Story 03):
      - $GC_BASE/events/
      - $GC_BASE/projections/
      - $GC_BASE/config.json (created only if missing, preserved on upgrade)
  9.  If not --skip-hooks:
      a. Run gc-install-hooks install (Task 4, delegates to Story 02)
      b. This registers all 10 hooks in ~/.claude/settings.json
 10.  Run first-run verification (Task 7):
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

**Idempotency Contract**

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

**Output Format**

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

**Files to Create/Modify**

| File | Action | Purpose |
|---|---|---|
| `src/bin/gc-install` | Create | Main installer script |
| `tests/bin/test_gc_install.sh` | Create | Installer tests |

**Dependencies**: Task 1 (prerequisites checker).

**Acceptance Test**

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

**Estimated Complexity**: L (Large)

---

### Task 3: Source File Distribution

**Description**

Define how source files are organized in the repository, how they are located by `gc-install`, and how they are copied to the target installation directory (`$GC_BASE`). This task also establishes version tracking via a `VERSION` file.

**Source Layout (Repository)**

The GlobalContext repository contains source files under `src/`:

```
/home/meywd/GlobalContext/
  src/
    bin/
      capture-event       # Story 01
      gc-hook             # Story 02
      gc-install-hooks    # Story 02
      gc-init             # Story 03
      gc-query            # Story 05
      gc-doctor           # Story 00 (this plan)
      gc-install          # Story 00 (this plan)
      gc-uninstall        # Story 02 (enhanced in this plan)
      project             # Story 04
    lib/
      paths.sh            # Story 03
      sanitize.sh         # Story 03
      session_dir.sh      # Story 03
      atomic_write.sh     # Story 03
      json_validate.sh    # Story 03
      event_write.sh      # Story 03
      session_meta.sh     # Story 03
      config.sh           # Story 03
      latest_symlink.sh   # Story 03
      projection_store.sh # Story 03
      rejected.sh         # Story 03
      prerequisites.sh    # Story 00 (this plan)
      debug_log.sh        # Story 02
    hook-config.json      # Story 02
  VERSION                 # Semantic version string, e.g. "1.0.0"
```

**Target Layout (Installed)**

```
~/.claude-context/         (GC_BASE)
  bin/
    capture-event          755
    gc-hook                755
    gc-install-hooks       755
    gc-init                755
    gc-query               755
    gc-doctor              755
    gc-uninstall           755
    project                755
  lib/
    paths.sh               644
    sanitize.sh            644
    session_dir.sh         644
    ...                    644
    hook-config.json       644
  VERSION                  644
  config.json              600 (created by gc-init, never overwritten)
  events/                  700
  projections/             700
```

**SRC_DIR Detection**

The `gc-install` script must locate its own source files. Strategy:

1. If running from the repository (development mode): `SRC_DIR` is relative to the script's location.
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/src"
   ```
2. If the env var `GC_SRC_DIR` is set: use it directly (for CI and custom deployments).
3. Validate: `SRC_DIR` must contain `bin/capture-event` (sanity check).

**Version Tracking**

- The `VERSION` file at the repository root contains a single line: the semantic version string (e.g., `1.0.0`).
- During install, this file is copied to `$GC_BASE/VERSION`.
- The upgrade check (Task 6) compares `$SRC_DIR/../VERSION` (available version) with `$GC_BASE/VERSION` (installed version).
- If `$GC_BASE/VERSION` does not exist, the system is treated as uninstalled.

**Deployment Function**

```bash
gc_deploy_files() {
  local src_dir="$1"
  local target_dir="$2"
  local dry_run="${3:-false}"

  # Deploy bin/ scripts
  mkdir -p "$target_dir/bin"
  for script in "$src_dir/bin/"*; do
    local name
    name=$(basename "$script")
    if [ "$dry_run" = "true" ]; then
      echo "  Would install: bin/$name"
    else
      cp "$script" "$target_dir/bin/$name"
      chmod 755 "$target_dir/bin/$name"
      echo "  bin/$name    installed"
    fi
  done

  # Deploy lib/ modules
  mkdir -p "$target_dir/lib"
  for module in "$src_dir/lib/"*; do
    local name
    name=$(basename "$module")
    if [ "$dry_run" = "true" ]; then
      echo "  Would install: lib/$name"
    else
      cp "$module" "$target_dir/lib/$name"
      chmod 644 "$target_dir/lib/$name"
    fi
  done
  echo "  lib/ ($(ls -1 "$src_dir/lib/" | wc -l) modules)    installed"

  # Deploy hook-config.json
  if [ -f "$src_dir/hook-config.json" ]; then
    cp "$src_dir/hook-config.json" "$target_dir/lib/hook-config.json"
    chmod 644 "$target_dir/lib/hook-config.json"
  fi

  # Deploy VERSION
  local version_file="$src_dir/../VERSION"
  if [ -f "$version_file" ]; then
    cp "$version_file" "$target_dir/VERSION"
    chmod 644 "$target_dir/VERSION"
  fi
}
```

**Files to Create/Modify**

| File | Action | Purpose |
|---|---|---|
| `VERSION` | Create | Version string file at repository root |
| `src/lib/deploy.sh` | Create | Source file deployment functions |
| `tests/lib/test_deploy.sh` | Create | Deployment tests |

**Dependencies**: Task 2 (gc-install calls deployment functions).

**Acceptance Test**

1. Run deployment to a temp directory. Verify all `bin/` scripts exist with permission `755`.
2. Verify all `lib/` modules exist with permission `644`.
3. Verify `VERSION` file is copied correctly.
4. Verify `hook-config.json` is deployed to `lib/`.
5. Run deployment twice. Verify all files are overwritten (upgrade behavior).
6. Verify `SRC_DIR` detection works when running from the repository.
7. Verify `GC_SRC_DIR` env var override works.
8. Verify sanity check fails if `SRC_DIR` does not contain `bin/capture-event`.

**Estimated Complexity**: M (Medium)

---

### Task 4: Hook Registration Automation

**Description**

Integrate hook registration into the `gc-install` flow by calling `gc-install-hooks install` (from Story 02). This task focuses on the installation-side orchestration: ensuring hooks are registered correctly, handling edge cases around `~/.claude/settings.json`, and verifying the result.

Story 02 (Plan 02, Tasks 5-7) owns the `gc-install-hooks` script itself. This task orchestrates its invocation from `gc-install` and handles pre/post conditions.

**Pre-Conditions (checked by gc-install before calling gc-install-hooks)**

1. `$GC_BASE/bin/gc-install-hooks` exists and is executable.
2. `$GC_BASE/bin/gc-hook` exists and is executable.
3. `$GC_BASE/bin/capture-event` exists and is executable.
4. `jq` is on PATH.

**Hook Registration Steps (within gc-install)**

```bash
register_hooks() {
  local gc_base="$1"
  local dry_run="${2:-false}"

  echo "Registering hooks..."

  # Ensure ~/.claude/ exists
  local claude_dir="$HOME/.claude"
  if [ ! -d "$claude_dir" ]; then
    if [ "$dry_run" = "true" ]; then
      echo "  Would create: $claude_dir (mode 0700)"
    else
      mkdir -p "$claude_dir"
      chmod 700 "$claude_dir"
      echo "  Created $claude_dir"
    fi
  fi

  if [ "$dry_run" = "true" ]; then
    echo "  Would register 10 hooks in $claude_dir/settings.json"
    return 0
  fi

  # Delegate to gc-install-hooks (Story 02)
  if "$gc_base/bin/gc-install-hooks" install; then
    echo "  10 hooks registered in $claude_dir/settings.json"
    # Report backup location
    local latest_backup
    latest_backup=$(ls -t "$claude_dir"/settings.json.bak.* 2>/dev/null | head -1)
    if [ -n "$latest_backup" ]; then
      echo "  Backup: $latest_backup"
    fi
    return 0
  else
    echo "  ERROR: Hook registration failed. Run gc-install-hooks install manually." >&2
    return 1
  fi
}
```

**Edge Cases Handled**

| Scenario | Handling |
|---|---|
| `~/.claude/` does not exist | Created with mode 0700 |
| `~/.claude/settings.json` does not exist | `gc-install-hooks` creates it |
| `~/.claude/settings.json` has existing user hooks | Preserved by `gc-install-hooks` (Story 02 contract) |
| `~/.claude/settings.json` has our hooks already | Updated in-place (idempotent, Story 02 contract) |
| `~/.claude/settings.json` is malformed JSON | `gc-install-hooks` aborts with clear error; `gc-install` reports the failure |
| `--skip-hooks` flag | Entire function is skipped |

**Files to Create/Modify**

| File | Action | Purpose |
|---|---|---|
| `src/bin/gc-install` | Modify (from Task 2) | Add `register_hooks` function |
| `tests/bin/test_gc_install_hooks_integration.sh` | Create | Hook registration integration tests |

**Dependencies**: Task 2 (gc-install script exists), Story 02 (gc-install-hooks must be implemented).

**Acceptance Test**

1. Run `gc-install` on a system with no `~/.claude/` directory. Verify directory is created with mode 0700 and settings.json is populated with 10 hooks.
2. Add a user hook to `settings.json` manually. Run `gc-install`. Verify user hook is preserved alongside GC hooks.
3. Run `gc-install` twice. Verify no duplicate hooks in `settings.json`.
4. Corrupt `settings.json` with invalid JSON. Run `gc-install`. Verify it reports the error clearly and does not overwrite the file.
5. Run `gc-install --skip-hooks`. Verify `settings.json` is not modified.
6. Verify a backup file is created before each modification.

**Estimated Complexity**: S (Small) -- orchestration only, Story 02 owns the logic.

---

### Task 5: gc-uninstall Script

**Description**

Enhance the `gc-uninstall` command (initially defined in Story 02, Plan 02 Task 12) with the full installation-aware uninstall flow. The enhanced version understands the complete file distribution from Task 3 and provides a `--purge` flag for full data removal.

The key distinction from Story 02's `gc-uninstall`:
- Story 02 focuses on hook removal from `settings.json` and basic store deletion.
- This task adds awareness of `bin/` and `lib/` scripts, the `VERSION` file, and a two-tier removal strategy (soft uninstall vs purge).

**Invocation**

```bash
gc-uninstall [--purge] [--force] [--dry-run]
```

| Flag | Description |
|---|---|
| (no flags) | **Soft uninstall**: Remove hooks from `settings.json`, remove `bin/` scripts and `lib/` modules. Preserve `events/`, `projections/`, and `config.json`. |
| `--purge` | **Full uninstall**: Remove everything including event data. Requires confirmation. |
| `--force` | Skip confirmation prompt (for scripted use). |
| `--dry-run` | Print what would be removed without making changes. |

**Uninstall Flow**

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

**Files to Create/Modify**

| File | Action | Purpose |
|---|---|---|
| `src/bin/gc-uninstall` | Create (or enhance from Story 02) | Full uninstall script |
| `tests/bin/test_gc_uninstall.sh` | Create | Uninstall tests |

**Dependencies**: Task 1 (for prerequisite awareness), Task 4 (gc-install-hooks uninstall).

**Acceptance Test**

1. Install, then `gc-uninstall` (soft). Verify hooks removed, `bin/` and `lib/` removed, `events/` and `config.json` preserved.
2. Install, write some events, then `gc-uninstall --purge --force`. Verify everything is deleted, `$GC_BASE` does not exist.
3. `gc-uninstall --purge` (without `--force`). Verify confirmation prompt appears. Type "no" -- verify nothing is deleted.
4. `gc-uninstall --dry-run`. Verify nothing is removed but the plan is printed.
5. `gc-uninstall` on a system where GlobalContext is not installed. Verify "not installed" message and exit 0.
6. `gc-uninstall` when `settings.json` has user hooks. Verify only GC hooks are removed.
7. After soft uninstall, `gc-install` can reinstall cleanly using the preserved data.
8. After purge, `gc-install` can perform a fresh install.

**Estimated Complexity**: M (Medium)

---

### Task 6: Upgrade Logic

**Description**

Implement version detection and upgrade logic within `gc-install`. When a user runs `gc-install` on a system that already has GlobalContext installed, the script must detect the current installed version, compare it to the available version, and decide whether to upgrade. Upgrades overwrite `bin/` and `lib/` files but never touch event data or `config.json`.

**Version Comparison**

```bash
gc_get_installed_version() {
  local gc_base="$1"
  if [ -f "$gc_base/VERSION" ]; then
    cat "$gc_base/VERSION"
  else
    echo "0.0.0"  # Not installed or pre-versioning install
  fi
}

gc_get_available_version() {
  local src_dir="$1"
  local version_file="$src_dir/../VERSION"
  if [ -f "$version_file" ]; then
    cat "$version_file"
  else
    echo "unknown"
  fi
}

gc_version_compare() {
  # Returns: "same", "upgrade", "downgrade", or "unknown"
  local installed="$1"
  local available="$2"

  if [ "$installed" = "$available" ]; then
    echo "same"
    return
  fi

  if [ "$installed" = "0.0.0" ] || [ "$available" = "unknown" ]; then
    echo "upgrade"  # Fresh install or unknown version always proceeds
    return
  fi

  # Numeric comparison of semver components
  local i_major i_minor i_patch a_major a_minor a_patch
  IFS='.' read -r i_major i_minor i_patch <<< "$installed"
  IFS='.' read -r a_major a_minor a_patch <<< "$available"

  if [ "$a_major" -gt "$i_major" ] 2>/dev/null ||
     ([ "$a_major" -eq "$i_major" ] && [ "$a_minor" -gt "$i_minor" ]) 2>/dev/null ||
     ([ "$a_major" -eq "$i_major" ] && [ "$a_minor" -eq "$i_minor" ] && [ "$a_patch" -gt "$i_patch" ]) 2>/dev/null; then
    echo "upgrade"
  else
    echo "downgrade"
  fi
}
```

**Upgrade Behavior Matrix**

| Comparison | `--force` | Action |
|---|---|---|
| same | No | Print "Already up to date (vX.Y.Z)", exit 0 |
| same | Yes | Full reinstall (overwrite all files) |
| upgrade | Any | Upgrade: overwrite bin/, lib/, VERSION; preserve config.json, events/, projections/ |
| downgrade | No | Print "WARNING: Installed version (X.Y.Z) is newer than available (A.B.C). Use --force to downgrade.", exit 0 |
| downgrade | Yes | Downgrade: overwrite all files (same as upgrade) |

**What Upgrade Preserves**

| Resource | Preserved | Overwritten |
|---|---|---|
| `$GC_BASE/config.json` | Yes | Never |
| `$GC_BASE/events/**` | Yes | Never |
| `$GC_BASE/projections/**` | Yes | Never |
| `$GC_BASE/logs/**` | Yes | Never |
| `$GC_BASE/bin/*` | No | Always (scripts may have changed) |
| `$GC_BASE/lib/*` | No | Always (libraries may have changed) |
| `$GC_BASE/VERSION` | No | Updated to new version |
| `~/.claude/settings.json` hooks | Updated | `gc-install-hooks install` handles this idempotently |

**Post-Upgrade Hook Re-registration**

After upgrading files, `gc-install` always re-runs `gc-install-hooks install`. This ensures hooks reflect any changes to the hook configuration (new events, changed timeouts, updated matchers). Since `gc-install-hooks` is idempotent, this is safe.

**Files to Create/Modify**

| File | Action | Purpose |
|---|---|---|
| `src/lib/version.sh` | Create | Version detection and comparison functions |
| `tests/lib/test_version.sh` | Create | Version comparison tests |
| `src/bin/gc-install` | Modify (from Task 2) | Integrate upgrade logic |

**Dependencies**: Task 2 (gc-install exists), Task 3 (VERSION file and deployment functions).

**Acceptance Test**

1. Fresh install (no `$GC_BASE/VERSION`): proceeds as new install.
2. Same version installed: prints "Already up to date", exits 0.
3. Same version with `--force`: overwrites all files.
4. Older version installed: upgrades files, preserves data.
5. Newer version installed (downgrade attempt): prints warning, exits 0.
6. Newer version with `--force`: downgrades files.
7. After upgrade: verify `config.json` has not been modified (check `created_at` timestamp).
8. After upgrade: verify event data files are untouched (check file modification times).
9. After upgrade: verify `VERSION` file contains the new version string.
10. After upgrade: verify hooks are re-registered (check `settings.json` for current config).

**Estimated Complexity**: M (Medium)

---

### Task 7: First-Run Verification (gc-doctor)

**Description**

Create the `gc-doctor` command that performs a comprehensive health check of the GlobalContext installation. This command is run automatically at the end of `gc-install` and can be invoked manually via `gc-query doctor`. It verifies prerequisites, directory structure, permissions, hook configuration, and end-to-end event flow.

**Invocation**

```bash
gc-doctor [--json] [--verbose]
```

| Flag | Description |
|---|---|
| `--json` | Output results as JSON (for programmatic consumption). |
| `--verbose` | Show detailed information for each check. |
| (no flags) | Human-readable summary with pass/fail for each check. |

**Health Checks**

| # | Check | Category | Pass Condition |
|---|---|---|---|
| 1 | Prerequisites | System | All required prerequisites met (Task 1) |
| 2 | Store directory exists | Structure | `$GC_BASE` exists and is a directory |
| 3 | Store permissions | Security | `$GC_BASE` has mode 700 |
| 4 | events/ directory | Structure | `$GC_BASE/events/` exists |
| 5 | projections/ directory | Structure | `$GC_BASE/projections/` exists |
| 6 | config.json exists | Config | `$GC_BASE/config.json` exists and is valid JSON |
| 7 | config.json version | Config | `version` field is present and non-empty |
| 8 | VERSION file | Version | `$GC_BASE/VERSION` exists |
| 9 | bin/ scripts present | Files | All expected scripts exist in `$GC_BASE/bin/` |
| 10 | bin/ scripts executable | Permissions | All `bin/` scripts have execute permission |
| 11 | lib/ modules present | Files | All expected modules exist in `$GC_BASE/lib/` |
| 12 | Hooks registered | Hooks | All 10 hooks present in `~/.claude/settings.json` |
| 13 | Hook commands valid | Hooks | Each hook command points to an existing executable |
| 14 | Write test | End-to-end | Write a test event, verify file is created |
| 15 | Read test | End-to-end | Read the test event back, verify envelope fields |
| 16 | Disk usage | Diagnostic | Report total store size (info only, no pass/fail) |
| 17 | Session count | Diagnostic | Report total sessions and events (info only) |
| 18 | Orphan temp files | Maintenance | Check for `*.tmp.*` files (warn if found) |

**Test Event Flow (Checks 14-15)**

```bash
gc_doctor_test_event() {
  local gc_base="$1"
  local test_session="__gc_doctor_test__"
  local test_event_type="DoctorTestEvent"
  local test_payload='{"session_id":"__gc_doctor_test__","test":true,"timestamp":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}'

  # Write test event
  echo "$test_payload" | "$gc_base/bin/capture-event" "$test_event_type" 2>/dev/null
  local write_exit=$?

  # Derive project-id for the test
  local project_id
  project_id=$("$gc_base/bin/capture-event" --derive-project-id "$(pwd)" 2>/dev/null || echo "_unknown-000000")

  # Check if event file was written
  local test_dir="$gc_base/events/$project_id/$test_session"
  if [ -d "$test_dir" ] && ls "$test_dir"/[0-9]*.json >/dev/null 2>&1; then
    # Read back and verify
    local event_file
    event_file=$(ls -1 "$test_dir"/[0-9]*.json | tail -1)
    if jq -e '.event_type == "DoctorTestEvent"' "$event_file" >/dev/null 2>&1; then
      echo "PASS"
    else
      echo "FAIL: event written but envelope malformed"
    fi
  else
    echo "FAIL: event file not created"
  fi

  # Cleanup
  rm -rf "$test_dir" 2>/dev/null
}
```

**Output Format (Text)**

```
GlobalContext Doctor
====================
Store: /home/user/.claude-context (v1.0.0)

Prerequisites:
  bash 5.2                  PASS
  jq 1.7.1                  PASS
  node 22.1.0               PASS
  sha256sum                  PASS
  flock                      PASS
  git 2.43.0                 PASS (optional)
  uuidgen                    PASS (optional)

Structure:
  Store directory            PASS
  Store permissions (700)    PASS
  events/ directory          PASS
  projections/ directory     PASS

Configuration:
  config.json                PASS
  config.json version        PASS (1.0.0)
  VERSION file               PASS (1.0.0)

Scripts:
  bin/ scripts (8)           PASS
  bin/ executable            PASS
  lib/ modules (12)          PASS

Hooks:
  Hooks registered (10/10)   PASS
  Hook commands valid         PASS

End-to-End:
  Write test event           PASS
  Read test event            PASS
  Cleanup test event         PASS

Diagnostics:
  Store size                 12.4 MB
  Sessions                   15 (across 3 projects)
  Total events               3,247
  Orphan temp files          0

Result: ALL CHECKS PASSED
```

**Output Format (JSON)**

```json
{
  "store_path": "/home/user/.claude-context",
  "version": "1.0.0",
  "checks": [
    {"name": "bash", "category": "prerequisites", "status": "pass", "detail": "5.2"},
    {"name": "jq", "category": "prerequisites", "status": "pass", "detail": "1.7.1"},
    ...
  ],
  "diagnostics": {
    "store_size_bytes": 13002752,
    "session_count": 15,
    "project_count": 3,
    "event_count": 3247,
    "orphan_temp_files": 0
  },
  "overall": "pass"
}
```

**Files to Create/Modify**

| File | Action | Purpose |
|---|---|---|
| `src/bin/gc-doctor` | Create | Health check command |
| `tests/bin/test_gc_doctor.sh` | Create | Doctor command tests |

**Dependencies**: Task 2 (gc-install calls doctor), Task 4 (hook registration must be done first).

**Acceptance Test**

1. Run `gc-doctor` after a clean install. All checks pass.
2. Remove `jq` from PATH. Run `gc-doctor`. Prerequisite check fails, overall result is "fail".
3. Remove a hook from `settings.json`. Run `gc-doctor`. Hooks check fails with specific missing hook.
4. Change `$GC_BASE` permissions to 777. Run `gc-doctor`. Permissions check fails.
5. Run `gc-doctor --json`. Output is valid JSON with all check results.
6. Run `gc-doctor --verbose`. Output includes extra detail for each check.
7. Verify test event is written and cleaned up (no `__gc_doctor_test__` directory remains).
8. Run `gc-doctor` on an uninitialized system. Reports all structure checks as failed.

**Estimated Complexity**: L (Large) -- many checks, two output formats, test event flow.

---

### Task 8: Integration Tests

**Description**

Create a comprehensive integration test suite that exercises the full installation lifecycle: fresh install, upgrade, uninstall (soft and purge), and reinstall. Tests verify that all components work together end-to-end in realistic scenarios.

All tests use isolated temporary directories for `$HOME`, `CLAUDE_CONTEXT_PATH`, and source files. No tests touch the real user environment.

**Files to Create**

| File | Action | Purpose |
|---|---|---|
| `tests/00-install-fresh.sh` | Create | Fresh install on a clean system |
| `tests/00-install-upgrade.sh` | Create | Upgrade over existing install |
| `tests/00-install-uninstall.sh` | Create | Uninstall (with and without --purge) |
| `tests/00-install-edge-cases.sh` | Create | Edge cases and error handling |
| `tests/00-install-all.sh` | Create | Runner script that executes all test files |

**Test Cases**

#### 00-install-fresh.sh

| # | Test | Validates |
|---|---|---|
| 1 | Fresh install creates all directories | Task 2, Task 3 |
| 2 | Fresh install deploys all bin/ scripts with 755 | Task 3 |
| 3 | Fresh install deploys all lib/ modules with 644 | Task 3 |
| 4 | Fresh install creates config.json with defaults | Task 2, Story 03 |
| 5 | Fresh install creates VERSION file | Task 3 |
| 6 | Fresh install registers all 10 hooks | Task 4 |
| 7 | Fresh install creates backup of settings.json | Task 4 |
| 8 | gc-doctor passes after fresh install | Task 7 |
| 9 | Write test event works after fresh install | Task 7, end-to-end |
| 10 | Store root has permissions 700 | Task 2 |
| 11 | CLAUDE_CONTEXT_PATH override works | M-4 |

#### 00-install-upgrade.sh

| # | Test | Validates |
|---|---|---|
| 12 | Upgrade detects version mismatch | Task 6 |
| 13 | Upgrade overwrites bin/ scripts | Task 6 |
| 14 | Upgrade overwrites lib/ modules | Task 6 |
| 15 | Upgrade preserves config.json | Task 6 |
| 16 | Upgrade preserves event data | Task 6 |
| 17 | Upgrade updates VERSION file | Task 6 |
| 18 | Upgrade re-registers hooks | Task 6 |
| 19 | Same version without --force skips upgrade | Task 6 |
| 20 | Same version with --force reinstalls | Task 6 |
| 21 | Downgrade blocked without --force | Task 6 |
| 22 | Downgrade allowed with --force | Task 6 |

#### 00-install-uninstall.sh

| # | Test | Validates |
|---|---|---|
| 23 | Soft uninstall removes hooks | Task 5 |
| 24 | Soft uninstall removes bin/ and lib/ | Task 5 |
| 25 | Soft uninstall preserves events/ | Task 5 |
| 26 | Soft uninstall preserves config.json | Task 5 |
| 27 | Purge uninstall removes everything | Task 5 |
| 28 | Purge requires confirmation | Task 5 |
| 29 | Purge --force skips confirmation | Task 5 |
| 30 | Dry run makes no changes | Task 5 |
| 31 | Uninstall preserves user hooks | Task 5, Story 02 |
| 32 | Reinstall after soft uninstall preserves data | Task 5, Task 6 |
| 33 | Reinstall after purge is a fresh install | Task 5, Task 2 |

#### 00-install-edge-cases.sh

| # | Test | Validates |
|---|---|---|
| 34 | Install aborts if jq missing | Task 1 |
| 35 | Install aborts if node missing | Task 1 |
| 36 | Install handles malformed settings.json | Task 4 |
| 37 | Install with --skip-hooks skips hook registration | Task 2 |
| 38 | Install with --dry-run makes no changes | Task 2 |
| 39 | Doctor detects missing prerequisites | Task 7 |
| 40 | Doctor detects missing hooks | Task 7 |
| 41 | Doctor handles uninitialized system | Task 7 |
| 42 | Uninstall on non-installed system exits 0 | Task 5 |
| 43 | Double install is idempotent | Task 2 |

**Test Harness**

Each test file uses a shared setup/teardown pattern:

```bash
#!/usr/bin/env bash
# Test harness for Story 00 installation tests
set -euo pipefail

PASS=0
FAIL=0
TEST_TMPDIR=""

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export HOME="$TEST_TMPDIR/home"
  export CLAUDE_CONTEXT_PATH="$TEST_TMPDIR/gc-store"
  mkdir -p "$HOME/.claude"
  # Copy source files to a temp location
  export GC_SRC_DIR="$TEST_TMPDIR/src"
  cp -r /home/meywd/GlobalContext/src "$GC_SRC_DIR"
  cp /home/meywd/GlobalContext/VERSION "$TEST_TMPDIR/VERSION" 2>/dev/null || echo "1.0.0" > "$TEST_TMPDIR/VERSION"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $msg"
    ((PASS++))
  else
    echo "  FAIL: $msg (expected '$expected', got '$actual')"
    ((FAIL++))
  fi
}

assert_file_exists() { ... }
assert_file_mode() { ... }
assert_dir_exists() { ... }

report() {
  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] && exit 0 || exit 1
}

trap teardown EXIT
```

**Dependencies**: All tasks (1-7).

**Acceptance Test**

1. Run `bash tests/00-install-all.sh`. All test files pass.
2. Run on a clean system with no prior GlobalContext installation. All tests pass.
3. Run with `CLAUDE_CONTEXT_PATH` override. All events and files are created at the custom path.
4. After all tests complete, the real `~/.claude-context/` and `~/.claude/settings.json` are untouched.

**Estimated Complexity**: L (Large) -- 43 test cases across 4 test files.

---

## File Summary

All file paths are relative to `/home/meywd/GlobalContext/`.

| File | Action | Task(s) |
|---|---|---|
| `src/lib/prerequisites.sh` | Create | 1 |
| `src/lib/deploy.sh` | Create | 3 |
| `src/lib/version.sh` | Create | 6 |
| `src/bin/gc-install` | Create | 2, 3, 4, 6 |
| `src/bin/gc-uninstall` | Create (or enhance from Story 02) | 5 |
| `src/bin/gc-doctor` | Create | 7 |
| `VERSION` | Create | 3 |
| `tests/lib/test_prerequisites.sh` | Create | 1 |
| `tests/lib/test_deploy.sh` | Create | 3 |
| `tests/lib/test_version.sh` | Create | 6 |
| `tests/bin/test_gc_install.sh` | Create | 2 |
| `tests/bin/test_gc_install_hooks_integration.sh` | Create | 4 |
| `tests/bin/test_gc_uninstall.sh` | Create | 5 |
| `tests/bin/test_gc_doctor.sh` | Create | 7 |
| `tests/00-install-fresh.sh` | Create | 8 |
| `tests/00-install-upgrade.sh` | Create | 8 |
| `tests/00-install-uninstall.sh` | Create | 8 |
| `tests/00-install-edge-cases.sh` | Create | 8 |
| `tests/00-install-all.sh` | Create | 8 |

---

## Implementation Order (Recommended)

| Phase | Tasks | Milestone |
|-------|-------|-----------|
| **Phase 1: Foundation** | Task 1 (Prerequisites Checker) | Can verify system readiness |
| **Phase 2: Core Scripts** | Task 3 (Source Distribution), Task 6 (Version Logic) | File deployment and version tracking defined |
| **Phase 3: Installer** | Task 2 (gc-install), Task 4 (Hook Registration) | Full install flow works end-to-end |
| **Phase 4: Lifecycle** | Task 5 (gc-uninstall) | Install + uninstall lifecycle complete |
| **Phase 5: Health Check** | Task 7 (gc-doctor) | System health can be verified |
| **Phase 6: Validation** | Task 8 (Integration Tests) | All scenarios tested |

Tasks 3 and 6 can be implemented in parallel (Phase 2). Tasks 2 and 4 can be partially parallelized (Task 4 depends on Task 2 existing but can be developed concurrently).

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `jq` not available on target system | Medium | High (install fails) | Clear error message with platform-specific install instructions. jq is the only hard JSON dependency. |
| Conflicting `~/.claude/settings.json` modifications | Low | Medium (hooks lost) | Backup before every modification. `gc-install-hooks` is the single writer for GC hooks. |
| SRC_DIR detection fails in unusual directory layouts | Low | Medium (install fails) | `GC_SRC_DIR` env var override allows manual specification. Sanity check for `bin/capture-event`. |
| Version comparison fails on non-semver strings | Low | Low (false upgrade) | Treat unparseable versions as "0.0.0" (forces upgrade). |
| macOS compatibility (stat, sha256sum, flock differences) | Medium | Medium (doctor false failures) | Platform detection in prerequisites checker. Use `shasum -a 256` as fallback for `sha256sum`. Use `stat -f%z` as fallback for `stat -c%s`. |
| User runs gc-uninstall --purge accidentally | Low | High (data loss) | Confirmation prompt required (unless --force). Summary shows exact data that will be deleted. |
| Test isolation leaks to real HOME | Very Low | High (real data modified) | All tests override `$HOME` and `$CLAUDE_CONTEXT_PATH` to temp directories. Trap ensures cleanup. |

---

## Notes for Implementation

1. **gc-install is the user-facing entry point** -- users should only need to run one command: `gc-install`. All other setup is orchestrated from there.
2. **gc-doctor is both automated and manual** -- it runs as part of `gc-install` (Task 7) and is available standalone for ongoing health monitoring.
3. **Idempotency is non-negotiable** -- every operation (install, upgrade, hook registration) must be safe to run repeatedly without data loss or duplication.
4. **CLAUDE_CONTEXT_PATH is respected everywhere** -- the base directory resolution pattern from Story 01/03 (`${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}`) must be used consistently in all new scripts.
5. **Soft uninstall is the default** -- `gc-uninstall` without `--purge` preserves all event data. Users who want to reinstall should not lose their history by default.
6. **The VERSION file is the single source of truth for versioning** -- it lives at the repo root and is copied to `$GC_BASE/VERSION` during install. No version is embedded in config.json (that field tracks the config schema version, not the software version).
7. **gc-doctor output must be deterministic** -- given the same system state, doctor should produce the same results. No random test IDs or timestamps in the pass/fail output (diagnostics section can include timestamps).
8. **Platform compatibility** -- all scripts must work on both Linux and macOS. Where command syntax differs (`stat`, `sha256sum`/`shasum`, `mv -fT`/`ln -sfn`), detect and adapt at runtime.

---

## Effort Estimates

| Task | Complexity | Estimate |
|---|---|---|
| Task 1: Prerequisites Checker | M | 2-3 hours |
| Task 2: gc-install Script | L | 4-6 hours |
| Task 3: Source File Distribution | M | 2-3 hours |
| Task 4: Hook Registration Automation | S | 1-2 hours |
| Task 5: gc-uninstall Script | M | 2-3 hours |
| Task 6: Upgrade Logic | M | 2-3 hours |
| Task 7: First-Run Verification (gc-doctor) | L | 4-6 hours |
| Task 8: Integration Tests | L | 6-8 hours |
| **Total** | | **~23-34 hours (~3-4 working days)** |
