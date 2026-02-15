# Story 02: Hook Integration Layer -- Task Index

**Story**: 02-hook-integration
**Source Plan**: `/home/meywd/GlobalContext/plans/02-hook-integration-plan.md`
**Depends on**: Story 01 (Event Capture -- `capture-event` must exist and be executable)

---

## Tasks

| # | Task | File | Status | Complexity | Dependencies |
|---|------|------|--------|------------|--------------|
| 01 | Create `gc-hook` Wrapper Script | [01-gc-hook-wrapper.md](01-gc-hook-wrapper.md) | Pending | S | None |
| 02 | Create `gc-hook` Unit Test Suite | [02-gc-hook-unit-tests.md](02-gc-hook-unit-tests.md) | Pending | S | Task 01 |
| 03 | Add `CLAUDE_CONTEXT_PATH` Support (M-4) | [03-claude-context-path-support.md](03-claude-context-path-support.md) | Pending | S | Task 01 |
| 04 | Define Hook Configuration Data Structure | [04-hook-config-data-structure.md](04-hook-config-data-structure.md) | Pending | S | None |
| 05 | Implement `gc-install-hooks` -- Install | [05-gc-install-hooks-install.md](05-gc-install-hooks-install.md) | Pending | L | Task 01, Task 04 |
| 06 | Implement `gc-install-hooks` -- Uninstall | [06-gc-install-hooks-uninstall.md](06-gc-install-hooks-uninstall.md) | Pending | M | Task 05 |
| 07 | Implement `gc-install-hooks` -- Validate | [07-gc-install-hooks-validate.md](07-gc-install-hooks-validate.md) | Pending | M | Task 05, Task 01, Story 01 |
| 08 | Create Integration Test Suite | [08-integration-test-suite.md](08-integration-test-suite.md) | Pending | L | Task 01, Task 05, Task 06, Task 07 |
| 09 | Deployment Integration with Story 01 | [09-deployment-integration.md](09-deployment-integration.md) | Pending | S | Task 01, Task 05, Story 01 |
| 10 | Document Hook Payload Structures (M-5) | [10-hook-payload-docs.md](10-hook-payload-docs.md) | Pending | M | None |
| 11 | Add Debug Logging to gc-hook (G-4) | [11-debug-logging.md](11-debug-logging.md) | Pending | S | Task 01 |
| 12 | Create gc-uninstall Command (G-5) | [12-gc-uninstall.md](12-gc-uninstall.md) | Pending | S | Task 01, Task 06 |

---

## Implementation Order

Tasks are grouped into phases. All tasks within a phase can be worked in parallel. Phases must be completed sequentially.

| Phase | Tasks | Rationale |
|-------|-------|-----------|
| 1 | Task 01, Task 04, Task 10 | Independent foundations: wrapper script, config data, docs |
| 2 | Task 02, Task 03, Task 11 | Test and harden gc-hook, add debug logging |
| 3 | Task 05 | Core install logic (depends on Task 01 and Task 04) |
| 4 | Task 06, Task 07 | Uninstall and validate (depend on Task 05) |
| 5 | Task 12 | Full uninstall command (depends on Task 06) |
| 6 | Task 08 | Integration tests (depend on Tasks 05, 06, 07, 11, 12) |
| 7 | Task 09 | Deployment wiring (final step, depends on everything) |

---

## Dependency Graph

```
Task 01: gc-hook wrapper
  |
  +---> Task 02: gc-hook unit tests
  |
  +---> Task 03: CLAUDE_CONTEXT_PATH support (M-4)
  |
  +---> Task 05: gc-install-hooks install
  |       |
  |       +---> Task 06: gc-install-hooks uninstall
  |       |       |
  |       |       +---> Task 12: gc-uninstall [G-5] (needs 06)
  |       |
  |       +---> Task 07: gc-install-hooks validate
  |       |
  |       +---> Task 08: Integration tests (needs 05, 06, 07, 11, 12)
  |       |
  |       +---> Task 09: Deployment integration (needs 01, 05)
  |
  +---> Task 11: Debug logging [G-4] (needs 01)
  |
  Task 04: Hook config data structure (independent)
  |
  +---> Task 05 (consumed by install logic)

  Task 10: Payload documentation (independent, can run in parallel)
```

---

## Review Fixes Addressed

| Review Issue | Task | Description |
|--------------|------|-------------|
| C-3 | Task 01, Task 02 | gc-hook wrapper clearly defined and created in Story 02 |
| M-4 | Task 03 | Support `CLAUDE_CONTEXT_PATH` env var in gc-hook |
| M-5 | Task 10 | Document hook payload structures |
| G-4 | Task 11 | Debug logging for async hook stderr |
| G-5 | Task 12 | Full system uninstall command |

---

## Files Produced by This Story

### Created

| File | Task | Purpose |
|------|------|---------|
| `src/gc-hook` | 01, 11 | Hook wrapper script (deployed to `~/.claude-context/bin/gc-hook`) |
| `src/hook-config.json` | 04 | Canonical hook configuration data |
| `src/gc-install-hooks` | 05, 06, 07 | Hook lifecycle manager (deployed to `~/.claude-context/bin/gc-install-hooks`) |
| `src/lib/debug_log.sh` | 11 | Debug logging helper (deployed to `~/.claude-context/lib/debug_log.sh`) |
| `src/bin/gc-uninstall` | 12 | Full system uninstall (deployed to `~/.claude-context/bin/gc-uninstall`) |
| `tests/02-gc-hook-tests.sh` | 02 | Unit tests for gc-hook |
| `tests/02-debug-log-tests.sh` | 11 | Debug logging tests |
| `tests/02-uninstall-tests.sh` | 12 | Uninstall tests |
| `tests/02-integration-tests.sh` | 08 | Integration tests for full install lifecycle |
| `docs/HOOK-PAYLOADS.md` | 10 | Hook payload reference documentation |

### Modified

| File | Task | Change |
|------|------|--------|
| `src/install.sh` | 09 | Add gc-hook and gc-install-hooks deployment steps |
