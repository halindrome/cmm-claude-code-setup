#!/bin/bash
# cmm-sentinel-writer.sh — PostToolUse hook (index_repository OR index_status)
# NON-BLOCKING: always exits 0 (writes sentinel to unblock session gate)
#
# Purpose: Writes the session sentinel file after index_repository or index_status
#          completes, unblocking all tools gated by session-gate.sh.
#
# Install: cp hooks/project/cmm-sentinel-writer.sh .claude/hooks/
#          chmod +x .claude/hooks/cmm-sentinel-writer.sh
# Register in .claude/settings.json:
#   "hooks": { "PostToolUse": [{ "matcher": "mcp__codebase-memory-mcp__index_repository|mcp__codebase-memory-mcp__index_status", "hooks": [{"type": "command", "command": "bash .claude/hooks/cmm-sentinel-writer.sh"}] }] }

# --- Stable Sentinel Path Computation ---
# Walk the git superproject chain to find the outermost project root.
# Handles arbitrarily nested submodules — each iteration climbs one level until there is
# no further superproject. Falls back to BASH_SOURCE traversal for non-git environments.
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
_SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P 2>/dev/null)"
if [ -n "$_SCRIPT_ROOT" ] && [ -n "$PROJECT_ROOT" ] && [ "$_SCRIPT_ROOT" != "$PROJECT_ROOT" ]; then
    echo "cmm-hooks: path mismatch — hooks registered for '$_SCRIPT_ROOT' but git root is '$PROJECT_ROOT'." >&2
    echo "Project was moved or cloned. Re-run: bash setup.sh --project --force" >&2
fi

PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')
SENTINEL="/tmp/cmm-session-ready-${PROJECT_HASH}"

# Write sentinel to unblock session gate
echo "ready" > "$SENTINEL"

exit 0
