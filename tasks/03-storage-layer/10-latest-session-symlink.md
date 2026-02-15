# Task 10: Latest Session Symlink Management

**Story**: 03-storage-layer
**Status**: Pending
**Estimated Complexity**: S (Small) -- 1-2 hours

---

## Description

Implement atomic symlink update for the per-project `latest` symlink at `projections/{project-id}/latest`, which points to the most recently started session's projection directory within that project.

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/latest_symlink.sh` | Create | Symlink creation and update |
| `tests/lib/test_latest_symlink.sh` | Create | Symlink tests |

---

## Specification

Function: `gc_update_latest_symlink(project_id, session_id)`:

```
1. Compute target: the session_id string (relative path within projections/{project-id}/)
2. Ensure project projection dir: mkdir -p "$GC_PROJECTIONS_DIR/$project_id"
3. Compute symlink path: $GC_PROJECTIONS_DIR/$project_id/latest
4. Create temp symlink: ln -s "$session_id" "$GC_PROJECTIONS_DIR/$project_id/.latest.tmp.$$"
5. Rename over existing: mv -fT "$GC_PROJECTIONS_DIR/$project_id/.latest.tmp.$$" "$GC_PROJECTIONS_DIR/$project_id/latest"
   (On macOS where mv -T is not available, use: ln -sfn "$session_id" "$GC_PROJECTIONS_DIR/$project_id/latest")
6. If symlink creation fails: log warning to stderr, do not block event capture
```

Platform considerations:

- Linux: `mv -fT` for atomic rename of symlink.
- macOS: `ln -sfn` which atomically replaces the symlink.
- Detect platform and use the appropriate method.

Function: `gc_read_latest_session_id(project_id) -> session_id`:

- `readlink "$GC_PROJECTIONS_DIR/$project_id/latest"` -- returns the session ID.
- If symlink does not exist: return empty string.

---

## Dependencies

- **Task 01**: `/home/meywd/GlobalContext/tasks/03-storage-layer/01-shared-path-resolver.md` (paths.sh)

---

## Acceptance Tests

1. Call `gc_update_latest_symlink "proj-abc123" "session-1"` -- symlink at `projections/proj-abc123/latest` points to `session-1`.
2. Call `gc_update_latest_symlink "proj-abc123" "session-2"` -- symlink now points to `session-2`.
3. `gc_read_latest_session_id "proj-abc123"` returns `"session-2"`.
4. Symlink target is a relative path (not absolute).
5. Two different projects have independent `latest` symlinks.
6. Works on both Linux and macOS (test on CI or both platforms).
7. If projections directory does not exist -- error logged, no crash.
8. Target projection directory does not need to exist for symlink creation.
