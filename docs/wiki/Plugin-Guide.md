# Plugin Guide

GlobalContext can be installed as a Claude Code plugin for one-command installation and automatic hook configuration.

## Table of Contents

- [Installation](#installation)
- [Slash Commands](#slash-commands)
- [Skills](#skills)
- [Agents](#agents)
- [Plugin Directory Structure](#plugin-directory-structure)
- [Configuration](#configuration)
- [Comparison: Plugin vs Manual](#comparison-plugin-vs-manual)

## Installation

### Install from Plugin Marketplace

```bash
claude plugin install globalcontext
```

This automatically:
- Creates `~/.claude-context/` store
- Installs all hook handlers
- Registers slash commands
- Enables context-recovery skill and agent

### Verify Installation

```bash
# Check plugin status
claude plugin list

# Test with slash command
/globalcontext:status
```

### Uninstall

```bash
# Remove plugin (preserves event data)
claude plugin uninstall globalcontext

# Remove plugin and all data
claude plugin uninstall globalcontext --purge
```

## Slash Commands

The plugin provides 9 slash commands namespaced under `globalcontext`. All commands are wrappers around `gc-query` subcommands.

### Command Reference

| Slash Command | Equivalent CLI | Description |
|---------------|----------------|-------------|
| `/globalcontext:last` | `gc-query last` | Get context from most recent session |
| `/globalcontext:session` | `gc-query session <id>` | Get context from specific session |
| `/globalcontext:sessions` | `gc-query sessions` | List all sessions |
| `/globalcontext:search` | `gc-query search <keyword>` | Search events across sessions |
| `/globalcontext:replay` | `gc-query replay <id>` | Replay session as narrative |
| `/globalcontext:tail` | `gc-query tail <id> [N]` | Show last N events |
| `/globalcontext:events` | `gc-query events <id>` | Raw event access |
| `/globalcontext:status` | `gc-query status` | Show store health |
| `/globalcontext:doctor` | `gc-query doctor` | Run health checks |

### /globalcontext:last

Retrieve context from the most recent session in the current project.

**Usage**:
```
/globalcontext:last
```

**Optional Arguments**:
- `--format json` - Return raw JSON instead of markdown
- `--include-parent` - Include context from parent sessions (session chain)

**Output**:
- Session metadata (when started, model, project directory)
- All user prompts
- Key tool calls and results
- Files modified
- Last state (what you were working on)
- Compaction markers

**Example**:
```
User: /globalcontext:last

Claude: Here's the context from your last session (started 2026-02-14 at 10:00):

# Context: Session abc123

## Session Info
- Started: 2026-02-14T10:00:00Z
- Model: claude-opus-4-6
- Project: /home/user/my-project
- Events: 142

## Conversation
### Prompt 1
> Fix the failing test in auth.test.js that checks token expiry

Actions taken:
1. Read auth.test.js (45 lines)
2. Edit auth.test.js (replaced assertion)
3. Bash: npm test -> All 12 tests passed

## Last State
Working on: Fixing auth token expiry test and verifying the fix
Last action: Bash npm test -> All 12 tests passed
```

### /globalcontext:session

Get context from a specific session by ID.

**Usage**:
```
/globalcontext:session <session-id>
```

**Arguments**:
- `<session-id>` - Full session ID or unique prefix

**Optional Arguments**:
- `--format json` - Return raw JSON
- `--include-parent` - Include parent session context

**Example**:
```
/globalcontext:session abc123
/globalcontext:session abc  # prefix matching
```

### /globalcontext:sessions

List all recorded sessions for the current project.

**Usage**:
```
/globalcontext:sessions
```

**Optional Arguments**:
- `--all-projects` - List sessions across all projects
- `--limit <N>` - Limit to N most recent sessions
- `--format json` - Return raw JSON

**Output**:
- Session ID
- Started/ended timestamps
- Event count
- Last prompt preview
- Status

**Example**:
```
User: /globalcontext:sessions --limit 5

Claude: Here are the 5 most recent sessions:

| Session ID | Started | Events | Last Prompt |
|------------|---------|--------|-------------|
| abc123 | 2026-02-14 10:00 | 142 | Fix the failing test... |
| def456 | 2026-02-13 15:30 | 89 | Add authentication to API |
| ghi789 | 2026-02-12 09:00 | 203 | Refactor database schema |
```

### /globalcontext:search

Search across sessions for events matching a keyword.

**Usage**:
```
/globalcontext:search <keyword>
```

**Arguments**:
- `<keyword>` - Search term (plain text or regex)

**Optional Arguments**:
- `--all-projects` - Search all projects
- `--type <event-type>` - Filter by event type
- `--limit <N>` - Max results
- `--case-sensitive` - Case-sensitive search

**Example**:
```
/globalcontext:search authentication
/globalcontext:search "bug fix" --type UserPromptReceived
/globalcontext:search error --all-projects
```

### /globalcontext:replay

Replay a session as a human-readable narrative.

**Usage**:
```
/globalcontext:replay <session-id>
```

**Arguments**:
- `<session-id>` - Session to replay

**Optional Arguments**:
- `--from <seq>` - Start from sequence number
- `--to <seq>` - End at sequence number
- `--format markdown` - Output as markdown

**Example**:
```
/globalcontext:replay abc123
/globalcontext:replay abc123 --from 10 --to 50
```

### /globalcontext:tail

Show the last N events from a session.

**Usage**:
```
/globalcontext:tail <session-id> [N]
```

**Arguments**:
- `<session-id>` - Session ID
- `N` - Number of events (default: 20)

**Optional Arguments**:
- `--format json` - Return as JSON array

**Example**:
```
/globalcontext:tail abc123 10
/globalcontext:tail latest 50
```

### /globalcontext:events

Raw event access for debugging or custom analysis.

**Usage**:
```
/globalcontext:events <session-id>
```

**Arguments**:
- `<session-id>` - Session ID

**Optional Arguments**:
- `--from <seq>` - Start from sequence
- `--to <seq>` - End at sequence
- `--type <event-type>` - Filter by type
- `--format json` - JSON array (default: jsonl)

**Example**:
```
/globalcontext:events abc123 --type ToolCallCompleted
/globalcontext:events abc123 --from 10 --to 20
```

### /globalcontext:status

Show store health and statistics for the current project.

**Usage**:
```
/globalcontext:status
```

**Optional Arguments**:
- `--all-projects` - Status for all projects
- `--format json` - Return raw JSON

**Output**:
- Store location
- Project ID
- Session count
- Total events
- Disk usage
- Latest session info
- Projection status

**Example**:
```
User: /globalcontext:status

Claude: GlobalContext Status
==================
Store: ~/.claude-context
Project: my-project-a3f7b2
Sessions: 15
Total events: 2,847
Disk usage: 45.2 MB
Latest session: abc123 (started: 2026-02-14T10:00:00Z)
Projections: 15 (0 stale)
```

### /globalcontext:doctor

Run comprehensive health checks on the event store.

**Usage**:
```
/globalcontext:doctor
```

**Optional Arguments**:
- `--all-projects` - Check all projects
- `--format json` - Return raw JSON

**Checks**:
- Store directory structure
- Sequence gaps
- Corrupt JSON files
- Orphaned lock files
- Session metadata consistency
- Projection staleness
- Disk space

**Output**:
- Overall health status
- Detailed findings
- Recommendations

**Example**:
```
User: /globalcontext:doctor

Claude: GlobalContext Health Check
========================
Status: Healthy

Checks Performed:
✓ Store directory structure
✓ Event file integrity (2,847 events checked)
✓ Sequence numbering (no gaps)
✓ Session metadata consistency
✓ Projection freshness (15 sessions)
✓ Disk space (45.2 MB / 500 GB available)

No issues found.
```

## Skills

The plugin provides one skill for context recovery workflows.

### context-recovery Skill

**Purpose**: Automatically recover and inject context from previous sessions.

**Invocation**:
The skill is automatically triggered when Claude Code detects a session start after compaction, or manually via:

```
/skill context-recovery
```

**Behavior**:
1. Detect if current session follows a compaction or session change
2. Locate previous session via `projections/{project-id}/latest` symlink
3. Load context projection
4. Format as markdown for LLM consumption
5. Inject into current conversation

**Configuration**:
Defined in `skills/context-recovery/skill.json`:

```json
{
  "name": "context-recovery",
  "description": "Automatically recover context from previous sessions",
  "trigger": "SessionStart",
  "condition": "source in ['compact', 'resume']",
  "script": "${CLAUDE_PLUGIN_ROOT}/skills/context-recovery/recover.sh"
}
```

**Use Cases**:
- Resume work after compaction
- Continue from previous day's session
- Recover from crash

## Agents

The plugin provides one agent for investigating session history.

### context-investigator Agent

**Purpose**: Interactive agent for exploring session history, searching events, and analyzing patterns.

**Invocation**:
```
@context-investigator
```

**Capabilities**:
- Search across sessions
- Compare sessions
- Identify patterns
- Generate reports
- Answer questions about past work

**Example Interaction**:
```
User: @context-investigator When did I last work on the authentication module?

Agent: Searching across all sessions for authentication-related work...

Found 3 sessions with authentication work:

1. Session abc123 (2026-02-14):
   - Fixed failing test in auth.test.js
   - Modified auth.ts, auth.test.js
   - 142 events, no errors

2. Session def456 (2026-02-13):
   - Added JWT token validation
   - Modified auth.ts, token.ts
   - 89 events, 1 error (npm test failed)

3. Session ghi789 (2026-02-10):
   - Initial authentication setup
   - Created auth.ts, auth.test.js
   - 67 events, no errors

Most recent: Session abc123 on 2026-02-14 at 10:00.
```

**Configuration**:
Defined in `agents/context-investigator/agent.json`:

```json
{
  "name": "context-investigator",
  "description": "Investigate session history and answer questions about past work",
  "script": "${CLAUDE_PLUGIN_ROOT}/agents/context-investigator/investigate.sh",
  "tools": ["gc-query", "grep", "jq"]
}
```

## Plugin Directory Structure

The plugin is organized as follows:

```
plugin/
├── .claude-plugin/
│   └── plugin.json                # Plugin manifest
├── hooks/
│   └── hooks.json                 # Hook configuration
├── commands/
│   ├── last.md                    # /globalcontext:last
│   ├── session.md                 # /globalcontext:session
│   ├── sessions.md                # /globalcontext:sessions
│   ├── search.md                  # /globalcontext:search
│   ├── replay.md                  # /globalcontext:replay
│   ├── tail.md                    # /globalcontext:tail
│   ├── events.md                  # /globalcontext:events
│   ├── status.md                  # /globalcontext:status
│   └── doctor.md                  # /globalcontext:doctor
├── skills/
│   └── context-recovery/
│       ├── skill.json             # Skill definition
│       └── recover.sh             # Recovery script
├── agents/
│   └── context-investigator/
│       ├── agent.json             # Agent definition
│       └── investigate.sh         # Investigation script
├── scripts/
│   ├── gc-hook                    # Hook wrapper
│   ├── gc-query                   # Query CLI
│   └── gc-init                    # Initialization
├── lib/
│   └── (shared libraries)         # Reusable Bash functions
├── README.md                      # Plugin documentation
├── LICENSE                        # MIT license
└── marketplace.json               # Marketplace metadata
```

## Configuration

### Plugin Manifest

`.claude-plugin/plugin.json`:

```json
{
  "name": "globalcontext",
  "version": "1.0.0",
  "description": "Event-sourced context store for Claude Code sessions",
  "author": "GlobalContext",
  "homepage": "https://github.com/globalcontext/globalcontext",
  "license": "MIT",
  "claude_code_version": ">=1.0.0"
}
```

### Hooks Configuration

All 10 hooks are declared in `hooks/hooks.json`:

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
    ]
    // ... (8 more hooks)
  }
}
```

### Environment Variables

The plugin sets these variables:

| Variable | Value | Purpose |
|----------|-------|---------|
| `CLAUDE_PLUGIN_ROOT` | Plugin directory path | Locate scripts and libraries |
| `CLAUDE_CONTEXT_PATH` | `~/.claude-context` | Store location (overridable) |

## Comparison: Plugin vs Manual

### Plugin Installation

**Pros**:
- One-command install: `claude plugin install globalcontext`
- Automatic hook registration
- Slash commands available immediately
- Auto-initialization on first use
- Marketplace updates

**Cons**:
- Requires Claude Code 1.0+
- Namespaced commands (`/globalcontext:` prefix)

### Manual Installation

**Pros**:
- Works without plugin system
- Direct CLI access (`gc-query` instead of `/globalcontext:query`)
- Full control over hook configuration

**Cons**:
- Manual `gc-install` required
- Manual hook installation (`gc-install-hooks install`)
- Manual `~/.claude/settings.json` edits
- Manual PATH configuration
- No automatic updates

### Feature Comparison

| Feature | Plugin | Manual |
|---------|--------|--------|
| Event capture | Yes | Yes |
| Projections | Yes | Yes |
| Query commands | Slash commands | CLI commands |
| Hook installation | Automatic | Manual |
| Store initialization | Automatic | Manual |
| Context recovery skill | Yes | No |
| Context investigator agent | Yes | No |
| Updates | Marketplace | Manual |

### Migration

#### Plugin to Manual

```bash
# Uninstall plugin (keep data)
claude plugin uninstall globalcontext

# Install manually
cd ~/path/to/globalcontext
./src/bin/gc-install
./src/bin/gc-install-hooks install
```

#### Manual to Plugin

```bash
# Remove manual installation
gc-uninstall --keep-data
gc-install-hooks uninstall

# Install plugin
claude plugin install globalcontext
```

Event data is preserved in both directions (stored in `~/.claude-context/`).

## First-Use Experience

### New Installation

1. Install plugin:
   ```bash
   claude plugin install globalcontext
   ```

2. Start Claude Code session

3. SessionStart hook fires, auto-initializes store:
   ```
   ~/.claude-context/events/
   ~/.claude-context/projections/
   ~/.claude-context/bin/
   ~/.claude-context/config.json
   ```

4. Work normally. Events captured automatically.

5. Query context anytime:
   ```
   /globalcontext:status
   /globalcontext:last
   ```

### After Compaction

1. Claude Code compacts context

2. PreCompact hook captures state

3. New session starts

4. context-recovery skill detects compaction

5. Previous context loaded automatically

6. LLM receives full context, can continue seamlessly

### After Session End

1. Start new Claude Code session

2. Run `/globalcontext:last`

3. See what you were working on

4. Continue from where you left off

## Troubleshooting

### Plugin Not Found

```bash
# Verify plugin marketplace connection
claude plugin list

# Install from GitHub (if marketplace unavailable)
claude plugin install github.com/globalcontext/globalcontext
```

### Slash Commands Not Working

```bash
# Check plugin installation
claude plugin list | grep globalcontext

# Reinstall
claude plugin uninstall globalcontext
claude plugin install globalcontext
```

### Hooks Not Firing

```bash
# Check hook configuration
cat ~/.claude/plugins/globalcontext/hooks/hooks.json

# Run doctor
/globalcontext:doctor

# Check logs (if available)
tail -f ~/.claude/logs/hooks.log
```

### No Sessions Found

```bash
# Check store exists
ls ~/.claude-context/events/

# Check current project ID
/globalcontext:status

# Initialize manually if needed
~/.claude-context/bin/gc-init
```

## Best Practices

### Daily Workflow

Start of day:
```
/globalcontext:last
```

After compaction:
```
# Context loaded automatically by skill
# Or manually: /globalcontext:last --include-parent
```

Check what happened:
```
/globalcontext:sessions --limit 5
```

### Project Switching

```
# Switch to new project directory
cd /home/user/other-project

# Check project sessions
/globalcontext:sessions

# Get last context for this project
/globalcontext:last
```

### Debugging

```
# Health check
/globalcontext:doctor

# Check recent events
/globalcontext:tail latest 20

# Search for errors
/globalcontext:search error --type ToolCallFailed
```

### Maintenance

```
# Check disk usage
/globalcontext:status

# If disk space is a concern
gc-query store-size
# Consider archiving old sessions (manual export to backup)
```

## Related Documentation

- [CLI Reference](CLI-Reference.md) - Detailed command documentation
- [Architecture](Architecture.md) - How the plugin system integrates
- [Event Types](Event-Types.md) - What hooks capture
- [Projections](Projections.md) - How queries work