# Task 03: Event Replay Engine

**Story**: 04-projection-engine
**Estimated Complexity**: M (3-5 hours)
**Status**: Pending

---

## Description

Build the core replay engine that reads event files from a session directory, validates them, orders them by sequence number, and streams them one at a time through a projection handler. This is the foundation for all projections.

The engine must NOT load all events into memory. It discovers event files, sorts them by numeric sequence, applies range filtering (`from`/`to`), reads each file one at a time, validates the event envelope, and calls `handler.handle(state, event)`.

The engine must also implement duplicate event detection by `tool_use_id` (review issue G-1). When the engine encounters two events with the same `tool_use_id` and same `event_type`, it keeps the first and skips the duplicate, logging a warning to stderr.

---

## Files to Create

| File | Purpose |
|------|---------|
| `/home/meywd/GlobalContext/lib/replay-engine.js` | Event replay engine with streaming and dedup |

---

## Specification / Implementation Details

```javascript
async function replayThrough(sessionId, handler, options = {}) {
  const { from = 1, to = Infinity } = options;
  const eventsDir = getEventsDir(sessionId);

  // 1. Discover event files
  const files = await discoverEventFiles(eventsDir);

  // 2. Sort by numeric sequence
  files.sort((a, b) => a.sequence - b.sequence);

  // 3. Detect gaps and log warnings
  detectSequenceGaps(files);

  // 4. Initialize handler state
  let state = handler.init();

  // 5. Track seen tool_use_ids for duplicate detection (G-1)
  const seenToolUseIds = new Map(); // tool_use_id -> { event_type, sequence }

  // 6. Stream through handler
  for (const file of files) {
    if (file.sequence < from || file.sequence > to) continue;

    const result = safeJsonParse(await fs.readFile(file.path, 'utf-8'), file.path);
    if (!result.ok) {
      warn(`Corrupt JSON at ${file.path}: ${result.error}`);
      continue;
    }

    const event = result.data;

    // Validate required fields
    if (!event.event_type || event.sequence == null) {
      warn(`Missing required fields in ${file.path}, skipping`);
      continue;
    }

    // Duplicate detection by tool_use_id (G-1)
    const toolUseId = event.data?.tool_use_id;
    if (toolUseId) {
      const key = `${toolUseId}:${event.event_type}`;
      if (seenToolUseIds.has(key)) {
        warn(`Duplicate event detected: tool_use_id=${toolUseId}, ` +
             `event_type=${event.event_type} at sequence ${event.sequence} ` +
             `(first seen at sequence ${seenToolUseIds.get(key)}). Skipping.`);
        continue;
      }
      seenToolUseIds.set(key, event.sequence);
    }

    state = handler.handle(state, event);
  }

  // 7. Finalize
  return handler.finalize(state);
}
```

### Event File Discovery

List directory, filter for `*.json` files, extract sequence number from filename (strip `.json`, parse as integer).

### Gap Detection

Iterate sorted sequences; if `seq[i+1] - seq[i] > 1`, log warning.

### Review Issues Addressed

- **G-1**: Duplicate event detection by `tool_use_id`. The replay engine maintains a `Map<string, number>` keyed by `"${tool_use_id}:${event_type}"`. When a duplicate key is encountered, the event is skipped and a warning is logged to stderr. Deduplication at the engine level means all projections benefit automatically without each handler implementing its own logic.

---

## Dependencies

- Task 01: Base Path Resolution and Shared Utilities (`/home/meywd/GlobalContext/tasks/04-projection-engine/01-base-path-resolution-and-shared-utilities.md`)

---

## Acceptance Tests

- Given a directory with files `000001.json` through `000014.json`, the engine calls `handler.handle` exactly 14 times in order.
- With `from: 5, to: 10`, handler is called exactly 6 times (sequences 5-10).
- A corrupt JSON file (e.g., `{invalid`) logs a warning to stderr and does not halt processing. Remaining events are processed.
- A missing sequence (1, 2, 4 -- missing 3) logs a gap warning and continues.
- An event missing `event_type` is skipped with a warning.
- Two events with the same `tool_use_id` and `event_type`: only the first is passed to the handler (G-1).
- An empty directory produces zero `handle` calls and returns `handler.finalize(handler.init())`.
- 1,000 event files are processed in under 2 seconds.
