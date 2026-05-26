#!/bin/bash
# cmm-query-stale-advisory.sh — PostToolUse:CMM query tools (stale index advisory)
# Non-blocking: prints advisory to stderr if CMM index is stale after a recent commit.
#
# Install: cp hooks/project/cmm-query-stale-advisory.sh .claude/hooks/ && chmod +x .claude/hooks/cmm-query-stale-advisory.sh
# Register in .claude/settings.json under PostToolUse with matcher:
#   mcp__codebase-memory-mcp__search_graph|mcp__codebase-memory-mcp__get_code_snippet|mcp__codebase-memory-mcp__trace_path|mcp__codebase-memory-mcp__query_graph
# Matcher: PostToolUse:CMM query tools

# --- Project root detection (shared library with /tmp cache) ---
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" 2>/dev/null && pwd -P)"
if [ -f "$_LIB_DIR/project-root.sh" ]; then
  source "$_LIB_DIR/project-root.sh"
else
  # Fallback: inline detection (pre-optimization installs)
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
  if [ -n "$PROJECT_ROOT" ]; then
      _GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --git-dir 2>/dev/null)"
      _GIT_COMMON="$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null)"
      [ "${_GIT_DIR:0:1}" != "/" ]    && _GIT_DIR="$PROJECT_ROOT/$_GIT_DIR"
      [ "${_GIT_COMMON:0:1}" != "/" ] && _GIT_COMMON="$PROJECT_ROOT/$_GIT_COMMON"
      if [ "$_GIT_DIR" != "$_GIT_COMMON" ]; then
          _MAIN_ROOT="$(cd "$_GIT_COMMON/.." 2>/dev/null && pwd -P)"
          [ -n "$_MAIN_ROOT" ] && PROJECT_ROOT="$_MAIN_ROOT"
      fi
  fi
  PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')
  CMM_SENTINEL="/tmp/cmm-session-ready-${PROJECT_HASH}"
fi

# --- Stale Check ---
# If the sentinel exists and contains exactly "stale" (anchored), print advisory to stderr.
# If sentinel is absent or contains "ready", exit silently.
# Always exit 0 — this hook is advisory only, never blocking.
if [ -f "$CMM_SENTINEL" ] && grep -q '^stale$' "$CMM_SENTINEL"; then
    echo "⚠ CMM index may be stale — run index_repository for up-to-date results." >&2
fi

exit 0
