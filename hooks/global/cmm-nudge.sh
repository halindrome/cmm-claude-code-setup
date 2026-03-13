#!/bin/bash
# cmm-nudge.sh — PreToolUse:Read hook (non-blocking CMM nudge)
# NON-BLOCKING: always exits 0 (advisory only, never blocks)
#
# Install: cp hooks/global/cmm-nudge.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/cmm-nudge.sh
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

# --- Extension Check: CMM Supported Languages (64 languages) ---
# Update this list if CMM adds new language support
case "$FILE_PATH" in
  *.py|*.go|*.js|*.jsx|*.ts|*.tsx|*.rs|*.java|*.cpp|*.cc|*.cxx|*.c|*.h|*.hpp|*.cs|\
  *.php|*.lua|*.scala|*.kt|*.kts|*.rb|*.sh|*.bash|*.zsh|*.zig|*.ex|*.exs|*.hs|\
  *.ml|*.mli|*.m|*.mm|*.swift|*.dart|*.pl|*.pm|*.groovy|*.erl|*.hrl|*.r|*.R|\
  *.clj|*.cljs|*.cljc|*.fs|*.fsx|*.fsi|*.jl|*.vim|*.nix|*.lisp|*.cl|*.elm|\
  *.f90|*.f95|*.f03|*.cu|*.cuh|*.cob|*.cbl|*.v|*.sv|*.el|*.lean|*.frm|*.wl|*.wls|\
  *.html|*.css|*.scss|*.sass|*.yaml|*.yml|*.toml|*.hcl|*.tf|*.sql|*.vue|*.svelte|\
  *.graphql|*.gql|*.proto|*.cmake|*.glsl|*.ini|*.cfg)
    ;; # matched — continue to checks below
  *)
    exit 0 ;; # not a CMM-indexed file type
esac

# --- Exception: Small Files (<50 lines) ---
if [ -f "$FILE_PATH" ] && [ "$(wc -l < "$FILE_PATH" 2>/dev/null)" -lt 50 ]; then
  exit 0
fi

# --- Advisory Output ---
echo "Tip: CMM graph tools (search_graph, get_code_snippet, trace_call_path) may be faster than Read for codebase exploration."

exit 0
