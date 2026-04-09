#!/bin/bash
# reindex-after-commit.sh — PostToolUse:Bash hook (marks CMM sentinel stale after git commit)
# Detects successful git commit calls and writes "stale" to the CMM sentinel file, prompting
# a stale-index advisory in session-gate.sh until the user refreshes the index.
# In VBW team mode the hook skips writing stale to prevent cascade-stalling parallel agents.
#
# Install: cp hooks/project/reindex-after-commit.sh .claude/hooks/ && chmod +x .claude/hooks/reindex-after-commit.sh
# Register in .claude/settings.json:
#   "hooks": { "PostToolUse": [{ "matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/reindex-after-commit.sh"}] }] }
# Matcher: PostToolUse:Bash

# --- Pre-Traversal Early Exit ---
# Read stdin once (can only be consumed once), then check if this is a git commit command.
# Exit immediately for non-commit Bash calls — avoids the expensive git traversal for ~95% of calls.
INPUT=$(cat)
echo "$INPUT" | grep -q '"git commit\|"git  *commit' || exit 0

# --- Stable Sentinel Path Computation ---
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
# Use the main project root so sentinel hashes are stable across worktree sessions.
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

PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')
CMM_SENTINEL="/tmp/cmm-session-ready-${PROJECT_HASH}"

# --- Input Parsing ---
# stdin already consumed into INPUT above — pipe from variable for python3 parsing
CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
STDOUT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_output',{}).get('stdout',''))" 2>/dev/null || echo "")

# --- Commit Detection ---
# Only act on git commit commands; exit immediately for all other Bash calls
case "$CMD" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# --- False-Positive Guard ---
# If git reported no actual commit (nothing staged), skip marking stale
case "$STDOUT" in
  *"nothing to commit"*|*"no changes"*) exit 0 ;;
esac

# --- Team-Mode Detection ---
# VBW team agents detect they are running inside a team context and skip marking stale.
# This prevents a commit in one agent's worktree from cascade-stalling all parallel agents.
# The main session (TEAM_MODE=0) is responsible for marking stale and reindexing.
#
# Bypass team-mode check when running inside a Dev subagent making a commit.
# Dev agent commits SHOULD mark sentinel stale so Scout/QA know to reindex.
# Set SUBAGENT_COMMIT=1 in the agent frontmatter hook command to enable this bypass.
if [ "${SUBAGENT_COMMIT:-0}" != "1" ]; then
  TEAM_MODE=0
  for d in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/teams/vbw-*; do
    [ -d "$d" ] && TEAM_MODE=1 && break
  done
  if [ "$TEAM_MODE" -eq 1 ]; then
    exit 0
  fi
fi

# --- Write Stale Marker ---
echo "stale" > "$CMM_SENTINEL"

# --- Nudge CMM Watcher via touch_project ---
# Resolve the project name from the superproject root path.
# PROJECT_ROOT is already resolved to the outermost superproject root by the sentinel logic above.
# CMM derives project names from the full absolute path: strip leading /, replace / with -.
# e.g. /Users/ahby/Sources/my-project -> Users-ahby-Sources-my-project
_CMM_PROJECT_NAME="${PROJECT_ROOT#/}"
_CMM_PROJECT_NAME="${_CMM_PROJECT_NAME//\//-}"

# Capture output silently; touch_project is fire-and-forget.
# Use the CLI interface (not MCP tool name) since this runs in a shell hook, not Claude's agent runtime.
_CMM_TOUCH_JSON=$(python3 -c "import json; print(json.dumps({'project': '$_CMM_PROJECT_NAME'.replace(chr(39), '')}))" 2>/dev/null || echo '{"project":"'"$_CMM_PROJECT_NAME"'"}')
_CMM_TOUCH_OUTPUT=$(codebase-memory-mcp cli touch_project "$_CMM_TOUCH_JSON" 2>/dev/null) && _CMM_TOUCH_OK=1 || _CMM_TOUCH_OK=0

# Debug logging (only when debug_logging=true in config)
_CMM_CONFIG="$PROJECT_ROOT/.vbw-planning/config.json"
if [ -f "$_CMM_CONFIG" ] && python3 -c "import sys,json; d=json.load(open('$_CMM_CONFIG')); sys.exit(0 if d.get('debug_logging') else 1)" 2>/dev/null; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] touch_project project=$_CMM_PROJECT_NAME output=$_CMM_TOUCH_OUTPUT cwd=$(pwd)" >> /tmp/cmm-touch-project.log 2>/dev/null || true
fi

# --- Informational Message ---
if [ "$_CMM_TOUCH_OK" -eq 1 ]; then
  cat <<'EOF' >&2
CMM note: Commit detected. touch_project nudged the CMM watcher — reindex expected in 5–60s.
Graph queries will return pre-commit results until then. To reindex immediately:
  mcp__codebase-memory-mcp__index_repository
EOF
else
  cat <<'EOF' >&2
CMM note: Commit detected. Sentinel marked stale (touch_project unavailable — CMM CLI not in PATH or server not running).
Graph queries may return pre-commit results. To reindex:
  mcp__codebase-memory-mcp__index_repository
EOF
fi

exit 0
