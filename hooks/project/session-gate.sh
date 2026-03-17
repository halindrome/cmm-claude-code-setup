#!/bin/bash
# session-gate.sh — PreToolUse:* hook (unified CMM + Context Mode session gate)
# BLOCKING: gates all tools until CMM index is refreshed and (if installed) Context Mode is initialized
#
# Purpose: Single merged gate replacing cmm-session-gate.sh and context-mode-session-gate.sh.
#          Sentinel path uses git-aware root detection (show-superproject-working-tree) so
#          the hash is stable whether the session CWD is the project root, a git submodule,
#          or a git worktree.
#
# Install: cp hooks/project/session-gate.sh .claude/hooks/ && chmod +x .claude/hooks/session-gate.sh
# Register in .claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "*", "hooks": [{"type": "command", "command": "bash .claude/hooks/session-gate.sh"}] }] }
# Matcher: PreToolUse:*

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

# --- Path Integrity Check ---
# Hooks are registered with absolute paths by setup.sh. If the project was moved or
# cloned without re-running setup.sh, BASH_SOURCE points to the old location while
# git resolves the actual current root — catch this mismatch early.
_SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P 2>/dev/null)"
if [ -n "$_SCRIPT_ROOT" ] && [ -n "$PROJECT_ROOT" ] && [ "$_SCRIPT_ROOT" != "$PROJECT_ROOT" ]; then
    echo "cmm-hooks: path mismatch — hooks registered for '$_SCRIPT_ROOT' but git root is '$PROJECT_ROOT'."
    echo "Project was moved or cloned. Re-run: bash setup.sh --project --force"
    exit 2
fi

PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')
CMM_SENTINEL="/tmp/cmm-session-ready-${PROJECT_HASH}"

# --- Input Parsing ---
INPUT=$(cat)
TOOL=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")

# If parsing failed, do not block — fail open to avoid spurious hook errors
[ -z "$TOOL" ] && exit 0

# --- Phase 1: Universal Allow-list ---
# Bypass both gates unconditionally
case "$TOOL" in
  Agent)        exit 0 ;;  # subagents run in their own session with their own gate
  ToolSearch)   exit 0 ;;  # schema fetch needed to escape the catch-22
  SendMessage)  exit 0 ;;  # inter-agent coordination; must never be gated
esac

# --- Phase 2: CMM Gate ---
# Allow-list: CMM bootstrap tools and read-only tools
case "$TOOL" in
  mcp__codebase-memory-mcp__index_repository)  # creates sentinel via cmm-sentinel-writer.sh
    exit 0 ;;
  mcp__codebase-memory-mcp__index_status)      # fast check; sentinel writer fires on success
    exit 0 ;;
  mcp__codebase-memory-mcp__delete_project)    # safe pre-index; needed for forced re-index
    exit 0 ;;
  Bash|Read|Grep|Glob)                         # read-only tools; safe to run in parallel with index_status
    exit 0 ;;
esac

# Check CMM sentinel
if [ ! -f "$CMM_SENTINEL" ]; then
  cat >&2 <<BLOCKED
BLOCKED: CMM index not refreshed for this session.

Run one of these first:
  mcp__codebase-memory-mcp__index_status       (fast check — opens gate if server is up)
  mcp__codebase-memory-mcp__index_repository   (full reindex)

If the CMM server is unavailable, create the bypass sentinel in your terminal:
  touch "/tmp/cmm-session-ready-${PROJECT_HASH}"
BLOCKED
  exit 2
fi

# --- Phase 3: Context Mode Gate (only if installed) ---
# Detection: check project .mcp.json and global Claude Code settings, then session DB
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

# Context Mode allow-list (bypass Context Mode sentinel check)
case "$TOOL" in
  mcp__context-mode__*)  exit 0 ;;
  ctx_execute)           exit 0 ;;
  ctx_search)            exit 0 ;;
  ctx_index)             exit 0 ;;
  ctx_fetch_and_index)   exit 0 ;;
  ctx_batch_execute)     exit 0 ;;
  ctx_execute_file)      exit 0 ;;
  ctx_stats)             exit 0 ;;
  ctx_doctor)            exit 0 ;;
  ctx_upgrade)           exit 0 ;;
  mcp__codebase-memory-mcp__*)  exit 0 ;;
esac

# Check Context Mode sentinel
CONTEXT_MODE_SENTINEL="/tmp/context-mode-ready-${PROJECT_HASH}"

if [ ! -f "$CONTEXT_MODE_SENTINEL" ]; then
  cat >&2 <<BLOCKED
BLOCKED: Context Mode is installed but not yet initialized for this session.

Run one of these to initialize:
  ctx_stats          (fast check — initializes Context Mode for this session)
  ctx_execute        (run any command through the sandbox to initialize)

If you want to bypass the gate temporarily, create the sentinel in your terminal:
  touch "/tmp/context-mode-ready-${PROJECT_HASH}"
BLOCKED
  exit 2
fi

exit 0
