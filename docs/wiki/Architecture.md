# Architecture

GlobalContext uses Event Sourcing and CQRS (Command Query Responsibility Segregation) to capture and query Claude Code session data. This page explains the system design, data flow, and key architectural decisions.

## Table of Contents

- [CQRS Design](#cqrs-design)
- [Event Sourcing Principles](#event-sourcing-principles)
- [Directory Layout](#directory-layout)
- [Data Flow](#data-flow)
- [Project-ID Scheme](#project-id-scheme)
- [Session Lifecycle](#session-lifecycle)
- [Sequence Numbering](#sequence-numbering)
- [Concurrency Control](#concurrency-control)
- [Design Decisions](#design-decisions)

## CQRS Design

GlobalContext separates write operations (event capture) from read operations (projections) to optimize each path independently.

### Write Side (Command)

**Technology**: Bash + jq

**Characteristics**:
- Fast and dumb
- No business logic
- No validation beyond structure
- Just append JSON to files
- Always exits successfully (never blocks Claude Code)

**Components**:
- `gc-hook`: Wrapper script that receives hook JSON on stdin
- `capture-event`: Core capture script that writes event files
- Shared libraries: paths, session metadata, atomic writes

**Performance Target**:
- Async hooks: < 50ms
- Sync hooks: < 100ms
- Never blocks or crashes

### Read Side (Query)

**Technology**: Node.js (zero npm dependencies)

**Characteristics**:
- Smart projection builders
- Event replay engine
- Multiple output formats (JSON, text, markdown)
- Incremental and full rebuild support

**Components**:
- `project`: CLI for building projections
- `gc-query`: CLI for querying sessions
- Projection handlers: timeline, files, decisions, context, summary
- Event replay engine: streams events through handlers

**Performance Target**:
- 1,000 events in < 2 seconds
- 50,000 events in < 60 seconds
- Memory bounded by projection size, not event count

## Event Sourcing Principles

### Immutability

Events are facts. Once written, they never change. This provides:
- Complete audit trail
- Time-travel queries (replay to any point)
- Safe concurrent reads (no locks needed)
- Reproducible projections (rebuild anytime)

### Append-Only

New events are always appended. Sequence numbers increase monotonically. Benefits:
- No update conflicts
- Simple concurrency model (only coordinate sequence assignment)
- Natural time ordering

### Event Envelope

Every event shares a common structure:

```json
{
  "event_id": "uuid-v4",
  "event_type": "ToolCallCompleted",
  "project_id": "my-project-a3f7b2",
  "session_id": "abc123",
  "sequence": 42,
  "timestamp": "2026-02-14T10:30:00.000Z",
  "data": { /* raw hook payload */ }
}
```

The envelope provides:
- Global uniqueness (event_id)
- Type discrimination (event_type)
- Scoping (project_id, session_id)
- Ordering (sequence, timestamp)
- Complete context (data)

### Projections as Views

Projections are derived data. They contain no information not present in events. Benefits:
- Rebuildable from events (if corrupted or schema changes)
- Multiple projections from same events (different views of same data)
- Incremental updates (only process new events)

## Directory Layout

```
~/.claude-context/
├── events/
│   └── {project-id}/
│       └── {session-id}/
│           ├── session.json
│           ├── .lock
│           ├── 000001.json
│           ├── 000002.json
│           └── ...
├── projections/
│   └── {project-id}/
│       ├── {session-id}/
│       │   ├── timeline.json
│       │   ├── files-touched.json
│       │   ├── decisions.json
│       │   ├── context.json
│       │   └── summary.json
│       └── latest -> {session-id}
├── bin/
│   ├── capture-event
│   ├── gc-hook
│   ├── gc-init
│   ├── gc-query
│   └── project
└── config.json
```

### Key Paths

| Path | Purpose |
|------|---------|
| `events/{project-id}/{session-id}/` | Per-session event store |
| `events/{project-id}/{session-id}/session.json` | Session metadata (updated on every event) |
| `events/{project-id}/{session-id}/.lock` | flock file for sequence coordination |
| `events/{project-id}/{session-id}/NNNNNN.json` | Individual event files (6-digit zero-padded sequence) |
| `projections/{project-id}/{session-id}/` | Per-session projection output |
| `projections/{project-id}/latest` | Symlink to most recent session in this project |
| `bin/` | Executable scripts |
| `config.json` | Store configuration |

## Data Flow

### Event Capture Flow

```
1. Claude Code Hook Fires
   ↓
2. gc-hook receives JSON on stdin
   ↓
3. Auto-initialize store if needed (SessionStart only)
   ↓
4. capture-event reads stdin
   ↓
5. Extract session_id from payload
   ↓
6. Derive project_id from cwd
   ↓
7. Create session directory (mkdir -p)
   ↓
8. Acquire flock on .lock file
   ↓
9. Count existing event files → compute next sequence
   ↓
10. Generate event_id (UUID), timestamp
   ↓
11. Construct envelope with jq
   ↓
12. Write event file atomically
   ↓
13. Update session.json (within same flock)
   ↓
14. Release flock (automatic on fd close)
   ↓
15. Exit 0 (always, even on error)
```

### Projection Build Flow

```
1. User invokes: gc-query last
   ↓
2. Resolve project_id from cwd
   ↓
3. Follow projections/{project-id}/latest symlink
   ↓
4. Check if context.json exists and is up-to-date
   ↓
5. If stale or missing:
   a. Load existing projection (if any) to get _last_sequence
   b. Scan events/{project-id}/{session-id}/ for new events
   c. Replay new events through context handler
   d. Merge into existing projection
   e. Write updated projection atomically
   ↓
6. Format projection as markdown
   ↓
7. Output to stdout
```

### Session Discovery Flow

```
1. User invokes: gc-query sessions
   ↓
2. Scan events/ directory for all project-id directories
   ↓
3. For each project:
   a. Scan for session-id directories
   b. Read session.json from each
   c. Collect metadata (started_at, event_count, last_prompt, etc.)
   ↓
4. Sort by started_at descending
   ↓
5. Format as table and output
```

## Project-ID Scheme

Project IDs provide human-readable + collision-resistant identifiers for project directories.

### Format

```
{basename}-{hash6}
```

Where:
- `basename` = last component of absolute path, sanitized to `[a-zA-Z0-9_-]`
- `hash6` = first 6 hex characters of SHA-256 hash of full absolute path

### Examples

| Working Directory | Project ID |
|------------------|------------|
| `/home/user/my-project` | `my-project-a3f7b2` |
| `/home/user/work/my-project` | `my-project-e91c04` |
| `/tmp/test` | `test-7f3a2b` |
| `/home/user/Code/GlobalContext` | `GlobalContext-f8d3c5` |

### Derivation Algorithm

```bash
gc_derive_project_id() {
  local project_dir="$1"
  if [ -z "$project_dir" ]; then
    echo "_unknown-000000"
    return
  fi
  local basename
  basename=$(basename "$project_dir" | tr -cd 'a-zA-Z0-9_-')
  [ -z "$basename" ] && basename="_root"
  local hash
  hash=$(printf '%s' "$project_dir" | sha256sum | cut -c1-6)
  echo "${basename}-${hash}"
}
```

### Benefits

- Human-readable: `my-project-a3f7b2` tells you which project
- Collision-resistant: Different paths with same name get different hashes
- Filesystem-safe: Only alphanumeric, hyphens, underscores
- Consistent: Same path always produces same project-id
- Per-project scoping: Each project has its own event namespace

## Session Lifecycle

### Session Start

1. Claude Code starts or resumes a session
2. SessionStart hook fires (sync)
3. gc-hook checks if store exists at `~/.claude-context/`
4. If not, runs `gc-init` to create directory structure
5. capture-event writes first event: SessionStarted
6. session.json created with metadata from SessionStarted event

### Session Active

1. Events captured as hooks fire (UserPromptReceived, ToolCallRequested, etc.)
2. Each event appends a new file with incremented sequence number
3. session.json updated on every event (event_count, last_event_at, etc.)
4. Projections built on-demand when gc-query runs

### Session Compaction

1. PreCompact hook fires (sync) before context is lost
2. CompactionTriggered event captured
3. This is the last chance to record state before context compression
4. Session continues with compacted context

### Session End

1. SessionEnd hook fires (async)
2. SessionEnded event captured
3. session.json updated with ended_at timestamp
4. Final projections can be built for full session

### Special Case: Crash or Kill

If Claude Code crashes or is killed:
- SessionEnd hook never fires
- session.json will have `ended_at: null`
- All events up to crash are preserved
- Next session will be a new session-id

## Sequence Numbering

### Assignment Algorithm

```
1. Acquire exclusive lock on {session-dir}/.lock using flock
2. List existing [0-9]*.json files in {session-dir}
3. Count them (exclude session.json, .lock, etc.)
4. Next sequence = count + 1
5. Zero-pad to 6 digits → filename
6. Write event file
7. Release lock (automatic on fd close)
```

### Zero-Padding

Sequences are zero-padded to 6 digits for correct lexicographic sorting:

| Sequence | Filename |
|----------|----------|
| 1 | 000001.json |
| 42 | 000042.json |
| 999 | 000999.json |
| 10000 | 010000.json |
| 999999 | 999999.json |

This supports up to 999,999 events per session, far beyond practical limits.

### Sequence in Envelope

The `sequence` field in the event envelope always matches the filename number:

```json
{
  "sequence": 42,
  ...
}
```

File: `000042.json`

## Concurrency Control

### Lock File

Each session directory has a `.lock` file used for flock-based exclusive locking.

### Lock Scope

The lock is held during:
1. Sequence number assignment (count existing files)
2. Event file write
3. session.json update

All three operations are atomic within the lock.

### Lock Timeout

```bash
flock -w 5 200 || { echo "Lock timeout" >&2; exit 0; }
```

- 5-second timeout
- If lock cannot be acquired, event is dropped (acceptable vs. blocking Claude Code)
- Warning logged to stderr

### Concurrent Writes

Two concurrent hooks for the same session:
1. First process acquires lock, writes event 1, releases lock
2. Second process waits, acquires lock, writes event 2, releases lock
3. Result: Two distinct, sequential event files (no gaps, no collisions)

### No Shared State

Key design decision: No global sessions index. Each session directory is independent. Benefits:
- No contention between different sessions
- Per-session locks only coordinate events within that session
- Projects are isolated (different project-ids have separate directories)

## Design Decisions

### Per-Session session.json

Instead of a global sessions.json:
- Each session has its own metadata file
- Updated within the same flock scope as event writes (no new contention)
- No shared write-side index violating CQRS
- gc-query sessions scans directories and reads per-session files

### Project-ID Directory Layer

Events organized by project first, then session:
- `events/{project-id}/{session-id}/`
- Natural scoping: gc-query from within a project defaults to that project
- Per-project latest symlink: `projections/{project-id}/latest`
- Cross-project queries still possible by scanning all project directories

### No gc-cleanup

No automatic deletion or retention-based cleanup:
- Contradicts append-only principle
- Estimated ~11GB for 90 days of heavy use (manageable)
- gc-query store-size reports disk usage
- If cleanup needed later, separate tool can be added

### flock-Based Locking

Using flock instead of advisory locks or directories:
- Portable (Linux, macOS, BSD)
- Automatic cleanup (lock released when process exits)
- Timeout support (prevents indefinite hangs)
- No orphan lock files (kernel manages)

### No Write-Side Truncation

Events stored with complete payloads, no size limits:
- CQRS: write side is fast and dumb
- Large tool outputs (1MB file reads) captured in full
- Projection engine handles summarization on read side
- Storage is cheap, information loss is expensive

### Bash Write Side, Node.js Read Side

Write side:
- Bash + jq: Zero installation friction, available everywhere
- Simple pipeline: stdin → jq → file
- No npm, no dependencies

Read side:
- Node.js: Better JSON processing, modularity, streaming
- Zero npm dependencies: Uses only built-in modules
- Clean separation: projection logic can be complex without affecting write path

## System Boundaries

### Inputs

- Claude Code hook events (JSON on stdin)
- User queries via gc-query commands
- Working directory (for project-id derivation)

### Outputs

- Event files (write path)
- Projection files (read path)
- Query results to stdout (text, JSON, markdown)
- Diagnostic messages to stderr

### External Dependencies

Required:
- bash
- jq
- flock
- Node.js (for projections)

Optional with fallbacks:
- uuidgen (fallback: /proc/sys/kernel/random/uuid, then timestamp+PID)
- date with %3N (fallback: second precision)

### Storage Location

Default: `~/.claude-context/`

Override: `CLAUDE_CONTEXT_PATH` environment variable

## Performance Characteristics

### Write Path

- Target: < 50ms per async hook, < 100ms per sync hook
- Actual: Typically 10-30ms on modern systems
- Bottlenecks: flock contention (mitigated by 5s timeout), disk I/O

### Read Path

- 1,000 events: < 2 seconds
- 50,000 events: < 60 seconds
- Memory: Bounded by projection size, not event count
- Bottleneck: JSON parsing (streaming mitigates)

### Storage Growth

Expected for 90 days of heavy use (100 events/day, 50KB avg payload):
- Events: ~450MB
- Projections: ~45MB
- Total: ~500MB

Actual will vary by:
- Tool output size (large file reads)
- Session frequency
- Project count

## Fault Tolerance

### Write Path Failures

All errors are silent from Claude Code perspective:
- Missing jq → event lost, logged to stderr
- Disk full → event lost, logged to stderr
- Lock timeout → event lost, logged to stderr
- Always exits 0 (never crashes Claude Code)

### Read Path Failures

Projections gracefully handle:
- Corrupt event files → skip with warning
- Missing sequence numbers → log gap, continue
- Missing fields → use defaults, continue
- I/O errors → report error, exit non-zero

### Recovery

- Events are immutable → corruption limited to single file
- Projections are rebuildable → corruption easily fixed
- session.json can be reconstructed from events if lost
- No global state → no single point of failure

## Extensibility

### Adding Event Types

1. Add new event type to capture-event (just pass through)
2. Update projection handlers to interpret new type
3. Rebuild projections to incorporate new events
4. Backward compatible (old projections skip unknown types)

### Adding Projections

1. Create handler with init/handle/finalize interface
2. Register in projection registry
3. No changes to event capture or storage layer

### Custom Projections

Future: Load custom handlers from `~/.claude-context/custom-projections/`

## Security Considerations

### File Permissions

- Event store: 700 (user-only)
- Event files: 600 (user read/write only)
- session.json: 600
- Projections: 600

### Path Traversal

Session IDs sanitized to `[a-zA-Z0-9_-]` (no dots, no slashes):
- Prevents `../` attacks
- Prevents hidden directories

### Sensitive Data

Events contain complete hook payloads:
- May include API keys, secrets, credentials from tool calls
- Stored in user-only readable directory
- No network transmission
- No sharing with external services

Users should:
- Protect ~/.claude-context/ with filesystem permissions
- Not commit event store to version control
- Consider encrypting home directory on shared systems

## Related Documentation

- [Event Types](Event-Types.md) - Event envelope and payload schemas
- [Projections](Projections.md) - Projection types and rebuild logic
- [CLI Reference](CLI-Reference.md) - Command syntax and options
- [Development](Development.md) - Testing and code conventions
