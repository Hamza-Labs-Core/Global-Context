# Task 03: Session ID Sanitization Function

**Story**: 01-event-capture
**Estimated Complexity**: S (Small)
**Status**: Pending

---

## Description

Implement a Bash function that sanitizes a session ID for safe use as a filesystem directory name. This follows Story 03's canonical sanitization rules (review issue M-2).

Rules (from Story 03):
- **Allowed characters**: `a-z`, `A-Z`, `0-9`, `-`, `_`
- **Disallowed characters**: `/`, `\`, spaces, null bytes, `.` (including leading dots), unicode beyond ASCII
- **Replacement**: Disallowed characters are replaced with `_`
- **Leading dot handling**: Leading dots are stripped (prevents hidden directories and `.`/`..` traversal)
- **Path traversal prevention**: After sanitization, verify the result does not equal `.` or `..`
- **Maximum length**: 255 characters (POSIX filesystem limit per Story 03, not 128 as in original Story 01)
- **Empty fallback**: If the sanitized result is empty, use `unknown-{uuid}` (where `{uuid}` comes from the UUID generation function, Task 4)

Note: The original (unsanitized) `session_id` is preserved in the event envelope's `session_id` field. Only the filesystem directory name uses the sanitized version.

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Add `sanitize_session_id` function |

---

## Specification/Implementation Details

```bash
sanitize_session_id() {
  local raw="$1"
  # Strip characters outside allowed set
  local safe
  safe=$(printf '%s' "$raw" | tr -cd 'a-zA-Z0-9_-')
  # Truncate to 255 characters
  safe="${safe:0:255}"
  # Prevent path traversal
  if [ -z "$safe" ] || [ "$safe" = "." ] || [ "$safe" = ".." ]; then
    safe="unknown-$(generate_uuid)"
  fi
  printf '%s' "$safe"
}
```

Note: dots are excluded from the `tr` character class entirely (unlike Story 01's original which allowed dots). This aligns with Story 03's rule that dots are disallowed, preventing hidden directories.

---

## Dependencies

- [Task 01: Base Dir Resolution](/home/meywd/GlobalContext/tasks/01-event-capture/01-base-dir-resolution.md)
- Soft dependency on [Task 04: UUID Generation](/home/meywd/GlobalContext/tasks/01-event-capture/04-uuid-generation.md) for the empty fallback case.

---

## Acceptance Tests

1. Input `abc-123` produces `abc-123` (no change).
2. Input `session/with/slashes` produces `sessionwithslashes`.
3. Input `has spaces here` produces `hasspaceshere`.
4. Input `..` produces `unknown-{uuid}`.
5. Input `.hidden` produces `hidden` (leading dot stripped by character class exclusion).
6. Input empty string `""` produces `unknown-{uuid}`.
7. Input a 300-character alphanumeric string is truncated to 255 characters.
8. Input `hello.world` produces `helloworld` (dots removed per Story 03 rules).
9. Verify the original session_id (before sanitization) is preserved in the event envelope.
