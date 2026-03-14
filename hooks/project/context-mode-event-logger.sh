#!/bin/bash
# context-mode-event-logger.sh — PostToolUse:* hook (logs tool events to .claude/context-mode.db SQLite)
#
# Purpose: Captures file edits, git operations, MCP calls, and ctx_* calls into a per-project
#          SQLite event journal for session continuity across compactions. No-ops if Context Mode
#          is not installed or sqlite3 is unavailable.
#
# Install: cp hooks/project/context-mode-event-logger.sh .claude/hooks/ && chmod +x .claude/hooks/context-mode-event-logger.sh
# Register in .claude/settings.json:
#   "hooks": { "PostToolUse": [{ "matcher": "*", "hooks": [{"type": "command", "command": "bash .claude/hooks/context-mode-event-logger.sh"}] }] }
# Matcher: PostToolUse:*

# --- Context Mode Presence Check ---
# No-op gracefully if Context Mode binary is not installed and no DB exists yet.
CONTEXT_MODE_INSTALLED=0
command -v context-mode >/dev/null 2>&1 && CONTEXT_MODE_INSTALLED=1
[ -f ".claude/context-mode.db" ] && CONTEXT_MODE_INSTALLED=1

if [ "$CONTEXT_MODE_INSTALLED" -eq 0 ]; then
  exit 0
fi

# --- sqlite3 Availability Check ---
command -v sqlite3 >/dev/null 2>&1 || exit 0

# --- Input Parsing ---
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")
TOOL_INPUT=$(echo "$INPUT" | python3 -c "import sys,json; print(str(json.load(sys.stdin).get('tool_input','')))" 2>/dev/null || echo "")
TOOL_RESULT=$(echo "$INPUT" | python3 -c "import sys,json; print(str(json.load(sys.stdin).get('tool_result','')))" 2>/dev/null || echo "")

# If parsing failed, do not block logging failure
[ -z "$TOOL_NAME" ] && exit 0

SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DB=".claude/context-mode.db"

# --- DB Schema Initialization ---
sqlite3 "$DB" <<'SQL' 2>/dev/null || exit 0
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT,
  tool_name TEXT,
  event_type TEXT,
  file_path TEXT,
  timestamp TEXT,
  input_size INTEGER,
  output_size INTEGER,
  status TEXT
);
SQL

# --- Event Type Classification ---
EVENT_TYPE="tool_call"
FILE_PATH=""

case "$TOOL_NAME" in
  Write|Edit)
    EVENT_TYPE="file_edit"
    FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); inp=d.get('tool_input',{}); print(inp.get('file_path', inp.get('path','')))" 2>/dev/null || echo "")
    ;;
  Bash)
    echo "$TOOL_INPUT" | grep -q 'git ' && EVENT_TYPE="git_op" || EVENT_TYPE="tool_call"
    ;;
  mcp__codebase-memory-mcp__*)
    EVENT_TYPE="cmm_call"
    ;;
  ctx_*)
    EVENT_TYPE="ctx_call"
    ;;
esac

# --- Compute sizes ---
INPUT_SIZE=${#TOOL_INPUT}
OUTPUT_SIZE=${#TOOL_RESULT}

# --- Determine status ---
STATUS="ok"
echo "$TOOL_RESULT" | grep -qi 'error\|exception\|failed\|traceback' && STATUS="error"

# --- Insert event row ---
# Escape single quotes in values to prevent SQL injection
TOOL_NAME_ESC="${TOOL_NAME//\'/\'\'}"
EVENT_TYPE_ESC="${EVENT_TYPE//\'/\'\'}"
FILE_PATH_ESC="${FILE_PATH//\'/\'\'}"
SESSION_ID_ESC="${SESSION_ID//\'/\'\'}"
STATUS_ESC="${STATUS//\'/\'\'}"

sqlite3 "$DB" "INSERT INTO events (session_id, tool_name, event_type, file_path, timestamp, input_size, output_size, status) VALUES ('${SESSION_ID_ESC}', '${TOOL_NAME_ESC}', '${EVENT_TYPE_ESC}', '${FILE_PATH_ESC}', '${TIMESTAMP}', ${INPUT_SIZE}, ${OUTPUT_SIZE}, '${STATUS_ESC}');" 2>/dev/null

# Never block on logging failure — PostToolUse hooks must always exit 0
exit 0
