# Task 05: Command Files (gc-query as Slash Commands)

**Story**: 06-plugin-packaging
**Estimated Complexity**: M (Medium)
**Dependencies**: [Task 01 - Plugin Manifest and Directory Scaffold](/home/meywd/GlobalContext/tasks/06-plugin-packaging/01-plugin-manifest-scaffold.md) (commands directory must exist)

---

## Description

Create markdown command files for each `gc-query` subcommand, making them available as `/globalcontext:<name>` slash commands within Claude Code. Each command file describes what it does, its arguments, and invokes the underlying `gc-query` script (or inline logic) to produce the result.

Commands are markdown files in the `commands/` directory. The filename (minus `.md`) becomes the slash command name, namespaced under the plugin name: `/globalcontext:last`, `/globalcontext:search`, etc.

---

## Files to Create

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

---

## Specification

Each command markdown file follows this structure:

```markdown
---
name: <command-name>
description: <one-line description>
---

<Instructions for Claude on how to execute this command>
```

### `plugin/commands/last.md`

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

### `plugin/commands/search.md`

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

### `plugin/commands/doctor.md`

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

---

## Acceptance Tests

1. All 9 command files exist in `plugin/commands/`.
2. Each file has valid YAML frontmatter with `name` and `description` fields.
3. Each file references `${CLAUDE_PLUGIN_ROOT}/scripts/gc-query` in its execution section.
4. Loading the plugin with `claude --plugin-dir ./plugin` exposes all 9 commands as `/globalcontext:<name>`.
5. Running `/globalcontext:status` in a Claude Code session invokes `gc-query status`.
6. Each command file documents its arguments and expected output format.
