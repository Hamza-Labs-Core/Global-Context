# Task 03: Add `CLAUDE_CONTEXT_PATH` Support (Review Fix M-4)

**Story**: 02-hook-integration
**Status**: Pending
**Estimated Complexity**: S (Small) -- one-line change per script, plus verification tests

---

## Description

Ensure both `gc-hook` and `gc-install-hooks` respect the `CLAUDE_CONTEXT_PATH` environment variable for the storage root path, rather than hardcoding `~/.claude-context/`. This addresses **review issue M-4**.

The pattern is simple: at the top of each script, resolve the base directory:

```bash
GC_BASE="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"
```

All subsequent path references use `$GC_BASE` instead of a hardcoded path.

For hook commands written to `settings.json`, the command string must remain `~/.claude-context/bin/gc-hook ...` (Claude Code expands `~`). The env var override is resolved at runtime inside `gc-hook`, not in the hook command string. This means:
- The `settings.json` hook commands always reference `~/.claude-context/bin/gc-hook` (the entry point).
- When `gc-hook` executes, it reads `CLAUDE_CONTEXT_PATH` and invokes `capture-event` from the correct location.
- Users who set `CLAUDE_CONTEXT_PATH` in their shell profile get the override applied to all hook invocations.

---

## Files to Modify

| File | Change |
|------|--------|
| `src/gc-hook` (from Task 1) | Already includes `GC_BASE` resolution; verify it is correct |
| `src/gc-install-hooks` (created in Task 5) | Must use `GC_BASE` for all path references during install/validate |

## Files to Create

None. The resolution is inline (a single variable assignment), not a separate helper file.

---

## Dependencies

- [Task 01: gc-hook wrapper](/home/meywd/GlobalContext/tasks/02-hook-integration/01-gc-hook-wrapper.md) -- gc-hook must exist

---

## Acceptance Tests

1. Set `CLAUDE_CONTEXT_PATH=/tmp/test-gc-store`.
2. Create `/tmp/test-gc-store/bin/capture-event` as a mock.
3. Run `echo '{"session_id":"x"}' | CLAUDE_CONTEXT_PATH=/tmp/test-gc-store src/gc-hook SessionStarted`.
4. Verify the mock at the custom path was invoked (not the default path).
5. Unset `CLAUDE_CONTEXT_PATH`, verify it falls back to `~/.claude-context`.
