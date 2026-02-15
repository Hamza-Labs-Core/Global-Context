# Task 06: Upgrade Logic

**Story**: 00-installation-setup
**Status**: Pending
**Estimated Complexity**: M (Medium) -- 2-3 hours

---

## Description

Implement version detection and upgrade logic within `gc-install`. When a user runs `gc-install` on a system that already has GlobalContext installed, the script must detect the current installed version, compare it to the available version, and decide whether to upgrade. Upgrades overwrite `bin/` and `lib/` files but never touch event data or `config.json`.

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/version.sh` | Create | Version detection and comparison functions |
| `tests/lib/test_version.sh` | Create | Version comparison tests |
| `src/bin/gc-install` | Modify (from Task 02) | Integrate upgrade logic |

All file paths are relative to `/home/meywd/GlobalContext/`.

---

## Specification / Implementation Details

### Version Comparison

```bash
gc_get_installed_version() {
  local gc_base="$1"
  if [ -f "$gc_base/VERSION" ]; then
    cat "$gc_base/VERSION"
  else
    echo "0.0.0"  # Not installed or pre-versioning install
  fi
}

gc_get_available_version() {
  local src_dir="$1"
  local version_file="$src_dir/../VERSION"
  if [ -f "$version_file" ]; then
    cat "$version_file"
  else
    echo "unknown"
  fi
}

gc_version_compare() {
  # Returns: "same", "upgrade", "downgrade", or "unknown"
  local installed="$1"
  local available="$2"

  if [ "$installed" = "$available" ]; then
    echo "same"
    return
  fi

  if [ "$installed" = "0.0.0" ] || [ "$available" = "unknown" ]; then
    echo "upgrade"  # Fresh install or unknown version always proceeds
    return
  fi

  # Numeric comparison of semver components
  local i_major i_minor i_patch a_major a_minor a_patch
  IFS='.' read -r i_major i_minor i_patch <<< "$installed"
  IFS='.' read -r a_major a_minor a_patch <<< "$available"

  if [ "$a_major" -gt "$i_major" ] 2>/dev/null ||
     ([ "$a_major" -eq "$i_major" ] && [ "$a_minor" -gt "$i_minor" ]) 2>/dev/null ||
     ([ "$a_major" -eq "$i_major" ] && [ "$a_minor" -eq "$i_minor" ] && [ "$a_patch" -gt "$i_patch" ]) 2>/dev/null; then
    echo "upgrade"
  else
    echo "downgrade"
  fi
}
```

### Upgrade Behavior Matrix

| Comparison | `--force` | Action |
|---|---|---|
| same | No | Print "Already up to date (vX.Y.Z)", exit 0 |
| same | Yes | Full reinstall (overwrite all files) |
| upgrade | Any | Upgrade: overwrite bin/, lib/, VERSION; preserve config.json, events/, projections/ |
| downgrade | No | Print "WARNING: Installed version (X.Y.Z) is newer than available (A.B.C). Use --force to downgrade.", exit 0 |
| downgrade | Yes | Downgrade: overwrite all files (same as upgrade) |

### What Upgrade Preserves

| Resource | Preserved | Overwritten |
|---|---|---|
| `$GC_BASE/config.json` | Yes | Never |
| `$GC_BASE/events/**` | Yes | Never |
| `$GC_BASE/projections/**` | Yes | Never |
| `$GC_BASE/logs/**` | Yes | Never |
| `$GC_BASE/bin/*` | No | Always (scripts may have changed) |
| `$GC_BASE/lib/*` | No | Always (libraries may have changed) |
| `$GC_BASE/VERSION` | No | Updated to new version |
| `~/.claude/settings.json` hooks | Updated | `gc-install-hooks install` handles this idempotently |

### Post-Upgrade Hook Re-registration

After upgrading files, `gc-install` always re-runs `gc-install-hooks install`. This ensures hooks reflect any changes to the hook configuration (new events, changed timeouts, updated matchers). Since `gc-install-hooks` is idempotent, this is safe.

---

## Dependencies

- **Task 02** (`/home/meywd/GlobalContext/tasks/00-installation/02-gc-install-script.md`) -- gc-install exists.
- **Task 03** (`/home/meywd/GlobalContext/tasks/00-installation/03-source-file-distribution.md`) -- VERSION file and deployment functions.

---

## Acceptance Tests

1. Fresh install (no `$GC_BASE/VERSION`): proceeds as new install.
2. Same version installed: prints "Already up to date", exits 0.
3. Same version with `--force`: overwrites all files.
4. Older version installed: upgrades files, preserves data.
5. Newer version installed (downgrade attempt): prints warning, exits 0.
6. Newer version with `--force`: downgrades files.
7. After upgrade: verify `config.json` has not been modified (check `created_at` timestamp).
8. After upgrade: verify event data files are untouched (check file modification times).
9. After upgrade: verify `VERSION` file contains the new version string.
10. After upgrade: verify hooks are re-registered (check `settings.json` for current config).
