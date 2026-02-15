# Task 03: Session Directory Creation and Lock File Management

**Story**: 03-storage-layer
**Status**: Pending
**Estimated Complexity**: S (Small) -- 1-2 hours

---

## Description

Implement the logic for creating per-session directories under `events/` on demand. Each directory contains event files and a `.lock` file for flock coordination. The directory is created lazily on the first event for a session.

This directly addresses review issue **C-1** by canonicalizing on `.lock` (not `_seq.lock`).

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/session_dir.sh` | Create | Session directory creation, lock file creation, existence check |
| `tests/lib/test_session_dir.sh` | Create | Unit and integration tests |

---

## Specification

Function: `gc_ensure_session_dir(project_id, session_id)`

1. Sanitize the session ID using `gc_sanitize_session_id` (Task 2).
2. Compute path: `$GC_EVENTS_DIR/{project_id}/{sanitized_id}/`.
3. Create directory: `mkdir -p "$dir"`.
4. Create lock file: `touch "$dir/.lock"` (idempotent).
5. Return the directory path on stdout.

The function must be safe under concurrent invocation -- `mkdir -p` is inherently safe, and `touch` is idempotent.

Lock file naming convention (canonical, C-1 resolution):

| Lock File | Location | Purpose |
|---|---|---|
| `.lock` | `events/{project-id}/{session-id}/.lock` | Per-session sequence number coordination and session.json update |

> **Amendment 1**: The global `.sessions.lock` has been removed. All locking is per-session only.

---

## Dependencies

- **Task 01**: `/home/meywd/GlobalContext/tasks/03-storage-layer/01-shared-path-resolver.md` (paths.sh)
- **Task 02**: `/home/meywd/GlobalContext/tasks/03-storage-layer/02-session-id-sanitization.md` (sanitize.sh)

---

## Acceptance Tests

1. Call `gc_ensure_session_dir "proj-abc123" "test-session-1"` -- directory `$GC_EVENTS_DIR/proj-abc123/test-session-1/` exists with `.lock` file.
2. Call again -- no error, no duplication, same result.
3. Call with `"proj-abc123" "session/bad"` -- directory is `$GC_EVENTS_DIR/proj-abc123/sessionbad/` (slashes stripped, not replaced).
4. Two parallel invocations with the same session ID complete without error.
5. Verify `.lock` file exists (not `_seq.lock`, not `lock`).
