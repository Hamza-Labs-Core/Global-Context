# Task 04: Projection Staleness Check Using _last_sequence (Fix M-6)

**Story**: 05-context-recovery
**Complexity**: S (Small)
**Status**: Pending

---

## Description

Implement a helper function that checks whether a projection is current by comparing `_last_sequence` from the projection file against the highest sequence number in the session's event directory. This replaces the unreliable `stat -c %Y` mtime comparison.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Create | `~/.claude-context/lib/projection-check.sh` |

---

## Specification / Implementation Details

```bash
# is_projection_current(project_id, session_id, projection_name)
# Returns 0 (true) if projection is current, 1 (false) if stale or missing
is_projection_current() {
  local project_id="$1"
  local session_id="$2"
  local projection_name="${3:-context}"
  local proj_file="$GC_PROJECTIONS_DIR/$project_id/$session_id/${projection_name}.json"

  # If projection file does not exist, it is stale
  [ -f "$proj_file" ] || return 1

  # Read _last_sequence from projection
  local proj_seq
  proj_seq=$(jq -r '._last_sequence // 0' "$proj_file" 2>/dev/null) || return 1

  # Find highest sequence number in events directory
  # Use [0-9]*.json to exclude session.json and other non-event files
  local highest_event
  highest_event=$(ls "$GC_EVENTS_DIR/$project_id/$session_id/"[0-9]*.json 2>/dev/null \
    | sed 's/.*\///' | sed 's/\.json$//' | sort -n | tail -1)
  [ -z "$highest_event" ] && return 1

  # Remove leading zeros for numeric comparison
  local event_seq=$((10#$highest_event))

  # Projection is current if _last_sequence >= highest event sequence
  [ "$proj_seq" -ge "$event_seq" ]
}
```

> **Note**: Plan 03, Task 11 provides `gc_is_projection_stale()` with similar logic. This function can either reuse that or be a thin wrapper. The key difference is this version is used by `gc-query` (read side) while Plan 03's is used by the projection engine.

---

## Dependencies

- [Task 01: Shared Store Path Resolution Helper](/home/meywd/GlobalContext/tasks/05-context-recovery/01-shared-store-path-resolution-helper.md) (paths.sh for `$GC_EVENTS_DIR`, `$GC_PROJECTIONS_DIR`)
- Story 04 (projection files must contain `_last_sequence` metadata)

---

## Acceptance Tests

1. With a projection file at `_last_sequence: 50` and events up to `000050.json`: returns current (exit 0).
2. With a projection file at `_last_sequence: 50` and events up to `000055.json`: returns stale (exit 1).
3. With no projection file: returns stale (exit 1).
4. With no events directory: returns stale (exit 1).
5. Works on both Linux and macOS (no platform-specific `stat` calls).

---

## Estimated Complexity: S
