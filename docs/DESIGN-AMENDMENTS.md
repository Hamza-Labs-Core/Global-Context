# Design Amendments

**Date**: 2026-02-14
**Status**: Approved
**Applies to**: All 5 stories and implementation plans

This document records design changes made after the initial story and plan reviews. All plans must incorporate these amendments.

---

## Amendment 1: Remove Global sessions.json

**Reason**: sessions.json was a shared write-side index updated on every event capture. This violated the CQRS principle ("write side is fast and dumb") by maintaining a materialized view on the hot path. It was the only shared resource in the system, introducing flock contention between concurrent sessions.

**Changes**:
- Remove `projections/sessions.json` from the storage layout
- Remove `projections/.sessions.lock` from the storage layout
- Remove all `gc_sessions_*` write-path functions from Plan 03
- Plan 03 Task 8 (Sessions Index) is replaced by Amendment 2 (per-session session.json)
- The `gc-query sessions` command (Plan 05 Task 16) scans event directories and reads per-session `session.json` files instead

---

## Amendment 2: Per-Session session.json

**Reason**: Session metadata should be per-session with zero shared state. The per-session `.lock` flock already exists for sequence coordination — session.json updates happen within the same lock scope, adding no new contention.

**Changes**:
- Each session directory contains a `session.json` file
- Created from the `SessionStarted` event (first event in a session)
- Updated on every subsequent event within the existing flock scope (increment `event_count`, update `last_event_at`, `last_event_type`)
- Extended by specific events: `SessionEnded` sets `ended_at`, `UserPromptReceived` updates `last_prompt`, `CompactionTriggered` updates state

**session.json schema**:

```json
{
  "session_id": "abc-123",
  "project_id": "my-project-a3f7b2",
  "project_dir": "/home/user/my-project",
  "started_at": "2026-02-14T10:00:00Z",
  "source": "manual",
  "model": "claude-opus-4-6",
  "event_count": 142,
  "last_event_at": "2026-02-14T11:30:00Z",
  "last_event_type": "TurnCompleted",
  "last_prompt": "Fix the auth bug in handler.ts",
  "ended_at": null,
  "previous_session_id": null
}
```

---

## Amendment 3: Project-ID Directory Layer

**Reason**: Events and projections should be organized by project for natural scoping. `gc-query last` from within a project should return that project's latest session without filtering. Cross-project queries remain possible by scanning all project directories.

**Changes**:

### Storage layout

```
events/{project-id}/{session-id}/session.json
events/{project-id}/{session-id}/.lock
events/{project-id}/{session-id}/000001.json

projections/{project-id}/{session-id}/context.json
projections/{project-id}/latest -> {session-id}
```

### Project ID derivation

Format: `{basename}-{hash6}` where:
- `basename` = last component of the project directory path (sanitized same as session IDs: `[a-zA-Z0-9_-]` only)
- `hash6` = first 6 hex characters of SHA-256 (or equivalent) of the full absolute path

Examples:
- `/home/user/my-project` → `my-project-a3f7b2`
- `/home/user/work/my-project` → `my-project-e91c04` (different hash, same basename)
- `/tmp/test` → `test-7f3a2b`

### Project detection

`gc-hook` extracts the project directory from the hook payload's `cwd` field (or `session.cwd`). If not present, falls back to `_unknown-000000`.

### Per-project latest symlink

Each project has its own `latest` symlink at `projections/{project-id}/latest`. The global `projections/latest` symlink is removed.

### Impact on gc-query

- `gc-query last`: Detects current working directory, derives project-id, scopes to that project
- `gc-query sessions`: Can list all projects or filter by `--project`
- `gc-query search`: Searches within a project by default, `--all-projects` to search globally

### Impact on paths.sh / paths.js

Path helper functions gain a `project_id` parameter:
- `gc_session_events_dir(project_id, session_id)` → `$GC_EVENTS_DIR/{project_id}/{session_id}`
- `gc_session_projections_dir(project_id, session_id)` → `$GC_PROJECTIONS_DIR/{project_id}/{session_id}`
- `gc_project_latest(project_id)` → `$GC_PROJECTIONS_DIR/{project_id}/latest`

### New shared function: gc_derive_project_id

```bash
gc_derive_project_id() {
  local project_dir="$1"
  if [ -z "$project_dir" ]; then
    echo "_unknown-000000"
    return
  fi
  local basename
  basename=$(basename "$project_dir" | tr -cd 'a-zA-Z0-9_-')
  [ -z "$basename" ] && basename="_root"
  local hash
  hash=$(printf '%s' "$project_dir" | sha256sum | cut -c1-6)
  echo "${basename}-${hash}"
}
```

---

## Amendment 4: Remove gc-cleanup (Defer)

**Reason**: The `gc-cleanup` command with retention-based deletion contradicts the "append-only, never deleted" core principle. At expected usage levels (~11GB over 90 days of heavy use), disk pressure is unlikely. `gc-query doctor` already reports disk usage. If cleanup is needed later, it can be added as a separate story.

**Changes**:
- Remove Plan 03 Task 12 (gc-cleanup command)
- Remove `retention_days` from config.json defaults (keep the field as reserved for future use)
- Remove `gc-cleanup` from the files inventory
- The `gc-query store-size` command (Plan 03 Task 13) remains as a diagnostic tool

---

## Summary of Plan Impacts

| Plan | Tasks Removed | Tasks Modified | Tasks Added |
|------|--------------|----------------|-------------|
| Plan 01 | — | Tasks 1, 6, 8, 9 (add project_id to paths, envelope, session dir) | Task: project_id derivation function |
| Plan 02 | — | Task 1 (gc-hook extracts cwd for project_id) | — |
| Plan 03 | Task 8 (global sessions index), Task 12 (gc-cleanup) | Tasks 1, 3, 6, 7, 10, 11 (all paths gain project-id layer) | Task: per-session session.json (replaces Task 8) |
| Plan 04 | — | Tasks 1, 3, 11 (paths gain project-id) | — |
| Plan 05 | — | Tasks 1, 3, 5, 6, 11, 14, 15, 16 (project-scoped queries, per-project latest) | — |
