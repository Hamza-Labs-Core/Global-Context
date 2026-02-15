# Task 15: Integration Test Suite

**Story**: 03-storage-layer
**Status**: Pending
**Estimated Complexity**: L (Large) -- 6-8 hours

---

## Description

Write end-to-end integration tests that exercise the full storage layer: init, write events, update per-session session.json, manage projections, and handle concurrent operations.

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `tests/integration/test_storage_layer.sh` | Create | Full integration test suite |
| `tests/integration/test_concurrent_writes.sh` | Create | Concurrency stress tests |
| `tests/integration/test_crash_recovery.sh` | Create | Crash recovery and orphan cleanup |

---

## Specification

### test_storage_layer.sh

1. **Init and verify**: Run gc-init, verify all directories and files. Verify no sessions.json or .sessions.lock.
2. **Write and read back**: Write 100 events across 3 sessions (2 projects), verify all files with project-id paths.
3. **Per-session metadata**: Verify each session has its own `session.json` with correct `event_count`.
4. **Latest symlink**: Verify per-project symlinks point to the last session started in each project.
5. **Projection scaffolding**: Write a projection, verify metadata (including `_project_id`), check staleness.
6. **Config**: Verify config.json, test read operations, verify no `retention_days` or `max_event_size_bytes`.
7. **Store size**: Run gc-query store-size, verify counts across projects.
8. **Idempotent init**: Run gc-init again, verify no data loss.
9. **CLAUDE_CONTEXT_PATH**: Run entire suite against a custom path.

### test_concurrent_writes.sh

1. Spawn 20 parallel `gc_write_event` calls for the same session.
2. Verify: 20 event files exist, sequence numbers 1-20, no gaps, no duplicates.
3. Verify: `session.json` `event_count` is 20 after all writes complete.
4. Repeat with 5 different sessions concurrently (across 2 projects).
5. Verify: each session's `session.json` has correct independent `event_count`.

### test_crash_recovery.sh

1. Create orphan temp files (`*.tmp.*`) in event directories.
2. Run gc-init -- verify orphan files are deleted.
3. Write an event to `_rejected/` -- verify it does not affect normal operations.
4. Simulate flock timeout -- verify orphan event file is created.

---

## Dependencies

- **All previous tasks (1-14)**:
  - `/home/meywd/GlobalContext/tasks/03-storage-layer/01-shared-path-resolver.md`
  - `/home/meywd/GlobalContext/tasks/03-storage-layer/02-session-id-sanitization.md`
  - `/home/meywd/GlobalContext/tasks/03-storage-layer/03-session-directory-and-lock-files.md`
  - `/home/meywd/GlobalContext/tasks/03-storage-layer/04-atomic-write-helper.md`
  - `/home/meywd/GlobalContext/tasks/03-storage-layer/05-json-validation-helper.md`
  - `/home/meywd/GlobalContext/tasks/03-storage-layer/06-event-file-writing.md`
  - `/home/meywd/GlobalContext/tasks/03-storage-layer/07-init-command.md`
  - `/home/meywd/GlobalContext/tasks/03-storage-layer/08-per-session-metadata.md`
  - `/home/meywd/GlobalContext/tasks/03-storage-layer/09-config-file.md`
  - `/home/meywd/GlobalContext/tasks/03-storage-layer/10-latest-session-symlink.md`
  - `/home/meywd/GlobalContext/tasks/03-storage-layer/11-projection-directory-scaffolding.md`
  - `/home/meywd/GlobalContext/tasks/03-storage-layer/13-gc-query-store-size.md`
  - `/home/meywd/GlobalContext/tasks/03-storage-layer/14-rejected-event-handling.md`

  (Task 12 is deferred and excluded.)

---

## Acceptance Tests

All test scripts exit with code 0. Specific pass/fail output for each test case.
