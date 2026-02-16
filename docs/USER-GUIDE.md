# GlobalContext User Guide

GlobalContext is an event-sourced context store for Claude Code sessions. It captures every hook event as immutable JSON and provides powerful query and projection capabilities for context recovery.

**What it does**: Ensures no context is ever truly lost across compactions, session changes, or restarts.

**Where it lives**: `~/.claude-context/`

**Current version**: 1.0.0

---

## Table of Contents

1. [Installation](#1-installation)
2. [How It Works](#2-how-it-works)
3. [Querying Your Context](#3-querying-your-context)
4. [Understanding Projections](#4-understanding-projections)
5. [Context Recovery](#5-context-recovery-the-killer-feature)
6. [Event Types Reference](#6-event-types-reference)
7. [Configuration](#7-configuration)
8. [Uninstalling](#8-uninstalling)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Installation

### Prerequisites

GlobalContext requires the following tools (typically pre-installed on most systems):

- **bash 4+** (bash 5 recommended)
- **jq 1.5+** (JSON query tool)
- **node 18+** (for projection engine and query commands)
- **sha256sum** or **shasum** (for project ID hashing)

Optional but recommended:
- **flock** (for concurrent write coordination)
- **git** (for version tracking)
- **uuidgen** (for event ID generation; falls back to bash-native if missing)

### Running gc-install

From the GlobalContext repository:

```bash
# Navigate to the repository
cd /home/meywd/GlobalContext

# Run the installer
./src/bin/gc-install
```

This will:
1. Check prerequisites
2. Deploy scripts to `~/.claude-context/bin/`
3. Create directory structure: `events/`, `projections/`
4. Register hooks in `~/.claude/settings.json`
5. Run health checks

Expected output:
```
GlobalContext Installer v1.0.0
==============================

Checking prerequisites...
  bash 5.2         ok
  jq 1.7.1         ok
  node 22.1.0      ok
  sha256sum        ok

Deploying source files to /home/user/.claude-context...
  bin/capture-event       installed
  bin/gc-hook             installed
  bin/gc-query            installed
  bin/project             installed
  ...

Registering hooks...
  10 hooks registered in ~/.claude/settings.json

Installation complete!
```

### Installation Flags

| Flag | Purpose |
|------|---------|
| `--force` | Overwrite all files even if versions match (useful for repairs) |
| `--skip-hooks` | Deploy files but don't register hooks (for development/testing) |
| `--dry-run` | Show what would be done without making changes |

Examples:
```bash
# Force reinstall
gc-install --force

# Install without hooks (manual testing)
gc-install --skip-hooks

# Preview installation
gc-install --dry-run
```

### Verifying Installation

Run the doctor command to verify everything is working:

```bash
gc-query doctor
```

Expected output:
```
GlobalContext Doctor
====================
[PASS] Store directory exists
[PASS] Store is writable
[PASS] Required directories exist
[PASS] config.json is valid
[PASS] All bin/ scripts executable
[PASS] Hooks registered (10/10)
[PASS] End-to-end test: write/read ok

Result: ALL CHECKS PASSED
```

---

## 2. How It Works

### The Event Capture Pipeline

Every time Claude Code fires a hook event, GlobalContext captures it:

```
Claude Code Hook → gc-hook wrapper → capture-event → JSON file
```

**Example flow**:
1. User submits a prompt
2. `UserPromptSubmit` hook fires
3. `gc-hook` receives hook payload on stdin
4. `capture-event` wraps it in an event envelope
5. Event written to `~/.claude-context/events/{project-id}/{session-id}/000042.json`
6. Per-session `session.json` updated

### Event File Naming

Events are numbered sequentially within each session:

```
000001.json   # First event (typically SessionStarted)
000002.json   # Second event
000003.json   # Third event
...
000142.json   # 142nd event
```

6-digit zero-padded numbers ensure proper alphabetical sorting.

### Per-Project Isolation

Events are organized by project to prevent cross-project contamination:

```
~/.claude-context/
  events/
    my-project-a3f7b2/           # Project 1
      session-abc-123/
        session.json
        000001.json
        000002.json
    another-project-e91c04/      # Project 2
      session-xyz-789/
        session.json
        000001.json
```

**Project ID format**: `{basename}-{hash6}`

Where:
- `basename` = last component of project path (sanitized)
- `hash6` = first 6 hex chars of SHA-256 hash of full path

Examples:
- `/home/user/my-project` → `my-project-a3f7b2`
- `/home/user/work/my-project` → `my-project-e91c04` (different hash)

### Per-Session Directories

Each session gets its own isolated directory:

```
events/{project-id}/{session-id}/
  session.json          # Session metadata
  .lock                 # Coordination lock for concurrent writes
  000001.json           # Event files (sequence numbered)
  000002.json
  ...
```

### Session Metadata (session.json)

Each session directory contains a `session.json` file with metadata:

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

This metadata is updated atomically within the same lock as event writes.

---

## 3. Querying Your Context

All queries use the `gc-query` command with subcommands.

### gc-query store-size

Check how much data you have stored.

```bash
gc-query store-size
```

**Output (text)**:
```
GlobalContext Store: /home/user/.claude-context
Sessions:      15
Total events:  3,247
Total size:    12.4 MB
Oldest:        2026-01-15 (session abc-123)
Newest:        2026-02-14 (session xyz-789)
```

**JSON output**:
```bash
gc-query store-size --format json
```

### gc-query status

Health check and statistics for the current project.

```bash
gc-query status
```

**Output**:
```
Store:          /home/user/.claude-context
Project:        my-project-a3f7b2 (/home/user/my-project)
Sessions:       5
Total events:   847
Latest session: abc-123 (started 2026-02-14 10:00:00)
Projections:    3 current, 2 stale
```

Flags:
- `--format json` - JSON output
- `--all-projects` - Store-wide stats across all projects

### gc-query sessions

List all sessions with metadata.

```bash
gc-query sessions
```

**Output**:
```
SESSION ID   STARTED              PROJECT                      EVENTS  STATE
abc-123      2026-02-14 10:00:00  /home/user/my-project        142     active
xyz-789      2026-02-13 15:30:00  /home/user/my-project        87      ended
def-456      2026-02-12 09:15:00  /home/user/my-project        231     compacted
```

**Filters**:
```bash
# Last week only
gc-query sessions --since 1w

# Compacted sessions only
gc-query sessions --state compacted

# Limit to 5 results
gc-query sessions --limit 5

# All projects
gc-query sessions --all-projects

# Specific project
gc-query sessions --project /home/user/other-project
```

**JSON output**:
```bash
gc-query sessions --format json
```

### gc-query last

Get context from the most recent session (current project).

```bash
gc-query last
```

**Output formats**:
```bash
# Markdown (default, LLM-friendly)
gc-query last

# JSON (programmatic access)
gc-query last --format json

# Plain text (human-readable, no markdown)
gc-query last --format text

# Compact (single line summary)
gc-query last --format compact
```

**Including parent sessions**:
```bash
# Follow the session chain
gc-query last --include-parent
```

This follows `previous_session_id` links to show context from earlier sessions in the chain.

### gc-query session

Get context from a specific session.

```bash
# Full session ID
gc-query session abc-123-def-456

# Partial ID (unique prefix)
gc-query session abc

# With parent chain
gc-query session abc --include-parent

# Different format
gc-query session abc --format json
```

If the partial ID matches multiple sessions, it lists matches:
```
Error: Ambiguous session ID 'ab'. Matches:
  abc-123-def
  abc-456-ghi
```

### gc-query events

Access raw event JSON for a session.

```bash
# All events (JSONL format, one per line)
gc-query events abc-123

# Specific range
gc-query events abc-123 --from 10 --to 20

# Filter by type
gc-query events abc-123 --type ToolCallCompleted

# JSON array output
gc-query events abc-123 --format json
```

### gc-query tail

Show the last N events from a session.

```bash
# Last 20 events (default)
gc-query tail abc-123

# Last 5 events
gc-query tail abc-123 5

# Last 50 events, specific format
gc-query tail abc-123 50 --format json
```

### gc-query search

Search across sessions for keywords.

```bash
# Search in prompts and tool results
gc-query search "authentication"

# Case-sensitive search
gc-query search --case-sensitive "AuthHandler"

# Search in prompts only
gc-query search --type UserPromptReceived "rate limiting"

# Limit results
gc-query search "test" --limit 5

# Search for file paths
gc-query search --file "src/auth/handler.ts"

# Search all projects
gc-query search "bug fix" --all-projects
```

**Output**:
```
Session abc-123, Event #42 (UserPromptReceived):
  "...need to fix the authentication bug in the login handler..."

Session abc-123, Event #87 (ToolCallCompleted):
  Read: /home/user/project/src/auth/handler.ts
  "...exports class AuthHandler..."

2 results found
```

### gc-query replay

Human-readable narrative of what happened in a session.

```bash
# Full replay
gc-query replay abc-123

# Specific range
gc-query replay abc-123 --from 10 --to 50

# Verbose (full payloads)
gc-query replay abc-123 --verbose

# Markdown format
gc-query replay abc-123 --format markdown
```

**Output**:
```
Step 1: Session started in /home/user/my-project (source: manual)
Step 2: User: "Fix the failing test in auth.test.js"
Step 3: Agent plans to use Read on file_path=auth.test.js
Step 4: Executed Read: 156 lines, test file for authentication
Step 5: Agent plans to use Edit on file_path=auth.test.js
Step 6: Executed Edit: replaced 3 lines in auth.test.js
Step 7: Turn completed
Step 8: User: "Run the test to verify"
...
```

### gc-query doctor

End-to-end health check of the entire system.

```bash
gc-query doctor
```

**Output**:
```
GlobalContext Doctor
====================
[PASS] Store directory exists
[PASS] Store is writable
[PASS] Required directories exist
[PASS] config.json is valid (version: 1.0.0)
[PASS] capture-event is executable
[PASS] project is executable
[PASS] gc-query is executable
[PASS] Hooks registered (10/10)
[PASS] jq available (jq-1.7.1)
[PASS] Disk space: 2.1GB free
[PASS] Latest symlink (my-project-a3f7b2): -> abc-123
[PASS] Sample event: valid
[PASS] Sample session.json: valid
[PASS] No stale global files

Result: 14 passed, 0 failed
```

Flags:
- `--format json` - JSON output for programmatic use
- `--verbose` - Show detailed information for each check

---

## 4. Understanding Projections

### What Are Projections?

Projections are materialized views built from event streams. They answer specific questions without replaying all events every time.

**Five projection types**:

| Projection | Purpose | File |
|------------|---------|------|
| `timeline` | Ordered summary of what happened | `timeline.json` |
| `files-touched` | All file operations in sequence | `files-touched.json` |
| `decisions` | User prompts + resulting actions | `decisions.json` |
| `context` | Full context snapshot for recovery | `context.json` |
| `summary` | High-level session summary | `summary.json` |

### How They're Built

Projections are built on demand by the `project` CLI:

```bash
# Build a specific projection
project timeline abc-123
project files abc-123
project decisions abc-123
project context abc-123
project summary abc-123
```

When you run `gc-query last`, it:
1. Checks if `context.json` is current (compares `_last_sequence` to latest event)
2. If stale or missing, calls `project context <session-id>` to rebuild
3. Reads the cached projection
4. Formats output

### Projection Metadata

All projection files contain metadata:

```json
{
  "_projection": "context",
  "_project_id": "my-project-a3f7b2",
  "_session_id": "abc-123",
  "_rebuilt_at": "2026-02-14T11:45:00Z",
  "_event_count": 142,
  "_last_sequence": 142,
  "data": { }
}
```

The `_last_sequence` field is crucial for staleness detection.

### Where They're Cached

```
~/.claude-context/
  projections/
    my-project-a3f7b2/           # Per-project
      abc-123/                    # Per-session
        timeline.json
        files-touched.json
        decisions.json
        context.json
        summary.json
      latest -> abc-123            # Symlink to latest session
```

### Output Formats

Most projections support multiple output formats:

```bash
# JSON (default, for programmatic use)
project timeline abc-123 --format json

# Text (human-readable)
project timeline abc-123 --format text

# Markdown (LLM-friendly)
project timeline abc-123 --format markdown

# Write to stdout only (no cache file)
project timeline abc-123 --output -
```

### Rebuilding Projections

Projections are automatically rebuilt when stale, but you can force a rebuild:

```bash
# Force full rebuild from scratch
project context abc-123 --rebuild

# Rebuild from a specific sequence
project context abc-123 --from 50
```

---

## 5. Context Recovery (The Killer Feature)

### The Problem

When Claude Code compacts, starts a new session, or you clear the conversation, all the rich detail of what happened is normally lost. GlobalContext solves this.

### Automatic Context Injection

When a session starts after compaction or clearing, GlobalContext automatically injects previous context into the new session:

**Flow**:
1. `PreCompact` hook fires → context.json projection built eagerly
2. Compaction occurs
3. New session starts
4. `SessionStart` hook fires → reads pre-built context.json
5. Injects compact markdown summary as `additionalContext`
6. Claude has full awareness of what happened before

**No user action required**. The LLM just knows what was happening.

### Manual Context Recovery

You can manually load context at any time:

```bash
# Get last context in markdown (paste into Claude)
gc-query last

# Get specific session context
gc-query session abc-123

# Include parent session context
gc-query last --include-parent
```

**Typical workflow**:
1. Session compacts or ends unexpectedly
2. Open terminal
3. Run `gc-query last --format markdown`
4. Copy output
5. Paste into new Claude session
6. Say: "Here's what we were working on before"

### Session Chaining

Sessions can be linked via `previous_session_id`:

```json
{
  "session_id": "new-session-123",
  "previous_session_id": "old-session-456",
  ...
}
```

Using `--include-parent` follows this chain:

```bash
gc-query last --include-parent
```

**Output structure**:
```markdown
## Session Context Recovery (Session Chain)

### Current Session: new-session-123
[Full context with all details]

---

### Parent Session: old-session-456
[Compact summary: key accomplishments, files modified, where left off]

---

### Grandparent Session: older-session-789
[One-line summary]
```

Progressive summarization keeps output manageable:
- **Current session**: Full detail
- **Parent (depth 1)**: Compact summary
- **Ancestors (depth 2+)**: One-liner only
- **Max depth**: 10 sessions (chain breaks with note if deeper)

### Context Recovery Skills

GlobalContext integrates with Claude Code skills:

**`/context-recovery` skill**:
Automatically fetches and formats context from the previous session.

**`context-investigator` agent**:
Interactive agent that helps explore session history, search for specific events, and reconstruct context from multiple sessions.

---

## 6. Event Types Reference

GlobalContext captures 10 event types from Claude Code hooks:

| Event Type | Hook | Sync/Async | Data Captured |
|------------|------|------------|---------------|
| `SessionStarted` | SessionStart | sync | session_id, cwd, model, source (manual/compact/clear/resume), previous_session_id |
| `UserPromptReceived` | UserPromptSubmit | sync | prompt text (full, no truncation) |
| `ToolCallRequested` | PreToolUse | async | tool_name, tool_input (parameters), request_id |
| `ToolCallCompleted` | PostToolUse | async | tool_name, tool_input, tool_result (full output), duration, request_id |
| `ToolCallFailed` | PostToolUseFailure | async | tool_name, tool_input, error_message, error_type, request_id |
| `AgentSpawned` | SubagentStart | async | agent_type, agent_description, agent_id |
| `AgentCompleted` | SubagentStop | async | agent_id, agent_type, status, result_summary |
| `TurnCompleted` | Stop | async | turn_count, tokens_used, cost |
| `CompactionTriggered` | PreCompact | sync | reason, context_size_before, compaction_timestamp |
| `SessionEnded` | SessionEnd | async | end_reason, duration_seconds, final_event_count |

**Sync vs Async**:
- **Sync**: Hook must complete before Claude Code continues (5s timeout). Used for critical events.
- **Async**: Hook runs in background (5s timeout). Used for high-frequency events to avoid latency.

### Event Envelope Schema

Every event file contains:

```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "event_type": "ToolCallCompleted",
  "project_id": "my-project-a3f7b2",
  "session_id": "abc-123",
  "sequence": 42,
  "timestamp": "2026-02-14T10:30:00.000Z",
  "data": {
    "tool_name": "Read",
    "tool_input": { "file_path": "/home/user/project/src/auth.ts" },
    "tool_result": "export class AuthHandler { ... }",
    "duration_ms": 23
  }
}
```

**7 required fields**:
1. `event_id` - UUID v4
2. `event_type` - One of the 10 types above
3. `project_id` - Derived from cwd
4. `session_id` - From hook payload
5. `sequence` - Monotonically increasing per session
6. `timestamp` - ISO 8601 UTC
7. `data` - Event-specific payload (always an object)

---

## 7. Configuration

### config.json Location

`~/.claude-context/config.json`

**Default contents**:
```json
{
  "version": "1.0.0",
  "created_at": "2026-02-14T10:00:00.000Z",
  "storage_path": "/home/user/.claude-context",
  "checksum": false
}
```

**Fields**:
- `version`: Config schema version (not software version)
- `created_at`: When the store was initialized
- `storage_path`: Base directory (matches `CLAUDE_CONTEXT_PATH` or default)
- `checksum`: Whether to compute checksums for events (not currently used)

**Note**: This config is created once during `gc-init` and never overwritten by upgrades. Custom fields are preserved.

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_CONTEXT_PATH` | `~/.claude-context` | Override base storage directory |
| `GC_DEBUG` | (unset) | Enable debug logging when set to `1` |

**Examples**:
```bash
# Use custom storage location
export CLAUDE_CONTEXT_PATH=/mnt/storage/claude-context
gc-query last

# Enable debug output
export GC_DEBUG=1
gc-query last
```

### Hook Timeout

All hooks have a 5-second timeout configured in `~/.claude/settings.json`.

**Why 5 seconds**:
- Event capture is just a file append (fast)
- Projection builds happen in PreCompact (sync) and have time to complete
- Async hooks (PostToolUse, etc.) run in background and won't block

**If hooks timeout**:
- Async hooks: Event capture fails but session continues
- Sync hooks (PreCompact, SessionStart): May interrupt the operation
- Check `gc-query doctor` to diagnose

---

## 8. Uninstalling

### Soft Uninstall (Default)

Removes hooks and scripts but preserves all event data.

```bash
gc-uninstall
```

**What's removed**:
- Hooks from `~/.claude/settings.json`
- Scripts from `~/.claude-context/bin/`
- Libraries from `~/.claude-context/lib/`
- VERSION file

**What's preserved**:
- `events/` directory (all captured events)
- `projections/` directory (all cached projections)
- `config.json`

After soft uninstall, you can reinstall and pick up where you left off:
```bash
gc-install
```

### Full Uninstall (Purge)

Removes everything including all event data.

```bash
gc-uninstall --purge
```

**Confirmation required**:
```
WARNING: This will permanently delete all captured event data.
  Sessions: 15
  Events: 3,247
  Size: 12.4 MB

Type 'yes' to confirm:
```

**Skip confirmation** (for scripts):
```bash
gc-uninstall --purge --force
```

### Dry Run

Preview what would be removed:

```bash
gc-uninstall --dry-run
gc-uninstall --purge --dry-run
```

---

## 9. Troubleshooting

### Running Diagnostics

Start with the doctor command:

```bash
gc-query doctor
```

This checks:
- Store directory exists and is writable
- Required directories (events/, projections/, bin/)
- config.json validity
- Script executability
- Hook registration
- jq availability
- Disk space
- Sample event and session.json validity

### Common Issues

#### "jq: command not found"

**Problem**: jq is not installed.

**Solution**:
```bash
# Debian/Ubuntu
sudo apt install jq

# macOS
brew install jq

# Verify
jq --version
```

#### "Store not initialized"

**Problem**: `~/.claude-context/` does not exist.

**Solution**:
```bash
gc-install
```

#### "Hooks not registered"

**Problem**: `~/.claude/settings.json` missing hook entries.

**Solution**:
```bash
# Re-register hooks
~/.claude-context/bin/gc-install-hooks install

# Or reinstall
gc-install --force
```

#### "No sessions found"

**Problem**: No events have been captured yet.

**Verify hooks are working**:
1. Start a Claude Code session
2. Submit a prompt
3. Check for event files:
   ```bash
   ls -la ~/.claude-context/events/
   ```

If no events appear:
- Run `gc-query doctor` to check hooks
- Check `~/.claude/settings.json` for GlobalContext hooks
- Restart Claude Code

#### "Projection is stale / corrupt"

**Problem**: Cached projection is out of date or malformed.

**Solution**:
```bash
# Force rebuild
project context <session-id> --rebuild

# Or delete and let it rebuild automatically
rm ~/.claude-context/projections/<project-id>/<session-id>/context.json
gc-query last
```

#### "Permission denied"

**Problem**: Store directory has wrong permissions.

**Solution**:
```bash
# Reset permissions
chmod 700 ~/.claude-context
chmod 700 ~/.claude-context/events
chmod 700 ~/.claude-context/projections
chmod 755 ~/.claude-context/bin/*
```

#### Large Store Size

**Check size**:
```bash
gc-query store-size
```

**Expected growth**: ~11GB per 90 days of heavy use (based on design assumptions).

**Options**:
1. Accept the disk usage (storage is cheap, context is valuable)
2. Archive old sessions:
   ```bash
   # Move events to archive location
   mkdir ~/claude-context-archive
   mv ~/.claude-context/events/old-project-* ~/claude-context-archive/
   ```
3. Manually delete old projects (events are immutable, so deletion is permanent):
   ```bash
   # CAUTION: Permanent deletion
   rm -rf ~/.claude-context/events/old-project-abc123
   rm -rf ~/.claude-context/projections/old-project-abc123
   ```

**Note**: `gc-cleanup` command is not implemented (contradicts append-only principle). Disk space management is manual.

### Debug Logging

Enable debug output:

```bash
export GC_DEBUG=1
gc-query last
```

This shows:
- Path resolution details
- Event file reads
- Projection cache hits/misses
- Hook execution trace

### Stale Symlinks

Check per-project latest symlink:

```bash
# View symlink target
ls -la ~/.claude-context/projections/my-project-*/latest

# Manually fix broken symlink
cd ~/.claude-context/projections/my-project-a3f7b2
rm latest
ln -s <actual-latest-session-id> latest
```

### Orphan Temp Files

Find orphan temp files from interrupted writes:

```bash
find ~/.claude-context/events -name '*.tmp.*'
```

These are safe to delete:
```bash
find ~/.claude-context/events -name '*.tmp.*' -delete
```

Or run `gc-init` which cleans them automatically.

### Getting Help

1. Run `gc-query doctor` and check all diagnostics
2. Check `~/.claude/settings.json` for hook configuration
3. Verify `CLAUDE_CONTEXT_PATH` if using custom location
4. Check disk space: `df -h ~/.claude-context`
5. Review this guide's troubleshooting section
6. Check project documentation in `/home/meywd/GlobalContext/docs/`

---

## Appendix: File Structure Reference

```
~/.claude-context/                     # Base directory (configurable via CLAUDE_CONTEXT_PATH)
  bin/
    capture-event                      # Event capture script (from Story 01)
    gc-hook                            # Hook wrapper (from Story 02)
    gc-install-hooks                   # Hook registration (from Story 02)
    gc-init                            # Store initialization (from Story 03)
    gc-query                           # Query CLI (from Story 05)
    gc-doctor                          # Health check (from Story 00)
    gc-uninstall                       # Uninstaller (from Story 02/00)
    project                            # Projection engine (from Story 04)
  lib/
    paths.sh                           # Path resolution
    sanitize.sh                        # Session ID sanitization
    session_dir.sh                     # Session directory management
    atomic_write.sh                    # Atomic file writes
    json_validate.sh                   # JSON validation
    event_write.sh                     # Event writing pipeline
    session_meta.sh                    # session.json management
    config.sh                          # config.json helpers
    latest_symlink.sh                  # Symlink management
    projection_store.sh                # Projection storage
    ... (additional libraries)
  events/
    {project-id}/                      # e.g., my-project-a3f7b2
      {session-id}/                    # e.g., abc-123-def-456
        session.json                   # Session metadata
        .lock                          # Coordination lock
        000001.json                    # First event
        000002.json                    # Second event
        ...
        _rejected/                     # Invalid events (debugging)
  projections/
    {project-id}/                      # e.g., my-project-a3f7b2
      {session-id}/                    # e.g., abc-123-def-456
        timeline.json
        files-touched.json
        decisions.json
        context.json
        summary.json
      latest -> {session-id}           # Symlink to latest session in project
  config.json                          # Store configuration
  VERSION                              # Software version
```

**Key principles**:
- **Project ID layer**: Events and projections organized by project
- **Per-session isolation**: Each session has its own directory
- **Immutable events**: Event files are never modified after creation
- **On-demand projections**: Built when needed, cached for speed
- **No global state**: No shared index files (per-session session.json only)

---

**Version**: 1.0.0
**Last Updated**: 2026-02-15
**Project**: GlobalContext Event-Sourced Context Store
**Repository**: `/home/meywd/GlobalContext/`
