# Task 08: Shared Library Bundling

**Story**: 06-plugin-packaging
**Estimated Complexity**: L (Large)
**Dependencies**: [Task 01 - Plugin Manifest and Directory Scaffold](/home/meywd/GlobalContext/tasks/06-plugin-packaging/01-plugin-manifest-scaffold.md) (lib directory must exist). Source files from Stories 01-05 must be implementation-ready.

---

## Description

Bundle all shared libraries from `src/lib/` into the plugin's `lib/` directory. This includes both Bash libraries (path resolution, sanitization, atomic writes, UUID generation, timestamps, debug logging) and Node.js modules (projection engine). All library paths must use `${CLAUDE_PLUGIN_ROOT}/lib/` for code references and `~/.claude-context/` (via `$GC_ROOT`) for data references.

The key change from the standalone installation model is that libraries are no longer deployed to `~/.claude-context/lib/`. They live inside the plugin directory and are sourced from there. This means the plugin directory is self-contained for code -- only data lives outside the plugin.

---

## Files to Create

### Bash Libraries

| File | Source | Purpose |
|------|--------|---------|
| `plugin/lib/paths.sh` | `src/lib/paths.sh` | Path resolution (GC_ROOT, GC_EVENTS_DIR, etc.) |
| `plugin/lib/sanitize.sh` | `src/lib/sanitize.sh` (from Story 03) | Session ID and project ID sanitization |
| `plugin/lib/atomic_write.sh` | `src/lib/atomic_write.sh` (from Story 03) | Atomic file write with temp+rename |
| `plugin/lib/uuid.sh` | Extracted from `src/capture-event` | UUID v4 generation with fallback chain |
| `plugin/lib/timestamp.sh` | Extracted from `src/capture-event` | ISO 8601 timestamp generation |
| `plugin/lib/debug_log.sh` | `src/lib/debug_log.sh` (from Story 02) | Debug logging with rotation |
| `plugin/lib/session_read.sh` | `src/lib/session_read.sh` (from Story 05) | Per-session session.json read model |
| `plugin/lib/projection_check.sh` | `src/lib/projection-check.sh` (from Story 05) | Projection staleness check |
| `plugin/lib/session_resolve.sh` | `src/lib/session-resolve.sh` (from Story 05) | Session ID resolution helpers |
| `plugin/lib/context_loader.sh` | `src/lib/context-loader.sh` (from Story 05) | Context projection loader |
| `plugin/lib/format_context.sh` | `src/lib/format-context.sh` (from Story 05) | Output formatters (markdown, text, compact, JSON) |
| `plugin/lib/session_chain.sh` | `src/lib/session-chain.sh` (from Story 05) | Cross-session chain resolution |

### Node.js Modules

| File | Source | Purpose |
|------|--------|---------|
| `plugin/lib/projection_engine.js` | `src/lib/projection_engine.js` (from Story 04) | Node.js projection engine |
| `plugin/lib/projections/*.js` | `src/lib/projections/*.js` (from Story 04) | Individual projection handlers |

### CLI Scripts

| File | Source | Purpose |
|------|--------|---------|
| `plugin/scripts/gc-query` | `src/gc-query` (from Story 05) | Query CLI entry point |
| `plugin/scripts/project` | `src/project` (from Story 04) | Projection engine CLI |

---

## Specification

All Bash libraries must be adapted so they resolve their own location via:

```bash
# At the top of each library file
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

And other libraries are sourced relative to `$_LIB_DIR`:

```bash
source "$_LIB_DIR/paths.sh"
source "$_LIB_DIR/sanitize.sh"
```

`paths.sh` remains the canonical path resolver. It sets `$GC_ROOT` from `$CLAUDE_CONTEXT_PATH` or the default. All data paths derive from `$GC_ROOT`. Code paths are relative to `$_LIB_DIR` (which is inside the plugin).

**Important**: the `gc-query` script from Story 05 is also bundled as `plugin/scripts/gc-query`. It sources libraries from `$PLUGIN_ROOT/lib/` instead of `$GC_ROOT/lib/`.

---

## Acceptance Tests

1. All library files exist in `plugin/lib/`.
2. Each Bash library uses `$_LIB_DIR` for self-location, not hardcoded paths.
3. `source plugin/lib/paths.sh` correctly resolves `$GC_ROOT` from `$CLAUDE_CONTEXT_PATH` or default.
4. `plugin/scripts/capture-event` can source all required libraries from `$PLUGIN_ROOT/lib/`.
5. `plugin/scripts/gc-query` can source all required libraries from `$PLUGIN_ROOT/lib/`.
6. No library file contains hardcoded references to `~/.claude-context/bin/` or `~/.claude-context/lib/`.
7. Node.js projection engine runs correctly when invoked from `plugin/lib/projection_engine.js`.
8. Running `echo '{"session_id":"lib-test"}' | plugin/scripts/gc-hook SessionStarted` works with all libraries sourced from the plugin.
