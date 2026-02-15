---
name: search
description: Search across sessions for events containing a keyword
---

# GlobalContext: Search

Search across GlobalContext sessions for events matching a keyword. Searches
user prompts, tool names, tool results, and file paths.

## Execution

The user will provide a search term as part of their message. Run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" search "<user's search term>"
```

## Arguments

- `--type <event-type>` -- filter by event type (e.g., UserPromptReceived)
- `--file <path>` -- search for events referencing a specific file
- `--limit <N>` -- limit results (default: 20)
- `--all-projects` -- search across all projects, not just the current one

## Output

Present search results grouped by session. For each match show:
- Session ID and timestamp
- Event type and sequence number
- Matching text snippet with surrounding context
