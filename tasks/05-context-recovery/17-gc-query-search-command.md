# Task 17: gc-query search Command

**Story**: 05-context-recovery
**Complexity**: L (Large)
**Status**: Pending

---

## Description

Search across sessions for events containing a keyword. Searches prompts, tool names, and tool results.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_search` function) |

---

## Specification / Implementation Details

1. Iterate through session event directories (or a specific session if `--session` is set).
2. For each event file, search the payload for the keyword:
   - `UserPromptReceived`: search `data.prompt`
   - `ToolCallCompleted`: search `data.tool_name` and first 500 chars of `data.tool_result`
   - `SessionStarted`: search `data.cwd`
3. Case-insensitive by default (`--case-sensitive` to override).
4. For `--file` flag: search for file paths in tool inputs and outputs.
5. Return results grouped by session, showing: session ID, sequence number, event type, matching text snippet (80 chars around match).
6. Limit results with `--limit` (default 20).
7. Sort by relevance (match count) then recency.
8. Handle special characters in search terms safely (escape for jq's `test()` function).

---

## Dependencies

- [Task 03: gc-query Entry Point and Argument Parser](/home/meywd/GlobalContext/tasks/05-context-recovery/03-gc-query-entry-point-and-argument-parser.md) (gc-query entry point)
- [Task 05: Session Resolution Helpers](/home/meywd/GlobalContext/tasks/05-context-recovery/05-session-resolution-helpers.md) (session resolution)

---

## Acceptance Tests

1. `gc-query search "rate limiting"` finds matches in prompts and tool results.
2. Results show session ID, sequence, event type, and snippet.
3. Case-insensitive by default.
4. `gc-query search --type UserPromptReceived "auth"` only searches prompts.
5. `gc-query search --limit 5 "test"` returns at most 5 results.
6. `gc-query search --file "src/auth/handler.ts"` finds all events referencing that file.
7. Exit code 0 with "No results found" when nothing matches.
8. Special characters (quotes, backslashes) do not crash the search.
9. Search across 50 sessions with 200 events each completes in under 5 seconds.

---

## Estimated Complexity: L
