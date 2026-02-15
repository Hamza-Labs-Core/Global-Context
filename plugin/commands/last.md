---
name: last
description: Retrieve context from the most recent session for the current project
---

# GlobalContext: Last Session Context

Retrieve and display the full context from the most recent GlobalContext session
for the current project directory.

## Execution

Run the following command to get the last session context:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" last --format markdown
```

If no sessions exist for the current project, inform the user that no previous
context was found and suggest they start working -- GlobalContext will capture
everything automatically.

## Arguments

- `--format json` -- return raw JSON instead of markdown
- `--include-parent` -- include context from parent sessions (session chain)

## Output

Present the recovered context to the user in a clear format. Highlight:
1. What was being worked on (last prompt and recent context)
2. Files that were modified
3. Key decisions made
4. Where work left off
