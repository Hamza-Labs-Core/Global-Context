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
