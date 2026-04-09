#!/bin/bash
# project-root.sh — Shared project-root detection with /tmp caching (source, don't execute)
# Exports: PROJECT_ROOT, PROJECT_HASH, CMM_SENTINEL, CTX_SENTINEL
#
# Caches PROJECT_ROOT and PROJECT_HASH to /tmp/cmm-project-root-<md5(pwd)> on first
# source. Subsequent sources read the cache file (zero git subprocesses). Safe to
# source multiple times — idempotent guard returns immediately on re-source.
#
# Install: cp -r hooks/lib ~/.claude/hooks/
# Hooks source via: source "${BASH_SOURCE[0]%/*}/lib/project-root.sh"

# --- Idempotent guard ---
[ -n "$_PROJECT_ROOT_LOADED" ] && return 0

# --- Cache key: md5 of $(pwd) ---
_PR_CWD="$(pwd)"
_PR_CACHE_KEY=$(echo -n "$_PR_CWD" | md5 -q 2>/dev/null || echo -n "$_PR_CWD" | md5sum 2>/dev/null | cut -d' ' -f1)
_PR_CACHE_FILE="/tmp/cmm-project-root-${_PR_CACHE_KEY}"

# --- Try cache first ---
if [ -f "$_PR_CACHE_FILE" ]; then
  _PR_CACHED_ROOT=$(sed -n '1p' "$_PR_CACHE_FILE" 2>/dev/null)
  _PR_CACHED_HASH=$(sed -n '2p' "$_PR_CACHE_FILE" 2>/dev/null)
  if [ -n "$_PR_CACHED_ROOT" ] && [ -d "$_PR_CACHED_ROOT" ] && [ -n "$_PR_CACHED_HASH" ]; then
    PROJECT_ROOT="$_PR_CACHED_ROOT"
    PROJECT_HASH="$_PR_CACHED_HASH"
    CMM_SENTINEL="/tmp/cmm-session-ready-${PROJECT_HASH}"
    CTX_SENTINEL="/tmp/cmm-ctx-ready-${PROJECT_HASH}"
    export PROJECT_ROOT PROJECT_HASH CMM_SENTINEL CTX_SENTINEL
    _PROJECT_ROOT_LOADED=1
    return 0
  fi
fi

# --- Cache miss or stale: full git superproject chain walk ---
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
    # Fallback: derive from BASH_SOURCE (non-git environments)
    _PR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
    if [ -n "$_PR_SCRIPT_DIR" ]; then
        PROJECT_ROOT="$(cd "$_PR_SCRIPT_DIR/../.." 2>/dev/null && pwd -P)"
    else
        PROJECT_ROOT="$_PR_CWD"
    fi
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
    [ -n "$_GIT_DIR" ] && [ "${_GIT_DIR:0:1}" != "/" ]    && _GIT_DIR="$PROJECT_ROOT/$_GIT_DIR"
    [ -n "$_GIT_COMMON" ] && [ "${_GIT_COMMON:0:1}" != "/" ] && _GIT_COMMON="$PROJECT_ROOT/$_GIT_COMMON"
    if [ -n "$_GIT_DIR" ] && [ -n "$_GIT_COMMON" ] && [ "$_GIT_DIR" != "$_GIT_COMMON" ]; then
        _MAIN_ROOT="$(cd "$_GIT_COMMON/.." 2>/dev/null && pwd -P)"
        [ -n "$_MAIN_ROOT" ] && PROJECT_ROOT="$_MAIN_ROOT"
    fi
fi

# --- Compute PROJECT_HASH ---
PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')

# --- Write cache ---
echo "$PROJECT_ROOT" > "$_PR_CACHE_FILE" 2>/dev/null
echo "$PROJECT_HASH" >> "$_PR_CACHE_FILE" 2>/dev/null

# --- Export sentinel paths ---
CMM_SENTINEL="/tmp/cmm-session-ready-${PROJECT_HASH}"
CTX_SENTINEL="/tmp/cmm-ctx-ready-${PROJECT_HASH}"
export PROJECT_ROOT PROJECT_HASH CMM_SENTINEL CTX_SENTINEL

_PROJECT_ROOT_LOADED=1
