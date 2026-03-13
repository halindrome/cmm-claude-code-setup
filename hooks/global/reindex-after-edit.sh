#!/bin/bash
# reindex-after-edit.sh — PostToolUse:Write|Edit hook (CMM reindex reminder)
# NON-BLOCKING: always exits 0 (advisory only, never blocks)
# Debounce: 60 seconds between prompts
#
# Install: cp hooks/global/reindex-after-edit.sh ~/.claude/hooks/
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

# Only trigger for CMM-indexed file types (64 languages)
case "$FILE" in
  *.py|*.go|*.js|*.jsx|*.ts|*.tsx|*.rs|*.java|*.cpp|*.cc|*.cxx|*.c|*.h|*.hpp|\
*.cs|*.php|*.lua|*.scala|*.kt|*.kts|*.rb|*.sh|*.bash|*.zsh|*.zig|*.ex|*.exs|\
*.hs|*.ml|*.mli|*.m|*.mm|*.swift|*.dart|*.pl|*.pm|*.groovy|*.erl|*.hrl|\
*.r|*.R|*.clj|*.cljs|*.cljc|*.fs|*.fsx|*.fsi|*.jl|*.vim|*.nix|*.lisp|*.cl|\
*.elm|*.f90|*.f95|*.f03|*.cu|*.cuh|*.cob|*.cbl|*.v|*.sv|*.el|*.lean|*.frm|\
*.wl|*.wls|*.html|*.css|*.scss|*.sass|*.yaml|*.yml|*.toml|*.hcl|*.tf|*.sql|\
*.vue|*.svelte|*.graphql|*.gql|*.proto|*.cmake|*.glsl|*.ini|*.cfg)
    ;; # matched — continue
  *) exit 0 ;; # not a CMM-indexed file type
esac

# Debounce: skip if we prompted within the last 60 seconds
STAMP="/tmp/cmm-reindex-stamp-$(id -u)"
if [ -f "$STAMP" ]; then
  # Cross-platform stat: macOS uses -f %m, Linux uses -c %Y
  LAST=$(stat -f %m "$STAMP" 2>/dev/null || stat -c %Y "$STAMP" 2>/dev/null || echo 0)
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
