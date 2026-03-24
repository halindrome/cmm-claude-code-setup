#!/bin/bash
# cmm-nudge.sh — PreToolUse:Read hook (non-blocking CMM nudge)
# NON-BLOCKING: always exits 0 (advisory only, never blocks)
#
# Install: cp -r hooks/lib ~/.claude/hooks/ && cp hooks/global/cmm-nudge.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/cmm-nudge.sh
# Register in ~/.claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "Read", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/cmm-nudge.sh"}] }] }

# --- Input Parsing ---
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null)

[ -z "$FILE_PATH" ] && exit 0

# --- Exception: Meta/Config Files (check BEFORE extension match) ---
BASENAME=$(basename "$FILE_PATH")
case "$BASENAME" in
  CLAUDE.md|MEMORY.md|AGENTS.md|README.md|CHANGELOG.md|LICENSE|LICENSE.md) exit 0 ;;
  *-PLAN.md|*-RESEARCH.md|*-CONTEXT.md|*-SUMMARY.md) exit 0 ;;
  conftest.py|setup.py|setup.cfg|pyproject.toml|package.json|tsconfig.json|Cargo.toml|go.mod|go.sum) exit 0 ;;
esac

# --- Exception: Planning/Config Paths ---
case "$FILE_PATH" in
  */.vbw-planning/*|*/.planning/*|*/.claude/*|*/node_modules/*|*/.git/*) exit 0 ;;
esac

# --- Extension Check: CMM Supported Languages (67 built-in + user-defined) ---
# Built-in list + user config from ~/.config/codebase-memory-mcp/config.json
# and {repo}/.codebase-memory.json (extra_extensions). Cached per session.
source "${BASH_SOURCE[0]%/*}/../lib/is-cmm-ext.sh" 2>/dev/null \
  || source "${BASH_SOURCE[0]%/*}/lib/is-cmm-ext.sh" 2>/dev/null \
  || { exit 0; } # if lib missing, don't block

is_cmm_ext "$FILE_PATH" || exit 0

# --- Exception: Small Files (<50 lines) ---
if [ -f "$FILE_PATH" ] && [ "$(wc -l < "$FILE_PATH" 2>/dev/null)" -lt 50 ]; then
  exit 0
fi

# --- Advisory Output ---
echo "Tip: CMM graph tools (search_graph, get_code_snippet, trace_call_path) may be faster than Read for codebase exploration."

exit 0
