# Implementation Plan: Story 05 -- Context Recovery & Retrieval

**Story**: 05-context-recovery.md
**Date**: 2026-02-14
**Status**: Planning
**Estimated Total Tasks**: 20
**Review Fixes Incorporated**: C-2, C-4, M-4, M-6, G-3
**Design Amendments**: 1, 2, 3. See `docs/DESIGN-AMENDMENTS.md`.

### Amendment Impacts on This Plan

- **Amendment 1** (Remove global sessions.json): Task 2 (schema alignment) is simplified — no global sessions.json to merge. `gc-query sessions` (Task 16) scans `events/{project-id}/*/session.json` instead of reading a single file.
- **Amendment 2** (Per-session session.json): `gc-query` reads per-session `session.json` files for metadata. No global lock, no shared state.
- **Amendment 3** (Project-ID layer): `gc-query last` detects current working directory, derives project-id, scopes to that project. `gc-query sessions` groups by project. Per-project `latest` symlink.

---

## Review Fixes Summary

This plan incorporates the following fixes from `docs/REVIEW.md`:

| Fix ID | Issue | How Addressed |
|--------|-------|---------------|
| **C-2** | sessions.json schema mismatch between Story 03 and Story 05 | ~~Task 2 uses the canonical sessions.json schema~~ **Superseded by Amendment 2**: global sessions.json removed. gc-query reads per-session `session.json` files and computes derived fields (state, duration, etc.) on read. |
| **C-4** | Compaction-to-recovery flow undefined | Task 14 implements the PreCompact hook building the context.json projection eagerly. Task 15 implements the SessionStart hook reading the pre-built projection. The flow is: PreCompact builds projection -> compaction occurs -> SessionStart reads pre-built projection -> returns additionalContext. |
| **M-4** | CLAUDE_CONTEXT_PATH env var not respected | Task 1 reuses the shared `paths.sh` library from Story 03. Every script uses `$GC_ROOT` instead of hardcoded `~/.claude-context/`. |
| **M-6** | Staleness check uses unreliable mtime | Task 4 uses `_last_sequence` from the projection file compared against the highest sequence number in the events directory, instead of comparing file modification times. |
| **G-3** | No gc-query doctor command | Task 17 implements `gc-query doctor` for end-to-end health validation. |

---

## Prerequisites

These must be complete before starting Story 05:

- **Story 01** (Event Capture): `capture-event` script exists and writes events to `~/.claude-context/events/{project-id}/{session-id}/{sequence}.json`
- **Story 02** (Hook Integration): `gc-hook` wrapper and hook configuration in `~/.claude/settings.json` are in place
- **Story 03** (Storage Layer): Directory structure, per-session `session.json`, per-project `latest` symlink, `.lock` files, `config.json` all exist. Shared library (`src/lib/paths.sh`) provides path resolution.
- **Story 04** (Projection Engine): `project` CLI and all five projection handlers (timeline, files, decisions, context, summary) are implemented and working

---

## Task 1: Shared Store Path Resolution Helper

### Description

Reuse the shared path resolver from Story 03 (`src/lib/paths.sh`) which resolves the store path, respecting the `CLAUDE_CONTEXT_PATH` environment variable (fix M-4). Every script in Story 05 sources this library instead of hardcoding `~/.claude-context/`.

> **Note**: This task is satisfied by Plan 03, Task 1 (`src/lib/paths.sh`). Story 05 scripts source the same library. No separate `store-path.sh` is needed. The variables below are provided by `paths.sh`:

### Files to Create/Modify

| Action | Path |
|--------|------|
| Reuse | `src/lib/paths.sh` (from Story 03) |

### Implementation Details

Story 05 scripts source `paths.sh` and use these variables and functions:

```bash
source "$(dirname "$0")/../lib/paths.sh"
# Provides: $GC_ROOT, $GC_EVENTS_DIR, $GC_PROJECTIONS_DIR, $GC_BIN_DIR, $GC_CONFIG_FILE
# Provides: gc_session_events_dir(), gc_session_projections_dir(), gc_project_latest(), gc_derive_project_id()
```

### Dependencies

- Story 03, Task 1 (paths.sh must be implemented first)

### Acceptance Test

1. Without `CLAUDE_CONTEXT_PATH` set: source `paths.sh`, verify `$GC_ROOT` is `$HOME/.claude-context`.
2. With `CLAUDE_CONTEXT_PATH=/tmp/test-store`: source `paths.sh`, verify `$GC_ROOT` is `/tmp/test-store`.
3. All derived paths (`$GC_EVENTS_DIR`, `$GC_PROJECTIONS_DIR`, etc.) are consistent with the resolved root.
4. `gc_derive_project_id` returns `{basename}-{hash6}` format.

### Complexity: S

---

## Task 2: Per-Session session.json Read Model (Fix C-2)

### Description

Define the read model that `gc-query` uses when reading per-session `session.json` files. Story 03 writes a base set of fields; Story 05's `gc-query` computes derived fields (`state`, `duration_seconds`, etc.) at read time. No global `sessions.json` exists (Amendment 1).

> **Amendment 2**: This task was originally about merging a global `sessions.json` schema. Now it documents how `gc-query` reads per-session `session.json` files and computes derived fields on the fly.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Create | `src/lib/session_read.sh` | Read helper that loads session.json and computes derived fields |

### Per-Session session.json (Written by Story 03)

Each `events/{project-id}/{session-id}/session.json` contains these fields (written by `event_write.sh`):

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

### Derived Fields (Computed at Read Time by gc-query)

`gc-query` computes these additional fields when reading `session.json`:

- **`state`**: Derived from events — `"ended"` (has `ended_at`), `"compacted"` (has CompactionTriggered), `"orphaned"` (no events for 24h+), `"active"` (otherwise).
- **`duration_seconds`**: Computed from `started_at` and `ended_at` (or `last_event_at` if `ended_at` is null).

**Key decisions:**
- `source` canonical values: `"manual"`, `"compact"`, `"clear"`, `"resume"`.
- Derived fields are never written back to `session.json` — they are computed each time (CQRS: read side computes).
- Scanning `events/{project-id}/*/session.json` replaces reading a global index.

### Dependencies

- Task 1 (paths.sh for path resolution)

### Acceptance Test

1. `gc_read_session_with_derived(project_id, session_id)` returns all base fields plus computed `state` and `duration_seconds`.
2. Session with `ended_at` set: `state` is `"ended"`.
3. Session with no events for 24h+: `state` is `"orphaned"`.
4. Missing `session.json`: returns error gracefully, does not crash.

### Complexity: S

---

## Task 3: gc-query Entry Point and Argument Parser

### Description

Create the `gc-query` CLI entry point script with argument parsing, help text, and routing to subcommand functions. This is the skeleton that all subsequent tasks fill in.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Create | `~/.claude-context/bin/gc-query` |

### Implementation Details

The script must:
1. Source `lib/store-path.sh` for path resolution
2. Parse the first positional argument as the subcommand
3. Parse flags with a shift-based loop (no `getopt` dependency for portability)
4. Route to the correct subcommand function
5. Print usage/help when invoked with no arguments, `-h`, or `--help`
6. Exit with code 2 for invalid arguments

Subcommands to stub out (each returns "Not yet implemented" initially):
- `last`
- `session <session-id>`
- `sessions`
- `search <keyword>`
- `events <session-id>`
- `replay <session-id>`
- `tail <session-id> [N]`
- `status`
- `doctor`

### Dependencies

- Task 1 (store path helper)

### Acceptance Test

1. `gc-query` with no args prints help and exits with code 2.
2. `gc-query --help` prints help and exits with code 0.
3. `gc-query invalidcommand` prints error and exits with code 2.
4. `gc-query status` routes to the status stub.
5. Script is executable (mode 755).
6. Works on both Linux and macOS (no bash-4-only features in arg parsing).

### Complexity: M

---

## Task 4: Projection Staleness Check Using _last_sequence (Fix M-6)

### Description

Implement a helper function that checks whether a projection is current by comparing `_last_sequence` from the projection file against the highest sequence number in the session's event directory. This replaces the unreliable `stat -c %Y` mtime comparison.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Create | `~/.claude-context/lib/projection-check.sh` |

### Implementation Details

```bash
# is_projection_current(project_id, session_id, projection_name)
# Returns 0 (true) if projection is current, 1 (false) if stale or missing
is_projection_current() {
  local project_id="$1"
  local session_id="$2"
  local projection_name="${3:-context}"
  local proj_file="$GC_PROJECTIONS_DIR/$project_id/$session_id/${projection_name}.json"

  # If projection file does not exist, it is stale
  [ -f "$proj_file" ] || return 1

  # Read _last_sequence from projection
  local proj_seq
  proj_seq=$(jq -r '._last_sequence // 0' "$proj_file" 2>/dev/null) || return 1

  # Find highest sequence number in events directory
  # Use [0-9]*.json to exclude session.json and other non-event files
  local highest_event
  highest_event=$(ls "$GC_EVENTS_DIR/$project_id/$session_id/"[0-9]*.json 2>/dev/null \
    | sed 's/.*\///' | sed 's/\.json$//' | sort -n | tail -1)
  [ -z "$highest_event" ] && return 1

  # Remove leading zeros for numeric comparison
  local event_seq=$((10#$highest_event))

  # Projection is current if _last_sequence >= highest event sequence
  [ "$proj_seq" -ge "$event_seq" ]
}
```

### Dependencies

- Task 1 (paths.sh for `$GC_EVENTS_DIR`, `$GC_PROJECTIONS_DIR`)
- Story 04 (projection files must contain `_last_sequence` metadata)

> **Note**: Plan 03, Task 11 provides `gc_is_projection_stale()` with similar logic. This function can either reuse that or be a thin wrapper. The key difference is this version is used by `gc-query` (read side) while Plan 03's is used by the projection engine.

### Acceptance Test

1. With a projection file at `_last_sequence: 50` and events up to `000050.json`: returns current (exit 0).
2. With a projection file at `_last_sequence: 50` and events up to `000055.json`: returns stale (exit 1).
3. With no projection file: returns stale (exit 1).
4. With no events directory: returns stale (exit 1).
5. Works on both Linux and macOS (no platform-specific `stat` calls).

### Complexity: S

---

## Task 5: Session Resolution Helpers

### Description

Implement helper functions for resolving session IDs: latest session resolution (via symlink with fallback), prefix matching, and session existence validation.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Create | `~/.claude-context/lib/session-resolve.sh` |

### Implementation Details

Three functions:

1. **resolve_latest_session(project_id)**: Read the per-project `latest` symlink at `$GC_PROJECTIONS_DIR/$project_id/latest`. If missing or broken, fall back to scanning `$GC_EVENTS_DIR/$project_id/` for the most recently modified session directory.

2. **resolve_session_id(project_id, partial_id)**: If the given ID matches a session directory exactly under `$GC_EVENTS_DIR/$project_id/`, return it. Otherwise, search for directories whose name starts with the partial ID. If exactly one match, return it. If multiple matches, list them and exit with code 2. If no matches, exit with code 3.

3. **validate_session_exists(project_id, session_id)**: Check that `$GC_EVENTS_DIR/$project_id/$session_id/` exists and contains at least one `[0-9]*.json` file.

### Dependencies

- Task 1 (paths.sh for `gc_project_latest()`, `gc_session_events_dir()`)

### Acceptance Test

1. `resolve_latest_session "proj-abc123"` returns the session ID from the per-project `latest` symlink.
2. When the symlink is missing, it falls back to the most recent session directory in that project.
3. `resolve_session_id "proj-abc123" "abc"` returns `"abc-123-def"` when that is the only match.
4. `resolve_session_id "proj-abc123" "abc"` lists multiple matches and exits with code 2 when ambiguous.
5. `resolve_session_id "proj-abc123" "nonexistent"` exits with code 3.
6. `validate_session_exists` returns 0 for a session with events, 1 for a session directory with no events.

### Complexity: S

---

## Task 6: gc-query status Command

### Description

Implement the `status` subcommand showing store health and statistics. This is the simplest query command and validates that the store is accessible.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_status` function) |

### Implementation Details

1. Derive project_id from current working directory using `gc_derive_project_id`.
2. Count session directories under `$GC_EVENTS_DIR/$project_id/` (project-scoped by default).
3. Count total `[0-9]*.json` event files across all sessions in the project.
4. Calculate disk usage via `du -sh "$GC_ROOT"`.
5. Read the latest session ID from the per-project `latest` symlink, then read its `session.json` for start time.
6. Count projection directories and determine how many are stale using `is_projection_current`.
7. Output in text format (default) or JSON format.
8. `--all-projects` flag shows store-wide totals across all projects.

### Dependencies

- Task 3 (gc-query entry point)
- Task 4 (staleness check)

### Acceptance Test

1. `gc-query status` prints all required fields: total sessions, total events, disk usage, latest session, projections count.
2. Empty store: prints "Store is empty. No sessions recorded." and exits with code 0.
3. `gc-query status --format json` returns valid JSON with all fields.
4. Completes in under 3 seconds with 100+ sessions.

### Complexity: S

---

## Task 7: gc-query events Command

### Description

Implement raw event access. Read event files from a session directory and output them as JSONL (default) or JSON array. Support sequence range filtering and event type filtering.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_events` function) |

### Implementation Details

1. Derive project_id from cwd, then resolve the session ID (using `resolve_session_id`).
2. List all `[0-9]*.json` files in the session's events directory (`$GC_EVENTS_DIR/$project_id/$session_id/`), sorted numerically.
3. Apply `--from` and `--to` filters on sequence numbers.
4. Apply `--type` filter by reading each event's `event_type` field.
5. Output in the requested format (jsonl: one event per line; json: JSON array).

### Dependencies

- Task 3 (gc-query entry point)
- Task 5 (session resolution)

### Acceptance Test

1. `gc-query events <session-id>` outputs all events as JSONL.
2. `gc-query events <session-id> --from 10 --to 20` outputs only events 10-20.
3. `gc-query events <session-id> --type ToolCallCompleted` filters by type.
4. Events are in strict sequence order.
5. Exit code 3 if session does not exist.
6. Empty result (not error) if range contains no events.

### Complexity: S

---

## Task 8: gc-query tail Command

### Description

Show the last N events from a session. Thin wrapper around the events command.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_tail` function) |

### Implementation Details

1. Derive project_id from cwd, resolve session ID.
2. Determine total event count (count `[0-9]*.json` files in `$GC_EVENTS_DIR/$project_id/$session_id/`).
3. Compute `--from` as `max(1, total - N + 1)`.
4. Delegate to the events rendering logic.
5. Default N is 20.

### Dependencies

- Task 7 (events command, for rendering logic reuse)

### Acceptance Test

1. `gc-query tail <session-id>` shows last 20 events.
2. `gc-query tail <session-id> 5` shows last 5 events.
3. If session has fewer than N events, shows all events.
4. Exit code 3 if session does not exist.

### Complexity: S

---

## Task 9: Context Projection Builder Integration

### Description

Implement the function that loads or rebuilds a session's `context.json` projection. This is the core logic that powers `gc-query last` and `gc-query session`. It calls the `project` CLI from Story 04 to build/rebuild projections and reads the output.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Create | `~/.claude-context/lib/context-loader.sh` |

### Implementation Details

1. **load_context(project_id, session_id)**: Check if the context projection is current using `is_projection_current`. If current, read and return the cached projection. If stale or missing, call `project context <project-id> <session-id>` to rebuild, then read and return the result.

2. **build_context_if_needed(project_id, session_id)**: Same as load_context but only builds -- does not output. Used by the PreCompact hook (Task 14) to eagerly build the projection.

3. Handle errors gracefully: if the projection engine fails, output a degraded context by reading raw events directly and assembling a minimal context.

### Dependencies

- Task 4 (staleness check)
- Story 04 (the `project` CLI must exist and produce `context.json`)

### Acceptance Test

1. When projection is current, `load_context` reads from cache without calling `project`.
2. When projection is stale, `load_context` calls `project context <session-id>` and reads the result.
3. When projection is missing, `load_context` triggers a full build.
4. When `project` fails, `load_context` returns a degraded context with an error note instead of crashing.
5. Rebuild completes in under 2 seconds for a session with 500 events.

### Complexity: M

---

## Task 10: Output Formatters (Markdown, Text, Compact, JSON)

### Description

Implement the four output formatters that transform a context.json projection into the requested output format. The markdown formatter follows the exact template from Story 05, Requirement 4.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Create | `~/.claude-context/lib/format-context.sh` |

### Implementation Details

Four functions, each reading a context.json from stdin or as a file argument and outputting formatted text to stdout:

1. **format_json(context_file)**: Pretty-print the JSON as-is.

2. **format_markdown(context_file)**: Build markdown output following the template:
   - Session Info (ID, started, ended, project, event count, continuation link)
   - What Was Being Worked On (last prompt as blockquote, recent context bullets)
   - Actions Taken (numbered list of tool calls with verb + target + result)
   - Files Modified (markdown table: file, operations, last action)
   - Key Decisions (extracted from decision groups)
   - Where We Left Off (last_state section)

3. **format_text(context_file)**: Plain text with indentation and dashes, no markdown.

4. **format_compact(context_file)**: Single-line summary: `session_id | timestamp | project | events | last_prompt | files_modified_count`.

Apply progressive summarization for sessions with 100+ events (as defined in Story 05 Requirement 4):
- Last 20 events: full detail
- Events 21-50: tool name + target only
- Events 51-100: grouped
- Events 100+: one-line summary

### Dependencies

- Task 9 (context loader, for the data model)

### Acceptance Test

1. Markdown output contains all six sections: Session Info, What Was Being Worked On, Actions Taken, Files Modified, Key Decisions, Where We Left Off.
2. File paths use backtick formatting in markdown.
3. Prompts use blockquote `>` formatting in markdown.
4. Text output is readable without markdown rendering.
5. Compact output fits on a single line per session.
6. JSON output is valid parseable JSON.
7. Progressive summarization activates at 100+ tool call events.

### Complexity: L

---

## Task 11: gc-query last Command

### Description

Implement the primary "get last context" command. Resolves the latest session, loads or rebuilds its context projection, and outputs it in the requested format.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_last` function) |

### Implementation Details

1. Resolve latest session using `resolve_latest_session()`.
2. Load context using `load_context(session_id)`.
3. If `--include-parent` is set, follow the `previous_session_id` chain (Task 13).
4. Format output using the appropriate formatter (default: markdown).
5. Write to stdout.

### Dependencies

- Task 5 (session resolution)
- Task 9 (context loader)
- Task 10 (output formatters)

### Acceptance Test

1. `gc-query last` returns markdown for the most recent session.
2. `gc-query last --format json` returns valid JSON.
3. Exit code 3 with "No sessions found" when no sessions exist.
4. Uses cached projection when current; rebuilds only when stale.
5. Completes in under 500ms (cached) or under 2 seconds (rebuild of 500 events).
6. `gc-query last --include-parent` includes parent session context.

### Complexity: M

---

## Task 12: gc-query session Command

### Description

Retrieve context from a specific session by ID. Supports partial session ID matching.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_session` function) |

### Implementation Details

1. Resolve session ID using `resolve_session_id(partial_id)`.
2. Load or rebuild the context projection.
3. Format and output.

### Dependencies

- Task 5 (session resolution with prefix matching)
- Task 9 (context loader)
- Task 10 (output formatters)

### Acceptance Test

1. `gc-query session <full-id>` returns context for that session.
2. `gc-query session <prefix>` resolves unique prefix and returns context.
3. Ambiguous prefix lists matches and exits with code 2.
4. Nonexistent session exits with code 3.
5. `--include-parent` follows the session chain.

### Complexity: S

---

## Task 13: Cross-Session Chaining (--include-parent)

### Description

Implement the session chain resolution logic that follows `previous_session_id` links to include parent session context. Applies progressive summarization as chain depth increases.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Create | `~/.claude-context/lib/session-chain.sh` |

### Implementation Details

1. Starting from the current session's context, read `previous_session_id`.
2. If non-null, load the parent session's context.
3. Continue following the chain up to a maximum depth of 10.
4. Apply progressive summarization: each level deeper gets more summarized.
   - Current session: full detail
   - Parent (depth 1): compact summary (What Was Being Worked On + Files Modified + Where We Left Off)
   - Grandparent (depth 2+): one-liner summary only
5. Detect circular chains (track visited session IDs) and break with an error message.
6. If chain exceeds depth 10, note: "N additional ancestor sessions exist but are omitted."

Output structure for markdown:
```
## Session Context Recovery (Session Chain)

### Current Session: <current-id>
[full context]

---

### Parent Session: <parent-id>
[compact summary]

---

### Grandparent Session: <grandparent-id>
[one-liner]
```

### Dependencies

- Task 9 (context loader, for loading each session in the chain)
- Task 10 (formatters, for progressive summarization)

### Acceptance Test

1. A chain of 3 sessions: current gets full detail, parent gets compact, grandparent gets one-liner.
2. Chain of 11 sessions: stops at depth 10, notes omitted sessions.
3. Circular chain (A -> B -> A): detected and broken with error message.
4. Session with no parent: returns only current session context.
5. Parent session with missing events: degraded gracefully with a note.

### Complexity: M

---

## Task 14: PreCompact Hook -- Eager Projection Build (Fix C-4)

### Description

Modify the PreCompact hook handler to eagerly build the context.json projection for the current session BEFORE compaction occurs. This ensures the projection is ready when the post-compaction SessionStart fires, eliminating the need to build it within the tight 5-second SessionStart hook timeout.

This is the first half of the compaction-to-recovery flow (C-4):
```
PreCompact fires -> build context.json projection (this task)
                 -> compaction occurs
SessionStart fires -> read pre-built projection (Task 15)
                   -> return additionalContext
```

### Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-hook` (or the capture-event handler for PreCompact) |

### Implementation Details

1. When the PreCompact hook fires, after storing the CompactionTriggered event (normal capture):
2. Call `project context <current-session-id>` synchronously to build the context.json projection.
3. This must complete before the hook returns, since PreCompact is synchronous (the story spec says "The PreCompact handler must be synchronous to guarantee the snapshot is written before compaction occurs").
4. If the projection build fails, log the error but do not fail the hook.
5. The projection is now cached at `projections/{project-id}/{session-id}/context.json` and ready for the SessionStart hook.

### Dependencies

- Task 9 (context loader / build logic)
- Story 02 (gc-hook wrapper exists)
- Story 04 (project CLI exists)

### Acceptance Test

1. After a PreCompact hook fires, `projections/{project-id}/{session-id}/context.json` exists and is complete.
2. The projection's `_last_sequence` matches the CompactionTriggered event's sequence number.
3. If the projection build fails, the hook still returns successfully (exit 0).
4. The entire PreCompact hook (capture + projection build) completes within 5 seconds for a session with 500 events.

### Complexity: M

---

## Task 15: SessionStart Hook -- Automatic Context Injection (Fix C-4)

### Description

Modify the SessionStart hook handler to detect compaction/clear events and inject context from the previous session as `additionalContext`. This reads the pre-built projection from Task 14.

This is the second half of the compaction-to-recovery flow (C-4):
```
PreCompact fires -> build context.json projection (Task 14)
                 -> compaction occurs
SessionStart fires -> detect source="compact" (this task)
                   -> read pre-built context.json
                   -> format as markdown
                   -> return {"additionalContext": "..."}
```

### Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-hook` (SessionStart handler) |

### Implementation Details

1. After capturing the SessionStarted event (normal capture), check the `source` field in the hook payload (mapped from the hook's `session_start_type`).
2. **Source "compact"**: Read the previous session's pre-built `context.json` projection. Format as a compact markdown summary. Return `{"additionalContext": "## Context Recovery (Auto)\n\n..."}`.
3. **Source "clear"**: Same as compact but with different heading: "## Context Recovery (Cleared)". Include a note: "Previous conversation was cleared by user." Focus on accomplishments, not in-progress work.
4. **Source "resume"**: Skip for initial implementation (optional per story spec). Return `{}`.
5. **Source "manual"**: Return `{}` (no automatic injection).
6. The `additionalContext` value must be a single string, under 50KB.
7. The previous session ID comes from the hook payload or by reading the `latest` symlink (which still points to the old session at this point).
8. If reading the projection fails, return `{"additionalContext": "## Context Recovery\n\nNote: Unable to load previous session context. Use \`gc-query last\` to retrieve it manually."}` rather than failing the hook.

### Dependencies

- Task 14 (PreCompact builds the projection that this task reads)
- Task 10 (markdown formatter, compact variant for additionalContext)
- Task 1 (store path helper)

### Acceptance Test

1. SessionStart with source "compact" returns `additionalContext` containing previous session summary.
2. SessionStart with source "clear" returns `additionalContext` with "Cleared" label.
3. SessionStart with source "manual" returns `{}` (no additionalContext).
4. `additionalContext` is valid markdown, under 50KB.
5. Hook response completes within 5 seconds.
6. If projection is missing or corrupt, hook returns successfully with an error note.
7. After the hook returns, the LLM has enough context to continue without asking "what were we doing?"

### Complexity: L

---

## Task 16: gc-query sessions Command

### Description

List all sessions with metadata. Scans per-session `session.json` files across the project (or all projects with `--all-projects`).

### Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_sessions` function) |

### Implementation Details

1. Derive project_id from cwd. Scan `$GC_EVENTS_DIR/$project_id/*/session.json` to collect session metadata.
2. If a session directory has no `session.json`, fall back to reading its `SessionStarted` event (first `[0-9]*.json` file).
3. With `--all-projects`, scan `$GC_EVENTS_DIR/*/*/session.json` across all projects.
4. Compute derived fields not present in session.json:
   - `state`: Derive from events (has SessionEnded? -> "ended". Has CompactionTriggered? -> "compacted". Active with no events for 24h+ -> "orphaned". Otherwise -> "active").
   - `duration_seconds`: Compute from `started_at` and `ended_at` or `last_event_at`.
4. Apply filters: `--project`, `--state`, `--since`, `--limit`.
5. Sort by `started_at` descending.
6. Output in text format (default), or JSON/compact as requested.

For text mode, each row shows: session ID (truncated to 8 chars), start timestamp, project path, event count, state.

### Dependencies

- Task 2 (session read model with derived fields)
- Task 3 (gc-query entry point)

### Acceptance Test

1. `gc-query sessions` lists sessions for the current project, sorted by start time descending.
2. `gc-query sessions --all-projects` lists sessions across all projects.
3. `gc-query sessions --state compacted` filters by state.
4. `gc-query sessions --since 1w` returns only sessions from the last 7 days.
5. `gc-query sessions --limit 5` returns at most 5 sessions.
6. Exit code 0 with "No sessions found" when store is empty.
7. JSON output includes full session IDs and all metadata fields.
8. Completes in under 1 second with 100 sessions.

### Complexity: M

---

## Task 17: gc-query search Command

### Description

Search across sessions for events containing a keyword. Searches prompts, tool names, and tool results.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_search` function) |

### Implementation Details

1. Iterate through session event directories (or a specific session if `--session` is set).
2. For each event file, search the payload for the keyword:
   - `UserPromptReceived`: search `data.prompt`
   - `ToolCallCompleted`: search `data.tool_name` and first 500 chars of `data.tool_result`
   - `SessionStarted`: search `data.cwd`
3. Case-insensitive by default (`--case-sensitive` to override).
4. For `--file` flag: search for file paths in tool inputs and outputs.
5. Return results grouped by session, showing: session ID, sequence number, event type, matching text snippet (80 chars around match).
6. Limit results with `--limit` (default 20).
7. Sort by relevance (match count) then recency.
8. Handle special characters in search terms safely (escape for jq's `test()` function).

### Dependencies

- Task 3 (gc-query entry point)
- Task 5 (session resolution)

### Acceptance Test

1. `gc-query search "rate limiting"` finds matches in prompts and tool results.
2. Results show session ID, sequence, event type, and snippet.
3. Case-insensitive by default.
4. `gc-query search --type UserPromptReceived "auth"` only searches prompts.
5. `gc-query search --limit 5 "test"` returns at most 5 results.
6. `gc-query search --file "src/auth/handler.ts"` finds all events referencing that file.
7. Exit code 0 with "No results found" when nothing matches.
8. Special characters (quotes, backslashes) do not crash the search.
9. Search across 50 sessions with 200 events each completes in under 5 seconds.

### Complexity: L

---

## Task 18: gc-query replay Command

### Description

Transform raw events into a human-readable numbered narrative.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_replay` function) |

### Implementation Details

1. Read events from the session (using the same logic as `cmd_events`).
2. Apply `--from` and `--to` sequence range filters.
3. Transform each event into a narrative step using the event-to-narrative mapping from Story 05:
   - `SessionStarted` -> "Session started in {cwd} (source: {source})"
   - `UserPromptReceived` -> "User: \"{prompt}\"" (truncated to 200 chars)
   - `ToolCallRequested` -> "Agent plans to use {tool_name} on {target}"
   - `ToolCallCompleted` -> "Executed {tool_name}: {brief result}" (result summarized to 100 chars)
   - `ToolCallFailed` -> "FAILED: {tool_name} -- {error}"
   - `AgentSpawned` -> "Sub-agent started: {description}"
   - `AgentCompleted` -> "Sub-agent finished: {summary}"
   - `TurnCompleted` -> "Turn completed"
   - `CompactionTriggered` -> "--- COMPACTION ---" (visually distinct)
   - `SessionEnded` -> "Session ended"
   - Unknown -> "[Unknown: {type}] {data summary}"
4. Output as numbered steps: "Step 1: ...", "Step 2: ...".
5. `--verbose` includes full event payloads after each step.
6. Support text (default), markdown, and JSON output formats.

### Dependencies

- Task 3 (gc-query entry point)
- Task 5 (session resolution)
- Task 7 (events reading logic)

### Acceptance Test

1. `gc-query replay <session-id>` produces a numbered narrative.
2. Each event type renders with the correct template.
3. `gc-query replay <session-id> --from 40 --to 60` only replays that range.
4. `gc-query replay <session-id> --verbose` includes full payloads.
5. Compaction events are visually distinct (--- COMPACTION ---).
6. User prompts longer than 200 chars are truncated with "...".
7. Tool results longer than 100 chars are summarized.
8. Unknown event types render as "[Unknown: {type}]".
9. Missing events in sequence (gaps) are noted but do not break replay.
10. Replay of a 100-event session completes in under 1 second.

### Complexity: M

---

## Task 19: gc-query doctor Command (Fix G-3)

### Description

Implement an end-to-end health check command that validates the entire GlobalContext system is functioning correctly.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_doctor` function) |

### Implementation Details

Run the following checks and report pass/fail for each:

1. **Store directory exists**: Check `$GC_ROOT` exists and is a directory.
2. **Store is writable**: Attempt to create and delete a temp file in `$GC_ROOT`.
3. **Required directories exist**: Check `events/`, `projections/`, `bin/`.
4. **config.json exists and is valid**: Parse it with jq, check for required fields.
5. **capture-event is executable**: Check `bin/capture-event` exists and has execute permission.
6. **project is executable**: Check `bin/project` exists and has execute permission.
7. **gc-query is executable**: Check `bin/gc-query` exists (self-check).
8. **Hooks are installed**: Check `~/.claude/settings.json` exists and contains GlobalContext hook entries.
9. **jq is available**: Check `jq --version`.
10. **Disk space**: Check at least 10MB free space.
11. **Per-project latest symlink**: For current project, check if `projections/{project-id}/latest` exists and points to a valid target.
12. **Sample event read**: If any sessions exist, read one event file and verify it parses as valid JSON with all 7 required fields.
13. **Per-session session.json**: Spot-check a sample session's `session.json` is valid JSON.
14. **No stale global files**: Verify no `sessions.json` or `.sessions.lock` exists at store root (leftover from pre-Amendment design).

Output format:
```
GlobalContext Doctor
====================
[PASS] Store directory exists: /home/user/.claude-context
[PASS] Store is writable
[PASS] Required directories exist (events, projections, bin)
[PASS] config.json is valid (version: 1.0.0)
[PASS] capture-event is executable
[PASS] project is executable
[PASS] gc-query is executable
[WARN] Hooks not found in ~/.claude/settings.json
[PASS] jq is available (jq-1.6)
[PASS] Disk space: 2.1GB free
[PASS] Latest symlink (my-project-a3f7b2): -> abc-123
[PASS] Sample event: valid (session abc-123, event 000001.json, 7 fields)
[PASS] Sample session.json: valid (session abc-123, event_count: 142)
[PASS] No stale global files

Result: 13 passed, 1 warning, 0 failed
```

Exit code 0 if all checks pass or only warnings. Exit code 1 if any check fails.

### Dependencies

- Task 3 (gc-query entry point)
- Task 1 (store path helper)

### Acceptance Test

1. `gc-query doctor` runs all 14 checks and reports results.
2. On a healthy system, all checks pass and exit code is 0.
3. On a system missing hooks, a warning is shown (not a failure).
4. On a system with a missing `config.json`, a failure is shown and exit code is 1.
5. `gc-query doctor --format json` returns structured results as JSON.
6. `gc-query doctor --fix` attempts to fix issues (e.g., create missing directories).
7. Completes in under 3 seconds.

### Complexity: M

---

## Task 20: Edge Case Handling and Error Hardening

### Description

Systematic pass through all implemented commands to ensure edge cases from Story 05 are handled: no sessions, empty sessions, corrupt events, abnormal session endings, large contexts, concurrent access.

### Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add error handling throughout) |
| Modify | `~/.claude-context/lib/context-loader.sh` (add degraded mode) |
| Modify | `~/.claude-context/lib/format-context.sh` (add truncation logic) |

### Implementation Details

1. **No sessions**: All commands that require sessions return exit 3 with "No sessions found."
2. **Empty session**: `gc-query last` returns "Previous session (abc-123) started at [time] but recorded no events."
3. **Corrupt events**: Skip with warning "Warning: Event #42 could not be parsed and was skipped."
4. **Sequence gaps**: Note gaps but continue processing.
5. **Abnormal ending**: Sessions without `SessionEnded` event are handled (ended_at is null, duration computed from last_event_at).
6. **Large context (>200KB)**: Truncate tool results to 200 chars, omit old action details, add truncation note.
7. **Concurrent access**: Event reads are atomic (each file is a complete JSON object). No file locking on reads.
8. **jq not found**: Early check at gc-query entry point with clear error message.

### Dependencies

- All previous tasks (this is a hardening pass)

### Acceptance Test

1. `gc-query last` with empty store: exit 3, clear message.
2. `gc-query session <id>` for an empty session: returns minimal context.
3. `gc-query replay <id>` with a corrupt event at sequence 5: skips it with warning, continues.
4. `gc-query last` for a session with 500+ events producing >200KB: output is truncated with a note.
5. All commands exit cleanly (no partial stdout) on every error condition.
6. Error messages go to stderr, never to stdout.

### Complexity: M

---

## Implementation Order

The tasks should be implemented in this sequence, with some tasks parallelizable:

```
Phase 1: Foundation (Tasks 1-5)
  Task 1:  Store path helper                    [no deps]
  Task 2:  Per-session session.json read model   [no deps]
  Task 3:  gc-query entry point + arg parser    [depends: 1]
  Task 4:  Projection staleness check           [depends: 1]
  Task 5:  Session resolution helpers           [depends: 1]

Phase 2: Simple Commands (Tasks 6-8)
  Task 6:  gc-query status                      [depends: 3, 4]
  Task 7:  gc-query events                      [depends: 3, 5]
  Task 8:  gc-query tail                        [depends: 7]

Phase 3: Core Recovery (Tasks 9-12)
  Task 9:  Context projection loader            [depends: 4]
  Task 10: Output formatters (md/text/compact)  [depends: 9]
  Task 11: gc-query last                        [depends: 5, 9, 10]
  Task 12: gc-query session                     [depends: 5, 9, 10]

Phase 4: Advanced Features (Tasks 13-18)
  Task 13: Cross-session chaining               [depends: 9, 10]
  Task 14: PreCompact hook (eager build)        [depends: 9]
  Task 15: SessionStart hook (auto inject)      [depends: 10, 14]
  Task 16: gc-query sessions                    [depends: 2, 3]
  Task 17: gc-query search                      [depends: 3, 5]
  Task 18: gc-query replay                      [depends: 3, 5, 7]

Phase 5: Polish (Tasks 19-20)
  Task 19: gc-query doctor                      [depends: 3]
  Task 20: Edge case hardening                  [depends: all]
```

### Parallelization Notes

- Tasks 1 and 2 can be done in parallel.
- Tasks 4 and 5 can be done in parallel (both depend only on Task 1).
- Tasks 6, 7 can be done in parallel (both depend on Task 3 but not each other).
- Tasks 16, 17, 18 can be done in parallel (independent commands).
- Task 14 and Tasks 16-18 can be done in parallel.

---

## Dependency Graph

```
Task 1 (store-path.sh)
  |
  +-- Task 3 (gc-query entry point)
  |     |
  |     +-- Task 6 (status) -------- Task 4 (staleness check)
  |     |
  |     +-- Task 7 (events) -------- Task 5 (session resolve)
  |     |     |
  |     |     +-- Task 8 (tail)
  |     |
  |     +-- Task 16 (sessions) ----- Task 2 (session read model)
  |     +-- Task 17 (search) ------- Task 5
  |     +-- Task 18 (replay) ------- Task 5, Task 7
  |     +-- Task 19 (doctor)
  |
  +-- Task 4 (staleness)
  |     |
  |     +-- Task 9 (context loader)
  |           |
  |           +-- Task 10 (formatters)
  |           |     |
  |           |     +-- Task 11 (last) ----------- Task 5
  |           |     +-- Task 12 (session) -------- Task 5
  |           |     +-- Task 13 (chaining)
  |           |     +-- Task 15 (SessionStart hook) -- Task 14
  |           |
  |           +-- Task 14 (PreCompact hook)
  |
  +-- Task 5 (session resolve)

Task 20 (edge cases) -- depends on all above
```

---

## Complexity Summary

| Complexity | Count | Tasks |
|------------|-------|-------|
| S (Small)  | 7     | 1, 2, 4, 5, 7, 8, 12 |
| M (Medium) | 9     | 3, 6, 9, 11, 13, 14, 18, 19, 20 |
| L (Large)  | 2     | 10, 15, 17 |

**Estimated total effort**: Approximately 8-12 days for a single developer, or 5-7 days with two developers working in parallel on independent tasks.

---

## Testing Strategy

### Unit Test Fixtures

Create test fixtures at `~/.claude-context/test/fixtures/` with:

1. **test-session-simple/**: 14 events covering all event types (SessionStarted, UserPromptReceived, ToolCallRequested x3, ToolCallCompleted x3, ToolCallFailed x1, TurnCompleted x2, CompactionTriggered x1, SessionEnded x1).
2. **test-session-empty/**: Directory exists, no event files.
3. **test-session-corrupt/**: Mix of valid and corrupt event files.
4. **test-session-large/**: 500+ events for performance testing.
5. **test-session-chain/**: Three sessions linked by previous_session_id for chaining tests.

### Integration Test Script

Create `~/.claude-context/test/test-story-05.sh` that runs all acceptance tests:

```bash
# T01: gc-query with no sessions
# T02: gc-query last with one session
# T03: gc-query last --format json
# T04: gc-query session <id> valid
# T05: gc-query session <id> invalid
# T06: gc-query session <prefix> unique
# T07: gc-query sessions listing
# T08: gc-query sessions --project filter
# T09: gc-query search keyword in prompts
# T10: gc-query search keyword in tool calls
# T11: gc-query events raw output
# T12: gc-query events --from --to range
# T13: gc-query replay narrative
# T14: gc-query tail last N
# T15: gc-query status
# T16: Projection cache hit
# T17: Projection rebuild on stale
# T18: Progressive summarization at 100+ events
# T19: Output truncation at 200KB
# T20: Corrupt event handling
# T21: gc-query doctor
# T22: PreCompact -> SessionStart flow
# T23: Session chain with --include-parent
# T24: CLAUDE_CONTEXT_PATH override
# T25: _last_sequence staleness check
```

### Manual Verification Checklist

- [ ] Start a Claude session, do work, let it compact, verify auto-recovery injects context
- [ ] Start a new session, type "get last context", verify gc-query output is consumed by the LLM
- [ ] Run `gc-query sessions` in terminal, verify readable output
- [ ] Run `gc-query search` for a known keyword, verify results
- [ ] Run `gc-query replay` and verify the narrative is accurate
- [ ] Run `gc-query doctor` and verify all checks pass
- [ ] Set `CLAUDE_CONTEXT_PATH` to a custom path and verify all commands work
