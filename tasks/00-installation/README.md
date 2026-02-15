# Story 00: Installation & Setup -- Task Index

**Source Plan**: `/home/meywd/GlobalContext/plans/00-installation-plan.md`
**Status**: Planning
**Estimated Total Effort**: ~23-34 hours (~3-4 working days)

---

## Tasks

| # | Task | File | Status | Complexity | Estimate |
|---|---|---|---|---|---|
| 01 | Prerequisites Checker | [01-prerequisites-checker.md](01-prerequisites-checker.md) | Pending | M (Medium) | 2-3 hours |
| 02 | gc-install Script | [02-gc-install-script.md](02-gc-install-script.md) | Pending | L (Large) | 4-6 hours |
| 03 | Source File Distribution | [03-source-file-distribution.md](03-source-file-distribution.md) | Pending | M (Medium) | 2-3 hours |
| 04 | Hook Registration Automation | [04-hook-registration-automation.md](04-hook-registration-automation.md) | Pending | S (Small) | 1-2 hours |
| 05 | gc-uninstall Script | [05-gc-uninstall-script.md](05-gc-uninstall-script.md) | Pending | M (Medium) | 2-3 hours |
| 06 | Upgrade Logic | [06-upgrade-logic.md](06-upgrade-logic.md) | Pending | M (Medium) | 2-3 hours |
| 07 | First-Run Verification (gc-doctor) | [07-first-run-verification.md](07-first-run-verification.md) | Pending | L (Large) | 4-6 hours |
| 08 | Integration Tests | [08-integration-tests.md](08-integration-tests.md) | Pending | L (Large) | 6-8 hours |

---

## Dependency Graph

```
Task 01: Prerequisites Checker
  |
  +---> Task 02: gc-install Script
  |       |
  |       +---> Task 03: Source File Distribution
  |       |       |
  |       |       +---> Task 06: Upgrade Logic (needs 02, 03)
  |       |
  |       +---> Task 04: Hook Registration Automation (needs 02)
  |       |
  |       +---> Task 07: First-Run Verification (needs 02, 04)
  |
  +---> Task 05: gc-uninstall Script (needs 01, 04)
  |
  +---> Task 08: Integration Tests (needs all)
```

---

## Recommended Implementation Order

| Phase | Tasks | Milestone |
|-------|-------|-----------|
| **Phase 1: Foundation** | Task 01 (Prerequisites Checker) | Can verify system readiness |
| **Phase 2: Core Scripts** | Task 03 (Source Distribution), Task 06 (Version Logic) | File deployment and version tracking defined |
| **Phase 3: Installer** | Task 02 (gc-install), Task 04 (Hook Registration) | Full install flow works end-to-end |
| **Phase 4: Lifecycle** | Task 05 (gc-uninstall) | Install + uninstall lifecycle complete |
| **Phase 5: Health Check** | Task 07 (gc-doctor) | System health can be verified |
| **Phase 6: Validation** | Task 08 (Integration Tests) | All scenarios tested |

Tasks 03 and 06 can be implemented in parallel (Phase 2). Tasks 02 and 04 can be partially parallelized (Task 04 depends on Task 02 existing but can be developed concurrently).

---

## Dependencies on Other Stories

This is the **bootstrapping story**. It orchestrates the outputs of all other stories:

- **Story 01** (Event Capture): `capture-event` is deployed to `bin/`
- **Story 02** (Hook Integration): `gc-hook`, `gc-install-hooks` are deployed to `bin/`, hooks are registered in `~/.claude/settings.json`
- **Story 03** (Storage Layer): `gc-init` creates directory structure and `config.json`
- **Story 04** (Projection Engine): `project` is deployed to `bin/`
- **Story 05** (Context Recovery): `gc-query` is deployed to `bin/`

---

## Amendment Impacts

- **Amendment 3** (Project-ID layer): `gc-init` creates `events/` and `projections/` without pre-creating project subdirectories (those are created lazily by `capture-event`). The `gc-doctor` health check verifies the project-id directory structure.
- **Amendment 4** (Remove gc-cleanup): No cleanup step in install or uninstall. The `gc-doctor` command reports disk usage as a diagnostic, not an actionable cleanup.

---

## File Summary

All file paths are relative to `/home/meywd/GlobalContext/`.

| File | Action | Task(s) |
|---|---|---|
| `src/lib/prerequisites.sh` | Create | 01 |
| `src/lib/deploy.sh` | Create | 03 |
| `src/lib/version.sh` | Create | 06 |
| `src/bin/gc-install` | Create | 02, 03, 04, 06 |
| `src/bin/gc-uninstall` | Create (or enhance from Story 02) | 05 |
| `src/bin/gc-doctor` | Create | 07 |
| `VERSION` | Create | 03 |
| `tests/lib/test_prerequisites.sh` | Create | 01 |
| `tests/lib/test_deploy.sh` | Create | 03 |
| `tests/lib/test_version.sh` | Create | 06 |
| `tests/bin/test_gc_install.sh` | Create | 02 |
| `tests/bin/test_gc_install_hooks_integration.sh` | Create | 04 |
| `tests/bin/test_gc_uninstall.sh` | Create | 05 |
| `tests/bin/test_gc_doctor.sh` | Create | 07 |
| `tests/00-install-fresh.sh` | Create | 08 |
| `tests/00-install-upgrade.sh` | Create | 08 |
| `tests/00-install-uninstall.sh` | Create | 08 |
| `tests/00-install-edge-cases.sh` | Create | 08 |
| `tests/00-install-all.sh` | Create | 08 |

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `jq` not available on target system | Medium | High (install fails) | Clear error message with platform-specific install instructions. jq is the only hard JSON dependency. |
| Conflicting `~/.claude/settings.json` modifications | Low | Medium (hooks lost) | Backup before every modification. `gc-install-hooks` is the single writer for GC hooks. |
| SRC_DIR detection fails in unusual directory layouts | Low | Medium (install fails) | `GC_SRC_DIR` env var override allows manual specification. Sanity check for `bin/capture-event`. |
| Version comparison fails on non-semver strings | Low | Low (false upgrade) | Treat unparseable versions as "0.0.0" (forces upgrade). |
| macOS compatibility (stat, sha256sum, flock differences) | Medium | Medium (doctor false failures) | Platform detection in prerequisites checker. Use `shasum -a 256` as fallback for `sha256sum`. Use `stat -f%z` as fallback for `stat -c%s`. |
| User runs gc-uninstall --purge accidentally | Low | High (data loss) | Confirmation prompt required (unless --force). Summary shows exact data that will be deleted. |
| Test isolation leaks to real HOME | Very Low | High (real data modified) | All tests override `$HOME` and `$CLAUDE_CONTEXT_PATH` to temp directories. Trap ensures cleanup. |

---

## Notes for Implementation

1. **gc-install is the user-facing entry point** -- users should only need to run one command: `gc-install`. All other setup is orchestrated from there.
2. **gc-doctor is both automated and manual** -- it runs as part of `gc-install` (Task 07) and is available standalone for ongoing health monitoring.
3. **Idempotency is non-negotiable** -- every operation (install, upgrade, hook registration) must be safe to run repeatedly without data loss or duplication.
4. **CLAUDE_CONTEXT_PATH is respected everywhere** -- the base directory resolution pattern from Story 01/03 (`${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}`) must be used consistently in all new scripts.
5. **Soft uninstall is the default** -- `gc-uninstall` without `--purge` preserves all event data. Users who want to reinstall should not lose their history by default.
6. **The VERSION file is the single source of truth for versioning** -- it lives at the repo root and is copied to `$GC_BASE/VERSION` during install. No version is embedded in config.json (that field tracks the config schema version, not the software version).
7. **gc-doctor output must be deterministic** -- given the same system state, doctor should produce the same results. No random test IDs or timestamps in the pass/fail output (diagnostics section can include timestamps).
8. **Platform compatibility** -- all scripts must work on both Linux and macOS. Where command syntax differs (`stat`, `sha256sum`/`shasum`, `mv -fT`/`ln -sfn`), detect and adapt at runtime.
