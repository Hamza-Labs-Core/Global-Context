# GlobalContext - Claude Code Plugin

## What It Does

- Captures every hook event from your Claude Code sessions
- Builds projections (timeline, files, decisions, context)
- Recovers context after compaction, session end, or conversation clear
- Automatic context injection when sessions resume

## Installation

```
claude plugin install globalcontext
```

## Slash Commands

- `/globalcontext:last` -- Get context from the most recent session
- `/globalcontext:session <id>` -- Get context from a specific session
- `/globalcontext:sessions` -- List all sessions
- `/globalcontext:search <keyword>` -- Search across sessions
- `/globalcontext:replay <session-id>` -- Replay a session as a narrative
- `/globalcontext:tail <session-id> [N]` -- Show last N events
- `/globalcontext:events <session-id>` -- Raw event access
- `/globalcontext:status` -- Store health and statistics
- `/globalcontext:doctor` -- Full system health check

## Automatic Features

- **Context recovery skill**: auto-triggers when you ask "what were we doing?"
- **Context investigator agent**: deep cross-session analysis via Task tool
- **Auto-init**: store is created on first use, no manual setup needed
- **All 10 hook events captured automatically**

## Configuration

Set `CLAUDE_CONTEXT_PATH` to customize the data store location:

```bash
export CLAUDE_CONTEXT_PATH=/path/to/custom/store
```

## Data Location

- **Event store**: `~/.claude-context/` (or `$CLAUDE_CONTEXT_PATH`)
- **Plugin code**: managed by Claude Code plugin system

## Hook Events Captured

| Hook Event | Event Type | Mode |
|---|---|---|
| SessionStart | SessionStarted | sync |
| UserPromptSubmit | UserPromptReceived | sync |
| PreToolUse | ToolCallRequested | async |
| PostToolUse | ToolCallCompleted | async |
| PostToolUseFailure | ToolCallFailed | async |
| SubagentStart | AgentSpawned | async |
| SubagentStop | AgentCompleted | async |
| Stop | TurnCompleted | async |
| PreCompact | CompactionTriggered | sync |
| SessionEnd | SessionEnded | async |

## License

MIT
