# Task 06: Context Recovery Skill

**Story**: 06-plugin-packaging
**Estimated Complexity**: S (Small)
**Dependencies**: [Task 01 - Plugin Manifest and Directory Scaffold](/home/meywd/GlobalContext/tasks/06-plugin-packaging/01-plugin-manifest-scaffold.md) (skills directory must exist)

---

## Description

Create a SKILL.md file that Claude auto-invokes when it detects context loss. Skills are auto-triggered based on their description matching the user's intent. The context recovery skill triggers when the user asks about what they were doing, when context has been compacted, or when starting a new session after compaction.

Unlike commands (which require explicit `/globalcontext:last` invocation), the skill is activated automatically by Claude's intent-matching system when it detects that the user needs context recovery.

---

## Files to Create

| File | Purpose |
|------|---------|
| `plugin/skills/context-recovery/SKILL.md` | Auto-invoked skill for context loss detection and recovery |

---

## Specification

### `plugin/skills/context-recovery/SKILL.md`

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

---

## Acceptance Tests

1. `plugin/skills/context-recovery/SKILL.md` exists with valid YAML frontmatter.
2. Frontmatter contains `name: context-recovery` and a `description` field.
3. The description contains trigger phrases: "what were we doing", "compaction", "new session", "continue", "resume".
4. The skill references `${CLAUDE_PLUGIN_ROOT}/scripts/gc-query` for context retrieval.
5. Loading the plugin, starting a new session, and asking "what were we working on?" triggers the skill.
6. The skill does not trigger for unrelated queries (e.g., "write a function").
