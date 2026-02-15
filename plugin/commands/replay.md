---
name: replay
description: Replay a session's events as a chronological narrative
---

# GlobalContext: Replay Session

Replay the events from a specific session as a chronological narrative,
showing the flow of work from start to finish.

## Execution

The user will provide a session ID. Run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" replay "<session-id>"
```

## Arguments

- `<session-id>` -- the session to replay (required)
- `--format json` -- return raw events as JSON
- `--verbose` -- include full tool call details

## Output

Present the replay as a timeline:
1. Session start with project context
2. Each user prompt and the resulting actions
3. Tool calls with their outcomes (success/failure)
4. Key decision points
5. Session end or compaction event
