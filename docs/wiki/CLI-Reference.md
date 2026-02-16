# CLI Reference

Complete reference for all GlobalContext commands. Commands are organized by category: initialization, querying, and utilities.

## Table of Contents

- [Installation Commands](#installation-commands)
- [Query Commands](#query-commands)
- [Utility Commands](#utility-commands)
- [Common Flags](#common-flags)
- [Environment Variables](#environment-variables)

## Installation Commands

### gc-install

Install GlobalContext to `~/.claude-context/` and set up the event store.

**Synopsis**:
```bash
gc-install [options]
```

**Description**:
Creates directory structure, installs scripts, validates dependencies, and creates initial configuration.

**Flags**:

| Flag | Description |
|------|-------------|
| `--help` | Show help message |

**Examples**:
```bash
# Install GlobalContext
gc-install

# Check what would be installed
gc-install --help
```

**Notes**:
- Idempotent: safe to run multiple times
- Validates jq, flock, Node.js are available
- Creates `~/.claude-context/events/`, `projections/`, `bin/`
- Does not modify `~/.claude/settings.json` (use plugin or gc-install-hooks)

### gc-uninstall

Remove GlobalContext installation.

**Synopsis**:
```bash
gc-uninstall [options]
```

**Description**:
Removes installed scripts and configuration. Optionally removes event data.

**Flags**:

| Flag | Description |
|------|-------------|
| `--keep-data` | Preserve events and projections (default) |
| `--purge` | Delete all events and projections |
| `--help` | Show help message |

**Examples**:
```bash
# Remove scripts but keep data
gc-uninstall --keep-data

# Complete removal including all events
gc-uninstall --purge
```

### gc-init

Initialize the GlobalContext store.

**Synopsis**:
```bash
gc-init
```

**Description**:
Creates the directory structure at `~/.claude-context/`. Called automatically on first SessionStart hook if using the plugin.

**Examples**:
```bash
# Manually initialize store
gc-init
```

**Notes**:
- Idempotent: safe to run multiple times
- Creates events/, projections/, bin/ if missing
- Creates config.json with defaults

### gc-install-hooks

Install or uninstall hook configuration (manual installation only).

**Synopsis**:
```bash
gc-install-hooks <command>
```

**Arguments**:

| Argument | Description |
|----------|-------------|
| `install` | Add hooks to ~/.claude/settings.json |
| `uninstall` | Remove hooks from ~/.claude/settings.json |
| `status` | Show current hook installation status |

**Description**:
Manages hook configuration in `~/.claude/settings.json`. Creates backup before modifying.

**Examples**:
```bash
# Install hooks
gc-install-hooks install

# Check status
gc-install-hooks status

# Remove hooks
gc-install-hooks uninstall
```

**Notes**:
- Not needed when using plugin (hooks auto-configured)
- Creates backup at `~/.claude/settings.json.backup.TIMESTAMP`
- Preserves existing user hooks

## Query Commands

### gc-query

Primary command for querying the event store and projections.

**Synopsis**:
```bash
gc-query <subcommand> [options]
```

**Subcommands**:

| Subcommand | Description |
|------------|-------------|
| `last` | Get context from most recent session |
| `session` | Get context from specific session |
| `sessions` | List all sessions |
| `search` | Search events across sessions |
| `replay` | Replay session events as narrative |
| `events` | Raw event access |
| `tail` | Show last N events |
| `status` | Store health and statistics |
| `store-size` | Disk usage and event counts |
| `doctor` | Health check and diagnostics |

### gc-query last

Retrieve context from the most recent session in the current project.

**Synopsis**:
```bash
gc-query last [options]
```

**Flags**:

| Flag | Default | Description |
|------|---------|-------------|
| `--format <format>` | `markdown` | Output format: `json`, `text`, `markdown`, `compact` |
| `--include-parent` | false | Include parent session context (if chained) |
| `--help` | - | Show help message |

**Examples**:
```bash
# Get last context as markdown
gc-query last

# Get as JSON
gc-query last --format json

# Get as compact text
gc-query last --format compact

# Include parent session
gc-query last --include-parent
```

**Output**:
Returns the context projection for the most recent session, including:
- Session metadata (started_at, model, project directory)
- All user prompts
- Key tool calls and results
- Files modified
- Last state (what you were working on)
- Compaction markers

**Notes**:
- Scopes to current project (derived from cwd)
- Follows `projections/{project-id}/latest` symlink
- Builds or updates context projection if stale
- Output truncated at 200KB for compact format

### gc-query session

Retrieve context from a specific session.

**Synopsis**:
```bash
gc-query session <session-id> [options]
```

**Arguments**:

| Argument | Required | Description |
|----------|----------|-------------|
| `<session-id>` | Yes | Full session ID or unique prefix |

**Flags**:

| Flag | Default | Description |
|------|---------|-------------|
| `--format <format>` | `markdown` | Output format: `json`, `text`, `markdown`, `compact` |
| `--include-parent` | false | Include parent session context |
| `--help` | - | Show help message |

**Examples**:
```bash
# Get specific session by ID
gc-query session abc123def456

# Using prefix (must be unique)
gc-query session abc

# Get as JSON
gc-query session abc123 --format json

# Include parent session chain
gc-query session abc123 --include-parent
```

**Notes**:
- Supports prefix matching (e.g., `abc` matches `abc123def456` if unique)
- Returns error if prefix is ambiguous
- Scopes to current project

### gc-query sessions

List all sessions with metadata.

**Synopsis**:
```bash
gc-query sessions [options]
```

**Flags**:

| Flag | Default | Description |
|------|---------|-------------|
| `--format <format>` | `text` | Output format: `json`, `text` |
| `--all-projects` | false | List sessions from all projects |
| `--limit <n>` | unlimited | Limit output to N most recent sessions |
| `--help` | - | Show help message |

**Examples**:
```bash
# List sessions in current project
gc-query sessions

# List all sessions across all projects
gc-query sessions --all-projects

# List 10 most recent
gc-query sessions --limit 10

# Get as JSON
gc-query sessions --format json
```

**Output Columns** (text format):

| Column | Description |
|--------|-------------|
| Session ID | Unique session identifier (truncated) |
| Started | Start timestamp |
| Events | Number of events captured |
| Last Event | Most recent event type |
| Last Prompt | Preview of last user prompt |

**Notes**:
- Sorted by started_at descending (most recent first)
- Scans event directories and reads session.json files
- Does not build projections

### gc-query search

Search across sessions for events matching a keyword.

**Synopsis**:
```bash
gc-query search <keyword> [options]
```

**Arguments**:

| Argument | Required | Description |
|----------|----------|-------------|
| `<keyword>` | Yes | Search term (plain text or regex) |

**Flags**:

| Flag | Default | Description |
|------|---------|-------------|
| `--format <format>` | `text` | Output format: `json`, `text` |
| `--all-projects` | false | Search all projects |
| `--type <event-type>` | all | Filter by event type |
| `--limit <n>` | 100 | Max results to return |
| `--case-sensitive` | false | Case-sensitive search |
| `--help` | - | Show help message |

**Examples**:
```bash
# Search for "authentication"
gc-query search authentication

# Case-sensitive search
gc-query search "API_KEY" --case-sensitive

# Search only UserPromptReceived events
gc-query search "bug fix" --type UserPromptReceived

# Search all projects
gc-query search "error" --all-projects

# Limit to 20 results
gc-query search "test" --limit 20
```

**Output**:
For each match:
- Session ID
- Sequence number
- Event type
- Timestamp
- Matching context (snippet)

**Notes**:
- Searches event data payloads (JSON)
- Case-insensitive by default
- Supports basic regex patterns
- Results sorted by timestamp descending

### gc-query replay

Transform session events into a human-readable narrative.

**Synopsis**:
```bash
gc-query replay <session-id> [options]
```

**Arguments**:

| Argument | Required | Description |
|----------|----------|-------------|
| `<session-id>` | Yes | Session to replay |

**Flags**:

| Flag | Default | Description |
|------|---------|-------------|
| `--format <format>` | `text` | Output format: `json`, `text`, `markdown` |
| `--from <seq>` | 1 | Start from sequence number |
| `--to <seq>` | last | End at sequence number |
| `--help` | - | Show help message |

**Examples**:
```bash
# Replay entire session
gc-query replay abc123

# Replay sequence 10-50
gc-query replay abc123 --from 10 --to 50

# Output as markdown
gc-query replay abc123 --format markdown
```

**Output**:
Timeline projection formatted as narrative:
- Chronological sequence of events
- Summaries for each event type
- Tool inputs and outputs
- User prompts

**Notes**:
- Builds timeline projection
- Summaries generated from templates (no LLM calls)
- Useful for understanding session flow

### gc-query events

Raw event access for a session.

**Synopsis**:
```bash
gc-query events <session-id> [options]
```

**Arguments**:

| Argument | Required | Description |
|----------|----------|-------------|
| `<session-id>` | Yes | Session ID |

**Flags**:

| Flag | Default | Description |
|------|---------|-------------|
| `--format <format>` | `jsonl` | Output format: `json`, `jsonl` |
| `--from <seq>` | 1 | Start from sequence |
| `--to <seq>` | last | End at sequence |
| `--type <event-type>` | all | Filter by event type |
| `--help` | - | Show help message |

**Examples**:
```bash
# Get all events as JSONL
gc-query events abc123

# Get as JSON array
gc-query events abc123 --format json

# Get events 10-20
gc-query events abc123 --from 10 --to 20

# Get only ToolCallCompleted events
gc-query events abc123 --type ToolCallCompleted
```

**Output Formats**:

| Format | Description |
|--------|-------------|
| `jsonl` | One event per line (default, easy to pipe) |
| `json` | JSON array of events |

**Notes**:
- Returns raw event envelopes with complete data payloads
- Useful for debugging or custom analysis
- Can be piped to jq for filtering

### gc-query tail

Show last N events from a session.

**Synopsis**:
```bash
gc-query tail <session-id> [N] [options]
```

**Arguments**:

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `<session-id>` | Yes | - | Session ID |
| `N` | No | 20 | Number of events |

**Flags**:

| Flag | Default | Description |
|------|---------|-------------|
| `--format <format>` | `jsonl` | Output format: `json`, `jsonl` |
| `--help` | - | Show help message |

**Examples**:
```bash
# Last 20 events
gc-query tail abc123

# Last 50 events
gc-query tail abc123 50

# As JSON array
gc-query tail abc123 10 --format json
```

**Notes**:
- Equivalent to `gc-query events <session-id> --from <last-N>`
- Useful for checking recent activity

### gc-query status

Show store health and statistics for current project.

**Synopsis**:
```bash
gc-query status [options]
```

**Flags**:

| Flag | Default | Description |
|------|---------|-------------|
| `--format <format>` | `text` | Output format: `json`, `text` |
| `--all-projects` | false | Show status for all projects |
| `--help` | - | Show help message |

**Examples**:
```bash
# Status for current project
gc-query status

# Status for all projects
gc-query status --all-projects

# Get as JSON
gc-query status --format json
```

**Output**:
- Store location
- Current project ID
- Session count
- Total events
- Disk usage
- Latest session
- Projection count and staleness

**Notes**:
- Quick health check
- Does not trigger projection rebuilds

### gc-query store-size

Report disk usage and event counts across all projects.

**Synopsis**:
```bash
gc-query store-size [options]
```

**Flags**:

| Flag | Default | Description |
|------|---------|-------------|
| `--format <format>` | `text` | Output format: `json`, `text` |
| `--help` | - | Show help message |

**Examples**:
```bash
# Get store size
gc-query store-size

# Get as JSON
gc-query store-size --format json
```

**Output**:
- Total sessions across all projects
- Total events
- Total size (human-readable)
- Oldest session
- Newest session

**Notes**:
- Scans entire event store
- May take time for large stores (1000+ sessions)

### gc-query doctor

Run health checks on the event store.

**Synopsis**:
```bash
gc-query doctor [options]
```

**Flags**:

| Flag | Default | Description |
|------|---------|-------------|
| `--format <format>` | `text` | Output format: `json`, `text` |
| `--all-projects` | false | Check all projects |
| `--help` | - | Show help message |

**Examples**:
```bash
# Run health check
gc-query doctor

# Check all projects
gc-query doctor --all-projects
```

**Checks Performed**:
- Store directory exists and is writable
- Events directory structure
- Sequence gaps (missing event files)
- Corrupt JSON files
- Orphaned lock files
- Session metadata consistency
- Projection staleness
- Disk space

**Output**:
- Overall health status (healthy, warnings, errors)
- Detailed findings for each check
- Recommendations for issues found

**Notes**:
- Non-destructive (read-only checks)
- Useful for troubleshooting
- Returns exit code 0 if healthy, 1 if warnings, 2 if errors

## Utility Commands

### project

Build projections from events (low-level command).

**Synopsis**:
```bash
project <projection-type> <session-id> [options]
```

**Arguments**:

| Argument | Required | Description |
|----------|----------|-------------|
| `<projection-type>` | Yes | One of: `timeline`, `files`, `decisions`, `context`, `summary` |
| `<session-id>` | Yes | Session ID or `latest` |

**Flags**:

| Flag | Default | Description |
|------|---------|-------------|
| `--from <seq>` | 1 | Start from sequence |
| `--to <seq>` | last | End at sequence |
| `--rebuild` | false | Force full rebuild |
| `--format <format>` | `json` | Output format: `json`, `text`, `markdown` |
| `--output <path>` | default | Output file path (use `-` for stdout only) |
| `--quiet` | false | Suppress progress messages |
| `--help` | - | Show help message |

**Examples**:
```bash
# Build timeline for latest session
project timeline latest

# Build context projection for specific session
project context abc123

# Rebuild from scratch
project context abc123 --rebuild

# Build partial projection (sequences 10-50)
project timeline abc123 --from 10 --to 50

# Output to stdout as markdown
project context latest --format markdown --output -
```

**Projection Types**:

| Type | Output File | Description |
|------|-------------|-------------|
| `timeline` | timeline.json | Chronological event log |
| `files` | files-touched.json | All files read/written/edited |
| `decisions` | decisions.json | User prompts + resulting actions |
| `context` | context.json | Full session context for recovery |
| `summary` | summary.json | High-level metrics and narrative |

**Notes**:
- Usually called indirectly via gc-query commands
- Performs incremental rebuild by default (only new events)
- Use `--rebuild` after projection schema changes

### gc-hook

Hook wrapper script (internal, called by Claude Code).

**Synopsis**:
```bash
gc-hook <event-type>
```

**Arguments**:

| Argument | Required | Description |
|----------|----------|-------------|
| `<event-type>` | Yes | Event type (SessionStarted, UserPromptReceived, etc.) |

**Description**:
Receives hook JSON on stdin and passes to capture-event. Auto-initializes store on first SessionStart.

**Notes**:
- Called by Claude Code hook system
- Not intended for direct user invocation
- Always exits 0

## Common Flags

These flags are supported by multiple commands:

### Format Flags

| Format | Description | Used By |
|--------|-------------|---------|
| `json` | Machine-readable JSON | Most commands |
| `text` | Human-readable plain text | Most commands |
| `markdown` | Markdown formatted (LLM-friendly) | Context queries, replay |
| `compact` | Minimal text (no decorations) | last, session |
| `jsonl` | JSON Lines (one object per line) | events, tail |

### Filtering Flags

| Flag | Description | Used By |
|------|-------------|---------|
| `--from <seq>` | Start from sequence number | events, tail, replay, project |
| `--to <seq>` | End at sequence number | events, replay, project |
| `--type <event-type>` | Filter by event type | events, search |
| `--limit <n>` | Limit results | sessions, search |

### Scoping Flags

| Flag | Description | Used By |
|------|-------------|---------|
| `--all-projects` | Query all projects | status, sessions, search |
| `--include-parent` | Include parent session | last, session |

## Environment Variables

GlobalContext respects these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_CONTEXT_PATH` | `~/.claude-context` | Store location |
| `CLAUDE_PLUGIN_ROOT` | (plugin dir) | Plugin root (when installed as plugin) |
| `GC_PROJECT_DIR` | `$PWD` | Override project directory for gc-query |

**Examples**:
```bash
# Use custom store location
export CLAUDE_CONTEXT_PATH=/mnt/data/claude-context
gc-query last

# Query specific project from anywhere
export GC_PROJECT_DIR=/home/user/my-project
gc-query sessions
```

## Exit Codes

GlobalContext commands use standard exit codes:

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Invalid arguments or configuration error |
| 2 | Resource not found (session, projection, etc.) |
| 3 | I/O error or permission denied |

**Notes**:
- Write-path commands (gc-hook, capture-event) always exit 0 to avoid blocking Claude Code
- Query commands return non-zero on errors

## Examples by Use Case

### View Recent Work

```bash
# See what happened in last session
gc-query last

# See last 10 events
gc-query tail latest 10

# List recent sessions
gc-query sessions --limit 10
```

### Debug a Session

```bash
# Get full timeline
gc-query replay abc123

# Check specific events
gc-query events abc123 --from 40 --to 50

# Find error events
gc-query events abc123 --type ToolCallFailed
```

### Search for Something

```bash
# Find sessions mentioning authentication
gc-query search authentication

# Find specific prompts
gc-query search "fix the bug" --type UserPromptReceived

# Search across all projects
gc-query search "API key" --all-projects
```

### Check System Health

```bash
# Quick status check
gc-query status

# Full health check
gc-query doctor

# Check disk usage
gc-query store-size
```

### Context Recovery

```bash
# Resume work from last session
gc-query last --format markdown

# Include parent session context
gc-query last --include-parent

# Get compact summary
gc-query last --format compact
```

## Tips and Best Practices

### Performance

- Use `--limit` when listing sessions (faster for large stores)
- Use `--from`/`--to` to query event ranges (avoid loading full sessions)
- Use `jsonl` format for piping to jq (more efficient than `json`)

### Debugging

- Use `gc-query doctor` to diagnose issues
- Check raw events with `gc-query events` before blaming projections
- Use `--rebuild` flag on project command after schema changes

### Workflows

- Alias common commands:
  ```bash
  alias gcl='gc-query last'
  alias gcs='gc-query sessions'
  alias gcd='gc-query doctor'
  ```

- Pipe to jq for custom queries:
  ```bash
  gc-query events abc123 --format jsonl | jq 'select(.event_type == "UserPromptReceived")'
  ```

- Use compact format for quick context checks:
  ```bash
  gc-query last --format compact | head -20
  ```

## Related Documentation

- [Event Types](Event-Types.md) - Event schema reference
- [Projections](Projections.md) - Projection types and schemas
- [Architecture](Architecture.md) - How commands interact with the system
- [Plugin Guide](Plugin-Guide.md) - Slash command equivalents
