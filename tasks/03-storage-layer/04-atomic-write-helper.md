# Task 04: Atomic Write Helper

**Story**: 03-storage-layer
**Status**: Pending
**Estimated Complexity**: S (Small) -- 2-3 hours

---

## Description

Implement the canonical atomic write function used by all file writes in the system (events, projections, session.json, config.json). This is a shared utility that writes to a temp file, optionally fsyncs, then renames atomically.

This directly addresses review issue **M-3** (canonical atomic write pattern).

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/atomic_write.sh` | Create | Atomic write function |
| `tests/lib/test_atomic_write.sh` | Create | Tests including crash simulation |

---

## Specification

Function: `gc_atomic_write(target_path, content, [fsync])`

Canonical pattern (all stories must use this):

```
1. Generate temp filename: {target}.tmp.{$$}
   Example: 000042.json.tmp.12345
2. Write complete content to temp file
3. If fsync=true: sync the temp file (using dd or python -c 'import os; os.fsync(...)')
4. mv (rename) temp file to target filename
5. If any step fails: remove temp file (best-effort), return non-zero
```

Parameters:

- `target_path` (required): The final destination file path.
- `content` (required): The content to write. Passed via stdin or as a variable.
- `fsync` (optional, default: `false`): Whether to fsync before rename. Set to `true` for sync hooks and critical writes (session.json). Set to `false` for async hooks where latency matters.

Design decisions:

- Temp file name includes PID (`$$`) for uniqueness across concurrent processes.
- The rename (`mv`) is atomic on POSIX-compliant filesystems (ext4, APFS, tmpfs).
- If the write fails (e.g., disk full), only the temp file is left -- the target file is untouched.
- Temp files matching `*.tmp.*` are orphans from interrupted writes and can be safely deleted.

---

## Dependencies

- **Task 01**: `/home/meywd/GlobalContext/tasks/03-storage-layer/01-shared-path-resolver.md` (paths.sh, for any shared constants)

---

## Acceptance Tests

1. Write a file using `gc_atomic_write` -- target file exists with correct content.
2. Write to a non-existent directory -- function returns non-zero, no partial file.
3. Simulate crash (kill -9 during write of large content) -- target file is either absent or contains previous content, never partial.
4. Two concurrent `gc_atomic_write` calls to the same target -- last writer wins, file is valid.
5. Verify temp file is cleaned up on success (no `*.tmp.*` files remain).
6. Test with `fsync=true` -- function still works (may be slightly slower).
