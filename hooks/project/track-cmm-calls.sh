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

COUNTER_DIR="$HOME/.cache/codebase-memory-mcp"
COUNTER_FILE="$COUNTER_DIR/_call-counts.json"
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

exit 0
