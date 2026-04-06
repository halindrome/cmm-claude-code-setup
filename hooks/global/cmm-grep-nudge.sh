#!/bin/bash
# cmm-grep-nudge.sh — PreToolUse:Grep hook (hard-blocking CMM Grep gate)
# BLOCKING: exits 2 for broad code searches when CMM is available, redirecting to graph tools.
#
# Install: cp hooks/global/cmm-grep-nudge.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/cmm-grep-nudge.sh
#   (or: setup.sh --project also copies to .claude/hooks/cmm-grep-nudge.sh for agent frontmatter hooks)
# Register in ~/.claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "Grep", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/cmm-grep-nudge.sh"}] }] }

# --- Input Parsing ---
INPUT=$(cat)
PARSED=$(echo "$INPUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ti=d.get('tool_input',{})
pattern=ti.get('pattern','') or ''
path=ti.get('path','') or ''
glob=ti.get('glob','') or ''
gtype=ti.get('type','') or ''
print(pattern)
print(path)
print(glob)
print(gtype)
" 2>/dev/null)

GREP_PATTERN=$(echo "$PARSED" | sed -n '1p')
GREP_PATH=$(echo "$PARSED" | sed -n '2p')
GREP_GLOB=$(echo "$PARSED" | sed -n '3p')
GREP_TYPE=$(echo "$PARSED" | sed -n '4p')

# Fail open on empty pattern or parse error
[ -z "$GREP_PATTERN" ] && exit 0

# --- Exception: Planning/Config Paths ---
case "$GREP_PATH" in
  */.vbw-planning/*|*/.vbw-planning|*/.planning/*|*/.planning|\
  */.claude/*|*/.claude|*/node_modules/*|*/node_modules|*/.git/*|*/.git)
    exit 0 ;;
esac

# --- Exception: Single-file path (targeted search, not a directory scan) ---
if [ -n "$GREP_PATH" ] && [ -f "$GREP_PATH" ]; then
  exit 0
fi

# --- CMM Availability Check (fail open if CMM not configured) ---
# Derive repo root: prefer path argument, then cwd from JSON, then current dir.
# Mirrors cmm-nudge.sh pattern (which uses git -C dirname(file_path)).
REPO_ROOT=""
if [ -n "$GREP_PATH" ] && [ -e "$GREP_PATH" ]; then
  REPO_ROOT=$(git -C "$GREP_PATH" rev-parse --show-toplevel 2>/dev/null)
fi
if [ -z "$REPO_ROOT" ]; then
  CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
  if [ -n "$CWD" ]; then
    REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")
  fi
fi
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
fi

CMM_FOUND=false
if [ -f "$REPO_ROOT/.mcp.json" ] && grep -q 'codebase-memory-mcp' "$REPO_ROOT/.mcp.json" 2>/dev/null; then
  CMM_FOUND=true
fi
if [ "$CMM_FOUND" = false ]; then
  CLAUDE_SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  if [ -f "$CLAUDE_SETTINGS" ] && grep -q 'codebase-memory-mcp' "$CLAUDE_SETTINGS" 2>/dev/null; then
    CMM_FOUND=true
  fi
fi
[ "$CMM_FOUND" = false ] && exit 0

# --- Exception: Non-code glob (allow Grep for config/doc file types) ---
case "$GREP_GLOB" in
  *.json|*.yaml|*.yml|*.toml|*.md|*.mdx|*.txt|*.env|*.ini|*.cfg|*.conf|\
  *.xml|*.csv|*.lock|*.sum|*.html|*.htm|*.css|*.svg)
    exit 0 ;;
esac

# --- Exception: Non-code type filter ---
case "$GREP_TYPE" in
  json|yaml|toml|markdown|txt|html|css|xml)
    exit 0 ;;
esac

# --- Block: Redirect to CMM graph tools (stderr, exit 2) ---
cat >&2 <<EOF
BLOCKED: Use CMM graph tools instead of Grep for code search.
  - Find by name/definition: mcp__codebase-memory-mcp__search_graph
  - Search code text/patterns: mcp__codebase-memory-mcp__search_code
  Grep is allowed when:
    - searching non-code files (JSON, YAML, Markdown, config)
    - searching a single specific file path
    - searching inside .vbw-planning/, .claude/, node_modules/, .git/
EOF

# --- Block Counter ---
bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "grep" 2>/dev/null || true

exit 2
