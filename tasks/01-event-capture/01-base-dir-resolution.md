# Task 01: Base Directory Resolution with CLAUDE_CONTEXT_PATH Support

**Story**: 01-event-capture
**Estimated Complexity**: S (Small)
**Status**: Pending

---

## Description

Create a shared shell snippet (and document the pattern) that resolves the GlobalContext storage root. Every script in the system must use this pattern at the top. This addresses review issue M-4.

The pattern:

```bash
BASE_DIR="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"
EVENTS_DIR="$BASE_DIR/events"
```

This is not a separate file (to avoid adding a sourcing dependency), but a documented inline pattern that must appear at the top of both `capture-event` and `install.sh`.

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/capture-event` | Create -- add base dir resolution block at top |
| `/home/meywd/GlobalContext/src/install.sh` | Create -- add base dir resolution block at top |
| `/home/meywd/GlobalContext/docs/CONVENTIONS.md` | Create -- document the `CLAUDE_CONTEXT_PATH` pattern for all scripts to follow |

---

## Specification/Implementation Details

The base directory resolution pattern must be inlined at the top of every script in the system. It resolves the storage root using the `CLAUDE_CONTEXT_PATH` environment variable with a fallback to `~/.claude-context`.

```bash
BASE_DIR="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"
EVENTS_DIR="$BASE_DIR/events"
```

Key points:
- This is an **inline pattern**, not a sourced file, to avoid adding a sourcing dependency.
- Every script (`capture-event`, `install.sh`, and all future scripts) must include this block at the top.
- The `CONVENTIONS.md` document should describe this pattern so future scripts follow it consistently.

---

## Dependencies

None (first task).

---

## Acceptance Tests

1. Set `CLAUDE_CONTEXT_PATH=/tmp/gc-test` and source the snippet. Verify `BASE_DIR` equals `/tmp/gc-test`.
2. Unset `CLAUDE_CONTEXT_PATH` and source the snippet. Verify `BASE_DIR` equals `$HOME/.claude-context`.
3. Set `CLAUDE_CONTEXT_PATH` to a path with a trailing slash. Verify the script handles it (strip trailing slash or works regardless).
