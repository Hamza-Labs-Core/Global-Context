# Task 02: Directory Structure and install.sh

**Story**: 01-event-capture
**Estimated Complexity**: M (Medium)
**Status**: Pending

---

## Description

Implement the `install.sh` script that provisions the full directory structure, validates dependencies, and creates `config.json`. The script must be idempotent -- safe to run multiple times.

The directory structure created:

```
$BASE_DIR/
  events/            # Event store root
  projections/       # Projection output (future stories)
  bin/               # Executable scripts
    capture-event    # The capture script (copied from source)
  config.json        # Configuration with defaults
```

Dependency validation:
- `jq`: required -- abort with install instructions if missing.
- `flock`: required -- warn if missing, continue.
- `uuidgen`: optional -- note fallback if missing.

`config.json` defaults (created only if file does not exist):

```json
{
  "version": "1.0.0",
  "events_dir": "events",
  "created_at": "<ISO 8601 timestamp>"
}
```

Note: `events_dir` is a relative path (relative to `BASE_DIR`), not absolute, to keep the store relocatable.

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `/home/meywd/GlobalContext/src/install.sh` | Create |

---

## Specification/Implementation Details

The `install.sh` script must:

1. Use the base dir resolution pattern from Task 01 at the top.
2. Check for required dependencies (`jq` mandatory, `flock` required with warning, `uuidgen` optional).
3. Create the directory structure (`events/`, `projections/`, `bin/`).
4. Copy `capture-event` to `$BASE_DIR/bin/` with execute permission (`755`).
5. Create `config.json` only if it does not already exist (idempotency).
6. Set root directory permissions to `700`.
7. Be safe to run multiple times without overwriting existing data.

---

## Dependencies

- [Task 01: Base Dir Resolution](/home/meywd/GlobalContext/tasks/01-event-capture/01-base-dir-resolution.md) -- base dir resolution pattern must be defined.

---

## Acceptance Tests

1. Run `install.sh` on a clean system. Verify all directories exist under `$BASE_DIR`.
2. Verify `config.json` contains `version`, `events_dir`, and `created_at`.
3. Verify `capture-event` is in `$BASE_DIR/bin/` and has execute permission (`755`).
4. Run `install.sh` a second time. Verify no existing data is overwritten. Verify `config.json` is preserved.
5. Remove `jq` from `PATH` and run `install.sh`. Verify it aborts with clear instructions.
6. Run with `CLAUDE_CONTEXT_PATH=/tmp/gc-install-test`. Verify directories are created at that path.
7. Verify root directory has permissions `700`.
