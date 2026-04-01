#!/bin/bash
# track-hook-blocks.sh — Inline call from blocking hooks to increment block counts
# Usage: bash .claude/hooks/track-hook-blocks.sh "read"|"bash"
# Silent, never blocks, always exits 0.
#
# Install: cp hooks/project/track-hook-blocks.sh .claude/hooks/ && chmod +x .claude/hooks/track-hook-blocks.sh
# Called by: cmm-nudge.sh (read blocks), ctx-execute-enforcer.sh (bash blocks)

HOOK_TYPE="${1:-unknown}"

# --- Project Root Detection (CWD-based, same as track-cmm-calls.sh) ---
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')

COUNTER_DIR="$HOME/.cache/codebase-memory-mcp"
COUNTER_FILE="${COUNTER_DIR}/_block-counts-${PROJECT_HASH}.json"
mkdir -p "$COUNTER_DIR" 2>/dev/null

TEMP=$(mktemp)
python3 -c "
import json, os

hook_type = '$HOOK_TYPE'
counter_file = '$COUNTER_FILE'

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
with open('$TEMP', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null && mv "$TEMP" "$COUNTER_FILE" 2>/dev/null || rm -f "$TEMP"

exit 0
