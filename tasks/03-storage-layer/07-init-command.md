# Task 07: Init Command

**Story**: 03-storage-layer
**Status**: Pending
**Estimated Complexity**: M (Medium) -- 3-4 hours

---

## Description

Implement the `init` command that creates the full directory structure, configuration files, lock files, and validates the filesystem. Must be idempotent -- safe to run repeatedly without data loss.

This incorporates review issue **M-4** by using the shared path resolver from Task 1.

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/bin/gc-init` | Create | Init command script |
| `tests/bin/test_gc_init.sh` | Create | Init idempotency and correctness tests |

---

## Specification

Invocation: `gc-init` (no arguments)

Process:

```
 1. Source paths.sh to resolve GC_ROOT
 2. Print: "Initializing GlobalContext store at $GC_ROOT"
 3. Create root directory:    mkdir -p "$GC_ROOT" && chmod 700 "$GC_ROOT"
 4. Create events/:           mkdir -p "$GC_EVENTS_DIR" && chmod 700 "$GC_EVENTS_DIR"
 5. Create projections/:      mkdir -p "$GC_PROJECTIONS_DIR" && chmod 700 "$GC_PROJECTIONS_DIR"
 6. Create bin/:              mkdir -p "$GC_BIN_DIR" && chmod 755 "$GC_BIN_DIR"
 7. Create config.json:       if [ ! -f "$GC_CONFIG_FILE" ]; then
                                  write default config (see Task 9)
                                  chmod 600 "$GC_CONFIG_FILE"
                               fi
 8. Install bin/ scripts:     copy capture-event, project, gc-query to bin/
                               chmod 755 on each (always overwrite for upgrades)
 9. Clean orphan temp files:  find "$GC_EVENTS_DIR" -name '*.tmp.*' -delete
10. Validate writability:     write and delete a test file in GC_ROOT
11. Validate disk space:      check >= 10MB free (df -P or similar)
12. Print summary:            list what was created vs what was skipped
13. Exit 0 on success, non-zero on failure
```

> **Amendment 1**: No global `sessions.json` or `.sessions.lock` is created. Per-session metadata is created lazily when the first event is written (Task 6/8).

Idempotency rules:

| Resource | If Exists | If Not Exists |
|---|---|---|
| Directories | Skip (mkdir -p handles this) | Create |
| `config.json` | Skip, print "already exists" | Create with defaults |
| `bin/*` scripts | Overwrite (to support upgrades) | Create |

---

## Dependencies

- **Task 01**: `/home/meywd/GlobalContext/tasks/03-storage-layer/01-shared-path-resolver.md` (paths.sh)
- **Task 04**: `/home/meywd/GlobalContext/tasks/03-storage-layer/04-atomic-write-helper.md` (atomic_write.sh, used for config.json initial write)
- **Task 09**: `/home/meywd/GlobalContext/tasks/03-storage-layer/09-config-file.md` (config.sh, for gc_config_create)

---

## Acceptance Tests

1. Run `gc-init` on clean system -- all directories and files created with correct permissions.
2. Verify `$GC_ROOT` has permission 700.
3. Verify `config.json` exists with all default fields.
4. Verify no `sessions.json` or `.sessions.lock` files exist (Amendment 1).
5. Verify `bin/` scripts are executable (755).
6. Run `gc-init` again -- output says "already exists" for config.json, no data overwritten.
7. Set `CLAUDE_CONTEXT_PATH=/tmp/gc-test` and run `gc-init` -- store created at `/tmp/gc-test/`.
8. Create a `*.tmp.*` file in events/ before init -- verify it is cleaned up.
9. Verify disk space check (test on a nearly full tmpfs if feasible).
10. Exit code is 0 on success.
