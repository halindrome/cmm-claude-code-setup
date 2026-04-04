#!/bin/bash
# cmm-nudge.sh — PreToolUse:Read hook (hard-blocking CMM Read gate)
# BLOCKING: exits 2 for code files when CMM is available, redirecting to graph tools.
#
# Install: cp hooks/global/cmm-nudge.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/cmm-nudge.sh
#   (or: setup.sh --project also copies to .claude/hooks/cmm-nudge.sh for agent frontmatter hooks)
# Register in ~/.claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "Read", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/cmm-nudge.sh"}] }] }

# --- Input Parsing (dual-form: tool_input.file_path + top-level fallback) ---
INPUT=$(cat)
PARSED=$(echo "$INPUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ti=d.get('tool_input',{})
fp=ti.get('file_path','') or d.get('file_path','')
has_offset='1' if (ti.get('offset') is not None and ti.get('limit') is not None) else '0'
limit=str(ti.get('limit',0))
offset=str(ti.get('offset',0) or 0)
print(fp)
print(has_offset)
print(limit)
print(offset)
" 2>/dev/null)

FILE_PATH=$(echo "$PARSED" | sed -n '1p')
HAS_OFFSET=$(echo "$PARSED" | sed -n '2p')
READ_LIMIT=$(echo "$PARSED" | sed -n '3p')
READ_OFFSET=$(echo "$PARSED" | sed -n '4p')

[ -z "$FILE_PATH" ] && exit 0



# --- Exception: Targeted Read with offset+limit (sliced edit workflow) ---
if [ "$HAS_OFFSET" = "1" ] && [ "${READ_LIMIT:-0}" -le 100 ] 2>/dev/null; then
  exit 0
fi

# --- Exception: Meta/Config Files (check BEFORE extension match) ---
BASENAME=$(basename "$FILE_PATH")
case "$BASENAME" in
  CLAUDE.md|MEMORY.md|AGENTS.md|README.md|CONTRIBUTING.md|CHANGELOG.md|LICENSE|LICENSE.md) exit 0 ;;
  *-PLAN.md|*-RESEARCH.md|*-CONTEXT.md|*-SUMMARY.md|*-UAT.md|*-VERIFICATION.md) exit 0 ;;
  conftest.py|setup.py|setup.cfg|pyproject.toml|package.json|tsconfig.json|Cargo.toml|go.mod|go.sum|Makefile|Dockerfile) exit 0 ;;
esac

# --- Exception: Planning/Config Paths ---
case "$FILE_PATH" in
  */.vbw-planning/*|*/.planning/*|*/.claude/*|*/node_modules/*|*/.git/*) exit 0 ;;
esac

# --- CMM Availability Check (safety valve — don't block if CMM isn't configured) ---
REPO_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
  CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
  REPO_ROOT="${CWD:-.}"
fi

CMM_FOUND=false
# Check project .mcp.json
if [ -f "$REPO_ROOT/.mcp.json" ] && grep -q 'codebase-memory-mcp' "$REPO_ROOT/.mcp.json" 2>/dev/null; then
  CMM_FOUND=true
fi
# Check global settings.json as fallback
if [ "$CMM_FOUND" = false ]; then
  CLAUDE_SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  if [ -f "$CLAUDE_SETTINGS" ] && grep -q 'codebase-memory-mcp' "$CLAUDE_SETTINGS" 2>/dev/null; then
    CMM_FOUND=true
  fi
fi
# If CMM not found anywhere, allow Read (fail open)
[ "$CMM_FOUND" = false ] && exit 0

# --- Inline Extension Case (THE BLOCK DECISION — pure code extensions only) ---
case "$FILE_PATH" in
  *.py|*.go|*.js|*.jsx|*.ts|*.tsx|*.rs|*.java|*.cpp|*.cc|*.cxx|*.c|*.h|*.hpp|\
  *.cs|*.php|*.lua|*.scala|*.kt|*.rb|*.sh|*.bash|*.zsh|*.zig|*.ex|*.exs|*.hs|\
  *.swift|*.dart|*.pl|*.pm|*.groovy|*.erl|*.r|*.R|*.clj|*.fs|*.jl|*.el|*.cu|\
  *.sql|*.vue|*.svelte|*.graphql|*.proto|*.ml|*.m|*.mm|*.nix|*.elm|*.lean|\
  *.f90|*.f95|*.f03|*.f08|*.cuh|*.v|*.sv|*.glsl|*.frag|*.vert)
    ;; # matched — continue to block check
  *)
    exit 0 ;; # non-code extension — allow Read
esac

# --- Exception: Non-existent files (CMM can't index them either) ---
[ ! -f "$FILE_PATH" ] && exit 0

# --- Exception: Small Files (<50 lines) ---
if [ "$(wc -l < "$FILE_PATH" 2>/dev/null)" -lt 50 ]; then
  exit 0
fi

# --- Block: Redirect to CMM graph tools (stderr, exit 2) ---
cat >&2 <<EOF
BLOCKED: Use CMM graph tools instead of Read for '$BASENAME'.
  - Find by name:  mcp__codebase-memory-mcp__search_graph
  - Fetch source:  mcp__codebase-memory-mcp__get_code_snippet
  - Trace callers: mcp__codebase-memory-mcp__trace_call_path
  - Edit workflow: search_graph -> get_code_snippet (line range) -> Read(offset=N, limit=M) -> Edit
  Full Read is allowed when:
    - targeted read with offset+limit (up to 100 lines)
    - editing 6+ functions in same file
    - need imports/globals/module-level init
    - file < 50 lines
    - non-code files (JSON, YAML, Markdown, config)
EOF

# --- Block Counter ---
bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "read" 2>/dev/null || true

exit 2
