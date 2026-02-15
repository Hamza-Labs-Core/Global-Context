# Task 12: gc-cleanup Command

## DEFERRED

> **This task is DEFERRED per Design Amendment 4.**
>
> **Reason**: Retention-based deletion contradicts the append-only principle of the event store. The event store is designed as an append-only log, and introducing cleanup/deletion undermines this fundamental design guarantee.
>
> Disk usage is monitored by `gc-query store-size` (Task 13) and `gc-query doctor` (Plan 05). If cleanup is needed in the future, it will be added as a separate story with its own design review.
>
> See `docs/DESIGN-AMENDMENTS.md` -- Amendment 4 for full rationale.

**Story**: 03-storage-layer
**Status**: DEFERRED (Amendment 4)
**Estimated Complexity**: M (Medium) -- DEFERRED

---

## Original Scope (for reference only -- do not implement)

This task was originally planned to implement a `gc-cleanup` command that would delete sessions older than a configurable retention period. The following was the original scope:

- A `gc-cleanup` command that scans sessions and deletes those older than `retention_days`.
- Integration with `config.json` for `retention_days` setting.
- Safe deletion with dry-run mode.

This scope is no longer planned. The `retention_days` config field has also been removed from Task 09 (config.json).

---

## Dependencies

N/A (deferred)

---

## Acceptance Tests

N/A (deferred)
