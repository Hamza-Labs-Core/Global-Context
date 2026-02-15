---
name: sessions
description: List all GlobalContext sessions for the current project
---

# GlobalContext: List Sessions

List all recorded GlobalContext sessions, showing session IDs, timestamps,
event counts, and status.

## Execution

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" sessions --format markdown
```

## Arguments

- `--all-projects` -- list sessions across all projects, not just the current one
- `--limit <N>` -- limit the number of sessions shown (default: 20)
- `--format json` -- return raw JSON instead of markdown

## Output

Present sessions as a table or list with:
- Session ID
- Started at / ended at timestamps
- Event count
- Last prompt (truncated)
- Status (active, ended, compacted)
