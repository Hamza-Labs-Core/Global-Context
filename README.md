# GlobalContext

Event-sourced context store for Claude Code sessions. Captures every hook event as immutable JSON and provides projection-based queries for context recovery.

## Features

- Append-only event store — nothing is ever lost, even after compaction
- CQRS architecture — fast write side (Bash+jq), smart read side (Node.js)
- Per-project isolation with automatic project-id derivation
- Per-session event streams with monotonic sequence numbers
- Five projection types for flexible context retrieval
- Automatic context injection after compaction/clear
- Progressive summarization for large sessions
- Zero external dependencies (no npm install)
- Claude Code marketplace plugin

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/GlobalContext.git
cd GlobalContext

# Run the installer
./gc-install

# Verify installation
gc-query doctor
```

The installer will:
- Deploy scripts to `~/.claude-context/`
- Register 10 hooks in `~/.claude/settings.json`
- Initialize the event store structure
- Run health checks

### Verify

```bash
# Check store status
gc-query status

# Start a Claude Code session and do some work
# Events are captured automatically

# View last session context
gc-query last

# List all sessions
gc-query sessions
```

### Basic Usage

```bash
# Get context from most recent session
gc-query last

# Get context from a specific session
gc-query session abc-123

# Search across sessions
gc-query search "authentication"

# View raw events
gc-query events abc-123

# Replay session as a narrative
gc-query replay abc-123
```

## Architecture Overview

GlobalContext uses **CQRS (Command Query Responsibility Segregation)** to separate write and read operations:

**Write Side (Command)**: Bash+jq scripts capture hook events synchronously and append them to the event store. Fast, simple, zero business logic.

**Read Side (Query)**: Node.js projection engine builds materialized views on-demand. Smart context reconstruction, cross-session chaining, search.

```
Claude Code Session
       |
       | hook events (JSON on stdin)
       v
   gc-hook wrapper
       |
       | append to files
       v
   EVENT STORE
   ~/.claude-context/events/{project-id}/{session-id}/{sequence}.json
       |
       | project on demand
       v
   PROJECTIONS (read models)
   - timeline.json      (ordered summary)
   - files-touched.json (file operations)
   - decisions.json     (intent -> action chains)
   - context.json       (full reconstructable state)
   - summary.json       (condensed overview)
```

## CLI Reference

| Command | Description |
|---------|-------------|
| `gc-install` | Install GlobalContext to `~/.claude-context/` |
| `gc-uninstall` | Remove scripts and hooks (preserves data by default) |
| `gc-init` | Initialize store directory structure |
| `gc-doctor` | Run health checks and verify installation |
| `gc-hook` | Hook wrapper (called by Claude Code) |
| `gc-install-hooks` | Register/unregister hooks in `settings.json` |
| `gc-query` | Query interface (10 subcommands) |
| `capture-event` | Event capture script (called by gc-hook) |
| `project` | Projection engine (builds read models) |

## gc-query Subcommands

| Subcommand | Description |
|------------|-------------|
| `store-size` | Report total store size and event counts |
| `status` | Show store health and statistics |
| `events <session-id>` | Output raw events as JSONL |
| `tail <session-id> [N]` | Show last N events from a session (default: 20) |
| `last` | Get context from most recent session |
| `session <session-id>` | Get context from a specific session |
| `sessions` | List all sessions with metadata |
| `search <keyword>` | Search across sessions for events containing keyword |
| `replay <session-id>` | Transform events into human-readable narrative |
| `doctor` | Run end-to-end health validation |

### Common Flags

- `--format <json|text|markdown>` — Output format (default: markdown for context, text for lists)
- `--project <project-id>` — Filter by project
- `--all-projects` — Include all projects (default: current project only)
- `--include-parent` — Follow session chain to include parent context

## Event Types

| Event Type | Hook | Sync/Async | Purpose |
|------------|------|------------|---------|
| `SessionStarted` | SessionStart | sync | Session boundary, detect compaction/resume |
| `UserPromptReceived` | UserPromptSubmit | sync | Capture exact user prompts |
| `ToolCallRequested` | PreToolUse | async | What the LLM intends to do |
| `ToolCallCompleted` | PostToolUse | async | What actually happened (with results) |
| `ToolCallFailed` | PostToolUseFailure | async | Error tracking |
| `AgentSpawned` | SubagentStart | async | Sub-agent lifecycle start |
| `AgentCompleted` | SubagentStop | async | Sub-agent results |
| `TurnCompleted` | Stop | async | Turn boundaries |
| `CompactionTriggered` | PreCompact | sync | Last chance before context loss |
| `SessionEnded` | SessionEnd | async | Session lifecycle end |

## Projections

| Type | Description | Output File |
|------|-------------|-------------|
| `context-snapshot` | Full reconstructable state: prompts, tool calls, results, file states | `context.json` |
| `timeline` | Ordered summary of events with timestamps and descriptions | `timeline.json` |
| `summary` | Condensed overview: session stats, key actions, final state | `summary.json` |
| `files-touched` | All file operations (Read, Write, Edit, Glob) with sequence numbers | `files-touched.json` |
| `decisions` | User prompts paired with subsequent tool calls (intent -> action chains) | `decisions.json` |

## Directory Structure

```
~/.claude-context/                    (GC_ROOT)
├── events/                           Event store (append-only)
│   └── {project-id}/                 e.g., my-project-a3f7b2
│       └── {session-id}/
│           ├── session.json          Per-session metadata
│           ├── .lock                 flock for sequence coordination
│           ├── 000001.json
│           ├── 000002.json
│           └── ...
├── projections/                      Read models (built on-demand)
│   └── {project-id}/
│       ├── {session-id}/
│       │   ├── context.json
│       │   ├── timeline.json
│       │   ├── summary.json
│       │   ├── files-touched.json
│       │   └── decisions.json
│       └── latest -> {session-id}    Per-project latest symlink
├── bin/                              Executable scripts
│   ├── capture-event
│   ├── gc-hook
│   ├── gc-install-hooks
│   ├── gc-init
│   ├── gc-query
│   ├── gc-doctor
│   ├── gc-install
│   ├── gc-uninstall
│   └── project
├── lib/                              Shared libraries
│   ├── paths.sh
│   ├── sanitize.sh
│   ├── session_dir.sh
│   ├── atomic_write.sh
│   ├── json_validate.sh
│   ├── event_write.sh
│   ├── session_meta.sh
│   ├── config.sh
│   ├── latest_symlink.sh
│   ├── projection_store.sh
│   ├── prerequisites.sh
│   ├── debug_log.sh
│   └── hook-config.json
├── config.json                       Store configuration
└── VERSION                           Software version (1.0.0)
```

### Project ID Format

Project IDs are derived from the working directory: `{basename}-{hash6}` where hash is the first 6 hex characters of SHA-256 of the full absolute path.

Examples:
- `/home/user/my-project` → `my-project-a3f7b2`
- `/home/user/work/my-project` → `my-project-e91c04` (different hash, same basename)

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_CONTEXT_PATH` | `~/.claude-context` | Store root directory |
| `GC_SRC_DIR` | (auto-detected) | Source files directory (for development) |

## Development

### Prerequisites

- Bash 4+
- jq 1.5+
- Node.js 18+
- sha256sum or shasum
- flock (optional, for concurrent write safety)

### Running Tests

```bash
# Unit tests for individual components
bash tests/lib/test_prerequisites.sh
bash tests/lib/test_paths.sh

# Integration tests for full lifecycle
bash tests/00-install-fresh.sh
bash tests/00-install-upgrade.sh
bash tests/00-install-uninstall.sh

# Run all tests
bash tests/00-install-all.sh
```

### Project Structure

```
/home/meywd/GlobalContext/
├── src/                      Source files (deployed to ~/.claude-context/)
│   ├── bin/                  Executable scripts
│   └── lib/                  Shared libraries
├── docs/                     Documentation
│   ├── ARCHITECTURE.md       System overview
│   ├── DESIGN-AMENDMENTS.md  Post-review design changes
│   └── REVIEW.md            Review issues and resolutions
├── stories/                  Feature specifications
│   ├── 00-installation.md
│   ├── 01-event-capture.md
│   ├── 02-hook-integration.md
│   ├── 03-storage-layer.md
│   ├── 04-projection-engine.md
│   ├── 05-context-recovery.md
│   └── 06-plugin-packaging.md
├── plans/                    Implementation plans
│   ├── 00-installation-plan.md
│   ├── 01-event-capture-plan.md
│   ├── 02-hook-integration-plan.md
│   ├── 03-storage-layer-plan.md
│   ├── 04-projection-engine-plan.md
│   ├── 05-context-recovery-plan.md
│   └── 06-plugin-packaging-plan.md
├── tests/                    Test suite
└── VERSION                   Software version
```

## Design Principles

1. **Append-Only** — Events are immutable facts. Never updated, never deleted.
2. **Complete Capture** — Every hook event is recorded with full payload.
3. **Separation of Concerns (CQRS)** — Write side is fast and dumb. Read side is smart and flexible.
4. **Zero Friction** — Hooks run async where possible, never slowing down the LLM session.
5. **Self-Describing** — Events carry all context needed to understand them without external state.

## License

MIT
