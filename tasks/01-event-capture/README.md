# Story 01: Event Capture System -- Task Index

**Story**: 01-event-capture
**Total Tasks**: 12
**Estimated Total Effort**: ~3 days (12-16 hours)
**Source Plan**: `/home/meywd/GlobalContext/plans/01-event-capture-plan.md`

---

## Task List

| # | Task | File | Status | Complexity | Dependencies |
|---|------|------|--------|------------|--------------|
| 01 | Base Directory Resolution | [01-base-dir-resolution.md](01-base-dir-resolution.md) | Pending | S | None |
| 02 | Directory Structure and install.sh | [02-directory-structure-and-install.md](02-directory-structure-and-install.md) | Pending | M | Task 01 |
| 03 | Session ID Sanitization | [03-session-id-sanitization.md](03-session-id-sanitization.md) | Pending | S | Task 01, Task 04 (soft) |
| 04 | UUID v4 Generation | [04-uuid-generation.md](04-uuid-generation.md) | Pending | S | Task 01 |
| 05 | Timestamp Generation | [05-timestamp-generation.md](05-timestamp-generation.md) | Pending | S | Task 01 |
| 06 | Sequence Numbering and Locking | [06-sequence-numbering-and-locking.md](06-sequence-numbering-and-locking.md) | Pending | M | Task 01, Task 03 |
| 07 | Atomic Write Helper | [07-atomic-write-helper.md](07-atomic-write-helper.md) | Pending | S | Task 01 |
| 08 | Event Envelope Construction | [08-envelope-construction.md](08-envelope-construction.md) | Pending | M | Task 04, Task 05, Task 06 |
| 09 | Main Script Assembly | [09-main-script-assembly.md](09-main-script-assembly.md) | Pending | M | Tasks 01-08 |
| 10 | Error Handling and Safety | [10-error-handling-and-safety.md](10-error-handling-and-safety.md) | Pending | S | Task 09 |
| 11 | Performance Validation | [11-performance-validation.md](11-performance-validation.md) | Pending | S | Task 09, Task 10 |
| 12 | Integration Test Suite | [12-integration-test-suite.md](12-integration-test-suite.md) | Pending | L | Task 02, Task 09, Task 10 |

---

## Dependency Graph

```
Task 01 (Base Dir Resolution)
  |
  v
Task 02 (Directory Structure + install.sh)
  |
  v
Task 03 (Session ID Sanitization)
  |
  +---> Task 04 (UUID Generation)
  |       |
  |       v
  +---> Task 05 (Timestamp Generation)
  |       |
  |       v
  +---> Task 06 (Sequence Numbering + Locking)
          |
          v
        Task 07 (Atomic Write Helper)
          |
          v
        Task 08 (Envelope Construction)
          |
          v
        Task 09 (Main Script Assembly)
          |
          v
        Task 10 (Error Handling + Safety)
          |
          v
        Task 11 (Performance Validation)
          |
          v
        Task 12 (Integration Test Suite)
```

---

## Implementation Order (Recommended Phases)

| Phase | Tasks | Milestone |
|-------|-------|-----------|
| **Phase 1: Foundation** | 01, 02 | Directory structure exists, install works |
| **Phase 2: Core Functions** | 03, 04, 05 | Utility functions implemented and testable in isolation |
| **Phase 3: Write Path** | 06, 07, 08 | Sequence numbering, atomic writes, envelope construction |
| **Phase 4: Integration** | 09, 10 | Complete script assembled with error handling |
| **Phase 5: Validation** | 11, 12 | Performance verified, all acceptance criteria pass |

---

## Review Issues Incorporated

| Issue | Summary | Resolution |
|-------|---------|------------|
| C-1 | Lock file naming | Standardized on `.lock` (Task 06) |
| C-5 | UUID fallback generates non-standard IDs | Bash-native RFC 4122 UUID v4 fallback (Task 04) |
| M-2 | Sanitization rules differ | Adopted Story 03's stricter rules (Task 03) |
| M-3 | Atomic write pattern inconsistency | Temp file + rename pattern with selective fsync (Task 07) |
| M-4 | CLAUDE_CONTEXT_PATH not supported | Inline pattern in all scripts (Task 01) |

---

## Design Amendments Applied

- **Amendment 2**: Per-session session.json (affects Task 06, Task 09)
- **Amendment 3**: Project-ID directory layer -- `events/{project-id}/{session-id}/` (affects Task 06, Task 08, Task 09)

---

## Files Produced by This Story

| File | Task(s) |
|------|---------|
| `src/capture-event` | 01, 03, 04, 05, 06, 07, 08, 09, 10 |
| `src/install.sh` | 01, 02 |
| `tests/01-event-capture-test.sh` | 12 |
| `tests/perf-test.sh` | 11 |
| `docs/CONVENTIONS.md` | 01 |
