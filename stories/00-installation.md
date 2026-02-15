# Story 00: Installation & Setup

## Overview

This story covers the end-to-end installation, upgrade, uninstall, and first-run experience for GlobalContext. It provides a single `gc-install` entry point that orchestrates the full setup process: checking prerequisites, placing source files, delegating to `gc-init` (Story 03) for store initialization, delegating to `gc-install-hooks` (Story 02) for hook registration, and verifying the result with `gc-query doctor`.

The goal is a one-command install that takes a user from zero to fully operational GlobalContext in under 30 seconds, with clear feedback at every step.

### Relationship to Other Stories

- **Delegates to Story 03** (`gc-init`): Directory structure creation, config.json, copying scripts to `bin/`.
- **Delegates to Story 02** (`gc-install-hooks`): Hook registration in `~/.claude/settings.json`.
- **Does NOT duplicate**: Any functionality already specified in Stories 01-05. This story is the orchestrator and covers only what falls between the cracks.

### What This Story Covers (and What It Does Not)

| Concern | Covered Here | Covered Elsewhere |
|---------|:---:|:---:|
| Prerequisites check (jq, bash 4+, node 18+) | yes | -- |
| `gc-install` orchestration command | yes | -- |
| Clone/copy source to install location | yes | -- |
| `gc-init` (create ~/.claude-context/ structure) | -- | Story 03 |
| `gc-install-hooks` (register hooks in settings.json) | -- | Story 02 |
| `gc-query doctor` verification | calls it | Story 05 |
| Upgrade path (re-run gc-install) | yes | -- |
| Uninstall path (`gc-uninstall`) | yes | -- |
| First-run experience (post-install output) | yes | -- |

---

## Scope

### In Scope

- `gc-install` Bash script (the single entry point)
- Prerequisites validation with version checks
- Source placement to a known installation directory
- Orchestration of `gc-init` and `gc-install-hooks`
- Post-install verification via `gc-query doctor`
- `gc-uninstall` script for clean removal
- Upgrade-safe re-installation
- First-run user experience (summary output)

### Out of Scope (Non-Goals)

- Package manager integration (apt, brew, npm) -- future work
- Auto-update mechanism
- GUI or interactive prompts -- all operations are non-interactive
- Windows support
- The `gc-init` implementation itself (Story 03)
- The `gc-install-hooks` implementation itself (Story 02)
- The `gc-query doctor` implementation itself (Story 05)

---

## Requirements

### 1. Prerequisites Check

The installation must verify that all required tools are present and meet minimum version requirements before proceeding.

#### Required Dependencies

| Dependency | Minimum Version | Purpose | Detection |
|------------|----------------|---------|-----------|
| `bash` | 4.0+ | Script interpreter, associative arrays, `${var,,}` | `bash --version` |
| `jq` | 1.5+ | JSON parsing and construction (write side) | `jq --version` |
| `node` | 18.0+ | Projection engine, gc-query (read side) | `node --version` |

#### Optional Dependencies (with fallbacks)

| Dependency | Purpose | Fallback |
|------------|---------|----------|
| `uuidgen` | UUID v4 generation | `/proc/sys/kernel/random/uuid`, then timestamp+PID composite |
| `flock` | File-based exclusive locking | Write without lock (best-effort, documented risk) |
| `sha256sum` | Project ID derivation | `shasum -a 256` (macOS) |

#### Version Extraction

```bash
# bash version
bash_version=$(bash -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"')

# jq version (outputs "jq-1.6" or similar)
jq_version=$(jq --version 2>&1 | sed 's/jq-//')

# node version (outputs "v20.11.0" or similar)
node_version=$(node --version 2>&1 | sed 's/^v//')
```

#### Version Comparison

Version comparison must handle semver-style versions (major.minor.patch). Only the major version is strictly enforced; minor and patch are informational.

#### Output Format

```
[gc-install] Checking prerequisites...
[gc-install]   bash ............. 5.2 (>= 4.0 required)    OK
[gc-install]   jq ............... 1.6 (>= 1.5 required)    OK
[gc-install]   node ............. 20.11.0 (>= 18.0 required) OK
[gc-install]   flock ............ found                     OK
[gc-install]   uuidgen .......... found                     OK
[gc-install]   sha256sum ........ found                     OK
```

Or on failure:

```
[gc-install] Checking prerequisites...
[gc-install]   bash ............. 5.2 (>= 4.0 required)    OK
[gc-install]   jq ............... NOT FOUND                 FAIL
[gc-install]     Install jq:
[gc-install]       Ubuntu/Debian: sudo apt install jq
[gc-install]       macOS:        brew install jq
[gc-install]       Fedora:       sudo dnf install jq
[gc-install]   node ............. 16.20.0 (>= 18.0 required) FAIL
[gc-install]     Upgrade Node.js to version 18 or later:
[gc-install]       https://nodejs.org/
[gc-install]
[gc-install] Installation aborted. Fix the above issues and re-run gc-install.
```

#### Acceptance Criteria

- [ ] `gc-install` checks for `bash` >= 4.0, `jq` >= 1.5, and `node` >= 18.0 before proceeding.
- [ ] Missing required dependencies abort installation with clear, platform-specific install instructions.
- [ ] Version checks correctly parse and compare major version numbers.
- [ ] Optional dependencies (`flock`, `uuidgen`, `sha256sum`/`shasum`) are checked and their status is reported, but missing ones do not abort installation.
- [ ] If `sha256sum` is missing but `shasum` is present (macOS), the check passes with a note.
- [ ] All prerequisite output uses the `[gc-install]` prefix for consistency.
- [ ] The check runs in under 2 seconds on a typical system.

---

### 2. Source Placement

The `gc-install` command places GlobalContext source files into a known installation directory. This is the canonical location from which `gc-init` copies scripts into `~/.claude-context/bin/`.

#### Installation Directory

The source is placed at `~/.local/share/globalcontext/`. This follows the XDG Base Directory Specification for user-installed application data.

The location can be overridden with the `GLOBALCONTEXT_HOME` environment variable.

```bash
GC_INSTALL_DIR="${GLOBALCONTEXT_HOME:-$HOME/.local/share/globalcontext}"
```

#### Source Layout

```
~/.local/share/globalcontext/
├── bin/
│   ├── capture-event          # Write-side capture script (Bash)
│   ├── gc-hook                # Hook wrapper (Bash)
│   ├── gc-install-hooks       # Hook lifecycle manager (Bash)
│   ├── gc-init                # Store initializer (Bash)
│   ├── gc-query               # Query interface (Node.js)
│   ├── gc-install             # This installer (Bash)
│   ├── gc-uninstall           # Uninstaller (Bash)
│   └── project                # Projection engine (Node.js)
├── lib/
│   ├── paths.sh               # Shared path helpers (Bash)
│   ├── paths.js               # Shared path helpers (Node.js)
│   └── projections/           # Projection builder modules (Node.js)
│       ├── timeline.js
│       ├── files-touched.js
│       ├── decisions.js
│       └── context.js
└── VERSION                    # Installed version string
```

#### Placement Strategy

- If the source is from a git clone, `gc-install` copies files from the repository working directory.
- If the source is from a tarball or direct download, `gc-install` copies files from the current directory.
- The `gc-install` script detects whether it is running from within the GlobalContext source tree by checking for marker files (`VERSION`, `bin/capture-event`).

#### VERSION File

```
1.0.0
```

A single line containing the semver version string. Used by upgrade logic to determine whether an update is needed.

#### Acceptance Criteria

- [ ] `gc-install` copies source files to `~/.local/share/globalcontext/` (or `$GLOBALCONTEXT_HOME`).
- [ ] The `bin/`, `lib/`, and `VERSION` file are present after installation.
- [ ] All scripts in `bin/` are executable (`chmod 755`).
- [ ] The `GLOBALCONTEXT_HOME` environment variable overrides the default install directory.
- [ ] If the install directory already exists, files are updated (overwritten) without deleting other files that may be present.
- [ ] The `VERSION` file contains the current version string.
- [ ] `gc-install` detects that it is running from a valid source tree before attempting to copy.
- [ ] If `gc-install` is run from outside a valid source tree, it aborts with a clear error message.

---

### 3. gc-install Orchestration

The `gc-install` command is the single entry point for installation. It orchestrates the full setup by calling other components in sequence.

#### Installation Flow

```
gc-install
  1. Print banner with version
  2. Check prerequisites (Requirement 1)
     - If any required dependency fails: abort with instructions
  3. Place source files (Requirement 2)
     - Copy source to ~/.local/share/globalcontext/
  4. Run gc-init (Story 03)
     - Creates ~/.claude-context/ directory structure
     - Creates config.json
     - Copies scripts from source to ~/.claude-context/bin/
  5. Register hooks (Story 02)
     - Run gc-install-hooks install
     - Registers all 10 hooks in ~/.claude/settings.json
  6. Verify installation (Requirement 6)
     - Run gc-query doctor
     - Report pass/fail
  7. Print first-run summary (Requirement 7)
```

#### Banner

```
[gc-install] GlobalContext v1.0.0
[gc-install] Event-sourced context store for Claude Code
[gc-install] ────────────────────────────────────────────
```

#### Error Handling

Each step must complete successfully before proceeding to the next. If any step fails:

1. Print a clear error message identifying the failed step.
2. Print remediation instructions.
3. Exit with code 1.
4. Do not roll back completed steps (partial installation is safe to re-run).

#### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_CONTEXT_PATH` | `~/.claude-context` | Override the store location (passed through to gc-init) |
| `GLOBALCONTEXT_HOME` | `~/.local/share/globalcontext` | Override the source installation directory |

#### Acceptance Criteria

- [ ] `gc-install` runs all steps in order: prerequisites, source placement, gc-init, gc-install-hooks, verification.
- [ ] If any step fails, subsequent steps are skipped and a clear error is shown.
- [ ] The exit code is 0 on success and 1 on failure.
- [ ] `CLAUDE_CONTEXT_PATH` is respected and passed through to `gc-init`.
- [ ] `GLOBALCONTEXT_HOME` is respected for source placement.
- [ ] The banner displays the current version from the `VERSION` file.
- [ ] The full installation completes in under 10 seconds on a typical system (excluding network, since there is none).
- [ ] `gc-install` can be run from any working directory (it determines paths from the script location or source tree).

---

### 4. Upgrade Path

Running `gc-install` on a system with an existing GlobalContext installation updates scripts and configuration without losing event data.

#### Upgrade Detection

```bash
installed_version=""
if [ -f "$GC_INSTALL_DIR/VERSION" ]; then
  installed_version=$(cat "$GC_INSTALL_DIR/VERSION")
fi

new_version=$(cat "$SOURCE_DIR/VERSION")

if [ "$installed_version" = "$new_version" ]; then
  echo "[gc-install] GlobalContext $new_version is already installed."
  echo "[gc-install] Re-running to verify configuration..."
fi
```

#### What Gets Updated

| Component | Action on Upgrade |
|-----------|------------------|
| Source files (`~/.local/share/globalcontext/`) | Overwritten with new versions |
| Scripts in `~/.claude-context/bin/` | Overwritten by `gc-init` (Story 03 specifies this behavior) |
| `~/.claude-context/config.json` | Preserved (never overwritten -- Story 03) |
| `~/.claude-context/events/` | Preserved (never touched by install) |
| `~/.claude-context/projections/` | Preserved (never touched by install) |
| Hook entries in `~/.claude/settings.json` | Updated in-place by `gc-install-hooks` (Story 02) |
| `~/.claude/settings.json` non-hook settings | Preserved (Story 02 guarantees this) |

#### Version Upgrade Output

```
[gc-install] Detected existing installation: v1.0.0
[gc-install] Upgrading to v1.1.0...
[gc-install]
[gc-install] Updated:
[gc-install]   - Source files at ~/.local/share/globalcontext/
[gc-install]   - Scripts at ~/.claude-context/bin/
[gc-install]   - Hook configuration in ~/.claude/settings.json
[gc-install]
[gc-install] Preserved:
[gc-install]   - Event store at ~/.claude-context/events/ (untouched)
[gc-install]   - Projections at ~/.claude-context/projections/ (untouched)
[gc-install]   - Configuration at ~/.claude-context/config.json (untouched)
```

#### Acceptance Criteria

- [ ] Running `gc-install` over an existing installation updates scripts without losing any event or projection data.
- [ ] `config.json` is never overwritten during upgrade.
- [ ] The `events/` and `projections/` directories are never modified during upgrade.
- [ ] Scripts in `~/.claude-context/bin/` are replaced with the latest versions.
- [ ] Hook configuration in `~/.claude/settings.json` is updated in-place (no duplicates).
- [ ] The VERSION file is updated to the new version after upgrade.
- [ ] Running `gc-install` when the same version is already installed still verifies configuration and reports success.
- [ ] The upgrade output clearly distinguishes between what was updated and what was preserved.

---

### 5. Uninstall Path (gc-uninstall)

The `gc-uninstall` command removes GlobalContext hooks and optionally deletes the event store and source files.

#### Uninstall Flow

```
gc-uninstall [--purge]
  1. Remove hooks from ~/.claude/settings.json
     - Delegates to gc-install-hooks uninstall
  2. Remove scripts from ~/.claude-context/bin/
     - Only removes GlobalContext scripts (capture-event, gc-hook, gc-install-hooks, gc-query, project, gc-init)
  3. If --purge flag:
     a. Prompt for confirmation (unless --yes is also passed)
     b. Remove ~/.claude-context/ entirely (events, projections, config, everything)
     c. Remove ~/.local/share/globalcontext/ (source files)
  4. If no --purge flag:
     a. Preserve ~/.claude-context/events/ (user's data)
     b. Preserve ~/.claude-context/projections/
     c. Preserve ~/.claude-context/config.json
     d. Remove source files at ~/.local/share/globalcontext/
  5. Print summary of what was removed and what was preserved
```

#### Confirmation Prompt (--purge only)

```
[gc-uninstall] WARNING: --purge will permanently delete ALL captured events.
[gc-uninstall] Event store location: ~/.claude-context/
[gc-uninstall]
[gc-uninstall] This action cannot be undone.
[gc-uninstall] To confirm, pass --yes: gc-uninstall --purge --yes
```

The `--purge` flag requires `--yes` for non-interactive confirmation. There is no interactive prompt (consistent with the design principle of no interactive prompts).

#### Output

```
[gc-uninstall] Removing GlobalContext...
[gc-uninstall]   Hooks removed from ~/.claude/settings.json
[gc-uninstall]   Scripts removed from ~/.claude-context/bin/
[gc-uninstall]   Source removed from ~/.local/share/globalcontext/
[gc-uninstall]
[gc-uninstall] Preserved (use --purge --yes to delete):
[gc-uninstall]   - ~/.claude-context/events/     (your captured events)
[gc-uninstall]   - ~/.claude-context/projections/ (cached projections)
[gc-uninstall]   - ~/.claude-context/config.json  (configuration)
[gc-uninstall]
[gc-uninstall] GlobalContext has been uninstalled.
```

#### Acceptance Criteria

- [ ] `gc-uninstall` (without flags) removes hooks, scripts, and source files but preserves the event store, projections, and config.
- [ ] `gc-uninstall --purge --yes` removes everything, including the event store.
- [ ] `gc-uninstall --purge` (without `--yes`) prints a warning and exits without deleting anything.
- [ ] Hook removal delegates to `gc-install-hooks uninstall` (Story 02), preserving user hooks and non-hook settings.
- [ ] After uninstall (without purge), re-running `gc-install` restores full functionality with existing event data intact.
- [ ] After uninstall with `--purge --yes`, re-running `gc-install` creates a fresh installation.
- [ ] The uninstall output clearly lists what was removed and what was preserved.
- [ ] `gc-uninstall` exits 0 on success and 1 on failure.
- [ ] If GlobalContext is not installed (no files found), `gc-uninstall` prints a message and exits 0.

---

### 6. Post-Install Verification (gc-query doctor)

After installation, `gc-install` runs `gc-query doctor` to verify the installation is functional. This requirement defines what `gc-install` expects from the doctor command, not the doctor command itself (which is Story 05).

#### Expected Doctor Checks

| Check | What It Verifies |
|-------|------------------|
| Store exists | `~/.claude-context/` directory exists and is writable |
| Config valid | `config.json` exists and is valid JSON |
| Scripts present | All scripts in `bin/` exist and are executable |
| Hooks registered | All 10 hooks are present in `~/.claude/settings.json` |
| Write test | Can write and delete a test event file |
| Dependencies | jq, bash, node are available with correct versions |
| Permissions | Directory and file permissions are correct (700/600) |
| Disk space | At least 10MB of free space available |

#### Integration with gc-install

```bash
echo "[gc-install] Verifying installation..."
if ~/.claude-context/bin/gc-query doctor --quiet; then
  echo "[gc-install] Verification passed."
else
  echo "[gc-install] WARN: Some verification checks failed."
  echo "[gc-install]   Run 'gc-query doctor' for details."
fi
```

The `--quiet` flag causes `gc-query doctor` to output only pass/fail status. Without it, it outputs detailed results for each check.

Verification failure does NOT cause `gc-install` to exit with code 1. The installation itself succeeded; verification issues are warnings. The user is directed to `gc-query doctor` for details.

#### Acceptance Criteria

- [ ] `gc-install` runs `gc-query doctor` after all installation steps complete.
- [ ] Verification failure produces a warning, not an installation failure.
- [ ] The user is directed to run `gc-query doctor` for detailed results.
- [ ] `gc-install` uses `--quiet` flag to keep output concise during installation.

---

### 7. First-Run Experience

After successful installation, `gc-install` prints a summary that gives the user confidence the system is working and tells them what happens next.

#### Success Output

```
[gc-install] ────────────────────────────────────────────
[gc-install] GlobalContext v1.0.0 installed successfully!
[gc-install] ────────────────────────────────────────────
[gc-install]
[gc-install] What was set up:
[gc-install]   Source files:  ~/.local/share/globalcontext/
[gc-install]   Event store:   ~/.claude-context/
[gc-install]   Scripts:       ~/.claude-context/bin/
[gc-install]   Hooks:         ~/.claude/settings.json (10 hooks registered)
[gc-install]
[gc-install] What happens next:
[gc-install]   - Start a Claude Code session and events will be captured automatically
[gc-install]   - Use 'gc-query last' to see the most recent session context
[gc-install]   - Use 'gc-query sessions' to list all captured sessions
[gc-install]   - Use 'gc-query doctor' to check system health
[gc-install]
[gc-install] Event capture is now active. No further action needed.
```

#### Acceptance Criteria

- [ ] The first-run summary is printed after successful installation.
- [ ] The summary lists the key installed paths.
- [ ] The summary includes actionable next steps for the user.
- [ ] The summary mentions that event capture is automatic (no further action required).
- [ ] The output uses the `[gc-install]` prefix consistently.
- [ ] The summary is not printed if installation failed.

---

## Edge Cases

### E-1: bash Version < 4 (macOS Default)

**Scenario**: macOS ships with bash 3.2 due to licensing (GPL v2 vs v3). The user has not installed a newer bash via Homebrew.

**Expected behavior**: The prerequisites check detects bash 3.2, reports it as below the minimum, and provides macOS-specific instructions:

```
[gc-install]   bash ............. 3.2 (>= 4.0 required)    FAIL
[gc-install]     macOS ships with an outdated bash (3.2).
[gc-install]     Install a newer version: brew install bash
[gc-install]     Then ensure /opt/homebrew/bin/bash (or /usr/local/bin/bash)
[gc-install]     is in your PATH before /bin/bash.
```

**Note**: The `gc-install` script itself uses `#!/usr/bin/env bash` so it will use whichever `bash` is first in PATH. If Homebrew bash is installed but not in PATH, the check still fails because the runtime bash would be the system one.

---

### E-2: node Not Installed

**Scenario**: The user has bash and jq but not Node.js. The write side works (bash+jq), but the read side (projections, gc-query) will not.

**Expected behavior**: Installation aborts because Node.js is a required dependency. The read side is not optional -- without it, captured events cannot be queried.

```
[gc-install]   node ............. NOT FOUND                 FAIL
[gc-install]     Install Node.js 18 or later:
[gc-install]       https://nodejs.org/
[gc-install]       Or use nvm: nvm install 18
```

---

### E-3: Partial Previous Installation

**Scenario**: A previous `gc-install` run failed partway through. Some files exist, others do not.

**Expected behavior**: `gc-install` is idempotent at every step. Directories are created with `mkdir -p`. Files are overwritten. Config is preserved if it exists. The user can simply re-run `gc-install` to complete the installation.

---

### E-4: CLAUDE_CONTEXT_PATH Points to Non-Existent Location

**Scenario**: The user sets `CLAUDE_CONTEXT_PATH=/mnt/external/claude-context` but `/mnt/external/` does not exist.

**Expected behavior**: `gc-init` (called by `gc-install`) attempts `mkdir -p` on the path. If the parent directory does not exist or is not writable, `gc-init` fails with a clear error, and `gc-install` reports the failure:

```
[gc-install] ERROR: gc-init failed.
[gc-install]   Could not create store directory: /mnt/external/claude-context
[gc-install]   Ensure the parent directory exists and is writable.
```

---

### E-5: Home Directory Path Contains Spaces

**Scenario**: The user's home directory is `/home/John Doe/`.

**Expected behavior**: All paths in `gc-install` are properly quoted. The tilde-based paths in hook commands (`~/.claude-context/bin/gc-hook`) rely on Claude Code's tilde expansion, which handles spaces. The installation should succeed without issues.

---

### E-6: Running gc-install as Root

**Scenario**: The user runs `gc-install` with `sudo`.

**Expected behavior**: The installation proceeds using `$HOME` of the root user (typically `/root`). This is probably not what the user intended. `gc-install` detects this and prints a warning:

```
[gc-install] WARN: Running as root. Files will be installed to /root/.claude-context/
[gc-install]   If you meant to install for your user, run without sudo.
```

The installation is not blocked -- the user may have a legitimate reason to run as root.

---

### E-7: sha256sum Not Available (macOS)

**Scenario**: macOS does not ship `sha256sum` by default. It has `shasum -a 256` instead.

**Expected behavior**: The prerequisites check detects this and reports it as acceptable:

```
[gc-install]   sha256sum ........ not found (using shasum -a 256)  OK
```

The `gc_derive_project_id` function (defined in paths.sh) must handle both commands:

```bash
if command -v sha256sum &>/dev/null; then
  hash=$(printf '%s' "$path" | sha256sum | cut -c1-6)
elif command -v shasum &>/dev/null; then
  hash=$(printf '%s' "$path" | shasum -a 256 | cut -c1-6)
fi
```

---

### E-8: Uninstall When Hooks Have Been Manually Modified

**Scenario**: The user manually edited `~/.claude/settings.json` and changed a GlobalContext hook's timeout from 5000 to 10000.

**Expected behavior**: `gc-uninstall` delegates to `gc-install-hooks uninstall`, which identifies GlobalContext hooks by the `gc-hook` substring in the command field. The modified hook is still identified and removed correctly. User-defined hooks (without `gc-hook` in the command) are preserved.

---

### E-9: Multiple Installations in Different Locations

**Scenario**: The user runs `gc-install` once with default paths, then runs it again with `CLAUDE_CONTEXT_PATH=/tmp/test-context`.

**Expected behavior**: This creates two separate event stores. The hooks in `~/.claude/settings.json` point to `~/.claude-context/bin/gc-hook` (the default). The second store at `/tmp/test-context` would only be used if `CLAUDE_CONTEXT_PATH` is set in the environment when Claude Code runs. `gc-install` does not warn about this -- it is a valid use case for testing.

---

## Non-Goals

This story explicitly does NOT cover:

- **Package manager distribution** (apt, brew, npm) -- the installation is a manual script-based process for now.
- **Auto-update or self-update mechanism** -- upgrades are manual (re-run `gc-install`).
- **Shell completion** -- tab completion for gc-query subcommands is a future enhancement.
- **PATH modification** -- `gc-install` does not modify the user's shell profile (`~/.bashrc`, `~/.zshrc`). The scripts are accessed via full paths in hook commands. Users who want `gc-query` on their PATH can add `~/.claude-context/bin` manually.
- **Systemd/launchd service registration** -- GlobalContext has no daemons or background services.
- **Migration from older storage formats** -- version 1.0.0 is the first release; there are no older formats to migrate from.

---

## Technical Specifications

### File Locations

| File | Path | Purpose |
|------|------|---------|
| Installer | `bin/gc-install` (in source tree) | Entry point for installation |
| Uninstaller | `bin/gc-uninstall` (in source tree) | Entry point for uninstallation |
| Installed installer | `~/.local/share/globalcontext/bin/gc-install` | Allows re-running from installed location |
| Installed uninstaller | `~/.local/share/globalcontext/bin/gc-uninstall` | Allows running uninstall from installed location |
| Version file | `~/.local/share/globalcontext/VERSION` | Installed version tracking |

### Exit Codes

| Script | Exit Code | Meaning |
|--------|-----------|---------|
| gc-install | 0 | Installation completed successfully |
| gc-install | 1 | Installation failed (prerequisites, gc-init, or gc-install-hooks failure) |
| gc-uninstall | 0 | Uninstallation completed successfully |
| gc-uninstall | 1 | Uninstallation failed |
| gc-uninstall --purge (no --yes) | 2 | Aborted -- confirmation required |

### Dependencies

| Dependency | Required By | Hard/Soft |
|------------|-------------|-----------|
| `bash` >= 4.0 | gc-install, all bash scripts | Hard |
| `jq` >= 1.5 | gc-install, capture-event, gc-install-hooks | Hard |
| `node` >= 18.0 | gc-query, projection engine | Hard |
| `flock` | capture-event | Soft (fallback to unlocked writes) |
| `uuidgen` | capture-event | Soft (fallback chain) |
| `sha256sum` or `shasum` | project ID derivation | Soft (one of the two must be present) |

---

## Testing Plan

### Unit Tests

| Test | Description |
|------|-------------|
| T-1 | Prerequisites check passes when all dependencies are present with correct versions |
| T-2 | Prerequisites check fails clearly when jq is missing |
| T-3 | Prerequisites check fails clearly when node is missing |
| T-4 | Prerequisites check fails clearly when bash is below version 4 |
| T-5 | Prerequisites check passes with sha256sum fallback to shasum |
| T-6 | Version comparison correctly handles major.minor.patch format |
| T-7 | Version comparison: 18.0.0 >= 18.0 passes |
| T-8 | Version comparison: 16.20.0 >= 18.0 fails |

### Integration Tests

| Test | Description |
|------|-------------|
| T-9 | Fresh install on clean system creates all expected directories and files |
| T-10 | Fresh install produces correct first-run output |
| T-11 | Re-running gc-install on existing installation updates scripts, preserves data |
| T-12 | Re-running gc-install with same version reports "already installed" and verifies |
| T-13 | gc-uninstall removes hooks and scripts, preserves events |
| T-14 | gc-uninstall --purge --yes removes everything |
| T-15 | gc-uninstall --purge (without --yes) prints warning and exits 2 |
| T-16 | gc-install with CLAUDE_CONTEXT_PATH override creates store at custom location |
| T-17 | gc-install with GLOBALCONTEXT_HOME override places source at custom location |
| T-18 | gc-install after partial failure completes successfully on re-run |
| T-19 | gc-install detects running as root and prints warning |

### Manual Verification

| Test | Description |
|------|-------------|
| M-1 | Run gc-install on a fresh Linux system, then start a Claude Code session, verify events are captured |
| M-2 | Run gc-install on macOS with Homebrew bash, verify prerequisites pass |
| M-3 | Run gc-install, then gc-uninstall, then gc-install again -- verify full round-trip works |
| M-4 | Run gc-install, capture some events, upgrade to a new version, verify events are preserved |

---

## Definition of Done

- [ ] `gc-install` script exists and is executable in the source tree at `bin/gc-install`
- [ ] Prerequisites check validates bash >= 4.0, jq >= 1.5, node >= 18.0 with clear output
- [ ] Source files are copied to `~/.local/share/globalcontext/`
- [ ] `gc-init` is called and creates `~/.claude-context/` structure
- [ ] `gc-install-hooks` is called and registers all 10 hooks
- [ ] `gc-query doctor` is called for post-install verification
- [ ] First-run summary is printed with paths and next steps
- [ ] Running `gc-install` again upgrades scripts without losing data
- [ ] `gc-uninstall` removes hooks and scripts, preserving event data by default
- [ ] `gc-uninstall --purge --yes` removes everything including the event store
- [ ] Works on Linux (bash 5.x, ext4) and macOS (Homebrew bash 5.x, APFS)
- [ ] All test cases from the testing plan pass
- [ ] All output uses `[gc-install]` or `[gc-uninstall]` prefix consistently
