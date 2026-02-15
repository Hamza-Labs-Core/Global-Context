# Task 02: Projection Registry

**Story**: 04-projection-engine
**Estimated Complexity**: S (1-2 hours)
**Status**: Pending

---

## Description

Create the projection registry that maps CLI projection names to their handlers, formatters, version numbers, and output file names. This is the pluggable framework that all five projection types register into. Each registry entry contains the handler interface (`init`, `handle`, `finalize`), three formatters (`json`, `text`, `markdown`), a version number (explicitly set to `1` per review issue M-1), and the output filename.

The registry also exposes a `listProjections()` function for error messages and a `getProjection(name)` function that returns the full entry or null.

---

## Files to Create

| File | Purpose |
|------|---------|
| `/home/meywd/GlobalContext/lib/projection-registry.js` | Projection type registry |

---

## Specification / Implementation Details

```javascript
// Explicit version 1 definition (M-1)
const CURRENT_PROJECTION_VERSION = 1;

const registry = {};

function register(cliName, definition) {
  // definition: { name, description, version, outputFile, handler, formatters }
  if (!definition.version) {
    definition.version = CURRENT_PROJECTION_VERSION;
  }
  registry[cliName] = definition;
}

function getProjection(cliName) {
  return registry[cliName] || null;
}

function listProjections() {
  return Object.entries(registry).map(([key, val]) => ({
    cliName: key,
    name: val.name,
    description: val.description,
    version: val.version
  }));
}
```

Define version 1 as: the initial schema as documented in Story 04 sections 2-6. When the schema changes in the future, version increments to 2, and existing projections with version 1 trigger an automatic full rebuild.

### Review Issues Addressed

- **M-1**: Define projection version 1 explicitly. A `CURRENT_PROJECTION_VERSION` constant is set to `1`. Each registry entry explicitly includes `version: 1`. The incremental rebuild logic (Task 10) compares the stored `_projection_version` against the registry's `version` and triggers a full rebuild on mismatch.

---

## Dependencies

- Task 01: Base Path Resolution and Shared Utilities (`/home/meywd/GlobalContext/tasks/04-projection-engine/01-base-path-resolution-and-shared-utilities.md`)

---

## Acceptance Tests

- `listProjections()` returns an array (empty initially, populated after handler registration).
- `getProjection('timeline')` returns the timeline entry after registration, or null before.
- `getProjection('bogus')` returns null.
- Every registered projection has `version: 1` explicitly.
