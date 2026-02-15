# Task 10: Integration Tests

**Story**: 06-plugin-packaging
**Estimated Complexity**: L (Large)
**Dependencies**: All previous tasks (this is the validation pass)
- [Task 01 - Plugin Manifest and Directory Scaffold](/home/meywd/GlobalContext/tasks/06-plugin-packaging/01-plugin-manifest-scaffold.md)
- [Task 02 - Hook Configuration](/home/meywd/GlobalContext/tasks/06-plugin-packaging/02-hook-configuration.md)
- [Task 03 - Capture Event Script Adaptation](/home/meywd/GlobalContext/tasks/06-plugin-packaging/03-capture-script-adaptation.md)
- [Task 04 - Auto-Init on First Use](/home/meywd/GlobalContext/tasks/06-plugin-packaging/04-auto-init-first-use.md)
- [Task 05 - Command Files](/home/meywd/GlobalContext/tasks/06-plugin-packaging/05-command-files.md)
- [Task 06 - Context Recovery Skill](/home/meywd/GlobalContext/tasks/06-plugin-packaging/06-context-recovery-skill.md)
- [Task 07 - Context Recovery Agent](/home/meywd/GlobalContext/tasks/06-plugin-packaging/07-context-recovery-agent.md)
- [Task 08 - Shared Library Bundling](/home/meywd/GlobalContext/tasks/06-plugin-packaging/08-shared-library-bundling.md)
- [Task 09 - Marketplace Configuration](/home/meywd/GlobalContext/tasks/06-plugin-packaging/09-marketplace-configuration.md)

---

## Description

Create a comprehensive integration test suite that validates the plugin works end-to-end when loaded by Claude Code. Tests cover plugin loading, hook firing, event capture, command accessibility, auto-initialization, and environment variable overrides.

All tests use a temporary directory for both the plugin install location and the data store (`CLAUDE_CONTEXT_PATH`), ensuring no pollution of the real user environment.

---

## Files to Create

| File | Purpose |
|------|---------|
| `tests/06-plugin-integration-test.sh` | Main integration test script |
| `tests/fixtures/06/` | Test fixtures directory |

---

## Test Cases

| # | Test Case | Validates |
|---|-----------|-----------|
| 1 | Plugin manifest is valid JSON | Task 1 |
| 2 | hooks.json is valid JSON with all 10 hook events | Task 2 |
| 3 | hooks.json event types match expected mapping | Task 2 |
| 4 | hooks.json async flags are correct (3 sync, 7 async) | Task 2 |
| 5 | hooks.json matchers are correct (5 with ".*", rest without) | Task 2 |
| 6 | gc-hook exits 0 when capture-event succeeds | Task 3 |
| 7 | gc-hook exits 0 when capture-event fails | Task 3 |
| 8 | gc-hook produces zero stdout | Task 3 |
| 9 | gc-hook produces zero stderr (GC_DEBUG unset) | Task 3 |
| 10 | gc-hook passes event type and stdin correctly | Task 3 |
| 11 | Auto-init creates store on first use | Task 4 |
| 12 | Auto-init is idempotent (no error on second run) | Task 4 |
| 13 | Auto-init creates config.json with source=plugin | Task 4 |
| 14 | All 9 command files exist with valid frontmatter | Task 5 |
| 15 | SKILL.md exists with valid frontmatter | Task 6 |
| 16 | Agent markdown exists with valid frontmatter | Task 7 |
| 17 | All library files exist in plugin/lib/ | Task 8 |
| 18 | paths.sh resolves GC_ROOT correctly | Task 8 |
| 19 | capture-event sources libraries from plugin lib/ | Task 8 |
| 20 | marketplace.json is valid JSON | Task 9 |
| 21 | End-to-end: SessionStarted event captures correctly | Tasks 2-4, 8 |
| 22 | End-to-end: ToolCallCompleted event captures correctly | Tasks 2-3, 8 |
| 23 | End-to-end: all 10 event types produce valid event files | Tasks 2-3, 8 |
| 24 | CLAUDE_CONTEXT_PATH override works for all operations | Tasks 3-4 |
| 25 | Plugin loads without errors via --plugin-dir | All |
| 26 | No hardcoded ~/.claude-context/bin/ paths in any script | Task 3, 8 |
| 27 | Scripts work from arbitrary plugin install location | Task 3, 8 |
| 28 | Debug logging (GC_DEBUG=1) writes to log file | Task 3 |
| 29 | gc-query status runs from plugin scripts/ | Task 5, 8 |
| 30 | gc-query doctor runs from plugin scripts/ | Task 5, 8 |

---

## Specification

### Test Script Structure

```bash
#!/usr/bin/env bash
# GlobalContext Plugin Integration Tests

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="$PROJECT_DIR/plugin"

# Temporary test environment
TEST_DIR=$(mktemp -d)
export CLAUDE_CONTEXT_PATH="$TEST_DIR/store"
trap 'rm -rf "$TEST_DIR"' EXIT

PASS=0
FAIL=0

assert() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "[PASS] $desc"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $desc"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "[PASS] $desc"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $desc (expected: $expected, got: $actual)"
    FAIL=$((FAIL + 1))
  fi
}

# ... test cases ...

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

---

## Acceptance Tests

1. Run `bash tests/06-plugin-integration-test.sh`. All 30 test cases pass.
2. Run on a clean system with no `~/.claude-context/`. All tests pass (uses `CLAUDE_CONTEXT_PATH` for isolation).
3. The test suite cleans up after itself (temp directory removed on exit).
4. The test suite completes in under 30 seconds.
5. Each test case reports PASS or FAIL with a clear description.
