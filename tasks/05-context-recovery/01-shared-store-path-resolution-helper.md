# Task 01: Shared Store Path Resolution Helper

**Story**: 05-context-recovery
**Complexity**: S (Small)
**Status**: Pending

---

## Description

Reuse the shared path resolver from Story 03 (`src/lib/paths.sh`) which resolves the store path, respecting the `CLAUDE_CONTEXT_PATH` environment variable (fix M-4). Every script in Story 05 sources this library instead of hardcoding `~/.claude-context/`.

> **Note**: This task is satisfied by Plan 03, Task 1 (`src/lib/paths.sh`). Story 05 scripts source the same library. No separate `store-path.sh` is needed. The variables below are provided by `paths.sh`:

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Reuse | `src/lib/paths.sh` (from Story 03) |

---

## Specification / Implementation Details

Story 05 scripts source `paths.sh` and use these variables and functions:

```bash
source "$(dirname "$0")/../lib/paths.sh"
# Provides: $GC_ROOT, $GC_EVENTS_DIR, $GC_PROJECTIONS_DIR, $GC_BIN_DIR, $GC_CONFIG_FILE
# Provides: gc_session_events_dir(), gc_session_projections_dir(), gc_project_latest(), gc_derive_project_id()
```

---

## Dependencies

- Story 03, Task 1 (paths.sh must be implemented first)

---

## Acceptance Tests

1. Without `CLAUDE_CONTEXT_PATH` set: source `paths.sh`, verify `$GC_ROOT` is `$HOME/.claude-context`.
2. With `CLAUDE_CONTEXT_PATH=/tmp/test-store`: source `paths.sh`, verify `$GC_ROOT` is `/tmp/test-store`.
3. All derived paths (`$GC_EVENTS_DIR`, `$GC_PROJECTIONS_DIR`, etc.) are consistent with the resolved root.
4. `gc_derive_project_id` returns `{basename}-{hash6}` format.

---

## Estimated Complexity: S
