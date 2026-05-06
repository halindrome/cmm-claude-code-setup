#!/bin/bash
# reindex-after-edit.sh — PostToolUse:Write|Edit hook (CMM reindex reminder)
# NON-BLOCKING: always exits 0 (advisory only, never blocks)
# Debounce: 60 seconds between prompts
#
# Install: cp -r hooks/lib ~/.claude/hooks/ && cp hooks/global/reindex-after-edit.sh ~/.claude/hooks/
#          chmod +x ~/.claude/hooks/reindex-after-edit.sh
# Register in ~/.claude/settings.json:
#   "hooks": { "PostToolUse": [{ "matcher": "Write|Edit", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/reindex-after-edit.sh"}] }] }

INPUT=$(cat)

# Try jq first, fall back to python3
if command -v jq >/dev/null 2>&1; then
  FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
else
  FILE=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('file_path', '') or ti.get('path', ''))
" 2>/dev/null)
fi

# Skip if no file path
[ -z "$FILE" ] && exit 0

# Skip planning artifacts and config paths (don't need reindex)
case "$FILE" in
  */.vbw-planning/*|*/.claude/*|*/.git/*) exit 0 ;;
esac

# Only trigger for CMM-indexed file types (67 built-in + user-defined)
source "${BASH_SOURCE[0]%/*}/../lib/is-cmm-ext.sh" 2>/dev/null \
  || source "${BASH_SOURCE[0]%/*}/lib/is-cmm-ext.sh" 2>/dev/null \
  || { exit 0; }

is_cmm_ext "$FILE" || exit 0

# Debounce: skip if we prompted within the last 60 seconds
STAMP="/tmp/cmm-reindex-stamp-$(id -u)"
if [ -f "$STAMP" ]; then
  # Cross-platform mtime: date -r works on both BSD (macOS) and GNU (Linux)
  LAST=$(date -r "$STAMP" +%s 2>/dev/null || echo 0)
  NOW=$(date +%s)
  if [ $((NOW - LAST)) -lt 60 ]; then
    exit 0
  fi
fi
touch "$STAMP"

# Advisory output — extract just the filename for readability
BASENAME=$(basename "$FILE")
echo "Source file modified: $BASENAME"
echo "Consider refreshing the CMM index: index_repository"
echo "(Auto-sync may handle this automatically if enabled)"

exit 0
