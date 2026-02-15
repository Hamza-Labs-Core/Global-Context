# Story 04: Projection Engine (CQRS Read Side) -- Task Index

**Story**: 04-projection-engine
**Total Tasks**: 12
**Estimated Effort**: 47-79 hours
**Prerequisites**: Stories 01 (Event Capture) and 03 (Storage Layer) must be implemented first.

---

## Task List

| # | Task | File | Status | Complexity | Dependencies |
|---|------|------|--------|------------|--------------|
| 01 | Base Path Resolution and Shared Utilities | [01-base-path-resolution-and-shared-utilities.md](./01-base-path-resolution-and-shared-utilities.md) | pending | S | None |
| 02 | Projection Registry | [02-projection-registry.md](./02-projection-registry.md) | pending | S | 01 |
| 03 | Event Replay Engine | [03-event-replay-engine.md](./03-event-replay-engine.md) | pending | M | 01 |
| 04 | Files Touched Projection Handler | [04-files-touched-projection-handler.md](./04-files-touched-projection-handler.md) | pending | L | 01, 02, 03 |
| 05 | Timeline Projection Handler | [05-timeline-projection-handler.md](./05-timeline-projection-handler.md) | pending | M | 01, 02, 03 |
| 06 | Decisions Projection Handler | [06-decisions-projection-handler.md](./06-decisions-projection-handler.md) | pending | L | 01, 02, 03, 05 |
| 07 | Summary Projection Handler | [07-summary-projection-handler.md](./07-summary-projection-handler.md) | pending | M | 01, 02, 03 |
| 08 | Context Snapshot Projection Handler | [08-context-snapshot-projection-handler.md](./08-context-snapshot-projection-handler.md) | pending | L | 01, 02, 03, 05 |
| 09 | Output Format System and Shared Formatters | [09-output-format-system-and-shared-formatters.md](./09-output-format-system-and-shared-formatters.md) | pending | M | 01, 02 |
| 10 | Incremental Rebuild Logic | [10-incremental-rebuild-logic.md](./10-incremental-rebuild-logic.md) | pending | L | 03, 04, 05, 06, 07, 08 |
| 11 | CLI Entry Point (`project` script) | [11-cli-entry-point.md](./11-cli-entry-point.md) | pending | M | 01-10 (all) |
| 12 | Test Fixtures and Integration Tests | [12-test-fixtures-and-integration-tests.md](./12-test-fixtures-and-integration-tests.md) | pending | L | 01-11 (all) |

---

## Recommended Implementation Order

| Phase | Tasks | Deliverable |
|-------|-------|-------------|
| **Phase A: Foundation** | 01, 02, 03 | Replay engine and registry ready; can stream events through a handler |
| **Phase B: Core Projections** | 04, 05 (parallel) | Timeline and Files Touched projections working end-to-end |
| **Phase C: Advanced Projections** | 06, 07 (parallel) | Decisions and Summary projections working |
| **Phase D: Context + Formats** | 08, 09 | Context Snapshot with size management; all output formats |
| **Phase E: Integration** | 10, 11 | Incremental rebuild and CLI wiring |
| **Phase F: Validation** | 12 | Full test suite with fixtures and edge cases |

---

## Dependency Graph

```
Task 01 (Paths/Utils)
  |
  +---> Task 02 (Registry) --------+
  |                                |
  +---> Task 03 (Replay Engine) ---+---> Task 04  (Files Touched)
                                   |
                                   +---> Task 05  (Timeline + Summary Generators)
                                   |       |
                                   |       +---> Task 06  (Decisions)
                                   |       |
                                   |       +---> Task 08  (Context Snapshot)
                                   |
                                   +---> Task 07  (Summary)
                                   |
                                   +---> Task 09  (Output Format System)
                                   |
                                   +--- All handlers ---+
                                                        |
                                                        v
                                                  Task 10 (Incremental Rebuild)
                                                        |
                                                        v
                                                  Task 11 (CLI Entry Point)
                                                        |
                                                        v
                                                  Task 12 (Test Fixtures + Integration)
```

---

## Complexity Summary

| Complexity | Count | Estimate per task | Subtotal |
|------------|-------|-------------------|----------|
| S | 2 | 1-2 hours | 2-4 hours |
| M | 5 | 3-5 hours | 15-25 hours |
| L | 5 | 6-10 hours | 30-50 hours |
| **Total** | **12** | | **47-79 hours** |

---

## Review Issues Incorporated

| Issue | Title | Addressed In |
|-------|-------|-------------|
| G-1 | Duplicate event detection by `tool_use_id` | Task 03 (Replay Engine), Task 04 (Files Touched dedup) |
| G-2 | Extract file paths from `tool_response` too (Glob/Grep) | Task 04 (Files Touched projection) |
| M-1 | Define projection version 1 explicitly | Task 02 (Projection Registry), Task 10 (Incremental Rebuild) |
| M-4 | Support `CLAUDE_CONTEXT_PATH` env var | Task 01 (Base path resolution utility) |

## Design Amendments Incorporated

- **Amendment 3**: Project-ID directory layer. Path functions gain a `projectId` parameter. Per-project `latest` symlink at `projections/{projectId}/latest`. See `docs/DESIGN-AMENDMENTS.md`.
