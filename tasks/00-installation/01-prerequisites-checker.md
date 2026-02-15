# Task 01: Prerequisites Checker

**Story**: 00-installation-setup
**Status**: Pending
**Estimated Complexity**: M (Medium) -- 2-3 hours

---

## Description

Create a reusable function library that verifies the system has all required dependencies for GlobalContext. This library is called by both `gc-install` (to gate installation) and `gc-doctor` (to report health). It checks for each prerequisite independently and returns structured results so callers can decide how to proceed.

The checker does not abort on failure -- it reports what is missing and lets the caller decide. This design allows `gc-install` to abort early while `gc-doctor` can report partial health.

---

## Prerequisites to Check

| Prerequisite | Required | Check Method | Minimum Version | Fallback Behavior |
|---|---|---|---|---|
| `bash` | Yes | `${BASH_VERSINFO[0]}` | 4+ | Abort (the scripts themselves require bash 4+ for associative arrays) |
| `jq` | Yes | `command -v jq` + `jq --version` | 1.5+ | Abort (JSON manipulation is impossible without jq) |
| `node` | Yes | `command -v node` + `node --version` | 18+ | Abort (projection engine and gc-query require Node.js) |
| `git` | No | `command -v git` | Any | Warn (version tracking via git is optional; project-id derivation works without it) |
| `flock` | No | `command -v flock` | Any | Warn (capture-event falls back to unlocked writes with random suffix) |
| `uuidgen` | No | `command -v uuidgen` | Any | Info (bash-native UUID fallback is used) |
| `sha256sum` or `shasum` | Yes | `command -v sha256sum` or `command -v shasum` | Any | Abort (project-id derivation requires hashing) |

---

## Files to Create/Modify

| File | Action | Purpose |
|---|---|---|
| `src/lib/prerequisites.sh` | Create | Prerequisite checker library |
| `tests/lib/test_prerequisites.sh` | Create | Unit tests for prerequisite detection |

All file paths are relative to `/home/meywd/GlobalContext/`.

---

## Specification / Implementation Details

### Result Structure

The checker populates associative arrays and prints a human-readable summary:

```bash
# Each prerequisite sets:
#   PREREQ_STATUS[name]="ok|missing|outdated|optional_missing"
#   PREREQ_VERSION[name]="detected version string"
#   PREREQ_MESSAGE[name]="human-readable status message"

gc_check_prerequisites()  # populates arrays, returns 0 if all required pass, 1 otherwise
gc_print_prereq_report()  # prints formatted report to stdout
gc_prereq_ok()            # returns 0 if all required prerequisites are met
```

### Version Extraction

```bash
# bash version: already available as BASH_VERSINFO[0]
# jq version:   jq --version | sed 's/jq-//'     -> "1.7.1"
# node version: node --version | sed 's/^v//'     -> "22.1.0"
# git version:  git --version | awk '{print $3}'  -> "2.43.0"
```

### Error Messages

Each missing prerequisite produces a specific, actionable message:

| Missing | Message |
|---|---|
| bash 4+ | `ERROR: bash 4+ required (found: X.Y). On macOS: brew install bash` |
| jq | `ERROR: jq is required but not found. Install: sudo apt install jq (Debian/Ubuntu) or brew install jq (macOS)` |
| node 18+ | `ERROR: Node.js 18+ required (found: X.Y). Install from https://nodejs.org/` |
| sha256sum/shasum | `ERROR: sha256sum or shasum required for project-id hashing. Install coreutils.` |
| flock (optional) | `WARN: flock not found. Concurrent event writes will use best-effort mode (no locking).` |
| git (optional) | `INFO: git not found. Version tracking will be limited.` |
| uuidgen (optional) | `INFO: uuidgen not found. Using bash-native UUID generation (slightly weaker entropy).` |

---

## Dependencies

None (first task).

---

## Acceptance Tests

1. On a system with all prerequisites met: `gc_check_prerequisites` returns 0, report shows all "ok".
2. Remove `jq` from PATH: `gc_check_prerequisites` returns 1, `PREREQ_STATUS[jq]` is `"missing"`, message includes install instructions.
3. Mock bash version to 3: checker detects "outdated" and reports the specific version found.
4. Mock node version to 16: checker detects "outdated" with `"found: 16"` in the message.
5. Remove `flock` from PATH: checker returns 0 (flock is optional), but `PREREQ_STATUS[flock]` is `"optional_missing"`.
6. Remove `git` from PATH: checker returns 0 (git is optional), report shows INFO message.
7. `gc_print_prereq_report` output is human-readable with aligned columns and clear pass/fail indicators.
