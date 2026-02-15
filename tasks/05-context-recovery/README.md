# Story 05: Context Recovery & Retrieval -- Task Index

**Source Plan**: `/home/meywd/GlobalContext/plans/05-context-recovery-plan.md`
**Total Tasks**: 20
**Estimated Effort**: 8-12 days (single developer), 5-7 days (two developers)

---

## Task List

| # | Task | File | Status | Complexity | Dependencies |
|---|------|------|--------|------------|-------------|
| 01 | Shared Store Path Resolution Helper | [01-shared-store-path-resolution-helper.md](01-shared-store-path-resolution-helper.md) | Pending | S | Story 03, Task 1 |
| 02 | Per-Session session.json Read Model | [02-per-session-session-json-read-model.md](02-per-session-session-json-read-model.md) | Pending | S | Task 01 |
| 03 | gc-query Entry Point and Argument Parser | [03-gc-query-entry-point-and-argument-parser.md](03-gc-query-entry-point-and-argument-parser.md) | Pending | M | Task 01 |
| 04 | Projection Staleness Check (_last_sequence) | [04-projection-staleness-check.md](04-projection-staleness-check.md) | Pending | S | Task 01, Story 04 |
| 05 | Session Resolution Helpers | [05-session-resolution-helpers.md](05-session-resolution-helpers.md) | Pending | S | Task 01 |
| 06 | gc-query status Command | [06-gc-query-status-command.md](06-gc-query-status-command.md) | Pending | S | Tasks 03, 04 |
| 07 | gc-query events Command | [07-gc-query-events-command.md](07-gc-query-events-command.md) | Pending | S | Tasks 03, 05 |
| 08 | gc-query tail Command | [08-gc-query-tail-command.md](08-gc-query-tail-command.md) | Pending | S | Task 07 |
| 09 | Context Projection Builder Integration | [09-context-projection-builder-integration.md](09-context-projection-builder-integration.md) | Pending | M | Task 04, Story 04 |
| 10 | Output Formatters (Markdown, Text, Compact, JSON) | [10-output-formatters.md](10-output-formatters.md) | Pending | L | Task 09 |
| 11 | gc-query last Command | [11-gc-query-last-command.md](11-gc-query-last-command.md) | Pending | M | Tasks 05, 09, 10 |
| 12 | gc-query session Command | [12-gc-query-session-command.md](12-gc-query-session-command.md) | Pending | S | Tasks 05, 09, 10 |
| 13 | Cross-Session Chaining (--include-parent) | [13-cross-session-chaining.md](13-cross-session-chaining.md) | Pending | M | Tasks 09, 10 |
| 14 | PreCompact Hook -- Eager Projection Build | [14-precompact-hook-eager-projection-build.md](14-precompact-hook-eager-projection-build.md) | Pending | M | Task 09, Story 02, Story 04 |
| 15 | SessionStart Hook -- Automatic Context Injection | [15-sessionstart-hook-automatic-context-injection.md](15-sessionstart-hook-automatic-context-injection.md) | Pending | L | Tasks 01, 10, 14 |
| 16 | gc-query sessions Command | [16-gc-query-sessions-command.md](16-gc-query-sessions-command.md) | Pending | M | Tasks 02, 03 |
| 17 | gc-query search Command | [17-gc-query-search-command.md](17-gc-query-search-command.md) | Pending | L | Tasks 03, 05 |
| 18 | gc-query replay Command | [18-gc-query-replay-command.md](18-gc-query-replay-command.md) | Pending | M | Tasks 03, 05, 07 |
| 19 | gc-query doctor Command | [19-gc-query-doctor-command.md](19-gc-query-doctor-command.md) | Pending | M | Tasks 01, 03 |
| 20 | Edge Case Handling and Error Hardening | [20-edge-case-handling-and-error-hardening.md](20-edge-case-handling-and-error-hardening.md) | Pending | M | All (01-19) |

---

## Complexity Summary

| Complexity | Count | Tasks |
|------------|-------|-------|
| S (Small)  | 7     | 01, 02, 04, 05, 07, 08, 12 |
| M (Medium) | 9     | 03, 06, 09, 11, 13, 14, 18, 19, 20 |
| L (Large)  | 2 (+2) | 10, 15 (+ 17 is L in plan but listed as L here too) |

> Note: The plan lists Tasks 10, 15, 17 as Large. Tasks 3, 6, 9, 11, 13, 14, 18, 19, 20 as Medium. Tasks 1, 2, 4, 5, 7, 8, 12 as Small.

---

## Implementation Order

### Phase 1: Foundation (Tasks 01-05)

Tasks 01 and 02 can be done in parallel (no shared dependencies).
Tasks 04 and 05 can be done in parallel (both depend only on Task 01).

```
Task 01: Store path helper                    [no deps]           -> Pending
Task 02: Per-session session.json read model  [no deps]           -> Pending
Task 03: gc-query entry point + arg parser    [depends: 01]       -> Pending
Task 04: Projection staleness check           [depends: 01]       -> Pending
Task 05: Session resolution helpers           [depends: 01]       -> Pending
```

### Phase 2: Simple Commands (Tasks 06-08)

Tasks 06 and 07 can be done in parallel.

```
Task 06: gc-query status                      [depends: 03, 04]   -> Pending
Task 07: gc-query events                      [depends: 03, 05]   -> Pending
Task 08: gc-query tail                        [depends: 07]       -> Pending
```

### Phase 3: Core Recovery (Tasks 09-12)

```
Task 09: Context projection loader            [depends: 04]       -> Pending
Task 10: Output formatters (md/text/compact)  [depends: 09]       -> Pending
Task 11: gc-query last                        [depends: 05, 09, 10] -> Pending
Task 12: gc-query session                     [depends: 05, 09, 10] -> Pending
```

### Phase 4: Advanced Features (Tasks 13-18)

Tasks 14 and 16-18 can be done in parallel.
Tasks 16, 17, 18 can be done in parallel (independent commands).

```
Task 13: Cross-session chaining               [depends: 09, 10]   -> Pending
Task 14: PreCompact hook (eager build)        [depends: 09]       -> Pending
Task 15: SessionStart hook (auto inject)      [depends: 10, 14]   -> Pending
Task 16: gc-query sessions                    [depends: 02, 03]   -> Pending
Task 17: gc-query search                      [depends: 03, 05]   -> Pending
Task 18: gc-query replay                      [depends: 03, 05, 07] -> Pending
```

### Phase 5: Polish (Tasks 19-20)

```
Task 19: gc-query doctor                      [depends: 01, 03]   -> Pending
Task 20: Edge case hardening                  [depends: all]      -> Pending
```

---

## Dependency Graph

```
Task 01 (store-path.sh)
  |
  +-- Task 03 (gc-query entry point)
  |     |
  |     +-- Task 06 (status) -------- Task 04 (staleness check)
  |     |
  |     +-- Task 07 (events) -------- Task 05 (session resolve)
  |     |     |
  |     |     +-- Task 08 (tail)
  |     |
  |     +-- Task 16 (sessions) ----- Task 02 (session read model)
  |     +-- Task 17 (search) ------- Task 05
  |     +-- Task 18 (replay) ------- Task 05, Task 07
  |     +-- Task 19 (doctor)
  |
  +-- Task 04 (staleness)
  |     |
  |     +-- Task 09 (context loader)
  |           |
  |           +-- Task 10 (formatters)
  |           |     |
  |           |     +-- Task 11 (last) ----------- Task 05
  |           |     +-- Task 12 (session) -------- Task 05
  |           |     +-- Task 13 (chaining)
  |           |     +-- Task 15 (SessionStart hook) -- Task 14
  |           |
  |           +-- Task 14 (PreCompact hook)
  |
  +-- Task 05 (session resolve)

Task 20 (edge cases) -- depends on all above
```

---

## Prerequisites (from other stories)

These must be complete before starting Story 05:

- **Story 01** (Event Capture): `capture-event` script exists and writes events
- **Story 02** (Hook Integration): `gc-hook` wrapper and hook configuration in place
- **Story 03** (Storage Layer): Directory structure, per-session `session.json`, per-project `latest` symlink, `.lock` files, `config.json`, and `src/lib/paths.sh`
- **Story 04** (Projection Engine): `project` CLI and all five projection handlers implemented

---

## Review Fixes Incorporated

| Fix ID | Issue | Addressed In |
|--------|-------|-------------|
| **C-2** | sessions.json schema mismatch | Task 02 (Amendment 2: per-session read model) |
| **C-4** | Compaction-to-recovery flow undefined | Tasks 14, 15 (PreCompact + SessionStart hooks) |
| **M-4** | CLAUDE_CONTEXT_PATH env var not respected | Task 01 (reuse paths.sh) |
| **M-6** | Staleness check uses unreliable mtime | Task 04 (_last_sequence comparison) |
| **G-3** | No gc-query doctor command | Task 19 (gc-query doctor) |
