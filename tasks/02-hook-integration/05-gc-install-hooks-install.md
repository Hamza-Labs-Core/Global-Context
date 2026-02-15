# Task 05: Implement `gc-install-hooks` -- Install Command

**Story**: 02-hook-integration
**Status**: Pending
**Estimated Complexity**: L (Large) -- JSON merging with jq, backup logic, prerequisite checks, idempotency

---

## Description

Build the core installation logic: read existing `settings.json`, merge GlobalContext hooks into it (preserving user hooks and non-hook settings), and write the result back. This is the most complex script in Story 02.

---

## Files to Create

| File | Purpose |
|------|---------|
| `src/gc-install-hooks` | Executable Bash script |

---

## Specification / Implementation Details

The script supports three subcommands: `install`, `uninstall`, `validate`. This task covers `install`.

### Install Flow

```
gc-install-hooks install
  1. Resolve GC_BASE from CLAUDE_CONTEXT_PATH or default
  2. Pre-installation checks:
     a. Verify jq is on PATH (abort if missing)
     b. Verify $GC_BASE/bin/capture-event exists and is executable (abort if missing)
     c. Verify $GC_BASE/bin/gc-hook exists and is executable (abort if missing)
  3. Ensure ~/.claude/ directory exists (create with mode 0700 if missing)
  4. If ~/.claude/settings.json exists:
     a. Validate it is parseable JSON (abort with clear error if malformed)
     b. Create backup at ~/.claude/settings.json.bak.{YYYYMMDD-HHMMSS}
     c. Read content into variable
  5. If ~/.claude/settings.json does not exist:
     a. Start with empty object: '{}'
  6. Use jq to merge hooks:
     For each of the 10 hook events:
       a. Build the hook entry JSON object (type, command, async, timeout, matcher)
       b. If hooks.{EventName} array exists, filter out any entry containing "gc-hook"
          in its command, then append the new entry
       c. If hooks.{EventName} does not exist, create it with [new entry]
  7. Write merged JSON to ~/.claude/settings.json (2-space indentation)
  8. Validate written file is parseable by jq
  9. Print summary: "Installed 10 GlobalContext hooks. Backup: <path>"
```

### Key jq Operations

For each hook event, the merge can be done with a single jq pipeline:

```bash
# Remove existing GC hook from array (if any), then append new one
jq --argjson new_hook "$hook_json" \
   '.hooks.PreToolUse = ([.hooks.PreToolUse // [] | .[] | select(.command | contains("gc-hook") | not)] + [$new_hook])' \
   "$settings_file"
```

The entire merge should be done in as few jq invocations as possible (ideally one pass that handles all 10 events).

### Constants (defined once at the top of the script)

```bash
HOOK_TIMEOUT=5000
HOOK_IDENTIFIER="gc-hook"
GC_HOOK_PATH="~/.claude-context/bin/gc-hook"
```

---

## Dependencies

- [Task 01: gc-hook wrapper](/home/meywd/GlobalContext/tasks/02-hook-integration/01-gc-hook-wrapper.md) -- gc-hook must exist for prerequisite check
- [Task 04: Hook config data structure](/home/meywd/GlobalContext/tasks/02-hook-integration/04-hook-config-data-structure.md) -- hook-config.json for the canonical configuration

---

## Acceptance Tests

1. Start with no `~/.claude/settings.json`. Run `gc-install-hooks install`. Verify file is created with all 10 hooks.
2. Run again. Verify no duplicates (idempotent).
3. Add a user hook to PreToolUse manually. Run install. Verify user hook is preserved alongside GC hook.
4. Add a non-hook setting (`"model": "opus"`) to settings.json. Run install. Verify it is preserved.
5. Verify backup file exists at `~/.claude/settings.json.bak.*`.
6. Verify all 10 hooks have correct async flags, timeouts, and matchers per the mapping table.
7. Run `jq . ~/.claude/settings.json` to verify valid JSON with 2-space indentation.
