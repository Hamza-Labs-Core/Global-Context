# Story 03: Storage Layer -- Task Index

**Story**: 03-storage-layer
**Total Tasks**: 15 (13 active, 1 deferred, 1 integration)
**Estimated Total Effort**: ~24-38 hours (~3-4 working days)

**Design Amendments Applied**: 1, 2, 3, 4. See `docs/DESIGN-AMENDMENTS.md`.

---

## Task List

| # | Task | File | Status | Complexity | Estimate |
|---|---|---|---|---|---|
| 01 | Shared Path Resolver and Constants Module | [01-shared-path-resolver.md](01-shared-path-resolver.md) | pending | S | 1-2 hours |
| 02 | Session ID Sanitization Function | [02-session-id-sanitization.md](02-session-id-sanitization.md) | pending | S | 1-2 hours |
| 03 | Session Directory Creation and Lock File Management | [03-session-directory-and-lock-files.md](03-session-directory-and-lock-files.md) | pending | S | 1-2 hours |
| 04 | Atomic Write Helper | [04-atomic-write-helper.md](04-atomic-write-helper.md) | pending | S | 2-3 hours |
| 05 | JSON Validation Helper | [05-json-validation-helper.md](05-json-validation-helper.md) | pending | S | 1-2 hours |
| 06 | Event File Writing (Envelope, Sequence, Session Metadata) | [06-event-file-writing.md](06-event-file-writing.md) | pending | L | 4-6 hours |
| 07 | Init Command | [07-init-command.md](07-init-command.md) | pending | M | 3-4 hours |
| 08 | Per-Session Metadata (session.json) | [08-per-session-metadata.md](08-per-session-metadata.md) | pending | S | 1-2 hours |
| 09 | Config File (config.json) Management | [09-config-file.md](09-config-file.md) | pending | S | 1-2 hours |
| 10 | Latest Session Symlink Management | [10-latest-session-symlink.md](10-latest-session-symlink.md) | pending | S | 1-2 hours |
| 11 | Projection Directory and File Scaffolding | [11-projection-directory-scaffolding.md](11-projection-directory-scaffolding.md) | pending | M | 2-3 hours |
| 12 | gc-cleanup Command | [12-gc-cleanup.md](12-gc-cleanup.md) | **DEFERRED** | M | -- |
| 13 | gc-query store-size Command | [13-gc-query-store-size.md](13-gc-query-store-size.md) | pending | S | 2-3 hours |
| 14 | Rejected Event Handling | [14-rejected-event-handling.md](14-rejected-event-handling.md) | pending | S | 1-2 hours |
| 15 | Integration Test Suite | [15-integration-test-suite.md](15-integration-test-suite.md) | pending | L | 6-8 hours |

---

## Dependency Graph

```
Task 01: Shared Path Resolver + Project ID Derivation
  |
  +---> Task 02: Session ID Sanitization
  |       |
  |       +---> Task 03: Session Directory + Lock Files [C-1]
  |               |
  |               +---> Task 06: Event File Writing + session.json update
  |               |
  |               +---> Task 14: Rejected Event Handling
  |
  +---> Task 04: Atomic Write Helper [M-3]
  |       |
  |       +---> Task 06: Event File Writing
  |       +---> Task 07: Init Command [M-4]
  |       +---> Task 08: Per-Session Metadata (session.json)
  |       +---> Task 09: Config File
  |       +---> Task 11: Projection Scaffolding
  |       +---> Task 14: Rejected Event Handling
  |
  +---> Task 05: JSON Validation
  |       |
  |       +---> Task 06: Event File Writing
  |
  +---> Task 10: Latest Symlink (per-project)
  |
  +---> Task 09: Config File
          |
          +---> Task 07: Init Command
          +---> Task 13: gc-query store-size

Task 15: Integration Tests (depends on all active tasks)
```

---

## Implementation Order

The tasks should be implemented in this order. Tasks at the same order position can be parallelized where noted.

| Order | Task | Depends On | Review Issue |
|---|---|---|---|
| 1 | Task 01: Shared Path Resolver + Project ID | -- | M-4, Amendment 3 |
| 2 | Task 02: Session ID Sanitization | Task 01 | M-2 |
| 3 | Task 04: Atomic Write Helper | Task 01 | M-3 |
| 4 | Task 05: JSON Validation | (jq) | -- |
| 5 | Task 03: Session Directory + Lock Files | Tasks 01, 02 | C-1 |
| 6 | Task 09: Config File | Tasks 01, 04 | -- |
| 7 | Task 08: Per-Session Metadata | Tasks 01, 04 | Amendment 2 |
| 8 | Task 14: Rejected Event Handling | Tasks 01, 03, 04 | -- |
| 9 | Task 06: Event File Writing | Tasks 01-05, 08 | -- |
| 10 | Task 10: Latest Symlink (per-project) | Task 01 | Amendment 3 |
| 11 | Task 11: Projection Scaffolding | Tasks 01, 04 | -- |
| 12 | Task 07: Init Command | Tasks 01, 04, 09 | M-4 |
| 13 | Task 13: gc-query store-size | Tasks 01, 08, 09 | -- |
| 14 | Task 15: Integration Tests | All active tasks | -- |

**Parallelization notes**: Tasks 04 and 05 can be implemented in parallel. Tasks 10 and 11 can be implemented in parallel.

---

## Review Issues Addressed

| Issue | Resolution | Owner Task |
|---|---|---|
| **C-1**: Lock file naming | Canonicalized on `.lock` (not `_seq.lock`). Story 01 must be updated to reference this. | Task 03 |
| **C-2**: sessions.json schema | Superseded by Amendment 2: global sessions.json removed. Per-session `session.json` with focused schema. | Task 08 |
| **M-2**: Session ID sanitization | Canonical rules defined in Task 02. Only `[a-zA-Z0-9_-]` allowed. All other characters stripped (using `tr -cd`). Story 01 must call this function, not re-implement. | Task 02 |
| **M-3**: Atomic write pattern | Canonical pattern defined: temp file (`{target}.tmp.{pid}`) + optional fsync + rename. All stories must use `gc_atomic_write()`. | Task 04 |
| **M-4**: CLAUDE_CONTEXT_PATH env var | All path resolution goes through `paths.sh` which respects `CLAUDE_CONTEXT_PATH`. No script hardcodes `~/.claude-context`. | Task 01 |
