---
name: session
description: Retrieve context from a specific session by ID
---

# GlobalContext: Session Context

Retrieve and display context from a specific GlobalContext session identified
by its session ID.

## Execution

The user will provide a session ID. Run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" session "<session-id>" --format markdown
```

If the session is not found, inform the user and suggest running
`/globalcontext:sessions` to see available sessions.

## Arguments

- `<session-id>` -- the session identifier (required)
- `--format json` -- return raw JSON instead of markdown
- `--include-chain` -- follow the session chain to include parent sessions

## Output

Present the session context organized as:
1. Session metadata (ID, timestamps, event count)
2. User prompts and decisions
3. Files modified during the session
4. Final state when the session ended
