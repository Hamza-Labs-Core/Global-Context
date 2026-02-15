# Task 05: Timestamp Generation Function

**Story**: 01-event-capture
**Estimated Complexity**: S (Small)
**Status**: Pending

---

## Description

Implement a Bash function that generates an ISO 8601 UTC timestamp with millisecond precision. Include a fallback for environments where `%3N` (milliseconds) is not supported by `date`.

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Add `generate_timestamp` function |

---

## Specification/Implementation Details

Primary:
```bash
date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
```

Fallback (detects `%3N` not supported):
```bash
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Detection strategy: call `date -u +"%3N"` once and check if the output is a 3-digit number. If it outputs the literal `%3N`, the feature is not supported.

```bash
generate_timestamp() {
  # Check if %3N is supported (cache result if possible)
  local ms_check
  ms_check=$(date -u +"%3N" 2>/dev/null)
  if [[ "$ms_check" =~ ^[0-9]{3}$ ]]; then
    date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
  else
    date -u +"%Y-%m-%dT%H:%M:%SZ"
  fi
}
```

---

## Dependencies

- [Task 01: Base Dir Resolution](/home/meywd/GlobalContext/tasks/01-event-capture/01-base-dir-resolution.md)

---

## Acceptance Tests

1. On a system with `%3N` support: verify output matches `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$`.
2. On a system without `%3N` support (or mocked): verify output matches `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$`.
3. Verify the timestamp is in UTC (ends with `Z`).
