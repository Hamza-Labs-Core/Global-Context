---
name: events
description: Access raw events from a specific session
---

# GlobalContext: Raw Events

Access the raw event data from a specific session. This provides the
unprocessed event JSON for debugging or detailed analysis.

## Execution

The user will provide a session ID. Run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" events "<session-id>" --format json
```

## Arguments

- `<session-id>` -- the session to read events from (required)
- `--type <event-type>` -- filter by event type
- `--from <sequence>` -- start from a specific sequence number
- `--to <sequence>` -- end at a specific sequence number
- `--format json` -- return raw JSON (default for this command)

## Output

Present events as a JSON array or formatted list. Each event includes:
- event_id, event_type, sequence, timestamp
- Full data payload
