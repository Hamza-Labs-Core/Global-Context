# Story 06: Plugin Packaging -- Task Index

**Plan**: [plans/06-plugin-packaging-plan.md](/home/meywd/GlobalContext/plans/06-plugin-packaging-plan.md)
**Estimated Total Effort**: ~6 days (24-32 hours)
**Prerequisites**: Stories 01-05 must be implementation-ready

---

## Tasks

| # | Task | File | Status | Complexity | Dependencies |
|---|------|------|--------|------------|--------------|
| 01 | Plugin Manifest and Directory Scaffold | [01-plugin-manifest-scaffold.md](01-plugin-manifest-scaffold.md) | pending | S | None |
| 02 | Hook Configuration (hooks.json) | [02-hook-configuration.md](02-hook-configuration.md) | pending | M | Task 01 |
| 03 | Capture Event Script Adaptation | [03-capture-script-adaptation.md](03-capture-script-adaptation.md) | pending | M | Task 01, Task 08 |
| 04 | Auto-Init on First Use | [04-auto-init-first-use.md](04-auto-init-first-use.md) | pending | S | Task 01, Task 03 |
| 05 | Command Files (gc-query as Slash Commands) | [05-command-files.md](05-command-files.md) | pending | M | Task 01 |
| 06 | Context Recovery Skill | [06-context-recovery-skill.md](06-context-recovery-skill.md) | pending | S | Task 01 |
| 07 | Context Recovery Agent | [07-context-recovery-agent.md](07-context-recovery-agent.md) | pending | S | Task 01 |
| 08 | Shared Library Bundling | [08-shared-library-bundling.md](08-shared-library-bundling.md) | pending | L | Task 01 |
| 09 | Marketplace Configuration | [09-marketplace-configuration.md](09-marketplace-configuration.md) | pending | S | Task 01 |
| 10 | Integration Tests | [10-integration-tests.md](10-integration-tests.md) | pending | L | All (Tasks 01-09) |

---

## Implementation Order (Recommended)

| Phase | Tasks | Milestone |
|-------|-------|-----------|
| **Phase 1: Scaffold** | 01 | Plugin directory structure exists |
| **Phase 2: Core Infrastructure** | 02, 08 | Hooks defined, libraries bundled |
| **Phase 3: Script Adaptation** | 03, 04 | Scripts work from plugin root, auto-init works |
| **Phase 4: User Interface** | 05, 06, 07 | Commands, skill, and agent defined |
| **Phase 5: Distribution** | 09 | Marketplace config, README, LICENSE |
| **Phase 6: Validation** | 10 | All integration tests pass |

### Parallelization Notes

- Tasks 02 and 08 can be done in parallel (hooks.json is pure data; library bundling is file copying + path adaptation).
- Tasks 05, 06, and 07 can be done in parallel (commands, skill, and agent are independent markdown files).
- Task 09 can be done in parallel with Tasks 05, 06, 07 (marketplace config is independent).
- Task 10 must wait for all other tasks.

---

## Dependency Graph

```
Task 01 (Plugin Manifest + Scaffold)
  |
  +---> Task 02 (Hook Configuration)
  |       |
  |       +---> Task 03 (Capture Script Adaptation)
  |       |       |
  |       |       +---> Task 04 (Auto-Init on First Use)
  |       |
  |       +---> Task 08 (Shared Library Bundling) [also independent]
  |
  +---> Task 05 (Command Files)
  |
  +---> Task 06 (Context Recovery Skill)
  |
  +---> Task 07 (Context Recovery Agent)
  |
  +---> Task 08 (Shared Library Bundling)
  |
  +---> Task 09 (Marketplace Configuration)
  |
  +---> Task 10 (Integration Tests) [depends on all above]
```

---

## Complexity Summary

| Complexity | Count | Tasks |
|------------|-------|-------|
| S (Small) | 5 | 01, 04, 06, 07, 09 |
| M (Medium) | 3 | 02, 03, 05 |
| L (Large) | 2 | 08, 10 |
