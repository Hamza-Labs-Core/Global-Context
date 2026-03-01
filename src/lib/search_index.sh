#!/usr/bin/env bash
# search_index.sh -- FTS5 search index library for GlobalContext
# Provides functions for creating and populating the SQLite FTS5 search index.
# Called by capture-event (async indexing) and gc-query (search + reindex).

# Cached result for FTS5 availability check
_GC_HAS_FTS5=""

# _gc_has_fts5()
#   Returns 0 if sqlite3 is available and supports FTS5, 1 otherwise.
#   Result is cached after first call.
_gc_has_fts5() {
  if [[ -n "$_GC_HAS_FTS5" ]]; then
    return "$_GC_HAS_FTS5"
  fi
  if ! command -v sqlite3 &>/dev/null; then
    _GC_HAS_FTS5=1
    return 1
  fi
  if sqlite3 ':memory:' "CREATE VIRTUAL TABLE _fts5_test USING fts5(content);" 2>/dev/null; then
    _GC_HAS_FTS5=0
    return 0
  else
    _GC_HAS_FTS5=1
    return 1
  fi
}

# _gc_init_search_db()
#   Creates the search.db schema with WAL mode. Idempotent.
#   Requires GC_SEARCH_DB to be set (from paths.sh).
_gc_init_search_db() {
  local db="${GC_SEARCH_DB:-}"
  if [[ -z "$db" ]]; then
    echo "error: GC_SEARCH_DB not set" >&2
    return 1
  fi
  if [[ -f "$db" ]]; then
    return 0
  fi
  sqlite3 "$db" <<'SQL' >/dev/null
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS events_meta (
  rowid INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id TEXT NOT NULL,
  session_id TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  snippet TEXT NOT NULL DEFAULT '',
  UNIQUE(project_id, session_id, sequence)
);
CREATE VIRTUAL TABLE IF NOT EXISTS events_fts USING fts5(
  content,
  content='events_meta',
  content_rowid='rowid'
);
SQL
  chmod 600 "$db"
}

# _gc_extract_searchable_content(event_type, envelope_json)
#   Extracts the searchable text content from an event envelope.
#   Returns the content string on stdout.
_gc_extract_searchable_content() {
  local event_type="$1"
  local envelope_json="$2"

  case "$event_type" in
    UserPromptReceived)
      printf '%s' "$envelope_json" | jq -r '.data.prompt // .data.message // ""' 2>/dev/null
      ;;
    ToolCallCompleted)
      printf '%s' "$envelope_json" | jq -r '
        [.data.tool_name // "", (.data.tool_result // "" | tostring | .[:500])]
        | join(" ")
      ' 2>/dev/null
      ;;
    ToolCallRequested)
      printf '%s' "$envelope_json" | jq -r '
        [.data.tool_name // "", (.data.tool_input // "" | tostring | .[:500])]
        | join(" ")
      ' 2>/dev/null
      ;;
    ToolCallFailed)
      printf '%s' "$envelope_json" | jq -r '
        [.data.tool_name // "", .data.error // ""]
        | join(" ")
      ' 2>/dev/null
      ;;
    SessionStarted)
      printf '%s' "$envelope_json" | jq -r '.data.cwd // ""' 2>/dev/null
      ;;
    AgentSpawned|AgentCompleted)
      printf '%s' "$envelope_json" | jq -r '
        [.data.agent_type // "", .data.description // "", .data.result // ""]
        | map(select(. != "")) | join(" ")
      ' 2>/dev/null
      ;;
    *)
      printf '%s' "$envelope_json" | jq -r '
        [.data | .. | strings] | join(" ") | .[:1000]
      ' 2>/dev/null
      ;;
  esac
}

# _gc_index_event(project_id, session_id, sequence, event_type, timestamp, envelope_json)
#   Indexes a single event into the search database.
#   Uses INSERT OR IGNORE to skip duplicates.
_gc_index_event() {
  local project_id="$1"
  local session_id="$2"
  local sequence="$3"
  local event_type="$4"
  local timestamp="$5"
  local envelope_json="$6"

  local db="${GC_SEARCH_DB:-}"
  [[ -z "$db" || ! -f "$db" ]] && return 0

  local content
  content="$(_gc_extract_searchable_content "$event_type" "$envelope_json")" || return 0
  [[ -z "$content" ]] && return 0

  # Build snippet (first 200 chars of content)
  local snippet="${content:0:200}"

  # Escape single quotes for SQL
  project_id="${project_id//\'/\'\'}"
  session_id="${session_id//\'/\'\'}"
  event_type="${event_type//\'/\'\'}"
  timestamp="${timestamp//\'/\'\'}"
  snippet="${snippet//\'/\'\'}"
  content="${content//\'/\'\'}"

  sqlite3 "$db" <<SQL 2>/dev/null || true
INSERT OR IGNORE INTO events_meta (project_id, session_id, sequence, event_type, timestamp, snippet)
VALUES ('$project_id', '$session_id', $sequence, '$event_type', '$timestamp', '$snippet');
INSERT INTO events_fts (rowid, content)
SELECT rowid, '$content'
FROM events_meta
WHERE project_id = '$project_id' AND session_id = '$session_id' AND sequence = $sequence;
SQL
}
