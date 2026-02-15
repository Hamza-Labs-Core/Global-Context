#!/usr/bin/env bash
# deploy.sh -- Source file deployment functions for GlobalContext.
# Copies bin/ scripts, lib/ modules, hook-config.json, and VERSION
# from the source directory to the target installation directory.
set -euo pipefail

# ---------------------------------------------------------------------------
# gc_resolve_src_dir() -> prints source directory path
#   Determines where the source files are located.
#   1. If GC_SRC_DIR env var is set, use it.
#   2. Otherwise, resolve relative to the calling script's location.
#   Validates that the directory contains expected files.
# ---------------------------------------------------------------------------
gc_resolve_src_dir() {
  local src_dir=""

  if [ -n "${GC_SRC_DIR:-}" ]; then
    src_dir="$GC_SRC_DIR"
  else
    # Try to resolve from the script location (gc-install is in src/bin/)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"
    src_dir="$(cd "$script_dir/.." && pwd)"
  fi

  # Sanity check: src_dir should contain bin/ and lib/
  if [ ! -d "$src_dir/bin" ] || [ ! -d "$src_dir/lib" ]; then
    echo "ERROR: Source directory $src_dir does not contain bin/ and lib/ directories." >&2
    return 1
  fi

  printf '%s' "$src_dir"
}

# ---------------------------------------------------------------------------
# gc_deploy_files(src_dir, target_dir, dry_run)
#   Copies all source files from src_dir to target_dir.
#   bin/ scripts get 755, lib/ files get 644, VERSION gets 644.
# ---------------------------------------------------------------------------
gc_deploy_files() {
  local src_dir="$1"
  local target_dir="$2"
  local dry_run="${3:-false}"

  local bin_count=0
  local lib_count=0

  # Deploy bin/ scripts
  mkdir -p "$target_dir/bin"
  for script in "$src_dir/bin/"*; do
    [ -f "$script" ] || continue
    local name
    name=$(basename "$script")
    if [ "$dry_run" = "true" ]; then
      echo "  Would install: bin/$name"
    else
      cp "$script" "$target_dir/bin/$name"
      chmod 755 "$target_dir/bin/$name"
      echo "  bin/$name    installed"
    fi
    bin_count=$((bin_count + 1))
  done

  # Deploy lib/ modules
  mkdir -p "$target_dir/lib"
  for module in "$src_dir/lib/"*; do
    [ -f "$module" ] || continue
    local name
    name=$(basename "$module")
    if [ "$dry_run" = "true" ]; then
      echo "  Would install: lib/$name"
    else
      cp "$module" "$target_dir/lib/$name"
      chmod 644 "$target_dir/lib/$name"
    fi
    lib_count=$((lib_count + 1))
  done
  if [ "$dry_run" = "true" ]; then
    echo "  Would install: lib/ ($lib_count modules)"
  else
    echo "  lib/ ($lib_count modules)    installed"
  fi

  # Deploy top-level scripts (capture-event, gc-hook, gc-install-hooks)
  for script in capture-event gc-hook gc-install-hooks; do
    if [ -f "$src_dir/$script" ]; then
      if [ "$dry_run" = "true" ]; then
        echo "  Would install: bin/$script"
      else
        cp "$src_dir/$script" "$target_dir/bin/$script"
        chmod 755 "$target_dir/bin/$script"
        echo "  bin/$script    installed"
      fi
    fi
  done

  # Deploy hook-config.json if it exists
  if [ -f "$src_dir/hook-config.json" ]; then
    if [ "$dry_run" = "true" ]; then
      echo "  Would install: lib/hook-config.json"
    else
      cp "$src_dir/hook-config.json" "$target_dir/lib/hook-config.json"
      chmod 644 "$target_dir/lib/hook-config.json"
      echo "  lib/hook-config.json    installed"
    fi
  fi

  # Deploy VERSION
  local version_file="$src_dir/../VERSION"
  if [ -f "$version_file" ]; then
    if [ "$dry_run" = "true" ]; then
      echo "  Would install: VERSION"
    else
      cp "$version_file" "$target_dir/VERSION"
      chmod 644 "$target_dir/VERSION"
      echo "  VERSION    installed"
    fi
  fi
}
