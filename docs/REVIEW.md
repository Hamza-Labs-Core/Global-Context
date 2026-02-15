# Story Review: GlobalContext Event-Sourced Context Store

**Date**: 2026-02-14
**Reviewer**: Architecture Review Agent
**Status**: Review Complete
**Overall Score**: 7.5/10 — Strong foundation, requires refinement before implementation

---

## Critical Issues (5)

### C-1: Lock File Naming Conflict
**Stories**: 01-event-capture (Section 3) vs 03-storage-layer (Section 8)
- Story 01 uses `_seq.lock` for the per-session lock file
- Story 03 uses `.lock` for the per-session lock file
- **Resolution**: Standardize on `.lock` (Story 03's convention). Update Story 01 to use `.lock`.

### C-2: sessions.json Schema Mismatch
**Stories**: 03-storage-layer (Section 4) vs 05-context-recovery (Section 5)
- Story 03 defines sessions.json fields: `session_id, started_at, last_event_at, event_count, source, model, project_dir`
- Story 05 defines different fields: `session_id, started_at, ended_at, state, project_dir, event_count, events_by_type, previous_session_id, continuation_of, continued_by, source, model, duration_seconds, last_prompt, summary`
- Story 05 is a superset but uses different field names for some concepts
- **Resolution**: Merge into one canonical schema. Story 03 should define the full schema; Story 05 should reference it. Use Story 05's richer schema as the canonical one.
- **Status**: Superseded by Design Amendment 2. Global sessions.json is removed entirely. Replaced by per-session `session.json` inside each session directory. See `docs/DESIGN-AMENDMENTS.md`.

### C-3: gc-hook Wrapper Missing from Story 01
**Stories**: 01-event-capture, 02-hook-integration
- Story 02 introduces a `gc-hook` wrapper script that invokes `capture-event`
- Story 01 only describes `capture-event` — no mention of `gc-hook`
- The hook config in Story 02 calls `gc-hook`, not `capture-event` directly
- **Resolution**: Story 02 owns the `gc-hook` wrapper. Story 01 owns `capture-event`. This is correct separation — just ensure the install story in 02 creates both scripts. Add a note to Story 01 that `capture-event` is called via `gc-hook`, not directly by hooks.

### C-4: PreCompact/Compaction Handling Gap
**Stories**: 01, 02, 04, 05
- PreCompact fires synchronously before compaction (Story 02)
- capture-event stores the CompactionTriggered event (Story 01)
- BUT: who builds the context snapshot before compaction? Story 04 (projections) says projections are on-demand. Story 05 says automatic context injection on SessionStart with source "compact"
- **Problem**: Between PreCompact (event stored) and the next SessionStart (where context injection happens), the old session's events exist but no projection has been built yet. The SessionStart hook in Story 05 must build the projection synchronously within the 5s hook timeout.
- **Resolution**: Story 05's SessionStart hook handler must: (1) detect source="compact", (2) call `project context <previous-session-id>` synchronously, (3) return the context as additionalContext. This is a tight 5s budget. Document this clearly and consider pre-building the projection in the PreCompact hook instead.

### C-5: UUID Fallback Generates Non-Standard IDs
**Story**: 01-event-capture (Section 2)
- When both `uuidgen` and `/proc/sys/kernel/random/uuid` are unavailable, the fallback is a timestamp+PID composite
- This is not a valid UUID and could cause issues if downstream systems expect RFC 4122 format
- **Resolution**: Use a bash-native UUID v4 generator as the final fallback: `printf '%04x%04x-%04x-%04x-%04x-%04x%04x%04x' $RANDOM $RANDOM $RANDOM $(($RANDOM & 0x0fff | 0x4000)) $(($RANDOM & 0x3fff | 0x8000)) $RANDOM $RANDOM $RANDOM`. Or accept non-UUID and document it.

---

## Major Issues (6)

### M-1: Projection Version Checking Undefined
**Stories**: 04-projection-engine (Section 7), 03-storage-layer
- Story 04 mentions `_projection_version` for schema migration but doesn't define what version numbers map to what schemas
- No mechanism to detect stale projections from a previous version of GlobalContext
- **Resolution**: Define version 1 explicitly. Add a VERSION file to ~/.claude-context/ that the projection engine reads.

### M-2: Session ID Sanitization Discrepancy
**Stories**: 01-event-capture (Section 4) vs 03-storage-layer (Section 3)
- Story 01 allows `[a-zA-Z0-9._-]`, max 128 chars
- Story 03 has a more detailed table including leading-dot handling, path traversal prevention, max 255 chars
- **Resolution**: Consolidate into Story 03's more thorough sanitization. Story 01 should reference Story 03's rules.

### M-3: Atomic Write Pattern Inconsistency
**Stories**: 01, 03, 04
- Story 01 uses direct write (no temp file + rename pattern)
- Story 03 specifies full atomic write (temp file + fsync + rename)
- Story 04 specifies atomic write (temp file + rename, no fsync)
- **Resolution**: Standardize on Story 03's pattern (temp + fsync + rename) across all stories. For the capture script (Story 01), trade-off: fsync adds ~10ms latency. Consider making fsync optional (off by default for async hooks, on for sync hooks).

### M-4: Storage Path Override Not Propagated
**Stories**: 03-storage-layer (Section 10), all others
- Story 03 defines `CLAUDE_CONTEXT_PATH` env var for custom paths
- Stories 01, 02, 04, 05 all hardcode `~/.claude-context/`
- **Resolution**: All scripts must respect `CLAUDE_CONTEXT_PATH`. Define a shared helper or config read at the top of every script.

### M-5: Hook Payload Structure Not Documented in Story 02
**Story**: 02-hook-integration
- Story 02 maps hook events to capture-event calls but doesn't document what JSON Claude Code sends on stdin for each hook
- Story 01 documents expected payload fields per event type but they're "expected" not "guaranteed"
- **Resolution**: Add a reference section to Story 02 or link to Story 01's Section 8 for payload schemas. Note that payloads are Claude Code's contract, not ours.

### M-6: Projection Staleness Check Uses Unreliable mtime
**Story**: 05-context-recovery (Section 10)
- Uses `stat -c %Y` to compare file modification times
- `stat` flags differ between macOS (`-f %m`) and Linux (`-c %Y`)
- mtime can be unreliable on some filesystems (NFS, containers)
- **Resolution**: Use `_last_sequence` from the projection file compared to the count of event files. This is filesystem-independent and more reliable.

---

## Coverage Gaps (5)

### G-1: No Duplicate Event Detection
- If a hook fires twice for the same tool call (theoretically possible with async hooks), two events with different sequence numbers but the same `tool_use_id` would be recorded
- **Resolution**: Add a NOTE to Story 04 that projections should deduplicate by `tool_use_id` when correlating ToolCallRequested/ToolCallCompleted pairs.

### G-2: Tool Result Extraction for Glob/Grep Incomplete
**Story**: 04-projection-engine (Section 3, Files Touched)
- Documents extraction of `file_path` from Read/Write/Edit and `pattern`/`path` from Glob/Grep
- But Glob/Grep results (the actual files found) are in `tool_response`, not `tool_input`
- The files-touched projection would miss files that were found by Glob but not subsequently Read
- **Resolution**: Story 04 should extract file paths from both `tool_input` AND `tool_response` for Glob/Grep results.

### G-3: No Health Check / Self-Test Command
- No story defines a way to verify the entire system is working end-to-end
- **Resolution**: Add to Story 05's gc-query: `gc-query doctor` that validates: event store exists, hooks are installed, capture-event is executable, can write/read a test event, projections directory exists.

### G-4: No Log File
- All stories mention "log to stderr" for errors, but stderr from async hooks goes nowhere
- **Resolution**: Add an optional log file (`~/.claude-context/logs/capture.log`) with rotation. Story 01 should support `CLAUDE_CONTEXT_LOG` env var.
- **Status**: Resolved in Plan 02 Task 11. `gc-hook` writes to `~/.claude-context/logs/hook.log` when `GC_DEBUG=1` is set. Default off (production safety). 1MB rotation.

### G-5: Uninstall/Cleanup Not Fully Defined
- Story 02 has hook uninstall but no story covers full system uninstall (remove all of ~/.claude-context/)
- **Resolution**: Add a `gc-uninstall` command or document the process.
- **Status**: Resolved in Plan 02 Task 12. `gc-uninstall` command removes hooks (via `gc-install-hooks uninstall`), deletes `~/.claude-context/`, supports `--keep-data`, `--force`, and `--dry-run` flags.

---

## Cross-Story Dependencies

| Dependency | From | To | Status |
|---|---|---|---|
| capture-event script exists | Story 01 | Story 02 (hooks call it) | Documented |
| Storage directory structure | Story 03 | Story 01, 04, 05 | Partially documented |
| Event envelope schema | Story 01 | Story 04 (projections read events) | Documented |
| sessions.json format | Story 03 | Story 05 (gc-query reads it) | CONFLICTING (see C-2) |
| Projection files format | Story 04 | Story 05 (gc-query reads projections) | Documented |
| gc-hook wrapper | Story 02 | Story 01 (capture-event called via gc-hook) | Needs clarification (see C-3) |
| config.json | Story 03 | Story 01 (max_event_size_bytes), Story 04, Story 05 | Partially documented |

---

## Summary

### Strengths
- Comprehensive acceptance criteria in each story
- Clear separation of concerns (CQRS write/read split)
- Good edge case coverage within individual stories
- Testing plans included in every story
- Event type documentation is thorough

### Areas for Improvement
- Cross-story consistency needs alignment (schemas, naming, patterns)
- Integration points between stories need explicit interface contracts
- The compaction → recovery flow needs end-to-end specification
- Platform compatibility (Linux vs macOS) needs systematic handling

### Recommended Next Steps
1. Fix all 5 CRITICAL issues before implementation planning
2. Resolve MAJOR issues by adding cross-references between stories
3. Create a shared "conventions" document for patterns used across all stories (atomic writes, path handling, error format, env vars)
4. Define the end-to-end flows as sequence diagrams (especially compaction → recovery)
