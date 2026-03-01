---
name: gc-search
description: Search across GlobalContext sessions for events matching a keyword. Use when looking for specific code, files, tools, or prompts from any session.
argument-hint: "<keyword> [--type TYPE] [--all-projects] [--limit N]"
allowed-tools: "Bash(gc-query search *)"
---

# Search GlobalContext Events

You have access to GlobalContext's full-text search. Use it to find events across sessions by keyword.

## Commands

Run these via Bash:

### Basic search
```
gc-query search $ARGUMENTS
```

### Search with filters
```
gc-query search "keyword" --type ToolCallCompleted
gc-query search "keyword" --type UserPromptReceived
gc-query search "keyword" --session <session-id>
gc-query search "keyword" --limit 50
gc-query search "keyword" --all-projects
gc-query search "keyword" --format json
```

### Search for file references
```
gc-query search "keyword" --file "path/to/file"
```

## Available event type filters
- `UserPromptReceived` - User messages/prompts
- `ToolCallCompleted` - Completed tool calls (reads, writes, edits, bash, etc.)
- `ToolCallRequested` - Requested tool calls
- `ToolCallFailed` - Failed tool calls
- `SessionStarted` - Session start events
- `SessionEnded` - Session end events

## Behavior

1. Parse the user's search intent from `$ARGUMENTS`.
2. Run `gc-query search` with appropriate keyword and filters.
3. If results are found, present them clearly with session IDs, event types, and matched snippets.
4. If the user wants more detail on a result, use `/recall <session-id>` to load that session's context.
5. If no results found, suggest broadening the search (remove filters, try different keywords).
