# Task 03: Source File Distribution

**Story**: 00-installation-setup
**Status**: Pending
**Estimated Complexity**: M (Medium) -- 2-3 hours

---

## Description

Define how source files are organized in the repository, how they are located by `gc-install`, and how they are copied to the target installation directory (`$GC_BASE`). This task also establishes version tracking via a `VERSION` file.

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `VERSION` | Create | Version string file at repository root |
| `src/lib/deploy.sh` | Create | Source file deployment functions |
| `tests/lib/test_deploy.sh` | Create | Deployment tests |

All file paths are relative to `/home/meywd/GlobalContext/`.

---

## Specification / Implementation Details

### Source Layout (Repository)

The GlobalContext repository contains source files under `src/`:

```
/home/meywd/GlobalContext/
  src/
    bin/
      capture-event       # Story 01
      gc-hook             # Story 02
      gc-install-hooks    # Story 02
      gc-init             # Story 03
      gc-query            # Story 05
      gc-doctor           # Story 00 (this plan)
      gc-install          # Story 00 (this plan)
      gc-uninstall        # Story 02 (enhanced in this plan)
      project             # Story 04
    lib/
      paths.sh            # Story 03
      sanitize.sh         # Story 03
      session_dir.sh      # Story 03
      atomic_write.sh     # Story 03
      json_validate.sh    # Story 03
      event_write.sh      # Story 03
      session_meta.sh     # Story 03
      config.sh           # Story 03
      latest_symlink.sh   # Story 03
      projection_store.sh # Story 03
      rejected.sh         # Story 03
      prerequisites.sh    # Story 00 (this plan)
      debug_log.sh        # Story 02
    hook-config.json      # Story 02
  VERSION                 # Semantic version string, e.g. "1.0.0"
```

### Target Layout (Installed)

```
~/.claude-context/         (GC_BASE)
  bin/
    capture-event          755
    gc-hook                755
    gc-install-hooks       755
    gc-init                755
    gc-query               755
    gc-doctor              755
    gc-uninstall           755
    project                755
  lib/
    paths.sh               644
    sanitize.sh            644
    session_dir.sh         644
    ...                    644
    hook-config.json       644
  VERSION                  644
  config.json              600 (created by gc-init, never overwritten)
  events/                  700
  projections/             700
```

### SRC_DIR Detection

The `gc-install` script must locate its own source files. Strategy:

1. If running from the repository (development mode): `SRC_DIR` is relative to the script's location.
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/src"
   ```
2. If the env var `GC_SRC_DIR` is set: use it directly (for CI and custom deployments).
3. Validate: `SRC_DIR` must contain `bin/capture-event` (sanity check).

### Version Tracking

- The `VERSION` file at the repository root contains a single line: the semantic version string (e.g., `1.0.0`).
- During install, this file is copied to `$GC_BASE/VERSION`.
- The upgrade check (Task 06) compares `$SRC_DIR/../VERSION` (available version) with `$GC_BASE/VERSION` (installed version).
- If `$GC_BASE/VERSION` does not exist, the system is treated as uninstalled.

### Deployment Function

```bash
gc_deploy_files() {
  local src_dir="$1"
  local target_dir="$2"
  local dry_run="${3:-false}"

  # Deploy bin/ scripts
  mkdir -p "$target_dir/bin"
  for script in "$src_dir/bin/"*; do
    local name
    name=$(basename "$script")
    if [ "$dry_run" = "true" ]; then
      echo "  Would install: bin/$name"
    else
      cp "$script" "$target_dir/bin/$name"
      chmod 755 "$target_dir/bin/$name"
      echo "  bin/$name    installed"
    fi
  done

  # Deploy lib/ modules
  mkdir -p "$target_dir/lib"
  for module in "$src_dir/lib/"*; do
    local name
    name=$(basename "$module")
    if [ "$dry_run" = "true" ]; then
      echo "  Would install: lib/$name"
    else
      cp "$module" "$target_dir/lib/$name"
      chmod 644 "$target_dir/lib/$name"
    fi
  done
  echo "  lib/ ($(ls -1 "$src_dir/lib/" | wc -l) modules)    installed"

  # Deploy hook-config.json
  if [ -f "$src_dir/hook-config.json" ]; then
    cp "$src_dir/hook-config.json" "$target_dir/lib/hook-config.json"
    chmod 644 "$target_dir/lib/hook-config.json"
  fi

  # Deploy VERSION
  local version_file="$src_dir/../VERSION"
  if [ -f "$version_file" ]; then
    cp "$version_file" "$target_dir/VERSION"
    chmod 644 "$target_dir/VERSION"
  fi
}
```

---

## Dependencies

- **Task 02** (`/home/meywd/GlobalContext/tasks/00-installation/02-gc-install-script.md`) -- gc-install calls deployment functions.

---

## Acceptance Tests

1. Run deployment to a temp directory. Verify all `bin/` scripts exist with permission `755`.
2. Verify all `lib/` modules exist with permission `644`.
3. Verify `VERSION` file is copied correctly.
4. Verify `hook-config.json` is deployed to `lib/`.
5. Run deployment twice. Verify all files are overwritten (upgrade behavior).
6. Verify `SRC_DIR` detection works when running from the repository.
7. Verify `GC_SRC_DIR` env var override works.
8. Verify sanity check fails if `SRC_DIR` does not contain `bin/capture-event`.
