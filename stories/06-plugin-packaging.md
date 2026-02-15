# Story 06: Claude Code Plugin Packaging

## Overview

This story packages GlobalContext as a Claude Code plugin so users can install it with `claude plugin install globalcontext` instead of running the manual `gc-install` script from Story 00. The plugin approach replaces the manual installation and hook registration workflows (Stories 00 and 02) while leaving the underlying event capture, storage, projection, and query systems (Stories 01, 03, 04, 05) unchanged.

Claude Code plugins are self-contained directories with a `.claude-plugin/plugin.json` manifest. They support hooks, slash commands, agents, and MCP servers. By packaging GlobalContext as a plugin, users get one-command installation, automatic hook registration, namespaced slash commands, and marketplace-based distribution.

### Relationship to Other Stories

| Story | Relationship |
|-------|-------------|
| Story 00 (Installation) | **Replaced** -- the plugin system handles installation, upgrade, and uninstall. `gc-install` and `gc-uninstall` are no longer needed. |
| Story 01 (Event Capture) | **Unchanged** -- `capture-event` script is bundled in the plugin and works identically. |
| Story 02 (Hook Integration) | **Replaced** -- hooks are declared in `hooks/hooks.json` instead of injected into `~/.claude/settings.json`. The `gc-install-hooks` script and manual `settings.json` manipulation are eliminated. |
| Story 03 (Storage Layer) | **Unchanged** -- `gc-init` logic moves into the SessionStart hook for auto-initialization. |
| Story 04 (Projection Engine) | **Unchanged** -- projection scripts are bundled in the plugin. |
| Story 05 (Context Recovery) | **Unchanged** -- gc-query subcommands become plugin slash commands. The context-recovery agent is new. |

### What This Story Covers (and What It Does Not)

| Concern | Covered Here | Covered Elsewhere |
|---------|:---:|:---:|
| Plugin manifest (plugin.json) | yes | -- |
| Hook declaration via hooks/hooks.json | yes | -- |
| Slash commands wrapping gc-query | yes | -- |
| Context-recovery agent | yes | -- |
| Auto-initialization on first use | yes | -- |
| Plugin directory layout | yes | -- |
| Marketplace distribution (marketplace.json) | yes | -- |
| Event capture script (capture-event) | bundled | Story 01 |
| Storage layer (gc-init) | init logic reused | Story 03 |
| Projection engine | bundled | Story 04 |
| gc-query implementation | bundled | Story 05 |

---

## Scope

### In Scope

- Plugin manifest file (`.claude-plugin/plugin.json`)
- Hook declaration file (`hooks/hooks.json`) mapping all 10 hook events
- Slash commands exposing gc-query subcommands under the `globalcontext` namespace
- Context-recovery agent for automatic context restoration
- Auto-initialization of `~/.claude-context/` on first SessionStart
- Complete plugin directory layout
- Marketplace distribution configuration (`marketplace.json`)
- Coexistence documentation (what this replaces, what it does not)
- First-use experience flow

### Out of Scope (Non-Goals)

- MCP server integration -- GlobalContext does not expose an MCP server
- Interactive prompts or GUI elements
- Windows support
- Auto-update beyond what the plugin marketplace provides
- Changes to the event capture, storage, projection, or query implementations themselves
- Package manager distribution (apt, brew, npm) -- the plugin system is the distribution mechanism

---

## Requirements

### 1. Plugin Manifest

The plugin manifest at `.claude-plugin/plugin.json` declares the plugin identity, version, components, and metadata for the Claude Code plugin system.

#### Manifest Contents

```json
{
  "name": "globalcontext",
  "version": "1.0.0",
  "description": "Event-sourced context store that captures everything from Claude Code sessions. Never lose context to compaction, session ends, or conversation clears.",
  "author": "GlobalContext Contributors",
  "license": "MIT",
  "keywords": ["context", "event-sourcing", "session", "recovery", "history"],
  "repository": "https://github.com/globalcontext/globalcontext",
  "engines": {
    "claude-code": ">=1.0.0"
  },
  "components": {
    "hooks": "hooks/hooks.json",
    "commands": "commands/",
    "agents": "agents/"
  }
}
```

#### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Plugin identifier, used in `claude plugin install <name>` and command namespacing (`/globalcontext:*`) |
| `version` | string (semver) | Plugin version, used for upgrade detection |
| `description` | string | Human-readable description shown in marketplace and `claude plugin list` |
| `author` | string | Author or organization name |
| `license` | string | SPDX license identifier |
| `keywords` | string[] | Search terms for marketplace discovery |
| `repository` | string | Git repository URL for source and issue tracking |
| `engines` | object | Minimum Claude Code version required |
| `components` | object | Paths to plugin component directories/files, relative to the plugin root |

#### Acceptance Criteria

- [ ] `.claude-plugin/plugin.json` exists and is valid JSON (parseable by `jq .` and `JSON.parse`)
- [ ] `name` is `"globalcontext"` (lowercase, no spaces)
- [ ] `version` follows semver format (major.minor.patch)
- [ ] `components.hooks` points to `hooks/hooks.json`
- [ ] `components.commands` points to `commands/`
- [ ] `components.agents` points to `agents/`
- [ ] All paths in `components` are relative to the plugin root directory
- [ ] The manifest contains no absolute paths

---

### 2. Hook Migration

All 10 hook events from Story 02 are declared in `hooks/hooks.json` using the plugin hook format. This replaces the manual injection of hooks into `~/.claude/settings.json`.

#### hooks/hooks.json Structure

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/bin/gc-hook SessionStarted",
        "async": false,
        "timeout": 5000,
        "matcher": ""
      }
    ],
    "UserPromptSubmit": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/bin/gc-hook UserPromptReceived",
        "async": false,
        "timeout": 5000
      }
    ],
    "PreToolUse": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/bin/gc-hook ToolCallRequested",
        "async": true,
        "timeout": 5000,
        "matcher": ".*"
      }
    ],
    "PostToolUse": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/bin/gc-hook ToolCallCompleted",
        "async": true,
        "timeout": 5000,
        "matcher": ".*"
      }
    ],
    "PostToolUseFailure": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/bin/gc-hook ToolCallFailed",
        "async": true,
        "timeout": 5000,
        "matcher": ".*"
      }
    ],
    "SubagentStart": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/bin/gc-hook AgentSpawned",
        "async": true,
        "timeout": 5000,
        "matcher": ".*"
      }
    ],
    "SubagentStop": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/bin/gc-hook AgentCompleted",
        "async": true,
        "timeout": 5000,
        "matcher": ".*"
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/bin/gc-hook TurnCompleted",
        "async": true,
        "timeout": 5000
      }
    ],
    "PreCompact": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/bin/gc-hook CompactionTriggered",
        "async": false,
        "timeout": 5000
      }
    ],
    "SessionEnd": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/bin/gc-hook SessionEnded",
        "async": true,
        "timeout": 5000
      }
    ]
  }
}
```

#### Key Changes from Story 02

| Aspect | Story 02 (Manual) | Story 06 (Plugin) |
|--------|-------------------|-------------------|
| Hook location | `~/.claude/settings.json` | `hooks/hooks.json` in plugin dir |
| Script paths | `~/.claude-context/bin/gc-hook` (tilde) | `${CLAUDE_PLUGIN_ROOT}/bin/gc-hook` |
| Installation | `gc-install-hooks install` merges into settings.json | Automatic on `claude plugin install` |
| Uninstallation | `gc-install-hooks uninstall` removes from settings.json | Automatic on `claude plugin uninstall` |
| User hook coexistence | Manual array merging in settings.json | Plugin system handles isolation automatically |
| Backup of settings.json | Created by gc-install-hooks | Not needed; plugin hooks are separate from user settings |

#### Complete Hook Event Mapping

| Hook Event | GlobalContext Event Type | Sync | Matcher | Rationale |
|------------|--------------------------|------|---------|-----------|
| SessionStart | SessionStarted | sync | `""` | Session boundary; must capture before any other events. Also triggers store auto-initialization. |
| UserPromptSubmit | UserPromptReceived | sync | (none) | Exact user prompts; must capture before LLM processes them |
| PreToolUse | ToolCallRequested | async | `".*"` | High frequency; captures intent before tool runs |
| PostToolUse | ToolCallCompleted | async | `".*"` | High frequency; captures results after tool runs |
| PostToolUseFailure | ToolCallFailed | async | `".*"` | Error tracking; captures tool failures |
| SubagentStart | AgentSpawned | async | `".*"` | Sub-agent lifecycle tracking |
| SubagentStop | AgentCompleted | async | `".*"` | Sub-agent result capture |
| Stop | TurnCompleted | async | (none) | Turn boundary markers |
| PreCompact | CompactionTriggered | sync | (none) | Critical -- last chance before context loss |
| SessionEnd | SessionEnded | async | (none) | Session lifecycle closure |

#### gc-hook Wrapper Script (Plugin Version)

The `gc-hook` wrapper at `${CLAUDE_PLUGIN_ROOT}/bin/gc-hook` is functionally identical to Story 02 but uses `CLAUDE_PLUGIN_ROOT` for locating `capture-event`:

```bash
#!/usr/bin/env bash
# GlobalContext plugin hook wrapper v1
EVENT_TYPE="${1:?Missing event type}"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
STORE_DIR="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"

# Auto-initialize store on first use (Requirement 5)
if [ ! -d "$STORE_DIR/events" ]; then
  "$PLUGIN_ROOT/bin/gc-init" 2>/dev/null || true
fi

# Capture event in a subshell to isolate all side effects
("$PLUGIN_ROOT/bin/capture-event" "$EVENT_TYPE" </dev/stdin >/dev/null 2>/dev/null) || true

exit 0
```

#### Acceptance Criteria

- [ ] `hooks/hooks.json` exists and is valid JSON
- [ ] All 10 hook events are declared with correct event types, async flags, matchers, and timeouts
- [ ] All hook commands use `${CLAUDE_PLUGIN_ROOT}` prefix, not tilde paths or absolute paths
- [ ] Sync/async classification matches Story 02 exactly: SessionStart, UserPromptSubmit, PreCompact are sync; all others are async
- [ ] Matcher configuration matches Story 02 exactly: tool-related hooks use `".*"`, others omit or use `""`
- [ ] All timeouts are 5000ms
- [ ] The `gc-hook` wrapper always exits 0 regardless of errors
- [ ] The `gc-hook` wrapper produces no stdout output
- [ ] The `gc-hook` wrapper suppresses all stderr from `capture-event`
- [ ] Hooks do NOT modify `~/.claude/settings.json` -- the plugin system manages them

---

### 3. Commands (Slash Commands)

Plugin commands expose gc-query subcommands as slash commands namespaced under `globalcontext`. Users invoke them as `/globalcontext:last`, `/globalcontext:sessions`, etc.

Each command is defined as a file in the `commands/` directory with a companion JSON descriptor.

#### Command Inventory

| Slash Command | gc-query Equivalent | Description |
|---------------|---------------------|-------------|
| `/globalcontext:last` | `gc-query last` | Retrieve context from the most recent session |
| `/globalcontext:session` | `gc-query session <id>` | Retrieve context from a specific session |
| `/globalcontext:sessions` | `gc-query sessions` | List all captured sessions |
| `/globalcontext:search` | `gc-query search <keyword>` | Search across sessions for keywords |
| `/globalcontext:replay` | `gc-query replay <id>` | Replay events as a narrative |
| `/globalcontext:tail` | `gc-query tail <id> [N]` | Show last N events from a session |
| `/globalcontext:events` | `gc-query events <id>` | Raw event access |
| `/globalcontext:status` | `gc-query status` | Show store health and statistics |
| `/globalcontext:doctor` | `gc-query doctor` | Run health checks on the event store |

#### Command Descriptor Format

Each command has a JSON descriptor file in the `commands/` directory. Example for `last.json`:

```json
{
  "name": "last",
  "description": "Retrieve context from the most recent session for this project. Outputs a markdown summary of what happened, files modified, decisions made, and where work left off.",
  "args": [
    {
      "name": "format",
      "description": "Output format: json, markdown, text, or compact",
      "required": false,
      "default": "markdown"
    },
    {
      "name": "include-parent",
      "description": "Follow session chain and include parent session context",
      "required": false,
      "type": "boolean"
    }
  ]
}
```

#### Command Implementation

Each command is a shell script that delegates to `gc-query`:

```bash
#!/usr/bin/env bash
# /globalcontext:last command
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
STORE_DIR="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"

export CLAUDE_CONTEXT_PATH="$STORE_DIR"

exec "$PLUGIN_ROOT/bin/gc-query" last "$@"
```

#### Acceptance Criteria

- [ ] All 9 commands have both a JSON descriptor and a shell script in `commands/`
- [ ] Command scripts delegate to `gc-query` without reimplementing logic
- [ ] Command scripts use `${CLAUDE_PLUGIN_ROOT}` for locating `gc-query`
- [ ] Command scripts use `${CLAUDE_CONTEXT_PATH}` (or default `~/.claude-context`) for the store path
- [ ] All command scripts are executable (`chmod 755`)
- [ ] Command descriptors include accurate descriptions and argument definitions
- [ ] Arguments from gc-query flags are exposed as command arguments
- [ ] `/globalcontext:last` produces markdown output by default
- [ ] `/globalcontext:sessions` produces text output by default
- [ ] All commands work when invoked from any working directory

---

### 4. Context-Recovery Agent

The plugin includes a context-recovery agent that Claude can invoke automatically when it detects context loss (e.g., after compaction, when the user says "get last context", or when conversation history seems incomplete).

#### Agent Definition

```json
{
  "name": "context-recovery",
  "description": "Recovers context from previous sessions when context has been lost due to compaction, clearing, or starting a new session. Invoke this agent when the user asks about previous work, when context seems incomplete, or when the session started after compaction.",
  "trigger": "Invoke when the user says things like 'get last context', 'what was I working on?', 'continue where we left off', 'recover context', or when you detect context loss after compaction.",
  "instructions_file": "agents/context-recovery/instructions.md",
  "tools": ["Bash"]
}
```

#### Agent Instructions (agents/context-recovery/instructions.md)

The agent instructions tell Claude how to use gc-query to recover context:

```markdown
# Context Recovery Agent

You are a context recovery agent for the GlobalContext plugin. Your job is to
retrieve and present context from previous Claude Code sessions.

## What You Do

1. Run the gc-query command to retrieve context from the most recent session
2. Present the recovered context to the user in a clear, actionable format
3. Optionally follow session chains to provide deeper history

## Commands Available

All commands use the gc-query tool located at `${CLAUDE_PLUGIN_ROOT}/bin/gc-query`.

### Recover Last Session Context

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/gc-query" last --format markdown
```

### Recover with Parent Session Chain

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/gc-query" last --format markdown --include-parent
```

### List Recent Sessions

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/gc-query" sessions --limit 10
```

### Recover a Specific Session

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/gc-query" session <session-id> --format markdown
```

## How to Present Context

When you recover context, present it as a briefing:

1. Start with what the user was working on (from "What Was Being Worked On")
2. Summarize key actions taken (from "Actions Taken")
3. List files that were modified (from "Files Modified")
4. Highlight any key decisions (from "Key Decisions")
5. End with where work left off and what to do next (from "Where We Left Off")

## When to Act

- If the session just started after compaction, recover context immediately
- If the user asks about previous work, recover the relevant session
- If context seems incomplete, offer to recover from the previous session
- Do NOT recover context if the user explicitly wants a fresh start
```

#### Acceptance Criteria

- [ ] Agent definition file exists at `agents/context-recovery/agent.json`
- [ ] Agent instructions file exists at `agents/context-recovery/instructions.md`
- [ ] Agent has access to the Bash tool for running gc-query commands
- [ ] Agent instructions reference `${CLAUDE_PLUGIN_ROOT}/bin/gc-query` for command paths
- [ ] Agent can recover context from the latest session
- [ ] Agent can follow session chains with `--include-parent`
- [ ] Agent can list and query specific sessions
- [ ] Agent instructions describe when to act and when not to act
- [ ] Agent does not interfere with sessions that do not need context recovery

---

### 5. Store Auto-Initialization

The plugin must auto-initialize the `~/.claude-context/` store on first use without requiring the user to run `gc-init` manually. Initialization happens in the SessionStart hook, triggered by the first event capture attempt.

#### Initialization Logic

The `gc-init` script is bundled in the plugin at `${CLAUDE_PLUGIN_ROOT}/bin/gc-init`. The `gc-hook` wrapper calls it before `capture-event` if the store does not exist (see Requirement 2, gc-hook wrapper).

#### gc-init Behavior (Plugin Context)

```bash
#!/usr/bin/env bash
# GlobalContext store initialization (plugin version)
# Creates the store directory structure if it does not exist.
# Called by gc-hook on first use. Also callable directly.

STORE_DIR="${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}"

# Idempotent: safe to call multiple times
mkdir -p "$STORE_DIR/events" 2>/dev/null || exit 0
mkdir -p "$STORE_DIR/projections" 2>/dev/null || exit 0

# Create config.json if it does not exist
if [ ! -f "$STORE_DIR/config.json" ]; then
  cat > "$STORE_DIR/config.json" <<EOF
{
  "version": "1.0.0",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "store_path": "$STORE_DIR",
  "plugin_managed": true
}
EOF
  chmod 600 "$STORE_DIR/config.json" 2>/dev/null || true
fi

# Set directory permissions
chmod 700 "$STORE_DIR" 2>/dev/null || true
chmod 700 "$STORE_DIR/events" 2>/dev/null || true
chmod 700 "$STORE_DIR/projections" 2>/dev/null || true

exit 0
```

#### First-Use Detection

The `gc-hook` wrapper checks for the existence of `$STORE_DIR/events` as the initialization sentinel. If the directory does not exist, `gc-init` is called. This check is a single `[ ! -d ... ]` test -- negligible overhead on subsequent invocations.

#### Store Location

| Environment Variable | Default | Purpose |
|---------------------|---------|---------|
| `CLAUDE_CONTEXT_PATH` | `~/.claude-context` | Override the store location |

The store is always at `~/.claude-context/` (or `$CLAUDE_CONTEXT_PATH`), never inside the plugin directory. Plugin directories are cached/copied by Claude Code, making them unsuitable for mutable data.

#### Acceptance Criteria

- [ ] `gc-init` script exists at `${CLAUDE_PLUGIN_ROOT}/bin/gc-init` and is executable
- [ ] On first SessionStart hook, `~/.claude-context/` is created with `events/`, `projections/`, and `config.json`
- [ ] `gc-init` is idempotent: running it on an existing store does not modify or delete anything
- [ ] Directory permissions are set to 700 (user-only)
- [ ] `config.json` is created with `"plugin_managed": true` to distinguish from manual installation
- [ ] `config.json` is never overwritten if it already exists
- [ ] Initialization failures do not prevent the hook from completing (exit 0)
- [ ] The `CLAUDE_CONTEXT_PATH` environment variable is respected
- [ ] Initialization completes in under 100ms
- [ ] No user interaction is required for initialization

---

### 6. Plugin Directory Layout

The complete plugin directory structure, showing where all files are located relative to the plugin root.

#### Directory Tree

```
globalcontext/                          # Plugin root
|
+-- .claude-plugin/
|   +-- plugin.json                     # Plugin manifest (Requirement 1)
|
+-- hooks/
|   +-- hooks.json                      # Hook declarations for all 10 events (Requirement 2)
|
+-- commands/
|   +-- last.json                       # /globalcontext:last descriptor
|   +-- last.sh                         # /globalcontext:last implementation
|   +-- session.json                    # /globalcontext:session descriptor
|   +-- session.sh                      # /globalcontext:session implementation
|   +-- sessions.json                   # /globalcontext:sessions descriptor
|   +-- sessions.sh                     # /globalcontext:sessions implementation
|   +-- search.json                     # /globalcontext:search descriptor
|   +-- search.sh                       # /globalcontext:search implementation
|   +-- replay.json                     # /globalcontext:replay descriptor
|   +-- replay.sh                       # /globalcontext:replay implementation
|   +-- tail.json                       # /globalcontext:tail descriptor
|   +-- tail.sh                         # /globalcontext:tail implementation
|   +-- events.json                     # /globalcontext:events descriptor
|   +-- events.sh                       # /globalcontext:events implementation
|   +-- status.json                     # /globalcontext:status descriptor
|   +-- status.sh                       # /globalcontext:status implementation
|   +-- doctor.json                     # /globalcontext:doctor descriptor
|   +-- doctor.sh                       # /globalcontext:doctor implementation
|
+-- agents/
|   +-- context-recovery/
|       +-- agent.json                  # Agent descriptor (Requirement 4)
|       +-- instructions.md             # Agent instructions
|
+-- bin/
|   +-- gc-hook                         # Hook wrapper script
|   +-- gc-init                         # Store initialization script
|   +-- capture-event                   # Event capture script (from Story 01)
|   +-- gc-query                        # Query interface (from Story 05)
|   +-- project                         # Projection engine (from Story 04)
|
+-- lib/
|   +-- paths.sh                        # Shared path helpers (Bash)
|   +-- paths.js                        # Shared path helpers (Node.js)
|   +-- projections/                    # Projection builder modules (Node.js)
|       +-- timeline.js
|       +-- files-touched.js
|       +-- decisions.js
|       +-- context.js
|
+-- marketplace.json                    # Marketplace distribution config (Requirement 7)
+-- VERSION                             # Version string (e.g., "1.0.0")
+-- LICENSE                             # License file
```

#### Path References

All scripts within the plugin use `${CLAUDE_PLUGIN_ROOT}` to reference other plugin files:

| Purpose | Path Expression |
|---------|----------------|
| capture-event script | `${CLAUDE_PLUGIN_ROOT}/bin/capture-event` |
| gc-query script | `${CLAUDE_PLUGIN_ROOT}/bin/gc-query` |
| gc-init script | `${CLAUDE_PLUGIN_ROOT}/bin/gc-init` |
| gc-hook wrapper | `${CLAUDE_PLUGIN_ROOT}/bin/gc-hook` |
| paths.sh helpers | `${CLAUDE_PLUGIN_ROOT}/lib/paths.sh` |
| paths.js helpers | `${CLAUDE_PLUGIN_ROOT}/lib/paths.js` |
| Projection modules | `${CLAUDE_PLUGIN_ROOT}/lib/projections/` |
| Event store (data) | `${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}` |

#### Data vs. Code Separation

| Location | Contains | Mutable | Managed By |
|----------|----------|---------|------------|
| `${CLAUDE_PLUGIN_ROOT}/` | Plugin code, scripts, configs | No (read-only after install) | Plugin system (cached/copied) |
| `~/.claude-context/` | Events, projections, config.json | Yes (append-only events) | GlobalContext scripts |

#### Acceptance Criteria

- [ ] All files listed in the directory tree exist in the plugin
- [ ] All scripts in `bin/` are executable (`chmod 755`)
- [ ] No files reference absolute paths -- all use `${CLAUDE_PLUGIN_ROOT}` or `${CLAUDE_CONTEXT_PATH}`
- [ ] The `lib/` directory contains path helpers for both Bash and Node.js
- [ ] The `lib/projections/` directory contains all projection builder modules
- [ ] The plugin root does not contain any mutable data files (events, projections)
- [ ] The `VERSION` file contains the current version string matching `plugin.json`
- [ ] The plugin passes validation: `claude plugin validate` (if available)

---

### 7. Marketplace Distribution

The plugin is distributed via the Claude Code plugin marketplace. A `marketplace.json` file in the repository root provides the metadata needed for marketplace listing and `claude plugin install globalcontext`.

#### marketplace.json

```json
{
  "name": "globalcontext",
  "display_name": "GlobalContext",
  "version": "1.0.0",
  "description": "Event-sourced context store for Claude Code. Never lose context to compaction, clearing, or session boundaries.",
  "long_description": "GlobalContext captures every event from your Claude Code sessions -- tool calls, prompts, agent activity, compactions -- and stores them in an append-only event store. When context is lost, it can be recovered instantly. Search across sessions, replay what happened, and maintain perfect continuity across compactions and restarts.",
  "author": "GlobalContext Contributors",
  "license": "MIT",
  "repository": "https://github.com/globalcontext/globalcontext",
  "homepage": "https://github.com/globalcontext/globalcontext",
  "keywords": ["context", "event-sourcing", "session", "recovery", "history", "compaction"],
  "categories": ["productivity", "developer-tools"],
  "requirements": {
    "os": ["linux", "darwin"],
    "dependencies": {
      "bash": ">=4.0",
      "jq": ">=1.5",
      "node": ">=18.0"
    }
  },
  "screenshots": [],
  "changelog": {
    "1.0.0": "Initial release: event capture, projections, context recovery, slash commands"
  }
}
```

#### Installation Flow

```
User: claude plugin install globalcontext
  |
  v
Claude Code fetches plugin from marketplace (git clone)
  |
  v
Claude Code copies plugin to its plugin cache directory
  |
  v
Claude Code reads .claude-plugin/plugin.json
  |
  v
Claude Code registers hooks from hooks/hooks.json
  |
  v
Claude Code registers commands from commands/
  |
  v
Claude Code registers agents from agents/
  |
  v
Plugin is active. CLAUDE_PLUGIN_ROOT is set to the cached plugin path.
  |
  v
User starts a session -> SessionStart hook fires -> gc-init runs -> store created
  |
  v
Events are captured. Commands are available. Agent is ready.
```

#### Upgrade Flow

```
User: claude plugin update globalcontext
  |
  v
Claude Code fetches the latest version from marketplace
  |
  v
Claude Code replaces the cached plugin directory with the new version
  |
  v
Hooks, commands, and agents are re-registered from the new version
  |
  v
Event store at ~/.claude-context/ is untouched (data persists across upgrades)
```

#### Uninstall Flow

```
User: claude plugin uninstall globalcontext
  |
  v
Claude Code removes the cached plugin directory
  |
  v
Hooks, commands, and agents are deregistered
  |
  v
Event store at ~/.claude-context/ is preserved (user data is never deleted by uninstall)
  |
  v
User can reinstall later and all previous events are still available
```

#### Acceptance Criteria

- [ ] `marketplace.json` exists in the plugin root and is valid JSON
- [ ] `marketplace.json` specifies `os` requirements as `["linux", "darwin"]`
- [ ] `marketplace.json` specifies dependency requirements (bash, jq, node)
- [ ] `marketplace.json` version matches `plugin.json` version and `VERSION` file
- [ ] The plugin can be installed via `claude plugin install globalcontext` (or the equivalent marketplace flow)
- [ ] Plugin upgrade replaces code but preserves the event store
- [ ] Plugin uninstall removes code but preserves the event store
- [ ] The repository contains all files needed for marketplace distribution

---

### 8. Coexistence and Migration

This section defines how the plugin approach relates to the manual installation from Stories 00 and 02, and what migration looks like for existing users.

#### What the Plugin Replaces

| Story 00 Component | Plugin Equivalent | Status |
|---------------------|-------------------|--------|
| `gc-install` orchestration script | `claude plugin install globalcontext` | Replaced |
| Prerequisites check | `marketplace.json` requirements | Replaced |
| Source placement to `~/.local/share/globalcontext/` | Plugin cache managed by Claude Code | Replaced |
| `gc-init` delegation | Auto-initialization in SessionStart hook | Replaced |
| `gc-install-hooks` delegation | `hooks/hooks.json` declarative hooks | Replaced |
| `gc-query doctor` verification | `/globalcontext:doctor` command | Replaced |
| `gc-uninstall` | `claude plugin uninstall globalcontext` | Replaced |
| First-run summary output | Plugin install confirmation + first SessionStart | Replaced |
| `GLOBALCONTEXT_HOME` env var | No longer needed (plugin cache manages code location) | Removed |

| Story 02 Component | Plugin Equivalent | Status |
|---------------------|-------------------|--------|
| `gc-install-hooks install` | Automatic via `hooks/hooks.json` | Replaced |
| `gc-install-hooks uninstall` | Automatic via `claude plugin uninstall` | Replaced |
| `gc-install-hooks validate` | `/globalcontext:doctor` | Replaced |
| settings.json backup management | Not needed (plugin hooks are separate) | Removed |
| Manual hook merging with user hooks | Automatic isolation by plugin system | Replaced |

#### What Remains Unchanged

| Component | Location | Notes |
|-----------|----------|-------|
| `capture-event` (Story 01) | Bundled in plugin `bin/` | Same script, different path |
| Event envelope schema (Story 01) | N/A (data format) | Identical |
| Storage layout (Story 03) | `~/.claude-context/` | Identical location and structure |
| Projection engine (Story 04) | Bundled in plugin `lib/` | Same modules, different path |
| gc-query implementation (Story 05) | Bundled in plugin `bin/` | Same script, different path |
| `CLAUDE_CONTEXT_PATH` env var | Still supported | Same behavior |

#### Migration from Manual Installation

Users who previously installed GlobalContext via `gc-install` (Story 00) can migrate to the plugin:

```
1. Uninstall manual hooks:
   ~/.claude-context/bin/gc-install-hooks uninstall

2. Install the plugin:
   claude plugin install globalcontext

3. Verify:
   /globalcontext:doctor

4. (Optional) Remove manual installation artifacts:
   rm -rf ~/.local/share/globalcontext/
   rm -f ~/.claude-context/bin/gc-hook
   rm -f ~/.claude-context/bin/gc-install-hooks
   rm -f ~/.claude-context/bin/gc-install
   rm -f ~/.claude-context/bin/gc-uninstall
```

The event store at `~/.claude-context/events/` and projections at `~/.claude-context/projections/` are preserved and immediately accessible to the plugin.

#### Dual Installation Prevention

If both the manual installation and the plugin are active, hooks would fire twice for every event, causing duplicate events. The `gc-hook` wrapper in the plugin version checks for this:

```bash
# Detect dual installation
if [ -f "$HOME/.claude-context/bin/gc-hook" ] && [ "$PLUGIN_ROOT/bin/gc-hook" != "$HOME/.claude-context/bin/gc-hook" ]; then
  echo "[gc-hook] WARN: Both plugin and manual GlobalContext installations detected." >&2
  echo "[gc-hook] WARN: Run: ~/.claude-context/bin/gc-install-hooks uninstall" >&2
fi
```

This warning is logged to stderr (suppressed by the hook wrapper in normal operation) but will appear in diagnostic logs.

#### Acceptance Criteria

- [ ] The plugin uses the same event store location (`~/.claude-context/`) as the manual installation
- [ ] Existing events captured by the manual installation are fully accessible via plugin commands
- [ ] The plugin does not duplicate any scripts at `~/.claude-context/bin/` -- scripts are only in the plugin cache
- [ ] `CLAUDE_CONTEXT_PATH` env var is still respected by all plugin scripts
- [ ] Migration documentation is included in the plugin repository
- [ ] Dual installation is detected and a warning is logged
- [ ] `config.json` created by the plugin includes `"plugin_managed": true`
- [ ] `config.json` from a manual installation is not overwritten by the plugin

---

### 9. First-Use Experience

This describes what happens when a user installs the plugin and starts their first Claude Code session.

#### Installation

```
$ claude plugin install globalcontext
Installing globalcontext v1.0.0...
  Fetching from marketplace...
  Registering hooks (10 events)...
  Registering commands (9 commands)...
  Registering agents (1 agent)...
Done. GlobalContext is now active.

Available commands:
  /globalcontext:last      - Recover context from your last session
  /globalcontext:sessions  - List all captured sessions
  /globalcontext:status    - Check store health and statistics
  /globalcontext:doctor    - Run diagnostics

Context capture will begin automatically on your next session.
```

#### First Session

```
1. User starts: claude
   |
   v
2. SessionStart hook fires
   |
   v
3. gc-hook detects ~/.claude-context/events/ does not exist
   |
   v
4. gc-hook calls gc-init -> creates store structure
   |
   v
5. gc-hook calls capture-event SessionStarted -> first event written
   |
   v
6. Session proceeds normally, all events are captured
   |
   v
7. User can run /globalcontext:status to verify:

   GlobalContext Status
   Store path:      ~/.claude-context/
   Total sessions:  1
   Total events:    N (depends on activity)
   Disk usage:      <size>
   Latest session:  <session-id>
```

#### Second Session (After Compaction or Restart)

```
1. User starts: claude
   |
   v
2. SessionStart hook fires
   |
   v
3. gc-hook detects store already exists (skips init)
   |
   v
4. capture-event stores SessionStarted event
   |
   v
5. User says: "get last context" or "what was I working on?"
   |
   v
6. Claude invokes the context-recovery agent or runs /globalcontext:last
   |
   v
7. Full context from the previous session is presented
   |
   v
8. User continues working with full awareness of previous session
```

#### Acceptance Criteria

- [ ] Plugin installation completes without requiring any manual steps
- [ ] The first SessionStart hook triggers store auto-initialization
- [ ] The first session captures events correctly
- [ ] `/globalcontext:status` works after the first session
- [ ] Context recovery works from the second session onward
- [ ] No error messages appear during normal first-use flow
- [ ] The user does not need to know about `~/.claude-context/`, `gc-init`, or any internal details

---

## Edge Cases

### E-1: CLAUDE_PLUGIN_ROOT Not Set

**Scenario**: The `CLAUDE_PLUGIN_ROOT` environment variable is not set (e.g., running scripts directly outside of the plugin context).

**Expected behavior**: Scripts fall back to deriving the plugin root from their own location:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
```

This allows scripts to work both inside the plugin context (where `CLAUDE_PLUGIN_ROOT` is set) and when invoked directly for testing or debugging.

---

### E-2: Plugin Installed but jq Missing

**Scenario**: The user installs the plugin via the marketplace, but `jq` is not installed on their system.

**Expected behavior**: The `marketplace.json` `requirements.dependencies` field declares `jq >= 1.5`. If the Claude Code plugin system checks requirements before installation, the install is blocked with a message. If requirements are not enforced at install time, the first hook invocation will fail silently (capture-event detects missing jq, logs to stderr, exits 0). Events are lost until jq is installed, but the session is not disrupted.

The `/globalcontext:doctor` command detects this and reports:

```
[doctor] jq ............. NOT FOUND    FAIL
[doctor]   Install jq:
[doctor]     Ubuntu/Debian: sudo apt install jq
[doctor]     macOS: brew install jq
```

---

### E-3: Plugin Cache Relocated

**Scenario**: Claude Code copies the plugin to a different cache directory on upgrade or reinstall. The `CLAUDE_PLUGIN_ROOT` value changes.

**Expected behavior**: All scripts use `${CLAUDE_PLUGIN_ROOT}` at runtime, never hardcoded paths. The event store at `~/.claude-context/` is unaffected because it lives outside the plugin directory. Scripts continue to work regardless of where the plugin cache is located.

---

### E-4: Manual and Plugin Installations Coexist

**Scenario**: A user has both the manual installation (Story 00) and the plugin installed. Hooks from both fire on every event.

**Expected behavior**: Every event is captured twice (once by the manual hook pointing to `~/.claude-context/bin/gc-hook`, once by the plugin hook pointing to `${CLAUDE_PLUGIN_ROOT}/bin/gc-hook`). The flock mechanism assigns two consecutive sequence numbers for each event, resulting in duplicate events. The `gc-hook` wrapper logs a warning to stderr about the dual installation. The `/globalcontext:doctor` command detects duplicate events (events with identical timestamps and data but different sequence numbers) and reports the issue with remediation instructions.

---

### E-5: Plugin Uninstall and Reinstall

**Scenario**: User uninstalls the plugin, then reinstalls it later.

**Expected behavior**: Uninstall removes the plugin cache and deregisters hooks, commands, and agents. The event store at `~/.claude-context/` is untouched. On reinstall, the plugin picks up the existing event store. All previous sessions, events, and projections are immediately accessible. The `gc-init` auto-initialization check sees the store already exists and skips initialization.

---

### E-6: Custom Store Location via CLAUDE_CONTEXT_PATH

**Scenario**: User sets `CLAUDE_CONTEXT_PATH=/mnt/data/claude-context` in their shell environment before starting Claude Code.

**Expected behavior**: All plugin scripts (gc-hook, gc-init, capture-event, gc-query, commands) read `CLAUDE_CONTEXT_PATH` and use it as the store location. The SessionStart hook initializes the store at the custom path. Commands and the agent query from the custom path. The behavior is identical to the default path, just at a different location.

---

### E-7: bash < 4.0 on macOS

**Scenario**: macOS ships with bash 3.2. The user has not installed a newer bash.

**Expected behavior**: Same as Story 00 edge case E-1. The `marketplace.json` declares `bash >= 4.0` as a requirement. If enforced at install time, the user is warned. If not enforced, scripts that require bash 4+ features (associative arrays, `${var,,}`) will fail. The `gc-hook` wrapper is written to be bash 3.2-compatible for maximum safety (it is a thin wrapper that does not use bash 4+ features), so event capture still works. Only `gc-query` and projection building may require bash 4+ or Node.js.

---

### E-8: Large Number of Sessions (1000+)

**Scenario**: A prolific user has accumulated over 1000 sessions across multiple projects.

**Expected behavior**: The plugin commands that list or scan sessions (`/globalcontext:sessions`, `/globalcontext:search`, `/globalcontext:status`) have default limits (50, 20, N/A respectively) to prevent excessive output. The event store structure (per-project directories) means that most operations are scoped to the current project, not all sessions. Cross-project operations with `--all-projects` may be slower but have a 5-second performance target even at scale.

---

## Non-Goals

This story explicitly does NOT cover:

- **MCP server integration** -- GlobalContext does not expose an MCP server. All interactions are via hooks, commands, and agents.
- **Skills** -- While the plugin system supports skills (auto-invoked by Claude), GlobalContext uses agents instead, which provide more control over when context recovery is triggered.
- **Plugin settings UI** -- There is no plugin-specific settings interface. Configuration is via `config.json` and environment variables.
- **Cloud sync of events** -- The event store is local. Cloud sync is a future feature.
- **Plugin-level authentication** -- No API keys, tokens, or credentials are needed.
- **Changes to capture-event, gc-query, or projection logic** -- These are implemented in Stories 01, 04, and 05. This story packages them.
- **Backwards compatibility with Story 00/02 manual approach** -- Migration is one-way (manual to plugin). The plugin does not generate `gc-install-hooks` configurations.

---

## Technical Specifications

### File Locations

| File | Path (relative to plugin root) | Purpose |
|------|-------------------------------|---------|
| Plugin manifest | `.claude-plugin/plugin.json` | Plugin identity and component registration |
| Hook declarations | `hooks/hooks.json` | All 10 hook event handlers |
| Command descriptors | `commands/*.json` | Slash command metadata |
| Command scripts | `commands/*.sh` | Slash command implementations |
| Agent descriptor | `agents/context-recovery/agent.json` | Agent metadata |
| Agent instructions | `agents/context-recovery/instructions.md` | Agent behavior instructions |
| Hook wrapper | `bin/gc-hook` | Thin wrapper invoking capture-event |
| Store initializer | `bin/gc-init` | Creates ~/.claude-context/ structure |
| Event capture | `bin/capture-event` | Write-side event capture (Story 01) |
| Query interface | `bin/gc-query` | Read-side query tool (Story 05) |
| Projection engine | `bin/project` | Projection builder (Story 04) |
| Path helpers (Bash) | `lib/paths.sh` | Shared path computation |
| Path helpers (Node) | `lib/paths.js` | Shared path computation |
| Projection modules | `lib/projections/*.js` | Projection builders |
| Marketplace config | `marketplace.json` | Distribution metadata |
| Version file | `VERSION` | Version string |

### Environment Variables

| Variable | Default | Purpose | Used By |
|----------|---------|---------|---------|
| `CLAUDE_PLUGIN_ROOT` | (set by Claude Code) | Absolute path to the plugin directory | All plugin scripts |
| `CLAUDE_CONTEXT_PATH` | `$HOME/.claude-context` | Override the event store location | gc-hook, gc-init, capture-event, gc-query, commands |

### Dependencies

| Dependency | Minimum Version | Purpose | Hard/Soft |
|------------|----------------|---------|-----------|
| `bash` | 4.0+ | Script interpreter | Hard |
| `jq` | 1.5+ | JSON parsing and construction | Hard |
| `node` | 18.0+ | Projection engine, gc-query | Hard |
| `flock` | any | File-based exclusive locking | Soft (fallback to unlocked writes) |
| `uuidgen` | any | UUID v4 generation | Soft (fallback chain) |
| `sha256sum` or `shasum` | any | Project ID derivation | Soft (one of the two required) |

### Exit Codes

| Script | Exit Code | Meaning |
|--------|-----------|---------|
| `gc-hook` | 0 | Always (plugin contract: hooks never fail) |
| `gc-init` | 0 | Always (initialization failure is silent) |
| `capture-event` | 0 | Always (capture failure is silent) |
| `gc-query` | 0 | Success |
| `gc-query` | 1 | General error |
| `gc-query` | 2 | Invalid arguments |
| `gc-query` | 3 | Not found |
| Command scripts | (same as gc-query) | Pass-through from gc-query |

---

## Testing Plan

### Unit Tests

| Test | Description |
|------|-------------|
| T-01 | `.claude-plugin/plugin.json` is valid JSON with all required fields |
| T-02 | `hooks/hooks.json` is valid JSON with all 10 hook events declared |
| T-03 | All hook commands reference `${CLAUDE_PLUGIN_ROOT}` (no hardcoded paths) |
| T-04 | All command descriptors (`.json`) are valid JSON with required fields |
| T-05 | All command scripts (`.sh`) are executable and exit without error when passed `--help` |
| T-06 | `gc-hook` exits 0 when `capture-event` is missing |
| T-07 | `gc-hook` exits 0 when `capture-event` crashes |
| T-08 | `gc-hook` produces no stdout output |
| T-09 | `gc-hook` produces no stderr output (suppressed) |
| T-10 | `gc-hook` calls `gc-init` when store does not exist |
| T-11 | `gc-hook` skips `gc-init` when store already exists |
| T-12 | `gc-init` creates store structure with correct permissions |
| T-13 | `gc-init` is idempotent (running twice produces same state) |
| T-14 | `gc-init` does not overwrite existing `config.json` |
| T-15 | Agent descriptor is valid JSON with required fields |
| T-16 | `VERSION` file content matches `plugin.json` version |
| T-17 | `marketplace.json` version matches `plugin.json` version |

### Integration Tests

| Test | Description |
|------|-------------|
| T-18 | Fresh plugin installation creates no store (deferred to first hook) |
| T-19 | First SessionStart hook creates store and captures event |
| T-20 | Subsequent hooks capture events without re-initializing store |
| T-21 | `/globalcontext:last` returns context after events are captured |
| T-22 | `/globalcontext:sessions` lists captured sessions |
| T-23 | `/globalcontext:status` reports accurate statistics |
| T-24 | `/globalcontext:doctor` passes all checks after normal usage |
| T-25 | Plugin works with custom `CLAUDE_CONTEXT_PATH` |
| T-26 | Plugin works when `CLAUDE_PLUGIN_ROOT` is a different directory than original install |
| T-27 | Plugin upgrade preserves all event data at `~/.claude-context/` |
| T-28 | Plugin uninstall and reinstall preserves all event data |
| T-29 | All 10 hooks fire and capture events correctly |
| T-30 | Context-recovery agent can retrieve and present previous session context |

### Manual Verification

| Test | Description |
|------|-------------|
| M-01 | Install plugin via `claude plugin install`, start session, verify events are captured |
| M-02 | Run `/globalcontext:status` in a session, verify output |
| M-03 | End session, start new session, run `/globalcontext:last`, verify context recovery |
| M-04 | Trigger compaction, verify automatic context injection via SessionStart hook |
| M-05 | Run `/globalcontext:doctor`, verify all checks pass |
| M-06 | Migrate from manual installation to plugin, verify existing events are accessible |
| M-07 | Uninstall plugin, verify `~/.claude-context/` is preserved |
| M-08 | Reinstall plugin after uninstall, verify previous events are accessible |
| M-09 | Test on macOS with Homebrew bash, verify plugin works |
| M-10 | Test with `CLAUDE_CONTEXT_PATH` set to a custom directory |

---

## Implementation Notes

1. **CLAUDE_PLUGIN_ROOT is critical**: Every script must use `${CLAUDE_PLUGIN_ROOT}` for code references and `${CLAUDE_CONTEXT_PATH:-$HOME/.claude-context}` for data references. Never mix these. Plugin directories are cached/copied by Claude Code and may change location.

2. **No npm install**: The plugin must work with zero npm dependencies. Node.js scripts use only built-in modules (`fs`, `path`, `crypto`, `readline`). This is consistent with the existing design.

3. **gc-hook must be bash 3.2 compatible**: Since it is the entry point for all hooks and macOS ships with bash 3.2, the gc-hook wrapper must avoid bash 4+ features. The capture-event script and gc-query can require bash 4+ since they do heavier processing.

4. **Idempotent auto-initialization**: The `gc-init` call in `gc-hook` must be safe to call on every SessionStart. The `[ ! -d "$STORE_DIR/events" ]` guard makes this a single directory existence check on the fast path (subsequent invocations).

5. **Command scripts are thin wrappers**: Each command script should be 5-10 lines that set up environment variables and `exec` into `gc-query`. Do not duplicate gc-query logic in command scripts.

6. **The agent is advisory, not mandatory**: The context-recovery agent provides a structured way for Claude to recover context, but users can also run `/globalcontext:last` directly. The agent adds value by knowing when to offer recovery proactively.

7. **Plugin vs. manual installation scripts**: The plugin bundles the same `capture-event`, `gc-query`, and `project` scripts from Stories 01, 04, and 05. The only scripts that change are `gc-hook` (uses `CLAUDE_PLUGIN_ROOT` instead of tilde paths) and `gc-init` (simplified for auto-initialization). The `gc-install`, `gc-uninstall`, and `gc-install-hooks` scripts from Stories 00 and 02 are not included in the plugin.

8. **Testing without the marketplace**: During development, the plugin can be installed locally with `claude plugin install --path ./globalcontext` (or equivalent local install command) without publishing to the marketplace.

---

## Definition of Done

- [ ] `.claude-plugin/plugin.json` exists with valid metadata and component paths
- [ ] `hooks/hooks.json` declares all 10 hook events with correct sync/async, matchers, and timeouts
- [ ] All 9 slash commands are implemented with descriptors and scripts in `commands/`
- [ ] Context-recovery agent is defined with descriptor and instructions in `agents/`
- [ ] `gc-hook` wrapper uses `${CLAUDE_PLUGIN_ROOT}`, always exits 0, and auto-initializes the store
- [ ] `gc-init` creates `~/.claude-context/` structure idempotently
- [ ] All scripts use `${CLAUDE_PLUGIN_ROOT}` for code and `${CLAUDE_CONTEXT_PATH}` for data
- [ ] `marketplace.json` is complete and valid
- [ ] `VERSION` matches `plugin.json` version and `marketplace.json` version
- [ ] Plugin works on Linux (bash 5.x) and macOS (bash 3.2 for gc-hook, 5.x for other scripts)
- [ ] No npm dependencies
- [ ] Existing events from manual installations are accessible after migration
- [ ] Plugin uninstall preserves the event store
- [ ] All unit tests (T-01 through T-17) pass
- [ ] All integration tests (T-18 through T-30) pass
- [ ] Manual verification (M-01 through M-10) confirms end-to-end functionality
