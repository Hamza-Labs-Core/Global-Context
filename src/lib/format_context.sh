#!/usr/bin/env bash
# format_context.sh -- Output formatters for context projection data
# Provides: format_json, format_markdown, format_text, format_compact
# Part of Story 05, Task 10.
set -euo pipefail

# Source dependencies
_FORMAT_CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${_FORMAT_CONTEXT_DIR}/paths.sh"

# format_json(context_file_or_stdin)
#
# Pretty-print the context JSON as-is.
format_json() {
  local input="${1:-}"
  if [[ -n "$input" && -f "$input" ]]; then
    jq '.' "$input"
  else
    jq '.'
  fi
}

# format_markdown(context_file_or_stdin)
#
# Render context projection as markdown with sections:
# Session Info, What Was Being Worked On, Actions Taken,
# Files Modified, Key Decisions, Where We Left Off
format_markdown() {
  local input="${1:-}"
  local json
  if [[ -n "$input" && -f "$input" ]]; then
    json="$(cat "$input")"
  else
    json="$(cat)"
  fi

  local data
  data="$(printf '%s' "$json" | jq -r '.data // .')"

  local session_id project_id started_at last_event_at event_count
  local last_prompt ended_at previous_session_id

  session_id="$(printf '%s' "$data" | jq -r '.session_id // "unknown"')"
  project_id="$(printf '%s' "$data" | jq -r '.project_id // "unknown"')"
  started_at="$(printf '%s' "$data" | jq -r '.started_at // "unknown"')"
  last_event_at="$(printf '%s' "$data" | jq -r '.last_event_at // "unknown"')"
  event_count="$(printf '%s' "$data" | jq -r '.event_count // 0')"
  last_prompt="$(printf '%s' "$data" | jq -r '.last_prompt // ""')"
  ended_at="$(printf '%s' "$data" | jq -r '.ended_at // "in progress"')"
  previous_session_id="$(printf '%s' "$data" | jq -r '.previous_session_id // "none"')"

  # Section 1: Session Info
  echo "## Session Info"
  echo ""
  echo "- **Session ID**: \`${session_id}\`"
  echo "- **Project**: \`${project_id}\`"
  echo "- **Started**: ${started_at}"
  echo "- **Last Activity**: ${last_event_at}"
  echo "- **Ended**: ${ended_at}"
  echo "- **Event Count**: ${event_count}"
  if [[ "$previous_session_id" != "none" && "$previous_session_id" != "null" && -n "$previous_session_id" ]]; then
    echo "- **Continuation of**: \`${previous_session_id}\`"
  fi
  echo ""

  # Section 2: What Was Being Worked On
  echo "## What Was Being Worked On"
  echo ""
  if [[ -n "$last_prompt" && "$last_prompt" != "null" ]]; then
    echo "> ${last_prompt}"
    echo ""
  else
    echo "No prompt recorded."
    echo ""
  fi

  # Section 3: Actions Taken
  local actions_count
  actions_count="$(printf '%s' "$data" | jq -r '.actions | length // 0')"

  echo "## Actions Taken"
  echo ""
  if [[ "$actions_count" -gt 0 ]]; then
    local i=0
    while [[ $i -lt $actions_count ]]; do
      local action
      action="$(printf '%s' "$data" | jq -r ".actions[$i]")"
      local tool_name target result_summary
      tool_name="$(printf '%s' "$action" | jq -r '.tool_name // "unknown"')"
      target="$(printf '%s' "$action" | jq -r '.target // ""')"
      result_summary="$(printf '%s' "$action" | jq -r '.result_summary // ""')"

      local line="${i+1}. **${tool_name}**"
      if [[ -n "$target" && "$target" != "null" ]]; then
        line="${line} on \`${target}\`"
      fi
      if [[ -n "$result_summary" && "$result_summary" != "null" ]]; then
        line="${line} -- ${result_summary}"
      fi
      echo "$line"
      i=$((i + 1))
    done
    echo ""
  else
    echo "No actions recorded."
    echo ""
  fi

  # Section 4: Files Modified
  local files_count
  files_count="$(printf '%s' "$data" | jq -r '.files_modified | length // 0')"

  echo "## Files Modified"
  echo ""
  if [[ "$files_count" -gt 0 ]]; then
    echo "| File | Operations | Last Action |"
    echo "|------|-----------|-------------|"
    local j=0
    while [[ $j -lt $files_count ]]; do
      local fmod
      fmod="$(printf '%s' "$data" | jq -r ".files_modified[$j]")"
      local fpath ops last_action
      fpath="$(printf '%s' "$fmod" | jq -r '.path // "unknown"')"
      ops="$(printf '%s' "$fmod" | jq -r '.operations // "unknown"')"
      last_action="$(printf '%s' "$fmod" | jq -r '.last_action // "unknown"')"
      echo "| \`${fpath}\` | ${ops} | ${last_action} |"
      j=$((j + 1))
    done
    echo ""
  else
    echo "No files modified."
    echo ""
  fi

  # Section 5: Key Decisions
  local decisions_count
  decisions_count="$(printf '%s' "$data" | jq -r '.decisions | length // 0')"

  echo "## Key Decisions"
  echo ""
  if [[ "$decisions_count" -gt 0 ]]; then
    local k=0
    while [[ $k -lt $decisions_count ]]; do
      local decision
      decision="$(printf '%s' "$data" | jq -r ".decisions[$k]")"
      echo "- ${decision}"
      k=$((k + 1))
    done
    echo ""
  else
    echo "No key decisions recorded."
    echo ""
  fi

  # Section 6: Where We Left Off
  echo "## Where We Left Off"
  echo ""
  local last_state
  last_state="$(printf '%s' "$data" | jq -r '.last_state // empty' 2>/dev/null)"
  if [[ -n "$last_state" && "$last_state" != "null" ]]; then
    echo "$last_state"
  else
    if [[ -n "$last_prompt" && "$last_prompt" != "null" ]]; then
      echo "Last active on: ${last_prompt}"
    else
      echo "Session ended without explicit state."
    fi
  fi
  echo ""

  # Degraded context warning
  local is_degraded
  is_degraded="$(printf '%s' "$json" | jq -r '._degraded // false')"
  if [[ "$is_degraded" == "true" ]]; then
    local error_msg
    error_msg="$(printf '%s' "$data" | jq -r '.error // ""')"
    echo "---"
    echo ""
    echo "*Note: ${error_msg}*"
    echo ""
  fi
}

# format_text(context_file_or_stdin)
#
# Plain text output with indentation and dashes, no markdown.
format_text() {
  local input="${1:-}"
  local json
  if [[ -n "$input" && -f "$input" ]]; then
    json="$(cat "$input")"
  else
    json="$(cat)"
  fi

  local data
  data="$(printf '%s' "$json" | jq -r '.data // .')"

  local session_id project_id started_at last_event_at event_count last_prompt ended_at

  session_id="$(printf '%s' "$data" | jq -r '.session_id // "unknown"')"
  project_id="$(printf '%s' "$data" | jq -r '.project_id // "unknown"')"
  started_at="$(printf '%s' "$data" | jq -r '.started_at // "unknown"')"
  last_event_at="$(printf '%s' "$data" | jq -r '.last_event_at // "unknown"')"
  event_count="$(printf '%s' "$data" | jq -r '.event_count // 0')"
  last_prompt="$(printf '%s' "$data" | jq -r '.last_prompt // ""')"
  ended_at="$(printf '%s' "$data" | jq -r '.ended_at // "in progress"')"

  echo "Session: ${session_id}"
  echo "Project: ${project_id}"
  echo "Started: ${started_at}"
  echo "Last Activity: ${last_event_at}"
  echo "Ended: ${ended_at}"
  echo "Events: ${event_count}"
  echo ""

  if [[ -n "$last_prompt" && "$last_prompt" != "null" ]]; then
    echo "Last Prompt:"
    echo "  ${last_prompt}"
    echo ""
  fi

  local actions_count
  actions_count="$(printf '%s' "$data" | jq -r '.actions | length // 0')"
  if [[ "$actions_count" -gt 0 ]]; then
    echo "Actions:"
    local i=0
    while [[ $i -lt $actions_count ]]; do
      local tool_name target
      tool_name="$(printf '%s' "$data" | jq -r ".actions[$i].tool_name // \"unknown\"")"
      target="$(printf '%s' "$data" | jq -r ".actions[$i].target // \"\"")"
      local line="  - ${tool_name}"
      if [[ -n "$target" && "$target" != "null" ]]; then
        line="${line} on ${target}"
      fi
      echo "$line"
      i=$((i + 1))
    done
    echo ""
  fi

  local files_count
  files_count="$(printf '%s' "$data" | jq -r '.files_modified | length // 0')"
  if [[ "$files_count" -gt 0 ]]; then
    echo "Files Modified:"
    local j=0
    while [[ $j -lt $files_count ]]; do
      local fpath
      fpath="$(printf '%s' "$data" | jq -r ".files_modified[$j].path // \"unknown\"")"
      echo "  - ${fpath}"
      j=$((j + 1))
    done
    echo ""
  fi
}

# format_compact(context_file_or_stdin)
#
# Single-line summary per session.
format_compact() {
  local input="${1:-}"
  local json
  if [[ -n "$input" && -f "$input" ]]; then
    json="$(cat "$input")"
  else
    json="$(cat)"
  fi

  local data
  data="$(printf '%s' "$json" | jq -r '.data // .')"

  local session_id started_at project_id event_count last_prompt files_count

  session_id="$(printf '%s' "$data" | jq -r '.session_id // "unknown"')"
  started_at="$(printf '%s' "$data" | jq -r '.started_at // "unknown"')"
  project_id="$(printf '%s' "$data" | jq -r '.project_id // "unknown"')"
  event_count="$(printf '%s' "$data" | jq -r '.event_count // 0')"
  last_prompt="$(printf '%s' "$data" | jq -r '.last_prompt // ""')"
  files_count="$(printf '%s' "$data" | jq -r '.files_modified | length // 0')"

  # Truncate prompt to 60 chars
  if [[ ${#last_prompt} -gt 60 ]]; then
    last_prompt="${last_prompt:0:57}..."
  fi

  printf '%s | %s | %s | %s events | %s | %s files\n' \
    "$session_id" "$started_at" "$project_id" "$event_count" "$last_prompt" "$files_count"
}
