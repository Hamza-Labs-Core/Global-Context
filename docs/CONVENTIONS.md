# GlobalContext Conventions

## Base Directory Resolution

Every script in the GlobalContext system must resolve the storage root consistently. No script should hardcode `~/.claude-context` as a literal path -- always use `$CLAUDE_CONTEXT_PATH` with the default fallback.

### Pattern (via paths.sh -- preferred)

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

### Inline Pattern (exception for standalone scripts)

Scripts that must be fully self-contained for performance reasons (e.g., `capture-event`,
which runs on every hook invocation and cannot afford the overhead of sourcing a library)
may use the inline pattern instead of sourcing `paths.sh`:

```bash
BASE_DIR="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"
EVENTS_DIR="$BASE_DIR/events"
```

This is an intentional exception, not a violation of the "no hardcoded paths" rule.
The key requirement is that `CLAUDE_CONTEXT_PATH` is always respected as an override.
Scripts that are not performance-critical (e.g., `install.sh`) should source `paths.sh`
when available, falling back to the inline pattern only if `paths.sh` is not found.

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
