# Task 01: Plugin Manifest and Directory Scaffold

**Story**: 06-plugin-packaging
**Estimated Complexity**: S (Small)
**Dependencies**: None (first task)

---

## Description

Create the `.claude-plugin/plugin.json` manifest and the complete plugin directory structure. This establishes the plugin identity and layout that Claude Code's plugin loader expects.

The manifest defines the plugin's name, version, description, and entry points. The directory structure follows Claude Code's plugin conventions with directories for commands, agents, skills, hooks, scripts, and shared libraries.

---

## Files to Create

| File | Purpose |
|------|---------|
| `plugin/.claude-plugin/plugin.json` | Plugin manifest (name, version, description, author, homepage) |
| `plugin/commands/` | Directory for slash command markdown files (Task 5) |
| `plugin/agents/` | Directory for subagent definitions (Task 7) |
| `plugin/skills/` | Directory for auto-invoked skills (Task 6) |
| `plugin/hooks/` | Directory for hooks.json (Task 2) |
| `plugin/scripts/` | Directory for hook scripts and utilities (Tasks 3, 4) |
| `plugin/lib/` | Directory for shared bash/node libraries (Task 8) |

---

## Specification

`plugin/.claude-plugin/plugin.json`:

```json
{
  "name": "globalcontext",
  "version": "1.0.0",
  "description": "Event-sourced context store for Claude Code sessions. Captures all hook events, builds projections, and enables context recovery after compaction or session changes.",
  "author": "GlobalContext",
  "homepage": "https://github.com/globalcontext/globalcontext",
  "license": "MIT",
  "claude_code_version": ">=1.0.0"
}
```

---

## Acceptance Tests

1. The `plugin/.claude-plugin/plugin.json` file exists and is valid JSON.
2. `jq .name plugin/.claude-plugin/plugin.json` returns `"globalcontext"`.
3. All six subdirectories exist: `commands/`, `agents/`, `skills/`, `hooks/`, `scripts/`, `lib/`.
4. The plugin directory is loadable by `claude --plugin-dir ./plugin` without errors (structure validation only, no functional test yet).
