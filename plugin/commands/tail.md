---
name: tail
description: Show the last N events from a session
---

# GlobalContext: Tail Events

Show the most recent N events from a specific session. Useful for quickly
checking what happened recently in a session.

## Execution

The user will provide a session ID and optionally a count. Run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" tail "<session-id>" <N>
```

Default N is 10 if not specified.

## Arguments

- `<session-id>` -- the session to tail (required)
- `<N>` -- number of events to show (default: 10)
- `--format json` -- return raw JSON events

## Output

Present the last N events in chronological order showing:
- Sequence number and timestamp
- Event type
- Summary of the event data (prompt text, tool name, etc.)
