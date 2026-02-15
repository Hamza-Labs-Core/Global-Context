# Task 04: UUID v4 Generation Function

**Story**: 01-event-capture
**Estimated Complexity**: S (Small)
**Status**: Pending

---

## Description

Implement a Bash function that generates a UUID v4 using a three-tier fallback chain. This addresses review issue C-5 by using a bash-native RFC 4122-compliant UUID as the final fallback instead of a non-standard timestamp+PID composite.

Fallback chain:
1. `uuidgen` command (most Linux/macOS systems) -- convert to lowercase
2. Read from `/proc/sys/kernel/random/uuid` (Linux kernel fallback)
3. Bash-native UUID v4 using `$RANDOM` and `printf` (RFC 4122 compliant)

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Add `generate_uuid` function |

---

## Specification/Implementation Details

```bash
generate_uuid() {
  # Tier 1: uuidgen command
  if command -v uuidgen &>/dev/null; then
    uuidgen | tr 'A-F' 'a-f'
    return
  fi
  # Tier 2: Linux kernel fallback
  if [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
    return
  fi
  # Tier 3: Bash-native UUID v4 (RFC 4122 compliant)
  printf '%04x%04x-%04x-%04x-%04x-%04x%04x%04x' \
    $RANDOM $RANDOM \
    $RANDOM \
    $(( (RANDOM & 0x0FFF) | 0x4000 )) \
    $(( (RANDOM & 0x3FFF) | 0x8000 )) \
    $RANDOM $RANDOM $RANDOM
}
```

The final fallback produces a valid UUID v4 format string. The version nibble is set to `4` and the variant bits are set to `10`, per RFC 4122. The entropy source (`$RANDOM`) is 15-bit, so uniqueness is weaker than a true UUID, but sufficient for event IDs in a single-user filesystem store.

---

## Dependencies

- [Task 01: Base Dir Resolution](/home/meywd/GlobalContext/tasks/01-event-capture/01-base-dir-resolution.md)

---

## Acceptance Tests

1. With `uuidgen` available: verify output matches UUID v4 regex `^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`.
2. With `uuidgen` removed from PATH but `/proc/sys/kernel/random/uuid` available: verify output is a valid UUID.
3. With both unavailable: verify the bash-native fallback produces a string matching UUID v4 regex (version nibble = 4, variant = 8/9/a/b).
4. Call the function 100 times. Verify no duplicates.
