#!/bin/bash
# track-hook-blocks.sh — Inline call from blocking hooks to increment block counts
# Usage: bash .claude/hooks/track-hook-blocks.sh "read"|"bash"
# Silent, never blocks, always exits 0.
#
# Install: cp hooks/project/track-hook-blocks.sh .claude/hooks/ && chmod +x .claude/hooks/track-hook-blocks.sh
# Called by: cmm-nudge.sh (read blocks), ctx-execute-enforcer.sh (bash blocks)

HOOK_TYPE="${1:-unknown}"

# --- Project Root Detection (same pattern as track-cmm-calls.sh) ---
# Walk the git superproject chain to find the outermost project root.
# Handles arbitrarily nested submodules. Falls back to BASH_SOURCE traversal.
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

# --- Git Worktree Detection ---
# git worktrees share the main repo but show-superproject-working-tree returns empty.
# Detect via git-common-dir: in a worktree it points to the main .git dir.
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

# Legacy orphaned .git/modules/<name>/ recovery — matches hooks/lib/project-root.sh
if [ -n "$PROJECT_ROOT" ]; then
    case "$PROJECT_ROOT" in
      */.git/*)
        _MODULES_OWNER="${PROJECT_ROOT%%/.git/*}"
        if [ -n "$_MODULES_OWNER" ] && [ -d "$_MODULES_OWNER" ]; then
            _CANDIDATE="$(cd "$_MODULES_OWNER" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)"
            case "$_CANDIDATE" in
              */.git/*|"") : ;;
              *) PROJECT_ROOT="$_CANDIDATE" ;;
            esac
        fi
        ;;
    esac
fi

PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')

COUNTER_DIR="$HOME/.cache/codebase-memory-mcp"
COUNTER_FILE="${COUNTER_DIR}/_block-counts-${PROJECT_HASH}.json"
mkdir -p "$COUNTER_DIR" 2>/dev/null

TEMP=$(mktemp)
HOOK_TYPE="$HOOK_TYPE" COUNTER_FILE="$COUNTER_FILE" TEMP="$TEMP" python3 -c "
import json, os

hook_type = os.environ['HOOK_TYPE']
counter_file = os.environ['COUNTER_FILE']
temp_path = os.environ['TEMP']

# Read existing data or start fresh
try:
    with open(counter_file, 'r') as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {'total_blocks': 0, 'read_blocks': 0, 'bash_blocks': 0, 'by_hook': {}}

# Increment counters
data['total_blocks'] = data.get('total_blocks', 0) + 1

if hook_type == 'read':
    data['read_blocks'] = data.get('read_blocks', 0) + 1
    data.setdefault('by_hook', {})['cmm-nudge'] = data.get('by_hook', {}).get('cmm-nudge', 0) + 1
elif hook_type == 'bash':
    data['bash_blocks'] = data.get('bash_blocks', 0) + 1
    data.setdefault('by_hook', {})['ctx-execute-enforcer'] = data.get('by_hook', {}).get('ctx-execute-enforcer', 0) + 1

# Write to temp file
with open(temp_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null && mv "$TEMP" "$COUNTER_FILE" 2>/dev/null || rm -f "$TEMP"

exit 0
