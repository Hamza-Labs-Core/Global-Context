# Task 08: Event Envelope Construction

**Story**: 01-event-capture
**Estimated Complexity**: M (Medium)
**Status**: Pending

---

## Description

Implement the JSON envelope construction using a single `jq` invocation. This combines session_id extraction, envelope wrapping, and JSON output into one call for performance.

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Add envelope construction logic |

---

## Specification/Implementation Details

The envelope contains all 7 required fields:

```json
{
  "event_id": "<uuid>",
  "event_type": "<from $1>",
  "project_id": "<derived from cwd>",
  "session_id": "<from payload>",
  "sequence": <integer>,
  "timestamp": "<ISO 8601>",
  "data": { <raw payload> }
}
```

Combined `jq` invocation (extracts session_id AND builds envelope):

```bash
envelope_json=$(printf '%s' "$payload" | jq -c \
  --arg eid "$event_id" \
  --arg etype "$event_type" \
  --arg pid "$project_id" \
  --argjson seq "$next_seq" \
  --arg ts "$timestamp" \
  '{
    event_id: $eid,
    event_type: $etype,
    project_id: $pid,
    session_id: (.session_id // "unknown"),
    sequence: $seq,
    timestamp: $ts,
    data: .
  }')
```

For the session_id extraction (needed before the envelope for the directory path), extract it in a separate, fast `jq` call:

```bash
session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty')
```

This means two `jq` invocations total: one for session_id extraction (needed for directory), one for envelope construction. This is acceptable -- combining them into one call would require restructuring the flow since the session directory must exist before the envelope can be written.

For malformed JSON input: if `jq` fails to parse the payload, wrap the raw text as a string in the `data` field:

```bash
if ! session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null); then
  session_id="unknown"
  # Build envelope with raw string data
  envelope_json=$(jq -cn \
    --arg eid "$event_id" \
    --arg etype "$event_type" \
    --arg pid "$project_id" \
    --arg sid "unknown" \
    --argjson seq "$next_seq" \
    --arg ts "$timestamp" \
    --arg data "$payload" \
    '{event_id:$eid, event_type:$etype, project_id:$pid, session_id:$sid, sequence:$seq, timestamp:$ts, data:$data}')
fi
```

Output format: compact JSON (`jq -c`) per Story 03's encoding rules (no pretty-print, minimizes disk usage).

---

## Dependencies

- [Task 04: UUID Generation](/home/meywd/GlobalContext/tasks/01-event-capture/04-uuid-generation.md) -- for event_id.
- [Task 05: Timestamp Generation](/home/meywd/GlobalContext/tasks/01-event-capture/05-timestamp-generation.md) -- for timestamp.
- [Task 06: Sequence Numbering](/home/meywd/GlobalContext/tasks/01-event-capture/06-sequence-numbering-and-locking.md) -- for sequence number.

---

## Acceptance Tests

1. Pipe `{"session_id":"test-abc","tool_name":"Read"}` and verify the envelope contains all 7 fields (including project_id).
2. Verify `data` contains the original payload unmodified (including `session_id` field).
3. Verify `event_type` matches the `$1` argument.
4. Verify `event_id` is a valid UUID.
5. Verify `sequence` is an integer (not a string).
6. Verify `timestamp` is ISO 8601 UTC.
7. Pipe malformed input `"not json"` and verify the envelope is still valid JSON with `data` as a string.
8. Pipe JSON without `session_id` and verify `session_id` defaults to `"unknown"`.
9. Verify output is compact JSON (single line, no extra whitespace).
10. Pipe a 1MB JSON payload and verify it is captured completely in the `data` field.
