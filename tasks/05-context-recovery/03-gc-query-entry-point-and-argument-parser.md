# Task 03: gc-query Entry Point and Argument Parser

**Story**: 05-context-recovery
**Complexity**: M (Medium)
**Status**: Pending

---

## Description

Create the `gc-query` CLI entry point script with argument parsing, help text, and routing to subcommand functions. This is the skeleton that all subsequent tasks fill in.

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Create | `~/.claude-context/bin/gc-query` |

---

## Specification / Implementation Details

The script must:
1. Source `lib/store-path.sh` for path resolution
2. Parse the first positional argument as the subcommand
3. Parse flags with a shift-based loop (no `getopt` dependency for portability)
4. Route to the correct subcommand function
5. Print usage/help when invoked with no arguments, `-h`, or `--help`
6. Exit with code 2 for invalid arguments

Subcommands to stub out (each returns "Not yet implemented" initially):
- `last`
- `session <session-id>`
- `sessions`
- `search <keyword>`
- `events <session-id>`
- `replay <session-id>`
- `tail <session-id> [N]`
- `status`
- `doctor`

---

## Dependencies

- [Task 01: Shared Store Path Resolution Helper](/home/meywd/GlobalContext/tasks/05-context-recovery/01-shared-store-path-resolution-helper.md) (store path helper)

---

## Acceptance Tests

1. `gc-query` with no args prints help and exits with code 2.
2. `gc-query --help` prints help and exits with code 0.
3. `gc-query invalidcommand` prints error and exits with code 2.
4. `gc-query status` routes to the status stub.
5. Script is executable (mode 755).
6. Works on both Linux and macOS (no bash-4-only features in arg parsing).

---

## Estimated Complexity: M
