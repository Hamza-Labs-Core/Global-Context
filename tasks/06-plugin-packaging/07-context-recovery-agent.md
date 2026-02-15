# Task 07: Context Recovery Agent

**Story**: 06-plugin-packaging
**Estimated Complexity**: S (Small)
**Dependencies**: [Task 01 - Plugin Manifest and Directory Scaffold](/home/meywd/GlobalContext/tasks/06-plugin-packaging/01-plugin-manifest-scaffold.md) (agents directory must exist)

---

## Description

Create an agent markdown file for deep context recovery. Unlike the skill (which provides quick context for common cases), the agent is designed for thorough investigation across sessions: reading events, rebuilding projections, searching across sessions, and producing a comprehensive context recovery report.

Agents are invoked via the Task tool and can perform multi-step autonomous operations. The context recovery agent is for cases where the skill's quick lookup is insufficient -- for example, when the user needs to trace a decision across multiple sessions or find when a specific change was made.

---

## Files to Create

| File | Purpose |
|------|---------|
| `plugin/agents/context-investigator.md` | Deep context recovery agent definition |

---

## Specification

### `plugin/agents/context-investigator.md`

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

---

## Acceptance Tests

1. `plugin/agents/context-investigator.md` exists with valid YAML frontmatter.
2. Frontmatter contains `name: context-investigator` and a `description` field.
3. The agent definition lists all available gc-query subcommands with correct invocation syntax.
4. The agent references `${CLAUDE_PLUGIN_ROOT}/scripts/gc-query` for all data access.
5. Loading the plugin exposes the agent as invocable via the Task tool.
6. The agent can be invoked with a question like "When did we decide to use event sourcing?" and it uses gc-query search to find relevant events.
