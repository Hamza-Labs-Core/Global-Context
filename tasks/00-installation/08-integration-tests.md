# Task 08: Integration Tests

**Story**: 00-installation-setup
**Status**: Pending
**Estimated Complexity**: L (Large) -- 6-8 hours

---

## Description

Create a comprehensive integration test suite that exercises the full installation lifecycle: fresh install, upgrade, uninstall (soft and purge), and reinstall. Tests verify that all components work together end-to-end in realistic scenarios.

All tests use isolated temporary directories for `$HOME`, `CLAUDE_CONTEXT_PATH`, and source files. No tests touch the real user environment.

---

## Files to Create

| File | Action | Purpose |
|---|---|---|
| `tests/00-install-fresh.sh` | Create | Fresh install on a clean system |
| `tests/00-install-upgrade.sh` | Create | Upgrade over existing install |
| `tests/00-install-uninstall.sh` | Create | Uninstall (with and without --purge) |
| `tests/00-install-edge-cases.sh` | Create | Edge cases and error handling |
| `tests/00-install-all.sh` | Create | Runner script that executes all test files |

All file paths are relative to `/home/meywd/GlobalContext/`.

---

## Specification / Implementation Details

### Test Cases

#### 00-install-fresh.sh

| # | Test | Validates |
|---|---|---|
| 1 | Fresh install creates all directories | Task 02, Task 03 |
| 2 | Fresh install deploys all bin/ scripts with 755 | Task 03 |
| 3 | Fresh install deploys all lib/ modules with 644 | Task 03 |
| 4 | Fresh install creates config.json with defaults | Task 02, Story 03 |
| 5 | Fresh install creates VERSION file | Task 03 |
| 6 | Fresh install registers all 10 hooks | Task 04 |
| 7 | Fresh install creates backup of settings.json | Task 04 |
| 8 | gc-doctor passes after fresh install | Task 07 |
| 9 | Write test event works after fresh install | Task 07, end-to-end |
| 10 | Store root has permissions 700 | Task 02 |
| 11 | CLAUDE_CONTEXT_PATH override works | M-4 |

#### 00-install-upgrade.sh

| # | Test | Validates |
|---|---|---|
| 12 | Upgrade detects version mismatch | Task 06 |
| 13 | Upgrade overwrites bin/ scripts | Task 06 |
| 14 | Upgrade overwrites lib/ modules | Task 06 |
| 15 | Upgrade preserves config.json | Task 06 |
| 16 | Upgrade preserves event data | Task 06 |
| 17 | Upgrade updates VERSION file | Task 06 |
| 18 | Upgrade re-registers hooks | Task 06 |
| 19 | Same version without --force skips upgrade | Task 06 |
| 20 | Same version with --force reinstalls | Task 06 |
| 21 | Downgrade blocked without --force | Task 06 |
| 22 | Downgrade allowed with --force | Task 06 |

#### 00-install-uninstall.sh

| # | Test | Validates |
|---|---|---|
| 23 | Soft uninstall removes hooks | Task 05 |
| 24 | Soft uninstall removes bin/ and lib/ | Task 05 |
| 25 | Soft uninstall preserves events/ | Task 05 |
| 26 | Soft uninstall preserves config.json | Task 05 |
| 27 | Purge uninstall removes everything | Task 05 |
| 28 | Purge requires confirmation | Task 05 |
| 29 | Purge --force skips confirmation | Task 05 |
| 30 | Dry run makes no changes | Task 05 |
| 31 | Uninstall preserves user hooks | Task 05, Story 02 |
| 32 | Reinstall after soft uninstall preserves data | Task 05, Task 06 |
| 33 | Reinstall after purge is a fresh install | Task 05, Task 02 |

#### 00-install-edge-cases.sh

| # | Test | Validates |
|---|---|---|
| 34 | Install aborts if jq missing | Task 01 |
| 35 | Install aborts if node missing | Task 01 |
| 36 | Install handles malformed settings.json | Task 04 |
| 37 | Install with --skip-hooks skips hook registration | Task 02 |
| 38 | Install with --dry-run makes no changes | Task 02 |
| 39 | Doctor detects missing prerequisites | Task 07 |
| 40 | Doctor detects missing hooks | Task 07 |
| 41 | Doctor handles uninitialized system | Task 07 |
| 42 | Uninstall on non-installed system exits 0 | Task 05 |
| 43 | Double install is idempotent | Task 02 |

### Test Harness

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

---

## Dependencies

- **All Tasks (01-07)**:
  - `/home/meywd/GlobalContext/tasks/00-installation/01-prerequisites-checker.md`
  - `/home/meywd/GlobalContext/tasks/00-installation/02-gc-install-script.md`
  - `/home/meywd/GlobalContext/tasks/00-installation/03-source-file-distribution.md`
  - `/home/meywd/GlobalContext/tasks/00-installation/04-hook-registration-automation.md`
  - `/home/meywd/GlobalContext/tasks/00-installation/05-gc-uninstall-script.md`
  - `/home/meywd/GlobalContext/tasks/00-installation/06-upgrade-logic.md`
  - `/home/meywd/GlobalContext/tasks/00-installation/07-first-run-verification.md`

---

## Acceptance Tests

1. Run `bash tests/00-install-all.sh`. All test files pass.
2. Run on a clean system with no prior GlobalContext installation. All tests pass.
3. Run with `CLAUDE_CONTEXT_PATH` override. All events and files are created at the custom path.
4. After all tests complete, the real `~/.claude-context/` and `~/.claude/settings.json` are untouched.
