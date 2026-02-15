# Task 05: Session Resolution Helpers

**Story**: 05-context-recovery
**Complexity**: S (Small)
**Status**: Pending

---

## Description

Implement helper functions for resolving session IDs: latest session resolution (via symlink with fallback), prefix matching, and session existence validation.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Create | `~/.claude-context/lib/session-resolve.sh` |

---

## Specification / Implementation Details

Three functions:

1. **resolve_latest_session(project_id)**: Read the per-project `latest` symlink at `$GC_PROJECTIONS_DIR/$project_id/latest`. If missing or broken, fall back to scanning `$GC_EVENTS_DIR/$project_id/` for the most recently modified session directory.

2. **resolve_session_id(project_id, partial_id)**: If the given ID matches a session directory exactly under `$GC_EVENTS_DIR/$project_id/`, return it. Otherwise, search for directories whose name starts with the partial ID. If exactly one match, return it. If multiple matches, list them and exit with code 2. If no matches, exit with code 3.

3. **validate_session_exists(project_id, session_id)**: Check that `$GC_EVENTS_DIR/$project_id/$session_id/` exists and contains at least one `[0-9]*.json` file.

---

## Dependencies

- [Task 01: Shared Store Path Resolution Helper](/home/meywd/GlobalContext/tasks/05-context-recovery/01-shared-store-path-resolution-helper.md) (paths.sh for `gc_project_latest()`, `gc_session_events_dir()`)

---

## Acceptance Tests

1. `resolve_latest_session "proj-abc123"` returns the session ID from the per-project `latest` symlink.
2. When the symlink is missing, it falls back to the most recent session directory in that project.
3. `resolve_session_id "proj-abc123" "abc"` returns `"abc-123-def"` when that is the only match.
4. `resolve_session_id "proj-abc123" "abc"` lists multiple matches and exits with code 2 when ambiguous.
5. `resolve_session_id "proj-abc123" "nonexistent"` exits with code 3.
6. `validate_session_exists` returns 0 for a session with events, 1 for a session directory with no events.

---

## Estimated Complexity: S
