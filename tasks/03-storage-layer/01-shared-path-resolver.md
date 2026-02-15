# Task 01: Shared Path Resolver and Constants Module

**Story**: 03-storage-layer
**Status**: Pending
**Estimated Complexity**: S (Small) -- 1-2 hours

---

## Description

Create a shared shell library that every script in the project sources. It resolves the storage root path (respecting `CLAUDE_CONTEXT_PATH`), defines directory constants, and provides common utility functions. This is the single place where the base path is determined -- no script should hardcode `~/.claude-context`.

This directly addresses review issue **M-4** (CLAUDE_CONTEXT_PATH env var support).

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/paths.sh` | Create | Shared shell library: path resolution, constants, common helpers |
| `tests/lib/test_paths.sh` | Create | Unit tests for path resolution logic |

---

## Specification

`paths.sh` must export the following:

```bash
# Resolve storage root
GC_ROOT="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"

# Directory constants
GC_EVENTS_DIR="$GC_ROOT/events"
GC_PROJECTIONS_DIR="$GC_ROOT/projections"
GC_BIN_DIR="$GC_ROOT/bin"
GC_CONFIG_FILE="$GC_ROOT/config.json"
# Note: No global sessions.json or .sessions.lock — per-session metadata only (Amendment 1)
```

It must also provide helper functions:

- `gc_session_events_dir(project_id, session_id)` -- returns `$GC_EVENTS_DIR/{project_id}/{sanitized-session-id}`
- `gc_session_lock_file(project_id, session_id)` -- returns `$GC_EVENTS_DIR/{project_id}/{sanitized-session-id}/.lock`
- `gc_session_projections_dir(project_id, session_id)` -- returns `$GC_PROJECTIONS_DIR/{project_id}/{sanitized-session-id}`
- `gc_project_latest(project_id)` -- returns `$GC_PROJECTIONS_DIR/{project_id}/latest`
- `gc_resolve_root()` -- validates and returns the root path, printing an error if the store is not initialized
- `gc_derive_project_id(project_dir)` -- returns `{basename}-{hash6}` (see Amendment 3)

---

## Dependencies

None. This is the foundation.

---

## Acceptance Tests

1. Source `paths.sh` with `CLAUDE_CONTEXT_PATH` unset -- `GC_ROOT` equals `$HOME/.claude-context`.
2. Source `paths.sh` with `CLAUDE_CONTEXT_PATH=/tmp/test-store` -- `GC_ROOT` equals `/tmp/test-store`.
3. All path constants are derived from `GC_ROOT` (grep shows no hardcoded `~/.claude-context`).
4. Run `tests/lib/test_paths.sh` -- all assertions pass.
