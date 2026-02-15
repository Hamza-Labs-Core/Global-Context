# Task 04: Files Touched Projection Handler

**Story**: 04-projection-engine
**Estimated Complexity**: L (6-10 hours)
**Status**: Pending

---

## Description

Implement the files-touched projection handler. This handler tracks every file that was read, written, edited, globbed, or grepped during the session. It extracts file paths from both `tool_input` (the request) and `tool_response` (the result) fields -- the latter being critical for Glob and Grep tools per review issue G-2.

This task is placed before Timeline because it exercises the most complex extraction logic and will surface integration issues with the replay engine early.

---

## Files to Create

| File | Purpose |
|------|---------|
| `/home/meywd/GlobalContext/lib/projections/files-touched.js` | Files touched handler + formatters |

---

## Specification / Implementation Details

### Handler State Structure

```javascript
{
  filesMap: {},  // path -> { operations: [], first_touched, last_touched, touch_count }
  stats: { total_files: 0, files_read: 0, files_written: 0, files_edited: 0, files_globbed: 0, files_grepped: 0 }
}
```

### Event Handling Per Event Type

1. **`ToolCallRequested`**: Extract paths from `event.data.tool_input` based on tool name:
   - Read: `tool_input.file_path`
   - Write: `tool_input.file_path`
   - Edit: `tool_input.file_path`
   - NotebookEdit: `tool_input.notebook_path`
   - Glob: Record `tool_input.path` + `tool_input.pattern` as a glob entry
   - Grep: If `tool_input.path` looks like a file (has extension), record it
   - Bash: Best-effort regex extraction for `cat`, `less`, `head`, `tail`, `echo >`, `cp`, `mv`, `rm`

2. **`ToolCallCompleted`**: Extract paths from `event.data.tool_response` (G-2):
   - Glob: Parse the response for file path lines (one path per line in typical output). Record each matched file as operation type `glob`.
   - Grep: Parse the response for file paths. In `files_with_matches` output mode, each line is a file path. Record each as operation type `grep`.

### Deduplication

Files are keyed by absolute path in the `filesMap`. Multiple operations on the same file append to the `operations` array.

### Tool-Call Pairing for Response Extraction

When processing a `ToolCallCompleted` event, use `tool_use_id` to identify the originating tool. If `tool_use_id` is not present, fall back to the tool_name from the event data.

### Glob Response Parsing

Split response by newlines, treat each non-empty line as a file path.

### Grep Response Parsing

In `files_with_matches` mode, each line is a file path. In `content` mode, extract file paths from `filename:line:content` format.

### Formatters

- **JSON**: Direct serialization of the projection schema.
- **Text**: Header line with stats, then each file with indented operations.
- **Markdown**: Table of files with operation counts, then detailed operations list.

### Review Issues Addressed

- **G-1**: Duplicate event detection by `tool_use_id` is handled at the replay engine level (Task 3), so this handler benefits from dedup automatically for tool-call pairing.
- **G-2**: Extract file paths from `tool_response` too (Glob/Grep). When processing `ToolCallCompleted` events for Glob and Grep tools, the handler parses `event.data.tool_response` (or `event.data.result`) for file paths and records each as an individual file operation.

---

## Dependencies

- Task 01: Base Path Resolution and Shared Utilities (`/home/meywd/GlobalContext/tasks/04-projection-engine/01-base-path-resolution-and-shared-utilities.md`)
- Task 02: Projection Registry (`/home/meywd/GlobalContext/tasks/04-projection-engine/02-projection-registry.md`)
- Task 03: Event Replay Engine (`/home/meywd/GlobalContext/tasks/04-projection-engine/03-event-replay-engine.md`)

---

## Acceptance Tests

- A Read event for `/foo/bar.js` records an entry with operation type `read`.
- A Write event records `write`. An Edit event records `edit`.
- A Glob `ToolCallRequested` records the pattern. A subsequent Glob `ToolCallCompleted` with matched files in `tool_response` records each matched file individually (G-2).
- A Grep `ToolCallCompleted` with file paths in `tool_response` records each file with operation type `grep` (G-2).
- Reading the same file twice produces one file entry with two operations.
- `first_touched` is the earliest timestamp; `last_touched` is the latest; `touch_count` equals the operations array length.
- Stats accurately count unique files per operation type.
- A `ToolCallRequested` with missing `tool_input` logs a warning and does not crash.
- Bash command `cat /etc/hosts` extracts `/etc/hosts` as a `read` operation.
- An unknown tool name does not record any file (no false positives).
- All three output formats produce valid output.
