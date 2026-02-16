# GlobalContext Wiki

Welcome to the GlobalContext documentation. GlobalContext is an event-sourced context store for Claude Code sessions that ensures nothing is ever lost when context compacts, sessions end, or conversations are cleared.

## Quick Links

- [Architecture](Architecture.md) - System design, CQRS pattern, event sourcing principles
- [CLI Reference](CLI-Reference.md) - Complete command documentation
- [Event Types](Event-Types.md) - All 10 event types and schemas
- [Projections](Projections.md) - Read models and query patterns
- [Plugin Guide](Plugin-Guide.md) - Installation and usage as Claude Code plugin
- [Development](Development.md) - Contributing and extending GlobalContext

## What is GlobalContext?

GlobalContext captures every hook event during Claude Code sessions as immutable, append-only event files. It uses CQRS (Command Query Responsibility Segregation) to separate the write path (fast event capture) from the read path (smart projections).

### Core Features

- **Complete Capture**: Records all 10 Claude Code hook events with full payloads
- **Immutable Storage**: Events are never modified or deleted (append-only)
- **CQRS Architecture**: Fast write side (Bash+jq), smart read side (Node.js)
- **Rich Projections**: Timeline, files-touched, decisions, context snapshots, summaries
- **Context Recovery**: Automatic restoration after compaction or session changes
- **Zero Dependencies**: Write side requires only bash and jq; read side uses Node.js with no npm packages

## Quick Start

Install as a Claude Code plugin:

```bash
claude plugin install globalcontext
```

The plugin automatically:
- Installs all hooks
- Initializes the store at `~/.claude-context/`
- Provides slash commands for querying sessions

## Storage Layout

```
~/.claude-context/
├── events/{project-id}/{session-id}/
│   ├── 000001.json          # immutable event files
│   ├── 000002.json
│   ├── session.json          # per-session metadata
│   └── .lock                 # flock coordination
├── projections/{project-id}/{session-id}/
│   ├── timeline.json
│   ├── files-touched.json
│   ├── decisions.json
│   ├── context.json
│   └── summary.json
├── bin/                      # installed scripts
└── config.json
```

## Project Organization

Events and projections are organized by project ID, derived from the working directory:

```
{basename}-{hash6}
```

For example, `/home/user/my-project` becomes `my-project-a3f7b2`, where `hash6` is the first 6 hex characters of SHA-256 hash of the full path.

## Key Concepts

### Events

Immutable records of everything that happens during a session. Each event has:
- Unique event ID (UUID)
- Event type (one of 10 types)
- Project ID and session ID
- Sequence number (monotonically increasing)
- Timestamp
- Complete hook payload data

### Projections

Materialized views built by replaying events. Always rebuildable from events. Five types:
- **Timeline**: Chronological log of session activity
- **Files Touched**: All files read, written, edited, or searched
- **Decisions**: User prompts linked to resulting actions
- **Context**: Full session context for recovery
- **Summary**: High-level metrics and narrative

### Session Lifecycle

1. SessionStart hook fires → auto-initialize store if needed
2. Events captured throughout session (prompts, tool calls, agents)
3. PreCompact hook fires → critical event before context loss
4. SessionEnd hook fires → session metadata finalized
5. Projections built on-demand via `gc-query` or slash commands

## Common Tasks

### View Last Session Context

```bash
gc-query last --format markdown
```

Or via slash command:

```
/globalcontext:last
```

### List All Sessions

```bash
gc-query sessions
```

### Search Across Sessions

```bash
gc-query search "authentication"
```

### Check Store Health

```bash
gc-query doctor
```

### View Session Timeline

```bash
gc-query replay <session-id>
```

## Architecture Overview

```
Claude Code Hooks → gc-hook → capture-event (Bash)
                                    ↓
                            Event Store (JSON files)
                                    ↓
                            project (Node.js) → Projections
                                    ↓
                            gc-query (Bash) → Query Results
```

**Write Side (Command)**:
- Bash + jq
- Fast, dumb event capture
- No business logic
- Just append to files

**Read Side (Query)**:
- Node.js (zero npm dependencies)
- Smart projection builders
- Event replay engine
- Multiple output formats

## Design Principles

1. **Append-Only**: Events are immutable. Never updated, never deleted.
2. **Complete Capture**: Every hook event is recorded with full payload.
3. **CQRS Separation**: Write side is fast and dumb. Read side is smart and flexible.
4. **Zero Friction**: Hooks run async where possible, never slowing down sessions.
5. **Self-Describing**: Events carry all context needed without external state.

## Getting Help

- Check the [CLI Reference](CLI-Reference.md) for command syntax
- Read [Event Types](Event-Types.md) to understand what's captured
- See [Projections](Projections.md) for query patterns
- Visit [Development](Development.md) to extend or contribute

## System Requirements

- Bash (pre-installed on all Unix systems)
- jq (for JSON processing)
- flock (for concurrency control, usually pre-installed)
- Node.js (for projection engine, no npm packages required)
- Claude Code 1.0.0 or later

## Documentation Sections

### For Users

- [Plugin Guide](Plugin-Guide.md) - Installation and slash commands
- [CLI Reference](CLI-Reference.md) - All commands and flags

### For Understanding the System

- [Architecture](Architecture.md) - How it works
- [Event Types](Event-Types.md) - What gets captured
- [Projections](Projections.md) - How to query data

### For Developers

- [Development](Development.md) - Project structure, testing, extending

## Next Steps

New users should read:

1. [Plugin Guide](Plugin-Guide.md) to install and use slash commands
2. [Architecture](Architecture.md) to understand the system design
3. [CLI Reference](CLI-Reference.md) for detailed command documentation
