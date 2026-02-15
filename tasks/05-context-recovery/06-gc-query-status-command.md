# Task 06: gc-query status Command

**Story**: 05-context-recovery
**Complexity**: S (Small)
**Status**: Pending

---

## Description

Implement the `status` subcommand showing store health and statistics. This is the simplest query command and validates that the store is accessible.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_status` function) |

---

## Specification / Implementation Details

1. Derive project_id from current working directory using `gc_derive_project_id`.
2. Count session directories under `$GC_EVENTS_DIR/$project_id/` (project-scoped by default).
3. Count total `[0-9]*.json` event files across all sessions in the project.
4. Calculate disk usage via `du -sh "$GC_ROOT"`.
5. Read the latest session ID from the per-project `latest` symlink, then read its `session.json` for start time.
6. Count projection directories and determine how many are stale using `is_projection_current`.
7. Output in text format (default) or JSON format.
8. `--all-projects` flag shows store-wide totals across all projects.

---

## Dependencies

- [Task 03: gc-query Entry Point and Argument Parser](/home/meywd/GlobalContext/tasks/05-context-recovery/03-gc-query-entry-point-and-argument-parser.md) (gc-query entry point)
- [Task 04: Projection Staleness Check](/home/meywd/GlobalContext/tasks/05-context-recovery/04-projection-staleness-check.md) (staleness check)

---

## Acceptance Tests

1. `gc-query status` prints all required fields: total sessions, total events, disk usage, latest session, projections count.
2. Empty store: prints "Store is empty. No sessions recorded." and exits with code 0.
3. `gc-query status --format json` returns valid JSON with all fields.
4. Completes in under 3 seconds with 100+ sessions.

---

## Estimated Complexity: S
