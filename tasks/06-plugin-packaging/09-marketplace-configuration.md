# Task 09: Marketplace Configuration

**Story**: 06-plugin-packaging
**Estimated Complexity**: S (Small)
**Dependencies**: [Task 01 - Plugin Manifest and Directory Scaffold](/home/meywd/GlobalContext/tasks/06-plugin-packaging/01-plugin-manifest-scaffold.md) (plugin directory must exist)

---

## Description

Create the marketplace configuration files required for distributing the plugin via `claude plugin install`. This includes a `marketplace.json` descriptor, a `README.md` for the plugin (describing what it does, how to install, how to use), a `CHANGELOG.md` for version tracking, and a `LICENSE` file.

---

## Files to Create

| File | Purpose |
|------|---------|
| `plugin/marketplace.json` | Marketplace distribution descriptor |
| `plugin/README.md` | Plugin documentation (installation, usage, commands) |
| `plugin/CHANGELOG.md` | Version history |
| `plugin/LICENSE` | License file (MIT) |

---

## Specification

### `plugin/marketplace.json`

```json
{
  "name": "globalcontext",
  "display_name": "GlobalContext",
  "version": "1.0.0",
  "description": "Event-sourced context store for Claude Code. Captures all session events, builds projections, and enables context recovery after compaction or session changes.",
  "repository": "https://github.com/globalcontext/globalcontext",
  "author": "GlobalContext",
  "license": "MIT",
  "keywords": ["context", "sessions", "event-sourcing", "recovery", "compaction"],
  "categories": ["productivity", "developer-tools"],
  "install": {
    "type": "git",
    "url": "https://github.com/globalcontext/globalcontext.git",
    "path": "plugin"
  },
  "requirements": {
    "jq": ">=1.6",
    "bash": ">=4.0",
    "node": ">=18.0.0"
  }
}
```

### `plugin/README.md` Content Outline

```
# GlobalContext - Claude Code Plugin

## What It Does
- Captures every hook event from your Claude Code sessions
- Builds projections (timeline, files, decisions, context)
- Recovers context after compaction, session end, or conversation clear
- Automatic context injection when sessions resume

## Installation
claude plugin install globalcontext

## Slash Commands
- /globalcontext:last -- Get context from the most recent session
- /globalcontext:session <id> -- Get context from a specific session
- /globalcontext:sessions -- List all sessions
- /globalcontext:search <keyword> -- Search across sessions
- /globalcontext:replay <session-id> -- Replay a session as a narrative
- /globalcontext:tail <session-id> [N] -- Show last N events
- /globalcontext:events <session-id> -- Raw event access
- /globalcontext:status -- Store health and statistics
- /globalcontext:doctor -- Full system health check

## Automatic Features
- Context recovery skill: auto-triggers when you ask "what were we doing?"
- Context investigator agent: deep cross-session analysis via Task tool
- Auto-init: store is created on first use, no manual setup needed
- All 10 hook events captured automatically

## Configuration
Set CLAUDE_CONTEXT_PATH to customize the data store location:
  export CLAUDE_CONTEXT_PATH=/path/to/custom/store

## Data Location
Event store: ~/.claude-context/ (or $CLAUDE_CONTEXT_PATH)
Plugin code: managed by Claude Code plugin system
```

### `plugin/CHANGELOG.md`

```
# Changelog

## 1.0.0 (2026-02-15)

### Added
- Initial plugin release
- All 10 hook events captured (SessionStart through SessionEnd)
- 9 slash commands for querying the event store
- Context recovery skill (auto-triggered)
- Context investigator agent (deep analysis)
- Auto-init on first use
- CLAUDE_CONTEXT_PATH support for custom store location
```

### `plugin/LICENSE`

Standard MIT license text.

---

## Acceptance Tests

1. `jq . plugin/marketplace.json` parses without error.
2. `plugin/README.md` exists and documents all 9 slash commands.
3. `plugin/CHANGELOG.md` exists with a 1.0.0 entry.
4. `plugin/LICENSE` exists with MIT license text.
5. The `marketplace.json` `install.path` points to the correct plugin subdirectory.
6. All keywords and categories are valid for the marketplace schema.
