# Task 10: Output Formatters (Markdown, Text, Compact, JSON)

**Story**: 05-context-recovery
**Complexity**: L (Large)
**Status**: Pending

---

## Description

Implement the four output formatters that transform a context.json projection into the requested output format. The markdown formatter follows the exact template from Story 05, Requirement 4.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Create | `~/.claude-context/lib/format-context.sh` |

---

## Specification / Implementation Details

Four functions, each reading a context.json from stdin or as a file argument and outputting formatted text to stdout:

1. **format_json(context_file)**: Pretty-print the JSON as-is.

2. **format_markdown(context_file)**: Build markdown output following the template:
   - Session Info (ID, started, ended, project, event count, continuation link)
   - What Was Being Worked On (last prompt as blockquote, recent context bullets)
   - Actions Taken (numbered list of tool calls with verb + target + result)
   - Files Modified (markdown table: file, operations, last action)
   - Key Decisions (extracted from decision groups)
   - Where We Left Off (last_state section)

3. **format_text(context_file)**: Plain text with indentation and dashes, no markdown.

4. **format_compact(context_file)**: Single-line summary: `session_id | timestamp | project | events | last_prompt | files_modified_count`.

Apply progressive summarization for sessions with 100+ events (as defined in Story 05 Requirement 4):
- Last 20 events: full detail
- Events 21-50: tool name + target only
- Events 51-100: grouped
- Events 100+: one-line summary

---

## Dependencies

- [Task 09: Context Projection Builder Integration](/home/meywd/GlobalContext/tasks/05-context-recovery/09-context-projection-builder-integration.md) (context loader, for the data model)

---

## Acceptance Tests

1. Markdown output contains all six sections: Session Info, What Was Being Worked On, Actions Taken, Files Modified, Key Decisions, Where We Left Off.
2. File paths use backtick formatting in markdown.
3. Prompts use blockquote `>` formatting in markdown.
4. Text output is readable without markdown rendering.
5. Compact output fits on a single line per session.
6. JSON output is valid parseable JSON.
7. Progressive summarization activates at 100+ tool call events.

---

## Estimated Complexity: L
