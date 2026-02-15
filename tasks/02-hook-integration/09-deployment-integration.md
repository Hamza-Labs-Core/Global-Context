# Task 09: Deployment Integration with Story 01 Installer

**Story**: 02-hook-integration
**Status**: Pending
**Estimated Complexity**: S (Small) -- a few lines added to the installer

---

## Description

Ensure that `gc-hook` and `gc-install-hooks` are deployed alongside `capture-event` during the Story 01 installation process. Update Story 01's `install.sh` (or create a top-level installer) to:

1. Copy `gc-hook` to `~/.claude-context/bin/gc-hook` and `chmod +x`.
2. Copy `gc-install-hooks` to `~/.claude-context/bin/gc-install-hooks` and `chmod +x`.
3. Run `gc-install-hooks install` to register the hooks in `settings.json`.

This task wires the two stories together.

---

## Files to Modify

| File | Change |
|------|--------|
| `src/install.sh` (or create `src/install-hooks.sh` if Story 01's installer is separate) | Add gc-hook and gc-install-hooks deployment steps |

---

## Specification / Implementation Details

After Story 01's `install.sh` deploys `capture-event`, add:

```bash
# Deploy hook wrapper (Story 02)
cp src/gc-hook "$GC_BASE/bin/gc-hook"
chmod +x "$GC_BASE/bin/gc-hook"

# Deploy hook installer (Story 02)
cp src/gc-install-hooks "$GC_BASE/bin/gc-install-hooks"
chmod +x "$GC_BASE/bin/gc-install-hooks"

# Register hooks in Claude Code settings
"$GC_BASE/bin/gc-install-hooks" install
```

---

## Dependencies

- [Task 01: gc-hook wrapper](/home/meywd/GlobalContext/tasks/02-hook-integration/01-gc-hook-wrapper.md) -- gc-hook
- [Task 05: gc-install-hooks install](/home/meywd/GlobalContext/tasks/02-hook-integration/05-gc-install-hooks-install.md) -- gc-install-hooks install
- Story 01 (install.sh must exist)

---

## Acceptance Tests

1. Run the full `install.sh` from a clean state.
2. Verify `~/.claude-context/bin/gc-hook` exists and is executable.
3. Verify `~/.claude-context/bin/gc-install-hooks` exists and is executable.
4. Verify `~/.claude/settings.json` contains all 10 hooks.
5. Run `echo '{"session_id":"test"}' | ~/.claude-context/bin/gc-hook SessionStarted` and verify it succeeds.
