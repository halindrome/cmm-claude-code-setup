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

# --- Stable Project Root Computation ---
# Walk the git superproject chain to find the outermost project root.
# Handles arbitrarily nested submodules — each iteration climbs one level until there is
# no further superproject. Falls back to BASH_SOURCE traversal for non-git environments.
# Git worktrees are handled separately below (they are not submodules).
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -n "$PROJECT_ROOT" ]; then
    _WALK="$PROJECT_ROOT"
    while true; do
        _PARENT="$(git -C "$_WALK" rev-parse --show-superproject-working-tree 2>/dev/null)"
        [ -z "$_PARENT" ] && break
        _WALK="$_PARENT"
    done
    PROJECT_ROOT="$_WALK"
fi
if [ -z "$PROJECT_ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
fi

# --- Git Worktree Detection ---
# git worktrees share the main repo but show-superproject-working-tree returns empty
# (worktrees are not submodules). Detect via git-common-dir: in a worktree it points
# to the main .git dir, while git-dir points into .git/worktrees/<name>.
# Use the main project root so the DB path is stable across worktree sessions.
if [ -n "$PROJECT_ROOT" ]; then
    _GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --git-dir 2>/dev/null)"
    _GIT_COMMON="$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null)"
    # Resolve relative paths (git may return relative paths in the main working tree)
    [ "${_GIT_DIR:0:1}" != "/" ]    && _GIT_DIR="$PROJECT_ROOT/$_GIT_DIR"
    [ "${_GIT_COMMON:0:1}" != "/" ] && _GIT_COMMON="$PROJECT_ROOT/$_GIT_COMMON"
    if [ "$_GIT_DIR" != "$_GIT_COMMON" ]; then
        _MAIN_ROOT="$(cd "$_GIT_COMMON/.." 2>/dev/null && pwd -P)"
        [ -n "$_MAIN_ROOT" ] && PROJECT_ROOT="$_MAIN_ROOT"
    fi
fi

# --- Read stdin once (stdin can only be consumed once) ---
INPUT=$(cat)

# --- Context Mode Presence Check ---
# 3-source detection matching ctx-execute-enforcer.sh and context-mode-sentinel-writer.sh:
# 1. Project .mcp.json for context-mode server entry
# 2. Global Claude Code settings for context-mode server entry
# 3. .claude/context-mode.db existence (prior session used Context Mode here)
CONTEXT_MODE_INSTALLED=0
if python3 -c "
import json, os, sys
# 1. Project .mcp.json
try:
    with open('${PROJECT_ROOT}/.mcp.json') as f:
        if 'context-mode' in json.load(f).get('mcpServers', {}):
            sys.exit(0)
except Exception: pass
# 2. Global Claude Code settings
for d in [os.environ.get('CLAUDE_CONFIG_DIR',''), os.path.expanduser('~/.config/claude-code'), os.path.expanduser('~/.claude')]:
    if not d: continue
    try:
        with open(os.path.join(d, 'settings.json')) as f:
            if 'context-mode' in json.load(f).get('mcpServers', {}):
                sys.exit(0)
    except Exception: pass
sys.exit(1)
" 2>/dev/null; then
  CONTEXT_MODE_INSTALLED=1
fi
# Also activate if a session DB already exists (context-mode was used here before)
[ -f "${PROJECT_ROOT}/.claude/context-mode.db" ] && CONTEXT_MODE_INSTALLED=1

if [ "$CONTEXT_MODE_INSTALLED" -eq 0 ]; then
  exit 0
fi

# --- Fast-path: skip heavy pipeline for tools with dedicated trackers ---
# Extract tool_name cheaply via bash (no python3 needed for the fast-path check).
# CMM and CTX tools are already tracked by track-cmm-calls.sh and track-ctx-calls.sh
# respectively — the full sqlite3/python3 event logging pipeline is unnecessary for them.
TOOL_NAME=$(echo "$INPUT" | grep -o '"tool_name": *"[^"]*"' | head -1 | sed 's/.*: *"//;s/"//')
case "$TOOL_NAME" in
  mcp__codebase-memory-mcp__*) exit 0 ;;  # tracked by track-cmm-calls.sh
  mcp__context-mode__*)        exit 0 ;;  # tracked by track-ctx-calls.sh
esac

# --- sqlite3 Availability Check ---
command -v sqlite3 >/dev/null 2>&1 || exit 0

# --- Input Parsing (full JSON parse for remaining tools) ---
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")
TOOL_INPUT=$(echo "$INPUT" | python3 -c "import sys,json; print(str(json.load(sys.stdin).get('tool_input','')))" 2>/dev/null || echo "")
TOOL_RESULT=$(echo "$INPUT" | python3 -c "import sys,json; print(str(json.load(sys.stdin).get('tool_result','')))" 2>/dev/null || echo "")

# If parsing failed, do not block logging failure
[ -z "$TOOL_NAME" ] && exit 0

SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DB="${PROJECT_ROOT}/.claude/context-mode.db"

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
  mcp__context-mode__ctx_*)
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
