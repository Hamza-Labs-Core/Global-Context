# Task 05: JSON Validation Helper

**Story**: 03-storage-layer
**Status**: Pending
**Estimated Complexity**: S (Small) -- 1-2 hours

---

## Description

Implement a function that validates a JSON string before it is written to disk. This ensures no corrupt or invalid JSON is ever persisted to the event store.

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/json_validate.sh` | Create | JSON validation and required-field checking |
| `tests/lib/test_json_validate.sh` | Create | Validation tests |

---

## Specification

Function: `gc_validate_event_json(json_string) -> 0 (valid) or 1 (invalid)`

Validation steps:

1. Parse JSON using `jq empty` -- if this fails, the JSON is malformed.
2. Check required fields: `event_id`, `event_type`, `project_id`, `session_id`, `sequence`, `timestamp`, `data` (7 fields).
3. Verify `sequence` is a positive integer.
4. Verify `timestamp` is a non-empty string (full ISO 8601 validation is out of scope for bash).
5. Verify `data` is an object (not null, not a string).

On failure:

- Print error reason to stderr.
- Return exit code 1.
- The caller is responsible for writing to `_rejected/` if desired.

Function: `gc_validate_json(json_string) -> 0 or 1`

- Simpler variant: just checks if the string is valid JSON (for non-event files like session.json, config.json).

---

## Dependencies

- External: `jq` must be installed (validated during init, Task 7).

---

## Acceptance Tests

1. Valid event JSON -- returns 0.
2. Malformed JSON (missing closing brace) -- returns 1.
3. JSON missing `event_id` -- returns 1.
4. JSON with `sequence: "not_a_number"` -- returns 1.
5. JSON with `data: null` -- returns 1.
6. Valid non-event JSON via `gc_validate_json` -- returns 0.
