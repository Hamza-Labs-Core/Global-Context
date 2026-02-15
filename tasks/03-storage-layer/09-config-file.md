# Task 09: Config File (config.json) Management

**Story**: 03-storage-layer
**Status**: Pending
**Estimated Complexity**: S (Small) -- 1-2 hours

---

## Description

Implement config.json creation with defaults and a reader that scripts use to load configuration values. Config is created once during init and never overwritten.

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/config.sh` | Create | Config creation, reading, validation |
| `tests/lib/test_config.sh` | Create | Config tests |

---

## Specification

Function: `gc_config_create()`:

Writes default config.json (via atomic write) if the file does not exist:

```json
{
  "version": "1.0.0",
  "created_at": "<ISO 8601 now>",
  "storage_path": "<$GC_ROOT>",
  "checksum": false
}
```

> **Amendment 4**: `retention_days` removed -- gc-cleanup is deferred, so retention config is meaningless.
> **CQRS note**: `max_event_size_bytes` removed -- the write side stores events as-is without size checks. If size management is needed, it belongs on the read side.

Function: `gc_config_read(field) -> value`:

- Reads a single field from config.json using jq.
- Example: `gc_config_read version` returns `"1.0.0"`.
- If config.json does not exist: print error "GlobalContext store not initialized. Run gc-init." and exit 1.
- If config.json is unparseable: print error "config.json is corrupt" and exit 1.
- If the requested field is missing: return the default value (hardcoded fallbacks).

Function: `gc_config_validate() -> 0 or 1`:

- Checks that config.json exists, is valid JSON, and contains all required fields.
- Returns 0 if valid, 1 if not.

Unknown fields are preserved -- the config reader ignores them, and no operation strips them.

---

## Dependencies

- **Task 01**: `/home/meywd/GlobalContext/tasks/03-storage-layer/01-shared-path-resolver.md` (paths.sh)
- **Task 04**: `/home/meywd/GlobalContext/tasks/03-storage-layer/04-atomic-write-helper.md` (atomic_write.sh)

---

## Acceptance Tests

1. Call `gc_config_create` -- file exists with all default fields.
2. Call again -- file is not overwritten (check `created_at` is unchanged).
3. `gc_config_read version` returns `"1.0.0"`.
4. `gc_config_read storage_path` returns the store root path.
5. Delete config.json, call `gc_config_read` -- error message printed, exit code 1.
6. Write `{invalid json` to config.json, call `gc_config_read` -- error message, exit code 1.
7. Add `"custom_field": "value"` to config.json, call `gc_config_create` -- custom field preserved (file not overwritten).
8. `gc_config_validate` returns 0 for valid config, 1 for corrupt config.
