#!/bin/bash
# context-mode-sentinel-writer.sh — PostToolUse hook (writes Context Mode session sentinel)
# NON-BLOCKING: always exits 0 (writes sentinel to unblock session-gate.sh Context Mode check)
#
# Purpose: Writes the Context Mode sentinel file after any ctx_* initialization tool
#          completes, unblocking tools gated by the Context Mode phase in session-gate.sh.
#
# Install: cp hooks/project/context-mode-sentinel-writer.sh .claude/hooks/
#          chmod +x .claude/hooks/context-mode-sentinel-writer.sh
# Register in .claude/settings.json:
#   PostToolUse matcher: mcp__context-mode__ctx_execute|...|mcp__context-mode__ctx_search|...|mcp__context-mode__ctx_stats

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
fi

# --- Path Integrity Check ---
_SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P 2>/dev/null)"
if [ -n "$_SCRIPT_ROOT" ] && [ -n "$PROJECT_ROOT" ] && [ "$_SCRIPT_ROOT" != "$PROJECT_ROOT" ]; then
    echo "cmm-hooks: path mismatch — hooks registered for '$_SCRIPT_ROOT' but git root is '$PROJECT_ROOT'." >&2
    echo "Project was moved or cloned. Re-run: bash setup.sh --project --force" >&2
fi

# --- Context Mode Presence Check (shared library) ---
# Uncached: this hook runs only after a ctx_* tool call, so the probe cost is
# negligible and a fresh read avoids writing a sentinel from stale state.
_CM_LIB=""
for _d in "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
  [ -f "$_d/context-mode-detect.sh" ] && { _CM_LIB="$_d/context-mode-detect.sh"; break; }
done
if [ -n "$_CM_LIB" ]; then
  source "$_CM_LIB"
  detect_context_mode "$PROJECT_ROOT"
else
  exit 0
fi

if [ "$CONTEXT_MODE_INSTALLED" -eq 0 ]; then
  exit 0
fi

# Write sentinel to unblock session gate
echo "ready" > "/tmp/context-mode-ready-${PROJECT_HASH}"

exit 0
