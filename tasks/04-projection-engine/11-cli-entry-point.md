# Task 11: CLI Entry Point (`project` Script)

**Story**: 04-projection-engine
**Estimated Complexity**: M (3-5 hours)
**Status**: Pending

---

## Description

Create the `project` CLI entry point script that parses arguments, resolves the session ID (including `latest` symlink), validates inputs, and orchestrates the replay engine, projection handlers, and output formatters. This is the top-level integration that wires all components together.

---

## Files to Create

| File | Purpose |
|------|---------|
| `/home/meywd/GlobalContext/bin/project` | Executable Node.js script with shebang line (CLI entry point) |

---

## Specification / Implementation Details

### Entry Point Structure

```javascript
#!/usr/bin/env node
'use strict';

const { parseArgs } = require('./lib/cli-parser');  // or inline parsing
const { getProjection, listProjections } = require('./lib/projection-registry');
const { buildProjection } = require('./lib/replay-engine');
const { outputProjection } = require('./lib/formatters');
const { getBasePath, getEventsDir, getLatestSymlink } = require('./lib/paths');
```

### Argument Parsing

No external dependencies -- use simple argv parsing:

```
project <projection-type> <session-id> [options]

Options:
  --from <n>        Start sequence (default: 1)
  --to <n>          End sequence (default: last)
  --rebuild         Force full rebuild
  --format <fmt>    json | text | markdown (default: json)
  --output <path>   Output path, use - for stdout only
  --quiet           Suppress stderr messages
```

**Amendment 3 Impact**: The CLI accepts `--project` or infers project-id from the event envelope's `project_id` field.

### Execution Flow

1. Parse args. If none provided, print usage and exit 1.
2. Validate `projection-type` against registry. If unknown, print error listing available types and exit 1.
3. Resolve `session-id`. If `latest`, read symlink at `~/.claude-context/projections/latest`. If symlink missing, exit 1 with message.
4. Validate event directory exists. If not, exit 1 with message.
5. Call `buildProjection(sessionId, projectionDef, options)`.
6. Call `outputProjection(projection, projectionDef, options)`.
7. Exit 0 on success, 2 on replay error.

### Error Output Format

- Error: `[project] ERROR: {message}` to stderr.
- Warning: `[project] WARNING: {message}` to stderr.

---

## Dependencies

- Task 01: Base Path Resolution and Shared Utilities (`/home/meywd/GlobalContext/tasks/04-projection-engine/01-base-path-resolution-and-shared-utilities.md`)
- Task 02: Projection Registry (`/home/meywd/GlobalContext/tasks/04-projection-engine/02-projection-registry.md`)
- Task 03: Event Replay Engine (`/home/meywd/GlobalContext/tasks/04-projection-engine/03-event-replay-engine.md`)
- Task 04: Files Touched Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/04-files-touched-projection-handler.md`)
- Task 05: Timeline Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/05-timeline-projection-handler.md`)
- Task 06: Decisions Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/06-decisions-projection-handler.md`)
- Task 07: Summary Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/07-summary-projection-handler.md`)
- Task 08: Context Snapshot Projection Handler (`/home/meywd/GlobalContext/tasks/04-projection-engine/08-context-snapshot-projection-handler.md`)
- Task 09: Output Format System and Shared Formatters (`/home/meywd/GlobalContext/tasks/04-projection-engine/09-output-format-system-and-shared-formatters.md`)
- Task 10: Incremental Rebuild Logic (`/home/meywd/GlobalContext/tasks/04-projection-engine/10-incremental-rebuild-logic.md`)

---

## Acceptance Tests

- `project timeline <session-id>` produces a timeline and writes it to the correct path.
- `project files <session-id>` produces a files-touched projection.
- `project decisions <session-id>` produces a decisions projection.
- `project context <session-id>` produces a context snapshot.
- `project summary <session-id>` produces a summary.
- `project timeline latest` resolves the symlink.
- `project timeline <session-id> --from 10 --to 50` limits the event range.
- `project timeline <session-id> --rebuild` forces a full rebuild.
- `project timeline <session-id> --format text` outputs plain text.
- `project timeline <session-id> --format markdown` outputs markdown.
- `project timeline <session-id> --output -` writes only to stdout.
- `project` with no arguments prints usage help and exits 1.
- `project bogus <session-id>` prints error about unknown type and exits 1.
- `project timeline nonexistent-session` prints error and exits 1.
- Exit code 0 on success, 1 on bad args, 2 on replay errors.
