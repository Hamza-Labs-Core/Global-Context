# Task 09: Main Script Assembly (capture-event)

**Story**: 01-event-capture
**Estimated Complexity**: M (Medium)
**Status**: Pending

---

## Description

Assemble the complete `capture-event` script by combining all the functions and logic from Tasks 1-8 into a single, well-structured Bash script. This is the integration task.

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Assemble complete script |

---

## Specification/Implementation Details

Script flow (pseudocode):

```
1.  #!/usr/bin/env bash
2.  Set trap to always exit 0 (see Task 10)
3.  Resolve BASE_DIR via CLAUDE_CONTEXT_PATH (Task 1)
4.  Validate $1 (event_type) is provided; warn on unknown types
5.  Check jq is available; exit 0 if missing
6.  Read stdin into $payload variable (single read)
7.  Validate $payload is non-empty
8.  Extract session_id from $payload using jq (fallback: "unknown")
9.  Sanitize session_id for filesystem use (Task 3)
10. Derive project_id from cwd (basename + hash6 of full path)
11. mkdir -p session directory ($EVENTS_DIR/$project_id/$safe_session_id)
12. Generate event_id via generate_uuid (Task 4)
13. Generate timestamp via generate_timestamp (Task 5)
14. Acquire flock on {session_dir}/.lock (Task 6)
15.   Count existing [0-9]*.json files for next sequence number
15.   Construct envelope JSON using jq (Task 8)
16.   Atomic write envelope to {session_dir}/{padded}.json (Task 7)
17. Release flock (automatic on subshell exit)
18. Exit 0
```

Known event types list (for warning on unknown types):

```bash
KNOWN_TYPES="SessionStarted UserPromptReceived ToolCallRequested ToolCallCompleted ToolCallFailed AgentSpawned AgentCompleted TurnCompleted CompactionTriggered SessionEnded"
```

Unknown event types produce a stderr warning but the event is still captured (forward compatibility).

Constants:

```bash
MAX_SESSION_ID_LENGTH=255
LOCK_TIMEOUT=5
SEQUENCE_PAD_WIDTH=6
SYNC_EVENT_TYPES="SessionStarted UserPromptReceived CompactionTriggered"
```

Stdin reading:

```bash
payload=$(cat)
```

This reads all of stdin into a variable. Using `cat` is simpler and handles large payloads better than `read` with IFS manipulation.

---

## Dependencies

- [Task 01: Base Dir Resolution](/home/meywd/GlobalContext/tasks/01-event-capture/01-base-dir-resolution.md)
- [Task 02: Directory Structure and install.sh](/home/meywd/GlobalContext/tasks/01-event-capture/02-directory-structure-and-install.md)
- [Task 03: Session ID Sanitization](/home/meywd/GlobalContext/tasks/01-event-capture/03-session-id-sanitization.md)
- [Task 04: UUID Generation](/home/meywd/GlobalContext/tasks/01-event-capture/04-uuid-generation.md)
- [Task 05: Timestamp Generation](/home/meywd/GlobalContext/tasks/01-event-capture/05-timestamp-generation.md)
- [Task 06: Sequence Numbering](/home/meywd/GlobalContext/tasks/01-event-capture/06-sequence-numbering-and-locking.md)
- [Task 07: Atomic Write Helper](/home/meywd/GlobalContext/tasks/01-event-capture/07-atomic-write-helper.md)
- [Task 08: Envelope Construction](/home/meywd/GlobalContext/tasks/01-event-capture/08-envelope-construction.md)

All component tasks (Tasks 1-8) must be complete before assembly.

---

## Acceptance Tests

1. Run `echo '{"session_id":"s1"}' | capture-event SessionStarted`. Verify `$BASE_DIR/events/{project-id}/s1/000001.json` exists with correct envelope (including `project_id` field).
2. Run all 10 event types. Verify each produces a valid event file.
3. Run with unknown event type `FutureEvent`. Verify event is captured and stderr contains a warning.
4. Run with no arguments. Verify stderr warning and exit 0.
5. Run with empty stdin. Verify stderr warning and exit 0.
6. Run from `/tmp` (different working directory). Verify it still works (absolute paths).
7. Verify no stdout output at all (redirect stdout to a file and check it is empty).
8. Verify `CLAUDE_CONTEXT_PATH` is respected.
