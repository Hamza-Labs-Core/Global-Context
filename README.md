# GlobalContext

Event-sourced context store for Claude Code sessions. Captures every hook event during LLM sessions so nothing is lost when context compacts, sessions end, or conversations are cleared.

## What It Does

- Records all Claude Code hook events (prompts, tool calls, agent spawns, compaction) as immutable append-only events
- Builds read-optimized projections: timeline, files-touched, decisions, full context snapshots
- Automatically recovers context after compaction or session restart
- Provides `gc-query` CLI for searching, replaying, and inspecting session history

## Architecture

**CQRS pattern** — write side and read side are fully separated:

- **Write side** (Bash + jq): Fast, dumb event capture. Appends JSON files under `~/.claude-context/events/{project-id}/{session-id}/`
- **Read side** (Node.js, no npm): Smart projection engine that builds materialized views from event streams

```
Claude Code Hooks → capture-event (bash) → Event Store (append-only JSON files)
                                                  ↓
                                           project (node) → Projections (timeline, files, decisions, context)
                                                  ↓
                                           gc-query (bash) → CLI queries, search, replay, auto-recovery
```

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
│   └── context.json
├── bin/                      # installed scripts
└── config.json
```

Project IDs are derived from working directory: `{basename}-{hash6}` (e.g., `my-project-a3f7b2`).

## Stories

| # | Story | Description |
|---|-------|-------------|
| 01 | [Event Capture](stories/01-event-capture.md) | Core `capture-event` script — envelope construction, sequencing, atomic writes |
| 02 | [Hook Integration](stories/02-hook-integration.md) | `gc-hook` wrapper, Claude Code settings.json configuration |
| 03 | [Storage Layer](stories/03-storage-layer.md) | Directory structure, locking, session metadata, config, init command |
| 04 | [Projection Engine](stories/04-projection-engine.md) | `project` CLI — timeline, files-touched, decisions, context builders |
| 05 | [Context Recovery](stories/05-context-recovery.md) | `gc-query` CLI — last, sessions, search, replay, doctor, auto-injection |

## Design Docs

- [Architecture](docs/ARCHITECTURE.md) — system overview, event schema, storage layout
- [Design Amendments](docs/DESIGN-AMENDMENTS.md) — post-review changes (per-session metadata, project-id layer, deferred cleanup)
- [Review](docs/REVIEW.md) — 16 review issues identified and resolved

## Key Design Decisions

- **Per-session `session.json`** instead of global sessions index (no shared state)
- **Per-project `latest` symlink** at `projections/{project-id}/latest`
- **No write-side truncation** — events stored as-is (CQRS: write side is fast and dumb)
- **No gc-cleanup** — append-only principle; deferred to future story if needed
- **flock-based concurrency** with 5-second timeout and orphan file fallback

## Status

Design phase complete. All stories and implementation plans reviewed for cross-document consistency. Ready for implementation starting with Story 03 (Storage Layer) and Story 01 (Event Capture) in parallel.
