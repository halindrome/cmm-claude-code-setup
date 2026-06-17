#!/bin/bash
# track-cmm-calls.sh — PostToolUse:mcp__codebase-memory-mcp__* hook (CMM call counter)
# Tracks call counts per CMM tool. Silent, never blocks, always exits 0.
#
# Install: cp hooks/project/track-cmm-calls.sh .claude/hooks/ && chmod +x .claude/hooks/track-cmm-calls.sh
# Register in .claude/settings.json:
#   "hooks": { "PostToolUse": [{ "matcher": "mcp__codebase-memory-mcp__*", "hooks": [{"type": "command", "command": "bash .claude/hooks/track-cmm-calls.sh"}] }] }
#
# Matcher: mcp__codebase-memory-mcp__* (all CMM tools)

INPUT=$(cat)
TOOL=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

[ -z "$TOOL" ] && exit 0

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
  [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P 2>/dev/null)"
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

COUNTER_DIR="$HOME/.cache/codebase-memory-mcp"
COUNTER_FILE="${COUNTER_DIR}/_call-counts-${PROJECT_HASH}.json"
mkdir -p "$COUNTER_DIR" 2>/dev/null

TEMP=$(mktemp)
python3 -c "
import json, os

tool = '$TOOL'
counter_file = '$COUNTER_FILE'

# Read existing data or start fresh
try:
    with open(counter_file, 'r') as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {'total_calls': 0, 'by_tool': {}}

# Increment counters
data['total_calls'] = data.get('total_calls', 0) + 1
data['by_tool'][tool] = data.get('by_tool', {}).get(tool, 0) + 1

# Write to temp file
with open('$TEMP', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null && mv "$TEMP" "$COUNTER_FILE" 2>/dev/null || rm -f "$TEMP"

# NOTE: the /tmp/cmm-recent-${PROJECT_HASH} sentinel (Phase 47 Finding B) was removed
# when cmm-nudge.sh moved from a hard-block + 60s recency gate to a soft per-file read
# budget. There is no longer a recency consumer, so this hook only maintains call counts.

exit 0
