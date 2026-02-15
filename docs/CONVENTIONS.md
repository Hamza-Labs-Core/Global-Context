# GlobalContext Conventions

## Base Directory Resolution

Every script in the GlobalContext system must resolve the storage root using the shared `paths.sh` library. No script should hardcode `~/.claude-context`.

### Pattern (via paths.sh)

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/paths.sh"
```

This provides:

| Variable | Value |
|----------|-------|
| `GC_ROOT` | `${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}` |
| `GC_EVENTS_DIR` | `$GC_ROOT/events` |
| `GC_PROJECTIONS_DIR` | `$GC_ROOT/projections` |
| `GC_BIN_DIR` | `$GC_ROOT/bin` |
| `GC_CONFIG_FILE` | `$GC_ROOT/config.json` |

### Environment Variable Override

Set `CLAUDE_CONTEXT_PATH` to override the default storage location:

```bash
export CLAUDE_CONTEXT_PATH=/tmp/my-test-store
```

This is useful for:
- Testing (isolate test data from production)
- Custom installations
- CI/CD environments

### Inline Pattern (for standalone scripts)

For scripts that cannot source `paths.sh` (e.g., `capture-event` which must be self-contained for performance), use the inline pattern:

```bash
BASE_DIR="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"
EVENTS_DIR="$BASE_DIR/events"
```

This must appear at the top of every standalone script, before any path references.

## Event Types

Known event types (forward-compatible -- unknown types are captured with a warning):

- `SessionStarted`
- `UserPromptReceived`
- `ToolCallRequested`
- `ToolCallCompleted`
- `ToolCallFailed`
- `AgentSpawned`
- `AgentCompleted`
- `TurnCompleted`
- `CompactionTriggered`
- `SessionEnded`

## Sync vs Async Event Types

Some event types are "sync" (critical) and receive `fsync` on write:

- `SessionStarted`
- `UserPromptReceived`
- `CompactionTriggered`

All others are "async" and skip `fsync` for performance.

## Session ID Sanitization

Session IDs are sanitized for filesystem safety:
- Allowed characters: `a-zA-Z0-9_-`
- All other characters (including dots, slashes, spaces) are stripped
- Empty results fall back to `unknown-{uuid}`
- Maximum length: 255 characters
- The original (unsanitized) session_id is preserved in the event envelope

## Project ID Derivation

Project IDs are derived from the working directory:
- Format: `{basename}-{hash6}`
- `basename`: last path component, sanitized to `[a-zA-Z0-9_-]`
- `hash6`: first 6 hex chars of SHA-256 of the full absolute path

## Event Envelope

All events are stored as compact JSON with 7 fields:

```json
{"event_id":"<uuid>","event_type":"<type>","project_id":"<id>","session_id":"<id>","sequence":<int>,"timestamp":"<iso8601>","data":{...}}
```

## File Naming

Event files: `{padded_sequence}.json` (e.g., `000001.json`)
Lock files: `.lock` (per session directory)
Session metadata: `session.json` (per session directory)
