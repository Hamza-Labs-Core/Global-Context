# Task 07: First-Run Verification (gc-doctor)

**Story**: 00-installation-setup
**Status**: Pending
**Estimated Complexity**: L (Large) -- 4-6 hours

---

## Description

Create the `gc-doctor` command that performs a comprehensive health check of the GlobalContext installation. This command is run automatically at the end of `gc-install` and can be invoked manually via `gc-query doctor`. It verifies prerequisites, directory structure, permissions, hook configuration, and end-to-end event flow.

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/bin/gc-doctor` | Create | Health check command |
| `tests/bin/test_gc_doctor.sh` | Create | Doctor command tests |

All file paths are relative to `/home/meywd/GlobalContext/`.

---

## Specification / Implementation Details

### Invocation

```bash
gc-doctor [--json] [--verbose]
```

| Flag | Description |
|---|---|
| `--json` | Output results as JSON (for programmatic consumption). |
| `--verbose` | Show detailed information for each check. |
| (no flags) | Human-readable summary with pass/fail for each check. |

### Health Checks

| # | Check | Category | Pass Condition |
|---|---|---|---|
| 1 | Prerequisites | System | All required prerequisites met (Task 01) |
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

### Test Event Flow (Checks 14-15)

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

### Output Format (Text)

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

### Output Format (JSON)

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

---

## Dependencies

- **Task 02** (`/home/meywd/GlobalContext/tasks/00-installation/02-gc-install-script.md`) -- gc-install calls doctor.
- **Task 04** (`/home/meywd/GlobalContext/tasks/00-installation/04-hook-registration-automation.md`) -- hook registration must be done first.

---

## Acceptance Tests

1. Run `gc-doctor` after a clean install. All checks pass.
2. Remove `jq` from PATH. Run `gc-doctor`. Prerequisite check fails, overall result is "fail".
3. Remove a hook from `settings.json`. Run `gc-doctor`. Hooks check fails with specific missing hook.
4. Change `$GC_BASE` permissions to 777. Run `gc-doctor`. Permissions check fails.
5. Run `gc-doctor --json`. Output is valid JSON with all check results.
6. Run `gc-doctor --verbose`. Output includes extra detail for each check.
7. Verify test event is written and cleaned up (no `__gc_doctor_test__` directory remains).
8. Run `gc-doctor` on an uninitialized system. Reports all structure checks as failed.
