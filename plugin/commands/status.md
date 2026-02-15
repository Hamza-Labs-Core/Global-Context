---
name: status
description: Show GlobalContext store health and statistics
---

# GlobalContext: Status

Display the health and statistics of the GlobalContext event store,
including session count, event count, disk usage, and age information.

## Execution

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" status
```

## Arguments

- `--format json` -- return raw JSON instead of text

## Output

Present the status information clearly:
- Store location
- Number of sessions
- Total event count
- Total disk usage
- Oldest and newest session timestamps
- Any warnings (low disk space, missing directories)
