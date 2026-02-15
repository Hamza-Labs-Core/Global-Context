# Task 02: Hook Configuration (hooks.json)

**Story**: 06-plugin-packaging
**Estimated Complexity**: M (Medium)
**Dependencies**: [Task 01 - Plugin Manifest and Directory Scaffold](/home/meywd/GlobalContext/tasks/06-plugin-packaging/01-plugin-manifest-scaffold.md) (directory structure must exist)

---

## Description

Define the complete hook configuration in `hooks/hooks.json` using the Claude Code plugin hooks format. This replaces the manual `gc-install-hooks` script from Story 02 -- hooks are declared in the plugin and registered automatically when the plugin is installed.

All 10 hook events are defined. Each hook calls `${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook` with the appropriate GlobalContext event type as the argument. Sync/async settings follow the same rationale as Story 02 (PreCompact, SessionStart, UserPromptSubmit are sync; all others are async). Matcher patterns use `".*"` for tool-related hooks to capture all tools.

---

## Files to Create

| File | Purpose |
|------|---------|
| `plugin/hooks/hooks.json` | Complete hook configuration for all 10 events |

---

## Specification

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

### Hook Event to Event Type Mapping (carried forward from Story 02)

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

---

## Acceptance Tests

1. `jq . plugin/hooks/hooks.json` parses without error.
2. `jq '.hooks | keys | length' plugin/hooks/hooks.json` returns `10`.
3. Sync events (SessionStart, UserPromptSubmit, PreCompact) have `"async": false`.
4. Async events (PreToolUse, PostToolUse, PostToolUseFailure, SubagentStart, SubagentStop, Stop, SessionEnd) have `"async": true`.
5. All hook commands reference `${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook`.
6. Tool-related hooks (PreToolUse, PostToolUse, PostToolUseFailure, SubagentStart, SubagentStop) have `"matcher": ".*"`.
7. All timeouts are 5000ms.
8. Each hook entry has `"type": "command"`.
