# Task 04: Hook Registration Automation

**Story**: 00-installation-setup
**Status**: Pending
**Estimated Complexity**: S (Small) -- 1-2 hours

---

## Description

Integrate hook registration into the `gc-install` flow by calling `gc-install-hooks install` (from Story 02). This task focuses on the installation-side orchestration: ensuring hooks are registered correctly, handling edge cases around `~/.claude/settings.json`, and verifying the result.

Story 02 (Plan 02, Tasks 5-7) owns the `gc-install-hooks` script itself. This task orchestrates its invocation from `gc-install` and handles pre/post conditions.

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/bin/gc-install` | Modify (from Task 02) | Add `register_hooks` function |
| `tests/bin/test_gc_install_hooks_integration.sh` | Create | Hook registration integration tests |

All file paths are relative to `/home/meywd/GlobalContext/`.

---

## Specification / Implementation Details

### Pre-Conditions (checked by gc-install before calling gc-install-hooks)

1. `$GC_BASE/bin/gc-install-hooks` exists and is executable.
2. `$GC_BASE/bin/gc-hook` exists and is executable.
3. `$GC_BASE/bin/capture-event` exists and is executable.
4. `jq` is on PATH.

### Hook Registration Steps (within gc-install)

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

### Edge Cases Handled

| Scenario | Handling |
|---|---|
| `~/.claude/` does not exist | Created with mode 0700 |
| `~/.claude/settings.json` does not exist | `gc-install-hooks` creates it |
| `~/.claude/settings.json` has existing user hooks | Preserved by `gc-install-hooks` (Story 02 contract) |
| `~/.claude/settings.json` has our hooks already | Updated in-place (idempotent, Story 02 contract) |
| `~/.claude/settings.json` is malformed JSON | `gc-install-hooks` aborts with clear error; `gc-install` reports the failure |
| `--skip-hooks` flag | Entire function is skipped |

---

## Dependencies

- **Task 02** (`/home/meywd/GlobalContext/tasks/00-installation/02-gc-install-script.md`) -- gc-install script exists.
- **Story 02** -- `gc-install-hooks` must be implemented.

---

## Acceptance Tests

1. Run `gc-install` on a system with no `~/.claude/` directory. Verify directory is created with mode 0700 and settings.json is populated with 10 hooks.
2. Add a user hook to `settings.json` manually. Run `gc-install`. Verify user hook is preserved alongside GC hooks.
3. Run `gc-install` twice. Verify no duplicate hooks in `settings.json`.
4. Corrupt `settings.json` with invalid JSON. Run `gc-install`. Verify it reports the error clearly and does not overwrite the file.
5. Run `gc-install --skip-hooks`. Verify `settings.json` is not modified.
6. Verify a backup file is created before each modification.
