# Task 11: Performance Validation

**Story**: 01-event-capture
**Estimated Complexity**: S (Small)
**Status**: Pending

---

## Description

Validate that the capture script meets the performance budget: under 100ms for typical async hook payloads, under 50ms target.

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/tests/perf-test.sh` | Create performance benchmark script |

---

## Specification/Implementation Details

Verification approach:

```bash
# Measure single invocation
time echo '{"session_id":"perf-test","tool_name":"Read","tool_input":{"file_path":"/tmp/test"}}' \
  | $BASE_DIR/bin/capture-event ToolCallCompleted
```

Performance budget:

| Hook Type | Target | Hard Limit |
|-----------|--------|------------|
| Async hooks | < 50ms | 100ms |
| Sync hooks | < 100ms | 5000ms |

If performance exceeds targets, optimize:
- Verify at most 4 subprocesses: `jq` (x2 -- session_id + envelope), `date` (x1), `uuidgen` (x1), implicit `flock`.
- Verify stdin is read exactly once.
- Verify no unnecessary disk reads.
- Consider caching the `%3N` support check in a variable.
- Consider combining the two `jq` calls if the flow can be restructured.

---

## Dependencies

- [Task 09: Main Script Assembly](/home/meywd/GlobalContext/tasks/01-event-capture/09-main-script-assembly.md) -- complete script needed.
- [Task 10: Error Handling and Safety](/home/meywd/GlobalContext/tasks/01-event-capture/10-error-handling-and-safety.md) -- error handling must be in place for realistic benchmarking.

---

## Acceptance Tests

1. Run the performance benchmark 20 times. Verify median execution time is under 100ms.
2. Run with a 1MB payload. Verify it completes (may exceed 100ms -- that is acceptable per the edge case documentation).
3. Count subprocess invocations using `strace -f -e trace=execve` (Linux). Verify at most 5 exec calls (bash itself + jq x2 + date + uuidgen).
