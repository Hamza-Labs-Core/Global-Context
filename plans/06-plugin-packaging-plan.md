# Implementation Plan: Story 06 -- Claude Code Plugin Packaging

**Date**: 2026-02-15
**Story**: 06-plugin-packaging
**Status**: Planning
**Estimated Total Effort**: ~6 days (24-32 hours)
**Prerequisites**: Stories 01-05 must be implementation-ready (source files exist for bundling). Story 00 (Installation) is superseded by this plan for plugin-based distribution.
**Design Amendments**: 1, 2, 3, 4. See `docs/DESIGN-AMENDMENTS.md`.

### Context

This plan packages GlobalContext as a Claude Code plugin, replacing the manual installation flow (Story 00) and manual hook registration (Story 02) with a single `claude plugin install globalcontext` command. The plugin format handles hook registration, script deployment, slash commands, skills, and agents within Claude Code's native plugin system.

### Relationship to Other Stories

This plan **supersedes Story 00** (Installation & Setup) for plugin-based distribution. Users who install via the plugin system do not need `gc-install`, `gc-install-hooks`, or `gc-uninstall` -- the plugin lifecycle handles all of that.

- **Story 01** (Event Capture): `capture-event` is bundled into `scripts/`
- **Story 02** (Hook Integration): `gc-hook` wrapper and hook config move from `~/.claude/settings.json` to `hooks/hooks.json` inside the plugin
- **Story 03** (Storage Layer): Shared libraries (`paths.sh`, `sanitize.sh`, `atomic_write.sh`) are bundled into `lib/`
- **Story 04** (Projection Engine): `project` CLI and Node.js modules are bundled into `lib/`
- **Story 05** (Context Recovery): `gc-query` subcommands become slash commands; context recovery becomes a skill and agent

### Amendment Impacts on This Plan

- **Amendment 3** (Project-ID layer): All paths inside the plugin use `${CLAUDE_PLUGIN_ROOT}` for code, `~/.claude-context/` (or `$CLAUDE_CONTEXT_PATH`) for data. The project-id layer applies to the data store, not the plugin directory.
- **Amendment 4** (Remove gc-cleanup): No cleanup command in the plugin. The `/globalcontext:doctor` command reports disk usage as a diagnostic.

---

## Task Dependency Graph

```
Task 1 (Plugin Manifest + Scaffold)
  |
  +---> Task 2 (Hook Configuration)
  |       |
  |       +---> Task 3 (Capture Script Adaptation)
  |       |       |
  |       |       +---> Task 4 (Auto-Init on First Use)
  |       |
  |       +---> Task 8 (Shared Library Bundling) [also independent]
  |
  +---> Task 5 (Command Files)
  |
  +---> Task 6 (Context Recovery Skill)
  |
  +---> Task 7 (Context Recovery Agent)
  |
  +---> Task 8 (Shared Library Bundling)
  |
  +---> Task 9 (Marketplace Configuration)
  |
  +---> Task 10 (Integration Tests) [depends on all above]
```

---

## Tasks

### Task 1: Plugin Manifest and Directory Scaffold

**Description**

Create the `.claude-plugin/plugin.json` manifest and the complete plugin directory structure. This establishes the plugin identity and layout that Claude Code's plugin loader expects.

The manifest defines the plugin's name, version, description, and entry points. The directory structure follows Claude Code's plugin conventions with directories for commands, agents, skills, hooks, scripts, and shared libraries.

**Files to Create**

| File | Purpose |
|------|---------|
| `plugin/.claude-plugin/plugin.json` | Plugin manifest (name, version, description, author, homepage) |
| `plugin/commands/` | Directory for slash command markdown files (Task 5) |
| `plugin/agents/` | Directory for subagent definitions (Task 7) |
| `plugin/skills/` | Directory for auto-invoked skills (Task 6) |
| `plugin/hooks/` | Directory for hooks.json (Task 2) |
| `plugin/scripts/` | Directory for hook scripts and utilities (Tasks 3, 4) |
| `plugin/lib/` | Directory for shared bash/node libraries (Task 8) |

**Specification**

`plugin/.claude-plugin/plugin.json`:

```json
{
  "name": "globalcontext",
  "version": "1.0.0",
  "description": "Event-sourced context store for Claude Code sessions. Captures all hook events, builds projections, and enables context recovery after compaction or session changes.",
  "author": "GlobalContext",
  "homepage": "https://github.com/globalcontext/globalcontext",
  "license": "MIT",
  "claude_code_version": ">=1.0.0"
}
```

**Dependencies**: None (first task).

**Acceptance Test**

1. The `plugin/.claude-plugin/plugin.json` file exists and is valid JSON.
2. `jq .name plugin/.claude-plugin/plugin.json` returns `"globalcontext"`.
3. All six subdirectories exist: `commands/`, `agents/`, `skills/`, `hooks/`, `scripts/`, `lib/`.
4. The plugin directory is loadable by `claude --plugin-dir ./plugin` without errors (structure validation only, no functional test yet).

**Estimated Complexity**: S

---

### Task 2: Hook Configuration (hooks.json)

**Description**

Define the complete hook configuration in `hooks/hooks.json` using the Claude Code plugin hooks format. This replaces the manual `gc-install-hooks` script from Story 02 -- hooks are declared in the plugin and registered automatically when the plugin is installed.

All 10 hook events are defined. Each hook calls `${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook` with the appropriate GlobalContext event type as the argument. Sync/async settings follow the same rationale as Story 02 (PreCompact, SessionStart, UserPromptSubmit are sync; all others are async). Matcher patterns use `".*"` for tool-related hooks to capture all tools.

**Files to Create**

| File | Purpose |
|------|---------|
| `plugin/hooks/hooks.json` | Complete hook configuration for all 10 events |

**Specification**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook SessionStarted",
            "async": false,
            "timeout": 5000
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook UserPromptReceived",
            "async": false,
            "timeout": 5000
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook ToolCallRequested",
            "async": true,
            "timeout": 5000
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook ToolCallCompleted",
            "async": true,
            "timeout": 5000
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook ToolCallFailed",
            "async": true,
            "timeout": 5000
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook AgentSpawned",
            "async": true,
            "timeout": 5000
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook AgentCompleted",
            "async": true,
            "timeout": 5000
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook TurnCompleted",
            "async": true,
            "timeout": 5000
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook CompactionTriggered",
            "async": false,
            "timeout": 5000
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook SessionEnded",
            "async": true,
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

**Hook Event to Event Type Mapping** (carried forward from Story 02):

| Hook Event | Event Type | Sync/Async | Matcher | Rationale |
|---|---|---|---|---|
| SessionStart | SessionStarted | sync | `""` | Session boundary; must capture before any other events |
| UserPromptSubmit | UserPromptReceived | sync | (none) | Exact user prompts; must capture before LLM processes |
| PreToolUse | ToolCallRequested | async | `".*"` | High frequency; captures intent |
| PostToolUse | ToolCallCompleted | async | `".*"` | High frequency; captures results |
| PostToolUseFailure | ToolCallFailed | async | `".*"` | Error tracking |
| SubagentStart | AgentSpawned | async | `".*"` | Sub-agent lifecycle |
| SubagentStop | AgentCompleted | async | `".*"` | Sub-agent results |
| Stop | TurnCompleted | async | (none) | Turn boundary markers |
| PreCompact | CompactionTriggered | sync | (none) | Critical -- last chance before context loss |
| SessionEnd | SessionEnded | async | (none) | Session lifecycle closure |

**Dependencies**: Task 1 (directory structure must exist).

**Acceptance Test**

1. `jq . plugin/hooks/hooks.json` parses without error.
2. `jq '.hooks | keys | length' plugin/hooks/hooks.json` returns `10`.
3. Sync events (SessionStart, UserPromptSubmit, PreCompact) have `"async": false`.
4. Async events (PreToolUse, PostToolUse, PostToolUseFailure, SubagentStart, SubagentStop, Stop, SessionEnd) have `"async": true`.
5. All hook commands reference `${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook`.
6. Tool-related hooks (PreToolUse, PostToolUse, PostToolUseFailure, SubagentStart, SubagentStop) have `"matcher": ".*"`.
7. All timeouts are 5000ms.
8. Each hook entry has `"type": "command"`.

**Estimated Complexity**: M

---

### Task 3: Capture Event Script Adaptation

**Description**

Adapt the `capture-event` and `gc-hook` scripts to work from `${CLAUDE_PLUGIN_ROOT}` instead of the hardcoded `~/.claude-context/bin/` path. The scripts themselves are deployed as `plugin/scripts/capture-event` and `plugin/scripts/gc-hook`. All code paths resolve relative to the plugin root; all data paths resolve to `~/.claude-context/` (or `$CLAUDE_CONTEXT_PATH`).

This is the critical distinction in the plugin model: **code lives in the plugin directory, data lives in the user's home directory**. The plugin may be installed in a read-only location managed by Claude Code's plugin system. The data store must remain in a user-writable location.

**Files to Create**

| File | Purpose |
|------|---------|
| `plugin/scripts/gc-hook` | Hook wrapper adapted for plugin root |
| `plugin/scripts/capture-event` | Event capture script adapted for plugin root |

**Specification**

`plugin/scripts/gc-hook` (adapted from `src/gc-hook`):

```bash
#!/usr/bin/env bash
# GlobalContext plugin hook wrapper v1
# Usage: gc-hook <EventType>
# Called by Claude Code hooks. Reads JSON from stdin, passes to capture-event.
# GUARANTEES: exit 0, zero stdout, zero stderr.

EVENT_TYPE="${1:?Missing event type}"

# Resolve code paths from plugin root
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Resolve data path: CLAUDE_CONTEXT_PATH env var, or default
GC_BASE="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"

# Source shared libraries from plugin
source "$PLUGIN_ROOT/lib/paths.sh" 2>/dev/null || true

# Run capture-event from plugin scripts directory
if [ "${GC_DEBUG:-0}" = "1" ]; then
  source "$PLUGIN_ROOT/lib/debug_log.sh" 2>/dev/null
  gc_debug_log "gc-hook invoked: event_type=$EVENT_TYPE"
  ("$PLUGIN_ROOT/scripts/capture-event" "$EVENT_TYPE" </dev/stdin >/dev/null 2>>"$GC_LOG_FILE") || {
    gc_debug_log "capture-event failed: exit=$?"
    true
  }
else
  ("$PLUGIN_ROOT/scripts/capture-event" "$EVENT_TYPE" </dev/stdin >/dev/null 2>/dev/null) || true
fi

exit 0
```

`plugin/scripts/capture-event` (adapted from `src/capture-event`):

Key changes from the standalone version:
- Resolves shared libraries via `$PLUGIN_ROOT/lib/` instead of `$GC_BASE/lib/`
- All `source` commands reference `$PLUGIN_ROOT/lib/paths.sh`, `$PLUGIN_ROOT/lib/sanitize.sh`, `$PLUGIN_ROOT/lib/atomic_write.sh`
- Data paths still use `$GC_ROOT` (resolved by `paths.sh` from `$CLAUDE_CONTEXT_PATH` or `~/.claude-context/`)
- The `PLUGIN_ROOT` is derived from `$(cd "$(dirname "$0")/.." && pwd)` -- one level up from `scripts/`

**Path Resolution Model**:

```
Code paths (read-only, plugin-managed):
  ${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook
  ${CLAUDE_PLUGIN_ROOT}/scripts/capture-event
  ${CLAUDE_PLUGIN_ROOT}/lib/paths.sh
  ${CLAUDE_PLUGIN_ROOT}/lib/sanitize.sh
  ${CLAUDE_PLUGIN_ROOT}/lib/atomic_write.sh
  ${CLAUDE_PLUGIN_ROOT}/lib/*.js

Data paths (read-write, user-managed):
  ~/.claude-context/events/{project-id}/{session-id}/*.json
  ~/.claude-context/projections/{project-id}/{session-id}/*.json
  ~/.claude-context/config.json
  ~/.claude-context/logs/hook.log
```

**Dependencies**: Task 1, Task 8 (shared libraries must be bundled for sourcing).

**Acceptance Test**

1. `plugin/scripts/gc-hook` is executable and exits 0 when run with `echo '{}' | plugin/scripts/gc-hook TestEvent`.
2. `plugin/scripts/gc-hook` produces zero stdout and zero stderr under all conditions (missing capture-event, crash, empty stdin).
3. `plugin/scripts/capture-event` correctly resolves `$PLUGIN_ROOT/lib/` for code and `$GC_ROOT` for data.
4. Running `echo '{"session_id":"test-s1"}' | CLAUDE_CONTEXT_PATH=/tmp/gc-test plugin/scripts/gc-hook SessionStarted` writes an event to `/tmp/gc-test/events/`.
5. No hardcoded `~/.claude-context/bin/` paths remain in either script.
6. Both scripts work when the plugin directory is at an arbitrary location (not `~/.claude-context/`).

**Estimated Complexity**: M

---

### Task 4: Auto-Init on First Use

**Description**

The SessionStart hook checks if the data store exists and initializes it if needed. This replaces the manual `gc-init` / `install.sh` step from Story 00. The check must be fast (just a directory existence test) and idempotent.

When a user installs the plugin and starts their first session, the SessionStart hook fires. If `~/.claude-context/` does not exist, `gc-hook` runs the initialization logic before invoking `capture-event`. This is a one-time cost on the very first session; subsequent sessions skip initialization in under 1ms.

**Files to Create/Modify**

| File | Action | Purpose |
|------|--------|---------|
| `plugin/scripts/gc-init` | Create | Initialization script for the data store |
| `plugin/scripts/gc-hook` | Modify | Add auto-init check before capture-event invocation |

**Specification**

`plugin/scripts/gc-init`:

```bash
#!/usr/bin/env bash
# GlobalContext store initialization
# Creates directory structure at $GC_ROOT
# Idempotent: safe to run multiple times

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$PLUGIN_ROOT/lib/paths.sh" 2>/dev/null || {
  GC_ROOT="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"
}

# Create directory structure
mkdir -p "$GC_ROOT/events" 2>/dev/null
mkdir -p "$GC_ROOT/projections" 2>/dev/null
mkdir -p "$GC_ROOT/logs" 2>/dev/null
chmod 700 "$GC_ROOT" 2>/dev/null

# Create config.json if missing
if [ ! -f "$GC_ROOT/config.json" ]; then
  cat > "$GC_ROOT/config.json" <<CONF
{
  "version": "1.0.0",
  "events_dir": "events",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source": "plugin"
}
CONF
fi

exit 0
```

Modification to `gc-hook` (added before the capture-event invocation):

```bash
# Auto-init: check if store exists, run gc-init if not
if [ ! -d "$GC_BASE/events" ]; then
  "$PLUGIN_ROOT/scripts/gc-init" 2>/dev/null || true
fi
```

**Key design decisions**:

- The check is `[ -d "$GC_BASE/events" ]` -- a single stat syscall, effectively free.
- `gc-init` is idempotent: `mkdir -p` is a no-op if directories exist, `config.json` is only written if missing.
- Errors in `gc-init` are suppressed (`2>/dev/null || true`) -- if init fails (permissions, disk full), the session is not disrupted.
- The `config.json` gains a `"source": "plugin"` field to distinguish plugin-installed stores from manually installed ones.

**Dependencies**: Task 1, Task 3 (gc-hook must exist to be modified).

**Acceptance Test**

1. On a system with no `~/.claude-context/`: run `echo '{"session_id":"init-test"}' | plugin/scripts/gc-hook SessionStarted`. Verify `~/.claude-context/events/` and `~/.claude-context/projections/` are created.
2. Verify `~/.claude-context/config.json` exists with `version`, `events_dir`, `created_at`, and `source` fields.
3. Verify `~/.claude-context/` has permissions `700`.
4. Run `gc-hook` again. Verify no errors and no duplicate initialization (idempotent).
5. Set `CLAUDE_CONTEXT_PATH=/tmp/gc-init-test`. Run `gc-hook`. Verify directories are created at the custom path.
6. Make `gc-init` fail (read-only filesystem). Verify `gc-hook` still exits 0 and the session is not disrupted.
7. Measure the time for the `[ -d ]` check on an existing store: under 1ms.

**Estimated Complexity**: S

---

### Task 5: Command Files (gc-query as Slash Commands)

**Description**

Create markdown command files for each `gc-query` subcommand, making them available as `/globalcontext:<name>` slash commands within Claude Code. Each command file describes what it does, its arguments, and invokes the underlying `gc-query` script (or inline logic) to produce the result.

Commands are markdown files in the `commands/` directory. The filename (minus `.md`) becomes the slash command name, namespaced under the plugin name: `/globalcontext:last`, `/globalcontext:search`, etc.

**Files to Create**

| File | Slash Command | gc-query Subcommand |
|------|---------------|---------------------|
| `plugin/commands/last.md` | `/globalcontext:last` | `gc-query last` |
| `plugin/commands/session.md` | `/globalcontext:session` | `gc-query session <id>` |
| `plugin/commands/sessions.md` | `/globalcontext:sessions` | `gc-query sessions` |
| `plugin/commands/search.md` | `/globalcontext:search` | `gc-query search <keyword>` |
| `plugin/commands/replay.md` | `/globalcontext:replay` | `gc-query replay <session-id>` |
| `plugin/commands/tail.md` | `/globalcontext:tail` | `gc-query tail <session-id> [N]` |
| `plugin/commands/events.md` | `/globalcontext:events` | `gc-query events <session-id>` |
| `plugin/commands/status.md` | `/globalcontext:status` | `gc-query status` |
| `plugin/commands/doctor.md` | `/globalcontext:doctor` | `gc-query doctor` |

**Specification**

Each command markdown file follows this structure:

```markdown
---
name: <command-name>
description: <one-line description>
---

<Instructions for Claude on how to execute this command>
```

Example -- `plugin/commands/last.md`:

```markdown
---
name: last
description: Retrieve context from the most recent session for the current project
---

# GlobalContext: Last Session Context

Retrieve and display the full context from the most recent GlobalContext session
for the current project directory.

## Execution

Run the following command to get the last session context:

\`\`\`bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" last --format markdown
\`\`\`

If no sessions exist for the current project, inform the user that no previous
context was found and suggest they start working -- GlobalContext will capture
everything automatically.

## Arguments

- `--format json` -- return raw JSON instead of markdown
- `--include-parent` -- include context from parent sessions (session chain)

## Output

Present the recovered context to the user in a clear format. Highlight:
1. What was being worked on (last prompt and recent context)
2. Files that were modified
3. Key decisions made
4. Where work left off
```

Example -- `plugin/commands/search.md`:

```markdown
---
name: search
description: Search across sessions for events containing a keyword
---

# GlobalContext: Search

Search across GlobalContext sessions for events matching a keyword. Searches
user prompts, tool names, tool results, and file paths.

## Execution

The user will provide a search term as part of their message. Run:

\`\`\`bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" search "<user's search term>"
\`\`\`

## Arguments

- `--type <event-type>` -- filter by event type (e.g., UserPromptReceived)
- `--file <path>` -- search for events referencing a specific file
- `--limit <N>` -- limit results (default: 20)
- `--all-projects` -- search across all projects, not just the current one

## Output

Present search results grouped by session. For each match show:
- Session ID and timestamp
- Event type and sequence number
- Matching text snippet with surrounding context
```

Example -- `plugin/commands/doctor.md`:

```markdown
---
name: doctor
description: Run health checks on the GlobalContext system
---

# GlobalContext: Doctor

Run comprehensive health checks on the GlobalContext system to verify everything
is functioning correctly.

## Execution

\`\`\`bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" doctor
\`\`\`

## Output

Present the health check results to the user. Flag any failures or warnings.
If issues are found, suggest remediation steps:
- Missing directories: suggest re-initializing with `gc-init`
- Missing scripts: suggest reinstalling the plugin
- Stale projections: suggest running gc-query to rebuild
- Disk space warnings: report usage and suggest reviewing old sessions
```

The remaining command files (`session.md`, `sessions.md`, `replay.md`, `tail.md`, `events.md`, `status.md`) follow the same pattern with appropriate descriptions, execution commands, arguments, and output instructions.

**Dependencies**: Task 1 (commands directory must exist).

**Acceptance Test**

1. All 9 command files exist in `plugin/commands/`.
2. Each file has valid YAML frontmatter with `name` and `description` fields.
3. Each file references `${CLAUDE_PLUGIN_ROOT}/scripts/gc-query` in its execution section.
4. Loading the plugin with `claude --plugin-dir ./plugin` exposes all 9 commands as `/globalcontext:<name>`.
5. Running `/globalcontext:status` in a Claude Code session invokes `gc-query status`.
6. Each command file documents its arguments and expected output format.

**Estimated Complexity**: M

---

### Task 6: Context Recovery Skill

**Description**

Create a SKILL.md file that Claude auto-invokes when it detects context loss. Skills are auto-triggered based on their description matching the user's intent. The context recovery skill triggers when the user asks about what they were doing, when context has been compacted, or when starting a new session after compaction.

Unlike commands (which require explicit `/globalcontext:last` invocation), the skill is activated automatically by Claude's intent-matching system when it detects that the user needs context recovery.

**Files to Create**

| File | Purpose |
|------|---------|
| `plugin/skills/context-recovery/SKILL.md` | Auto-invoked skill for context loss detection and recovery |

**Specification**

`plugin/skills/context-recovery/SKILL.md`:

```markdown
---
name: context-recovery
description: Automatically recover previous session context when the user appears to have lost context. Triggers on questions like "what were we doing", "what was I working on", "continue where we left off", resuming after context compaction, or starting a new session that follows a previous one. Also triggers when the conversation appears to have been compacted and the user references earlier work.
---

# Context Recovery Skill

You have detected that the user may need context from a previous session or from
before a context compaction event. Use GlobalContext to recover that context.

## When to Activate

- The user asks "what were we doing?" or similar
- The user references work from a previous session
- The conversation shows signs of compaction (loss of earlier context)
- The user says "continue", "resume", "pick up where we left off"
- A new session started after compaction or clearing

## Recovery Steps

1. First, check if context is available by running:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" last --format markdown
   ```

2. If context is found, present it to the user organized as:
   - **What was being worked on** (the last user prompt and recent context)
   - **Files that were modified** (with file paths)
   - **Key decisions** that were made
   - **Where work left off** (the last state before context loss)

3. If no context is found for the current project, try:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" sessions --limit 5
   ```
   And report what sessions exist.

4. Ask the user if they want to continue from where they left off or start fresh.

## Important Notes

- Do NOT fabricate context. Only present information returned by gc-query.
- If gc-query returns an error or empty result, tell the user honestly.
- Present recovered context as a summary, not a raw dump.
- The recovered context comes from the GlobalContext event store, which captures
  all hook events from previous sessions.
```

**Dependencies**: Task 1 (skills directory must exist).

**Acceptance Test**

1. `plugin/skills/context-recovery/SKILL.md` exists with valid YAML frontmatter.
2. Frontmatter contains `name: context-recovery` and a `description` field.
3. The description contains trigger phrases: "what were we doing", "compaction", "new session", "continue", "resume".
4. The skill references `${CLAUDE_PLUGIN_ROOT}/scripts/gc-query` for context retrieval.
5. Loading the plugin, starting a new session, and asking "what were we working on?" triggers the skill.
6. The skill does not trigger for unrelated queries (e.g., "write a function").

**Estimated Complexity**: S

---

### Task 7: Context Recovery Agent

**Description**

Create an agent markdown file for deep context recovery. Unlike the skill (which provides quick context for common cases), the agent is designed for thorough investigation across sessions: reading events, rebuilding projections, searching across sessions, and producing a comprehensive context recovery report.

Agents are invoked via the Task tool and can perform multi-step autonomous operations. The context recovery agent is for cases where the skill's quick lookup is insufficient -- for example, when the user needs to trace a decision across multiple sessions or find when a specific change was made.

**Files to Create**

| File | Purpose |
|------|---------|
| `plugin/agents/context-investigator.md` | Deep context recovery agent definition |

**Specification**

`plugin/agents/context-investigator.md`:

```markdown
---
name: context-investigator
description: Deep context recovery agent that can search across sessions, trace decision history, find when specific changes were made, and rebuild comprehensive context from the GlobalContext event store. Use when simple context recovery is insufficient.
---

# Context Investigator Agent

You are a context investigation agent with access to the GlobalContext event
store. Your job is to perform deep analysis of session history to answer
questions about past work, trace decisions, and recover detailed context.

## Available Tools

You have access to the following GlobalContext commands:

### List sessions
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" sessions --all-projects --format json
```

### Get specific session context
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" session <session-id> --format json
```

### Search across sessions
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" search "<keyword>" --all-projects
```

### Replay a session's events
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" replay <session-id>
```

### Get raw events from a session
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" events <session-id> --format json
```

### Get last N events
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" tail <session-id> <N>
```

## Investigation Strategy

1. **Start broad**: List recent sessions to understand the timeline.
2. **Narrow down**: Search for keywords related to the user's question.
3. **Deep dive**: Replay specific sessions or read raw events for detail.
4. **Cross-reference**: Follow session chains (previous_session_id) to trace
   work across compaction boundaries.
5. **Synthesize**: Combine findings into a coherent narrative.

## Output Format

Present your findings as a structured report:
- **Timeline**: When relevant work happened (session IDs, timestamps)
- **Key Events**: The specific events that answer the user's question
- **Context**: Surrounding events that provide additional understanding
- **Files Involved**: Which files were touched and how
- **Decisions**: What choices were made and why (if evident from prompts)

## Rules

- Only report what the event store contains. Never fabricate history.
- If a session has been lost or events are missing, note the gap.
- When presenting file changes, show the sequence of operations.
- Keep the report focused on the user's specific question.
```

**Dependencies**: Task 1 (agents directory must exist).

**Acceptance Test**

1. `plugin/agents/context-investigator.md` exists with valid YAML frontmatter.
2. Frontmatter contains `name: context-investigator` and a `description` field.
3. The agent definition lists all available gc-query subcommands with correct invocation syntax.
4. The agent references `${CLAUDE_PLUGIN_ROOT}/scripts/gc-query` for all data access.
5. Loading the plugin exposes the agent as invocable via the Task tool.
6. The agent can be invoked with a question like "When did we decide to use event sourcing?" and it uses gc-query search to find relevant events.

**Estimated Complexity**: S

---

### Task 8: Shared Library Bundling

**Description**

Bundle all shared libraries from `src/lib/` into the plugin's `lib/` directory. This includes both Bash libraries (path resolution, sanitization, atomic writes, UUID generation, timestamps, debug logging) and Node.js modules (projection engine). All library paths must use `${CLAUDE_PLUGIN_ROOT}/lib/` for code references and `~/.claude-context/` (via `$GC_ROOT`) for data references.

The key change from the standalone installation model is that libraries are no longer deployed to `~/.claude-context/lib/`. They live inside the plugin directory and are sourced from there. This means the plugin directory is self-contained for code -- only data lives outside the plugin.

**Files to Create**

| File | Source | Purpose |
|------|--------|---------|
| `plugin/lib/paths.sh` | `src/lib/paths.sh` | Path resolution (GC_ROOT, GC_EVENTS_DIR, etc.) |
| `plugin/lib/sanitize.sh` | `src/lib/sanitize.sh` (from Story 03) | Session ID and project ID sanitization |
| `plugin/lib/atomic_write.sh` | `src/lib/atomic_write.sh` (from Story 03) | Atomic file write with temp+rename |
| `plugin/lib/uuid.sh` | Extracted from `src/capture-event` | UUID v4 generation with fallback chain |
| `plugin/lib/timestamp.sh` | Extracted from `src/capture-event` | ISO 8601 timestamp generation |
| `plugin/lib/debug_log.sh` | `src/lib/debug_log.sh` (from Story 02) | Debug logging with rotation |
| `plugin/lib/session_read.sh` | `src/lib/session_read.sh` (from Story 05) | Per-session session.json read model |
| `plugin/lib/projection_check.sh` | `src/lib/projection-check.sh` (from Story 05) | Projection staleness check |
| `plugin/lib/session_resolve.sh` | `src/lib/session-resolve.sh` (from Story 05) | Session ID resolution helpers |
| `plugin/lib/context_loader.sh` | `src/lib/context-loader.sh` (from Story 05) | Context projection loader |
| `plugin/lib/format_context.sh` | `src/lib/format-context.sh` (from Story 05) | Output formatters (markdown, text, compact, JSON) |
| `plugin/lib/session_chain.sh` | `src/lib/session-chain.sh` (from Story 05) | Cross-session chain resolution |
| `plugin/lib/projection_engine.js` | `src/lib/projection_engine.js` (from Story 04) | Node.js projection engine |
| `plugin/lib/projections/*.js` | `src/lib/projections/*.js` (from Story 04) | Individual projection handlers |

**Specification**

All Bash libraries must be adapted so they resolve their own location via:

```bash
# At the top of each library file
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

And other libraries are sourced relative to `$_LIB_DIR`:

```bash
source "$_LIB_DIR/paths.sh"
source "$_LIB_DIR/sanitize.sh"
```

`paths.sh` remains the canonical path resolver. It sets `$GC_ROOT` from `$CLAUDE_CONTEXT_PATH` or the default. All data paths derive from `$GC_ROOT`. Code paths are relative to `$_LIB_DIR` (which is inside the plugin).

**Important**: the `gc-query` script from Story 05 is also bundled as `plugin/scripts/gc-query`. It sources libraries from `$PLUGIN_ROOT/lib/` instead of `$GC_ROOT/lib/`.

| File | Source | Purpose |
|------|--------|---------|
| `plugin/scripts/gc-query` | `src/gc-query` (from Story 05) | Query CLI entry point |
| `plugin/scripts/project` | `src/project` (from Story 04) | Projection engine CLI |

**Dependencies**: Task 1 (lib directory must exist). Source files from Stories 01-05 must be implementation-ready.

**Acceptance Test**

1. All library files exist in `plugin/lib/`.
2. Each Bash library uses `$_LIB_DIR` for self-location, not hardcoded paths.
3. `source plugin/lib/paths.sh` correctly resolves `$GC_ROOT` from `$CLAUDE_CONTEXT_PATH` or default.
4. `plugin/scripts/capture-event` can source all required libraries from `$PLUGIN_ROOT/lib/`.
5. `plugin/scripts/gc-query` can source all required libraries from `$PLUGIN_ROOT/lib/`.
6. No library file contains hardcoded references to `~/.claude-context/bin/` or `~/.claude-context/lib/`.
7. Node.js projection engine runs correctly when invoked from `plugin/lib/projection_engine.js`.
8. Running `echo '{"session_id":"lib-test"}' | plugin/scripts/gc-hook SessionStarted` works with all libraries sourced from the plugin.

**Estimated Complexity**: L

---

### Task 9: Marketplace Configuration

**Description**

Create the marketplace configuration files required for distributing the plugin via `claude plugin install`. This includes a `marketplace.json` descriptor, a `README.md` for the plugin (describing what it does, how to install, how to use), a `CHANGELOG.md` for version tracking, and a `LICENSE` file.

**Files to Create**

| File | Purpose |
|------|---------|
| `plugin/marketplace.json` | Marketplace distribution descriptor |
| `plugin/README.md` | Plugin documentation (installation, usage, commands) |
| `plugin/CHANGELOG.md` | Version history |
| `plugin/LICENSE` | License file (MIT) |

**Specification**

`plugin/marketplace.json`:

```json
{
  "name": "globalcontext",
  "display_name": "GlobalContext",
  "version": "1.0.0",
  "description": "Event-sourced context store for Claude Code. Captures all session events, builds projections, and enables context recovery after compaction or session changes.",
  "repository": "https://github.com/globalcontext/globalcontext",
  "author": "GlobalContext",
  "license": "MIT",
  "keywords": ["context", "sessions", "event-sourcing", "recovery", "compaction"],
  "categories": ["productivity", "developer-tools"],
  "install": {
    "type": "git",
    "url": "https://github.com/globalcontext/globalcontext.git",
    "path": "plugin"
  },
  "requirements": {
    "jq": ">=1.6",
    "bash": ">=4.0",
    "node": ">=18.0.0"
  }
}
```

`plugin/README.md` content outline:

```
# GlobalContext - Claude Code Plugin

## What It Does
- Captures every hook event from your Claude Code sessions
- Builds projections (timeline, files, decisions, context)
- Recovers context after compaction, session end, or conversation clear
- Automatic context injection when sessions resume

## Installation
claude plugin install globalcontext

## Slash Commands
- /globalcontext:last -- Get context from the most recent session
- /globalcontext:session <id> -- Get context from a specific session
- /globalcontext:sessions -- List all sessions
- /globalcontext:search <keyword> -- Search across sessions
- /globalcontext:replay <session-id> -- Replay a session as a narrative
- /globalcontext:tail <session-id> [N] -- Show last N events
- /globalcontext:events <session-id> -- Raw event access
- /globalcontext:status -- Store health and statistics
- /globalcontext:doctor -- Full system health check

## Automatic Features
- Context recovery skill: auto-triggers when you ask "what were we doing?"
- Context investigator agent: deep cross-session analysis via Task tool
- Auto-init: store is created on first use, no manual setup needed
- All 10 hook events captured automatically

## Configuration
Set CLAUDE_CONTEXT_PATH to customize the data store location:
  export CLAUDE_CONTEXT_PATH=/path/to/custom/store

## Data Location
Event store: ~/.claude-context/ (or $CLAUDE_CONTEXT_PATH)
Plugin code: managed by Claude Code plugin system
```

`plugin/CHANGELOG.md`:

```
# Changelog

## 1.0.0 (2026-02-15)

### Added
- Initial plugin release
- All 10 hook events captured (SessionStart through SessionEnd)
- 9 slash commands for querying the event store
- Context recovery skill (auto-triggered)
- Context investigator agent (deep analysis)
- Auto-init on first use
- CLAUDE_CONTEXT_PATH support for custom store location
```

`plugin/LICENSE`:

Standard MIT license text.

**Dependencies**: Task 1 (plugin directory must exist).

**Acceptance Test**

1. `jq . plugin/marketplace.json` parses without error.
2. `plugin/README.md` exists and documents all 9 slash commands.
3. `plugin/CHANGELOG.md` exists with a 1.0.0 entry.
4. `plugin/LICENSE` exists with MIT license text.
5. The `marketplace.json` `install.path` points to the correct plugin subdirectory.
6. All keywords and categories are valid for the marketplace schema.

**Estimated Complexity**: S

---

### Task 10: Integration Tests

**Description**

Create a comprehensive integration test suite that validates the plugin works end-to-end when loaded by Claude Code. Tests cover plugin loading, hook firing, event capture, command accessibility, auto-initialization, and environment variable overrides.

All tests use a temporary directory for both the plugin install location and the data store (`CLAUDE_CONTEXT_PATH`), ensuring no pollution of the real user environment.

**Files to Create**

| File | Purpose |
|------|---------|
| `tests/06-plugin-integration-test.sh` | Main integration test script |
| `tests/fixtures/06/` | Test fixtures directory |

**Test Cases**

| # | Test Case | Validates |
|---|-----------|-----------|
| 1 | Plugin manifest is valid JSON | Task 1 |
| 2 | hooks.json is valid JSON with all 10 hook events | Task 2 |
| 3 | hooks.json event types match expected mapping | Task 2 |
| 4 | hooks.json async flags are correct (3 sync, 7 async) | Task 2 |
| 5 | hooks.json matchers are correct (5 with ".*", rest without) | Task 2 |
| 6 | gc-hook exits 0 when capture-event succeeds | Task 3 |
| 7 | gc-hook exits 0 when capture-event fails | Task 3 |
| 8 | gc-hook produces zero stdout | Task 3 |
| 9 | gc-hook produces zero stderr (GC_DEBUG unset) | Task 3 |
| 10 | gc-hook passes event type and stdin correctly | Task 3 |
| 11 | Auto-init creates store on first use | Task 4 |
| 12 | Auto-init is idempotent (no error on second run) | Task 4 |
| 13 | Auto-init creates config.json with source=plugin | Task 4 |
| 14 | All 9 command files exist with valid frontmatter | Task 5 |
| 15 | SKILL.md exists with valid frontmatter | Task 6 |
| 16 | Agent markdown exists with valid frontmatter | Task 7 |
| 17 | All library files exist in plugin/lib/ | Task 8 |
| 18 | paths.sh resolves GC_ROOT correctly | Task 8 |
| 19 | capture-event sources libraries from plugin lib/ | Task 8 |
| 20 | marketplace.json is valid JSON | Task 9 |
| 21 | End-to-end: SessionStarted event captures correctly | Tasks 2-4, 8 |
| 22 | End-to-end: ToolCallCompleted event captures correctly | Tasks 2-3, 8 |
| 23 | End-to-end: all 10 event types produce valid event files | Tasks 2-3, 8 |
| 24 | CLAUDE_CONTEXT_PATH override works for all operations | Tasks 3-4 |
| 25 | Plugin loads without errors via --plugin-dir | All |
| 26 | No hardcoded ~/.claude-context/bin/ paths in any script | Task 3, 8 |
| 27 | Scripts work from arbitrary plugin install location | Task 3, 8 |
| 28 | Debug logging (GC_DEBUG=1) writes to log file | Task 3 |
| 29 | gc-query status runs from plugin scripts/ | Task 5, 8 |
| 30 | gc-query doctor runs from plugin scripts/ | Task 5, 8 |

**Specification**

Test script structure:

```bash
#!/usr/bin/env bash
# GlobalContext Plugin Integration Tests

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="$PROJECT_DIR/plugin"

# Temporary test environment
TEST_DIR=$(mktemp -d)
export CLAUDE_CONTEXT_PATH="$TEST_DIR/store"
trap 'rm -rf "$TEST_DIR"' EXIT

PASS=0
FAIL=0

assert() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "[PASS] $desc"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $desc"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "[PASS] $desc"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $desc (expected: $expected, got: $actual)"
    FAIL=$((FAIL + 1))
  fi
}

# ... test cases ...

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

**Dependencies**: All previous tasks (this is the validation pass).

**Acceptance Test**

1. Run `bash tests/06-plugin-integration-test.sh`. All 30 test cases pass.
2. Run on a clean system with no `~/.claude-context/`. All tests pass (uses `CLAUDE_CONTEXT_PATH` for isolation).
3. The test suite cleans up after itself (temp directory removed on exit).
4. The test suite completes in under 30 seconds.
5. Each test case reports PASS or FAIL with a clear description.

**Estimated Complexity**: L

---

## File Summary

All file paths are relative to `/home/meywd/GlobalContext/`.

| File | Action | Task(s) |
|------|--------|---------|
| `plugin/.claude-plugin/plugin.json` | Create | 1 |
| `plugin/hooks/hooks.json` | Create | 2 |
| `plugin/scripts/gc-hook` | Create | 3, 4 |
| `plugin/scripts/capture-event` | Create | 3 |
| `plugin/scripts/gc-init` | Create | 4 |
| `plugin/scripts/gc-query` | Create | 5, 8 |
| `plugin/scripts/project` | Create | 8 |
| `plugin/commands/last.md` | Create | 5 |
| `plugin/commands/session.md` | Create | 5 |
| `plugin/commands/sessions.md` | Create | 5 |
| `plugin/commands/search.md` | Create | 5 |
| `plugin/commands/replay.md` | Create | 5 |
| `plugin/commands/tail.md` | Create | 5 |
| `plugin/commands/events.md` | Create | 5 |
| `plugin/commands/status.md` | Create | 5 |
| `plugin/commands/doctor.md` | Create | 5 |
| `plugin/skills/context-recovery/SKILL.md` | Create | 6 |
| `plugin/agents/context-investigator.md` | Create | 7 |
| `plugin/lib/paths.sh` | Create | 8 |
| `plugin/lib/sanitize.sh` | Create | 8 |
| `plugin/lib/atomic_write.sh` | Create | 8 |
| `plugin/lib/uuid.sh` | Create | 8 |
| `plugin/lib/timestamp.sh` | Create | 8 |
| `plugin/lib/debug_log.sh` | Create | 8 |
| `plugin/lib/session_read.sh` | Create | 8 |
| `plugin/lib/projection_check.sh` | Create | 8 |
| `plugin/lib/session_resolve.sh` | Create | 8 |
| `plugin/lib/context_loader.sh` | Create | 8 |
| `plugin/lib/format_context.sh` | Create | 8 |
| `plugin/lib/session_chain.sh` | Create | 8 |
| `plugin/lib/projection_engine.js` | Create | 8 |
| `plugin/lib/projections/*.js` | Create | 8 |
| `plugin/marketplace.json` | Create | 9 |
| `plugin/README.md` | Create | 9 |
| `plugin/CHANGELOG.md` | Create | 9 |
| `plugin/LICENSE` | Create | 9 |
| `tests/06-plugin-integration-test.sh` | Create | 10 |

---

## Implementation Order (Recommended)

| Phase | Tasks | Milestone |
|-------|-------|-----------|
| **Phase 1: Scaffold** | 1 | Plugin directory structure exists |
| **Phase 2: Core Infrastructure** | 2, 8 | Hooks defined, libraries bundled |
| **Phase 3: Script Adaptation** | 3, 4 | Scripts work from plugin root, auto-init works |
| **Phase 4: User Interface** | 5, 6, 7 | Commands, skill, and agent defined |
| **Phase 5: Distribution** | 9 | Marketplace config, README, LICENSE |
| **Phase 6: Validation** | 10 | All integration tests pass |

### Parallelization Notes

- Tasks 2 and 8 can be done in parallel (hooks.json is pure data; library bundling is file copying + path adaptation).
- Tasks 5, 6, and 7 can be done in parallel (commands, skill, and agent are independent markdown files).
- Task 9 can be done in parallel with Tasks 5, 6, 7 (marketplace config is independent).
- Task 10 must wait for all other tasks.

---

## Complexity Summary

| Complexity | Count | Tasks |
|------------|-------|-------|
| S (Small) | 4 | 1, 4, 6, 7, 9 |
| M (Medium) | 3 | 2, 3, 5 |
| L (Large) | 2 | 8, 10 |

**Estimated total effort**: Approximately 6 days for a single developer, or 3-4 days with two developers working in parallel on independent tasks.

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `${CLAUDE_PLUGIN_ROOT}` not expanded in hooks.json commands | Medium | High (all hooks broken) | Test with actual plugin loading; fall back to relative paths from script location |
| Plugin directory is read-only (managed by Claude Code) | Medium | Medium (gc-init cannot write to plugin dir) | All data writes go to `~/.claude-context/`, never to the plugin directory |
| Claude Code plugin format changes before release | Low | High (restructure needed) | Pin to documented plugin spec version; keep structure minimal |
| Library sourcing fails due to path resolution | Medium | High (capture fails) | Every script resolves `PLUGIN_ROOT` independently via `$(dirname "$0")/..`; integration tests validate |
| Large payload through plugin hooks exceeds timeout | Low | Low (single event lost) | Same 5-second timeout as standalone; documented as acceptable |
| Skill triggers too aggressively on unrelated queries | Medium | Low (annoying but not broken) | Narrow the description keywords; users can disable the skill |
| Node.js not available for projection engine | Low | Medium (projections fail) | `gc-query` degrades gracefully; Bash-only projections as fallback (Story 04) |
| CLAUDE_CONTEXT_PATH not propagated to hook subprocess | Low | High (data written to wrong location) | Hooks inherit parent env; integration test verifies this explicitly |

---

## Key Design Decisions

1. **Code in plugin, data in home directory**: The plugin directory (`${CLAUDE_PLUGIN_ROOT}`) holds all scripts and libraries. The data store (`~/.claude-context/`) holds events, projections, and config. This separation allows the plugin to be installed in a read-only location while the data store remains writable.

2. **Auto-init replaces manual install**: The SessionStart hook creates the data store on first use. No manual `gc-install` step is needed. This is a single `[ -d ]` check per session -- effectively free.

3. **hooks.json replaces gc-install-hooks**: Hook registration is declarative (JSON file in the plugin) rather than imperative (installation script modifying `~/.claude/settings.json`). The plugin system handles merging.

4. **Slash commands wrap gc-query**: Each gc-query subcommand becomes a slash command. The command markdown files instruct Claude on how to invoke the underlying script and present results.

5. **Skill for automatic recovery, agent for deep investigation**: The skill handles the common case (quick context recovery on "what were we doing?"). The agent handles the complex case (cross-session investigation, decision tracing).

6. **Self-locating scripts**: Every script resolves its own location via `$(dirname "$0")` and derives `PLUGIN_ROOT` from there. No hardcoded paths. This makes the plugin work regardless of where Claude Code installs it.

7. **Backward compatibility**: The plugin can coexist with a standalone installation. If both exist, the plugin hooks fire alongside any hooks registered in `settings.json`. The data store is shared -- events from both paths land in the same `~/.claude-context/events/` directory.

---

## Notes for Implementation

1. **Test with real Claude Code**: The integration test script (Task 10) validates structure and scripts in isolation. Manual testing with `claude --plugin-dir ./plugin` is essential to verify hook firing, command exposure, skill triggering, and agent availability.

2. **`${CLAUDE_PLUGIN_ROOT}` expansion**: Verify that Claude Code expands this variable in hooks.json command strings before passing them to the shell. If not, the scripts must resolve their own location without relying on this variable.

3. **Permissions**: All scripts in `plugin/scripts/` must be executable (`chmod +x`). The plugin packaging step should ensure this. Git tracks the executable bit, so committing with `+x` is sufficient.

4. **No npm install**: The Node.js projection engine uses only Node.js built-ins (no npm dependencies), consistent with the project's design decision. The `.js` files are bundled directly.

5. **Existing Story 00 scripts**: `gc-install`, `gc-uninstall`, and `gc-doctor` from Story 00 remain available for users who prefer manual installation. The plugin is an alternative distribution method, not a replacement for the manual path. Both install to the same data store.
