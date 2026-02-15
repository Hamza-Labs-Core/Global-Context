# Task 18: gc-query replay Command

**Story**: 05-context-recovery
**Complexity**: M (Medium)
**Status**: Pending

---

## Description

Transform raw events into a human-readable numbered narrative.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Modify | `~/.claude-context/bin/gc-query` (add `cmd_replay` function) |

---

## Specification / Implementation Details

1. Read events from the session (using the same logic as `cmd_events`).
2. Apply `--from` and `--to` sequence range filters.
3. Transform each event into a narrative step using the event-to-narrative mapping from Story 05:
   - `SessionStarted` -> "Session started in {cwd} (source: {source})"
   - `UserPromptReceived` -> "User: \"{prompt}\"" (truncated to 200 chars)
   - `ToolCallRequested` -> "Agent plans to use {tool_name} on {target}"
   - `ToolCallCompleted` -> "Executed {tool_name}: {brief result}" (result summarized to 100 chars)
   - `ToolCallFailed` -> "FAILED: {tool_name} -- {error}"
   - `AgentSpawned` -> "Sub-agent started: {description}"
   - `AgentCompleted` -> "Sub-agent finished: {summary}"
   - `TurnCompleted` -> "Turn completed"
   - `CompactionTriggered` -> "--- COMPACTION ---" (visually distinct)
   - `SessionEnded` -> "Session ended"
   - Unknown -> "[Unknown: {type}] {data summary}"
4. Output as numbered steps: "Step 1: ...", "Step 2: ...".
5. `--verbose` includes full event payloads after each step.
6. Support text (default), markdown, and JSON output formats.

---

## Dependencies

- [Task 03: gc-query Entry Point and Argument Parser](/home/meywd/GlobalContext/tasks/05-context-recovery/03-gc-query-entry-point-and-argument-parser.md) (gc-query entry point)
- [Task 05: Session Resolution Helpers](/home/meywd/GlobalContext/tasks/05-context-recovery/05-session-resolution-helpers.md) (session resolution)
- [Task 07: gc-query events Command](/home/meywd/GlobalContext/tasks/05-context-recovery/07-gc-query-events-command.md) (events reading logic)

---

## Acceptance Tests

1. `gc-query replay <session-id>` produces a numbered narrative.
2. Each event type renders with the correct template.
3. `gc-query replay <session-id> --from 40 --to 60` only replays that range.
4. `gc-query replay <session-id> --verbose` includes full payloads.
5. Compaction events are visually distinct (--- COMPACTION ---).
6. User prompts longer than 200 chars are truncated with "...".
7. Tool results longer than 100 chars are summarized.
8. Unknown event types render as "[Unknown: {type}]".
9. Missing events in sequence (gaps) are noted but do not break replay.
10. Replay of a 100-event session completes in under 1 second.

---

## Estimated Complexity: M
