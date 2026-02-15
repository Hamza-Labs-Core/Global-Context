# Task 10: Document Hook Payload Structures (Review Fix M-5)

**Story**: 02-hook-integration
**Status**: Pending
**Estimated Complexity**: M (Medium) -- 10 payload structures to document with examples and field tables

---

## Description

Create a reference document that describes the JSON payload structure for each of the 10 hook events that Claude Code sends on stdin. This addresses **review issue M-5**.

The payloads are defined by Claude Code (not by GlobalContext), so this document serves as a reference for developers and for downstream projection consumers. It links to Story 01 Section 8 where the expected fields are first described.

---

## Files to Create

| File | Purpose |
|------|---------|
| `docs/HOOK-PAYLOADS.md` | Reference documentation |

---

## Specification / Implementation Details

### Content Structure

For each of the 10 hook events:

1. **Hook event name** (the Claude Code hook name, e.g., `PreToolUse`)
2. **GlobalContext event type** (e.g., `ToolCallRequested`)
3. **Sync/Async** designation
4. **Example JSON payload** (what arrives on stdin)
5. **Field descriptions** table
6. **Notes** on size, frequency, and downstream usage

### Example Entry

```
### PreToolUse -> ToolCallRequested (async)

Example payload:
{
  "session_id": "abc-123",
  "tool_name": "Bash",
  "tool_input": { "command": "ls -la" },
  "tool_use_id": "tu_01ABC"
}

| Field       | Type   | Description                          |
|-------------|--------|--------------------------------------|
| session_id  | string | Current session identifier           |
| tool_name   | string | Name of the tool being invoked       |
| tool_input  | object | Tool-specific input parameters       |
| tool_use_id | string | Unique ID for this tool invocation   |

Notes:
- High frequency event. Fires for every tool call.
- tool_input shape varies per tool (Bash has "command", Read has "file_path", etc.)
- Correlates with PostToolUse/PostToolUseFailure via tool_use_id.
```

### Required Sections

Also include a section noting:
- These payloads are Claude Code's contract, not GlobalContext's. If Claude Code changes payload formats, GlobalContext captures whatever is sent.
- GlobalContext stores the entire payload unmodified in the event envelope's `data` field.
- Downstream projections should handle missing or unexpected fields gracefully.

---

## Dependencies

- None (documentation only; can be written at any time)

---

## Acceptance Tests

1. Document exists and is well-formatted Markdown.
2. All 10 hook events are documented with example payloads.
3. Field descriptions match Story 01 Section 8.
4. The document includes a disclaimer about Claude Code owning the payload contract.
