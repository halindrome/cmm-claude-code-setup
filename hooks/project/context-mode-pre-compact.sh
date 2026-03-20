#!/bin/bash
# context-mode-pre-compact.sh — PreCompact hook (snapshot session state before context compression)
#
# Purpose: Builds a compaction snapshot recording the last 20 events, git HEAD, and a resume_hint
#          string into .claude/context-mode.db before the conversation auto-compacts. This allows
#          Claude to quickly reconstruct session context after compaction without re-reading history.
#          No-ops if Context Mode is not installed, no DB exists, or sqlite3 is unavailable.
#
# Install: cp hooks/project/context-mode-pre-compact.sh .claude/hooks/ && chmod +x .claude/hooks/context-mode-pre-compact.sh
# Register in .claude/settings.json:
#   "hooks": { "PreCompact": [{ "hooks": [{"type": "command", "command": "bash .claude/hooks/context-mode-pre-compact.sh"}] }] }
# Matcher: PreCompact
#
# IMPORTANT: PreCompact hooks MUST exit 0. Never exit 2 — blocking compaction is unsafe.

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

# --- Context Mode Presence Check ---
command -v context-mode >/dev/null 2>&1 || exit 0

# --- DB Existence Check ---
DB="${PROJECT_ROOT}/.claude/context-mode.db"
[ -f "$DB" ] || exit 0

# --- sqlite3 Availability Check ---
command -v sqlite3 >/dev/null 2>&1 || exit 0

SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Snapshot Table Initialization ---
sqlite3 "$DB" <<'SQL' 2>/dev/null || exit 0
CREATE TABLE IF NOT EXISTS snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT,
  timestamp TEXT,
  git_head TEXT,
  event_count INTEGER,
  resume_hint TEXT
);
SQL

# --- Query last 20 events for summary ---
EVENTS_RAW=$(sqlite3 "$DB" "SELECT tool_name, event_type, file_path FROM events ORDER BY id DESC LIMIT 20;" 2>/dev/null || echo "")

# --- Count event types from last 20 events ---
FILE_EDITS=$(echo "$EVENTS_RAW" | grep -c '|file_edit|' || echo 0)
GIT_OPS=$(echo "$EVENTS_RAW" | grep -c '|git_op|' || echo 0)
CMM_CALLS=$(echo "$EVENTS_RAW" | grep -c '|cmm_call|' || echo 0)
CTX_CALLS=$(echo "$EVENTS_RAW" | grep -c '|ctx_call|' || echo 0)
TOOL_CALLS=$(echo "$EVENTS_RAW" | grep -c '|tool_call|' || echo 0)

# Total events in session
EVENT_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM events WHERE session_id='${SESSION_ID//\'/\'\'}';" 2>/dev/null || echo 0)

# --- Get git HEAD ---
GIT_HEAD=$(git rev-parse --short HEAD 2>/dev/null || echo "no-git")

# --- Build resume_hint ---
RESUME_HINT="Last 20 events: ${FILE_EDITS} file_edits, ${GIT_OPS} git_ops, ${CMM_CALLS} cmm_calls, ${CTX_CALLS} ctx_calls, ${TOOL_CALLS} tool_calls. Session total: ${EVENT_COUNT} events. HEAD: ${GIT_HEAD}."

# --- Insert snapshot row ---
SESSION_ID_ESC="${SESSION_ID//\'/\'\'}"
GIT_HEAD_ESC="${GIT_HEAD//\'/\'\'}"
RESUME_HINT_ESC="${RESUME_HINT//\'/\'\'}"

sqlite3 "$DB" "INSERT INTO snapshots (session_id, timestamp, git_head, event_count, resume_hint) VALUES ('${SESSION_ID_ESC}', '${TIMESTAMP}', '${GIT_HEAD_ESC}', ${EVENT_COUNT}, '${RESUME_HINT_ESC}');" 2>/dev/null

# PreCompact hooks MUST always exit 0 — never block compaction
exit 0
