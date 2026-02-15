# Task 02: Session ID Sanitization Function

**Story**: 03-storage-layer
**Status**: Pending
**Estimated Complexity**: S (Small) -- 1-2 hours

---

## Description

Implement the canonical session ID sanitization rules in a dedicated, testable function within the shared library. This function is the single authoritative implementation -- Story 01 and all other stories must call it, not re-implement it.

This directly addresses review issue **M-2** (canonical session ID sanitization).

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/sanitize.sh` | Create | Session ID sanitization function |
| `tests/lib/test_sanitize.sh` | Create | Unit tests for all edge cases |

---

## Specification

Function: `gc_sanitize_session_id(raw_id) -> sanitized_id`

Rules (canonical, all other stories reference these):

1. **Allowed characters**: `a-z`, `A-Z`, `0-9`, `-`, `_`
2. **Disallowed characters stripped**: All characters not in `[a-zA-Z0-9_-]` are removed (using `tr -cd`). This includes `/`, `\`, spaces, null bytes, dots, non-ASCII.
3. **Path traversal prevention**: Dots are stripped by the character class, so `..` and `.hidden` are neutralized automatically.
4. **Empty result**: If after sanitization the string is empty, use `"unknown"`.
5. **Maximum length**: Truncate to 255 characters after sanitization.
6. The mapping is deterministic -- the same input always yields the same output.

Edge case table (canonical reference):

| Input | Output | Reason |
|---|---|---|
| `abc123` | `abc123` | Already valid |
| `session-2026` | `session-2026` | Hyphens allowed |
| `session/with/slashes` | `sessionwithslashes` | Slashes stripped |
| `has spaces` | `hasspaces` | Spaces stripped |
| `../../../etc/passwd` | `etcpasswd` | Dots and slashes stripped |
| (empty string) | `unknown` | Fallback |
| `.hidden` | `hidden` | Dot stripped |
| 300-char string | first 255 chars | Truncated |
| `UPPER-case` | `UPPER-case` | Case preserved |
| `with.dots.inside` | `withdotsinside` | Dots stripped |

---

## Dependencies

- **Task 01**: `/home/meywd/GlobalContext/tasks/03-storage-layer/01-shared-path-resolver.md` (paths.sh for UUID generation helper, if shared; otherwise standalone)

---

## Acceptance Tests

1. Run `tests/lib/test_sanitize.sh` -- all 10+ edge cases from the table above pass.
2. Call `gc_sanitize_session_id ""` -- returns `"unknown"`.
3. Call `gc_sanitize_session_id "$(python3 -c "print('a'*300))"` -- returns a 255-char string.
4. Verify determinism: calling twice with the same input returns identical output (except the empty-string fallback which generates a new UUID each time).
