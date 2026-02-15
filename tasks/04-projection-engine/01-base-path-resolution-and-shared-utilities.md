# Task 01: Base Path Resolution and Shared Utilities

**Story**: 04-projection-engine
**Estimated Complexity**: S (1-2 hours)
**Status**: Pending

---

## Description

Create the shared utility module that all other modules depend on. This module provides the base path for the GlobalContext data directory (respecting the `CLAUDE_CONTEXT_PATH` environment variable per review issue M-4), common path builders for events and projections directories, and small helpers used across projection handlers (timestamp formatting, string truncation, safe JSON parsing).

---

## Files to Create

| File | Purpose |
|------|---------|
| `/home/meywd/GlobalContext/lib/paths.js` | Base path resolution, directory helpers |
| `/home/meywd/GlobalContext/lib/utils.js` | String truncation, safe JSON parse, atomic file write, duration formatting |

---

## Specification / Implementation Details

### lib/paths.js

```javascript
// lib/paths.js
function getBasePath() {
  return process.env.CLAUDE_CONTEXT_PATH || path.join(os.homedir(), '.claude-context');
}

function getEventsDir(sessionId) {
  return path.join(getBasePath(), 'events', sessionId);
}

function getProjectionsDir(sessionId) {
  return path.join(getBasePath(), 'projections', sessionId);
}

function getLatestSymlink() {
  return path.join(getBasePath(), 'projections', 'latest');
}
```

**Amendment 3 Impact**: Path functions gain a `projectId` parameter. `getEventsDir(projectId, sessionId)` returns `{base}/events/{projectId}/{sessionId}`. `getProjectionsDir(projectId, sessionId)` returns `{base}/projections/{projectId}/{sessionId}`. Per-project `latest` symlink at `projections/{projectId}/latest`.

### lib/utils.js

```javascript
// lib/utils.js
function truncate(str, maxLen, suffix = '...') { ... }
function safeJsonParse(content, filePath) { ... }  // returns { ok, data, error }
async function atomicWrite(filePath, data) { ... } // temp file + rename pattern
function formatDuration(seconds) { ... }           // "1h 30m", "5m", "0m"
```

### Review Issues Addressed

- **M-4**: Support `CLAUDE_CONTEXT_PATH` env var. The `getBasePath()` function checks `process.env.CLAUDE_CONTEXT_PATH` first, falling back to `~/.claude-context/`. All path construction flows through this function.

---

## Dependencies

None (first task).

---

## Acceptance Tests

- `CLAUDE_CONTEXT_PATH=/tmp/test-gc node -e "require('./lib/paths').getBasePath()"` returns `/tmp/test-gc`.
- Without the env var, returns `~/.claude-context/`.
- `truncate('hello world', 5)` returns `'hello...'`.
- `formatDuration(5400)` returns `'1h 30m'`.
- `atomicWrite` creates a temp file and renames; if interrupted mid-write, the original file remains.
