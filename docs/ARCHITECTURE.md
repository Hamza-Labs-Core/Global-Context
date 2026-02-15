# GlobalContext: Event-Sourced Context Store for LLM Sessions

## Overview

GlobalContext is an event-sourced context store that captures everything that happens during Claude Code (or any LLM) sessions. It uses Event Sourcing and CQRS patterns to ensure no information is ever lost — even when context compacts, sessions end, or conversations are cleared.

## Problem Statement

Every time context compacts, a session ends, or you start fresh — all the rich detail of what happened (tool calls, agent reasoning, file changes, decisions) is lost or compressed. There is no way to:
- Go back to a specific step after compaction
- Resume from where you left off in a new session
- Audit what happened across sessions
- Replay a sequence of events to understand decisions

## Core Principles

1. **Append-Only** — Events are immutable facts. Never updated, never deleted.
2. **Complete Capture** — Every hook event is recorded with full payload.
3. **Separation of Concerns (CQRS)** — Write side (capture) is fast and dumb. Read side (projections) is smart and flexible.
4. **Zero Friction** — Hooks run async where possible, never slowing down the LLM session.
5. **Self-Describing** — Events carry all context needed to understand them without external state.

## System Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Claude Code Session               │
│                                                     │
│  User Message → Agent Reasoning → Tool Calls → ...  │
│       │              │               │              │
│       ▼              ▼               ▼              │
│   ┌─────────── Hook System ──────────────┐          │
│   │ SessionStart    UserPromptSubmit     │          │
│   │ PreToolUse      PostToolUse          │          │
│   │ SubagentStart   SubagentStop         │          │
│   │ Stop            PreCompact           │          │
│   │ SessionEnd      PostToolUseFailure   │          │
│   └──────────────┬───────────────────────┘          │
└──────────────────┼──────────────────────────────────┘
                   │ JSON on stdin
                   ▼
         ┌─────────────────┐
         │  Event Collector │  (bash/node script)
         │  (hook handler)  │
         └────────┬────────┘
                  │ append
                  ▼
         ┌─────────────────┐
         │   EVENT STORE    │  ~/.claude-context/events/
         │  (append-only)   │  {project-id}/{session-id}/{sequence}.json
         └────────┬────────┘
                  │ project
                  ▼
         ┌─────────────────┐
         │   PROJECTIONS    │  (read models)
         │                  │
         │ • Timeline       │  "what happened in order"
         │ • File Changes   │  "what files were touched"
         │ • Decisions      │  "what choices were made"
         │ • Context Snap   │  "rebuild full context"
         └─────────────────┘
```

## Hook Events Captured

| Hook Event | Event Type Stored | Sync/Async | Purpose |
|---|---|---|---|
| SessionStart | SessionStarted | sync | Session boundary, detect compaction/resume |
| UserPromptSubmit | UserPromptReceived | sync | Exact user prompts |
| PreToolUse | ToolCallRequested | async | What the LLM intends to do |
| PostToolUse | ToolCallCompleted | async | What actually happened (with results) |
| PostToolUseFailure | ToolCallFailed | async | Error tracking |
| SubagentStart | AgentSpawned | async | Sub-agent lifecycle |
| SubagentStop | AgentCompleted | async | Sub-agent results |
| Stop | TurnCompleted | async | Turn boundaries |
| PreCompact | CompactionTriggered | sync | Critical — last chance before context loss |
| SessionEnd | SessionEnded | async | Session lifecycle |

## Event Envelope Schema

```json
{
  "event_id": "uuid-v4",
  "event_type": "ToolCallCompleted",
  "project_id": "my-project-a3f7b2",
  "session_id": "abc123",
  "sequence": 42,
  "timestamp": "2026-02-14T10:30:00.000Z",
  "data": { }
}
```

## Storage Layout

```
~/.claude-context/
├── events/
│   ├── {project-id}/                        # e.g. my-project-a3f7b2
│   │   ├── {session-id}/
│   │   │   ├── session.json                 # per-session metadata
│   │   │   ├── .lock                        # flock for sequence coordination
│   │   │   ├── 000001.json
│   │   │   ├── 000002.json
│   │   │   └── ...
│   │   └── {another-session-id}/
│   └── {another-project-id}/
├── projections/
│   ├── {project-id}/
│   │   ├── {session-id}/
│   │   │   ├── timeline.json
│   │   │   ├── files-touched.json
│   │   │   ├── decisions.json
│   │   │   └── context.json
│   │   └── latest -> {session-id}           # per-project latest symlink
│   └── {another-project-id}/
├── bin/
│   ├── capture-event
│   ├── gc-hook
│   ├── project
│   └── gc-query
└── config.json
```

### Project ID Format

Project IDs are derived from the working directory: `{basename}-{short-hash}` where the hash is the first 6 hex characters of a hash of the full absolute path. This ensures uniqueness across different paths with the same directory name.

Example: `/home/user/work/my-project` → `my-project-a3f7b2`

## Hook Configuration

Hooks are registered in `~/.claude/settings.json` under the `hooks` key. Each hook event maps to one or more command hooks that pipe stdin JSON to the `capture-event` script.

Key design decisions:
- **async: true** on high-frequency events (PreToolUse, PostToolUse) to avoid latency
- **async: false** on critical events (PreCompact, SessionStart) to guarantee capture
- **timeout: 5s** on all hooks — capture is just a file append
- **matcher: ".*"** on tool-specific hooks to capture ALL tools

## CQRS: Command Side (Write)

The write side is a single `capture-event` script that:
1. Reads JSON from stdin (hook payload)
2. Extracts session_id and project directory (cwd)
3. Derives project_id from cwd (`{basename}-{short-hash}`)
4. Assigns a monotonically increasing sequence number (file-lock protected)
5. Wraps payload in event envelope
6. Writes to `~/.claude-context/events/{project-id}/{session-id}/{sequence}.json`
7. Updates `session.json` in the same session directory (within the same flock scope)

No business logic. No validation beyond structure. Just append.

## CQRS: Query Side (Read)

Projections are built on-demand by replaying events:

### Timeline Projection
Ordered summary of what happened — event types, timestamps, tool names, brief descriptions.

### Files Touched Projection
All files that were read, written, edited, or globbed — with the operation type and sequence number.

### Decisions Projection
User prompts + the tool calls that followed — capturing the "intent → action" chain.

### Context Snapshot Projection
The full reconstructable state: user prompts, tool calls with results, file states, agent outputs. This is what gets loaded when you say "get last context".

## Recovery Flow

```
User: "get last context"
  → Read latest session symlink
  → Read context.json projection (or rebuild from events)
  → LLM receives: prompts, tool calls, results, decisions, file states
  → Full continuity restored
```

## Technology Choices

- **Capture script**: Bash (zero dependencies, available everywhere)
- **Projection engine**: Node.js or Bash+jq (for JSON processing)
- **Storage**: Filesystem (JSON files) — no database needed
- **Concurrency**: flock-based file locking for sequence numbers
- **IDs**: UUID v4 for events, Claude Code's session_id for sessions
