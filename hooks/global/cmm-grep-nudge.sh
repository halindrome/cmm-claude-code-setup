#!/bin/bash
# cmm-grep-nudge.sh — PreToolUse:Grep hook (hard-blocking CMM Grep gate)
# BLOCKING: exits 2 for code-targeted Grep when CMM is available, redirecting to graph tools.
#
# Install: cp hooks/global/cmm-grep-nudge.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/cmm-grep-nudge.sh
# Register in ~/.claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "Grep", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/cmm-grep-nudge.sh"}] }] }

# --- Input Parsing ---
INPUT=$(cat)
PARSED=$(echo "$INPUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ti=d.get('tool_input',{})
glob_field=ti.get('glob','') or ''
type_field=ti.get('type','') or ''
path_field=ti.get('path','') or ''
pattern_field=ti.get('pattern','') or ''
print(glob_field)
print(type_field)
print(path_field)
print(pattern_field)
" 2>/dev/null)

GLOB_FIELD=$(echo "$PARSED" | sed -n '1p')
TYPE_FIELD=$(echo "$PARSED" | sed -n '2p')
PATH_FIELD=$(echo "$PARSED" | sed -n '3p')
PATTERN_FIELD=$(echo "$PARSED" | sed -n '4p')

# --- Exception: Planning/Config Paths (check path early) ---
case "$PATH_FIELD" in
  */.vbw-planning/*|*/.planning/*|*/.claude/*|*/node_modules/*|*/.git/*) exit 0 ;;
esac

# --- CMM Availability Check (safety valve — don't block if CMM isn't configured) ---
# Determine repo root from path field or cwd
if [ -n "$PATH_FIELD" ] && [ -d "$PATH_FIELD" ]; then
  REPO_ROOT=$(git -C "$PATH_FIELD" rev-parse --show-toplevel 2>/dev/null)
elif [ -n "$PATH_FIELD" ] && [ -f "$PATH_FIELD" ]; then
  REPO_ROOT=$(git -C "$(dirname "$PATH_FIELD")" rev-parse --show-toplevel 2>/dev/null)
fi
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
# If CMM not found anywhere, allow Grep (fail open)
[ "$CMM_FOUND" = false ] && exit 0

# --- Extra extensions cache (from .codebase-memory.json) ---
_EXT_CACHE=""
if [ -n "$REPO_ROOT" ]; then
  _EXT_CACHE="/tmp/cmm-user-ext-$(echo -n "$REPO_ROOT" | md5 -q 2>/dev/null || echo -n "$REPO_ROOT" | md5sum 2>/dev/null | cut -d' ' -f1)"
  if [ ! -f "$_EXT_CACHE" ]; then
    python3 -c "
import json, os
for p in ['${REPO_ROOT}/.codebase-memory.json']:
    if os.path.isfile(p):
        try:
            for ext in json.load(open(p)).get('extra_extensions',{}):
                print(ext)
        except: pass
" 2>/dev/null > "$_EXT_CACHE" || rm -f "$_EXT_CACHE"
  fi
fi

# Helper: check if a filename matches code extensions (inline list + extra_extensions)
_is_code_file() {
  local f="$1"
  case "$f" in
    *.py|*.go|*.js|*.jsx|*.ts|*.tsx|*.rs|*.java|*.cpp|*.cc|*.cxx|*.c|*.h|*.hpp|\
    *.cs|*.php|*.lua|*.scala|*.kt|*.rb|*.sh|*.bash|*.zsh|*.zig|*.ex|*.exs|*.hs|\
    *.swift|*.dart|*.pl|*.pm|*.groovy|*.erl|*.r|*.R|*.clj|*.fs|*.jl|*.el|*.cu|\
    *.sql|*.vue|*.svelte|*.graphql|*.proto|*.ml|*.m|*.mm|*.nix|*.elm|*.lean|\
    *.f90|*.f95|*.f03|*.f08|*.cuh|*.v|*.sv|*.glsl|*.frag|*.vert)
      return 0 ;;
  esac
  if [ -n "$_EXT_CACHE" ] && [ -s "$_EXT_CACHE" ]; then
    local bn; bn=$(basename "$f")
    while IFS= read -r _ext; do
      case "$bn" in *"$_ext") return 0 ;; esac
    done < "$_EXT_CACHE"
  fi
  return 1
}

SHOULD_BLOCK=false
BLOCK_TARGET=""

# --- Check glob field for code extensions ---
if [ -n "$GLOB_FIELD" ]; then
  _GLOB_MATCHED=false
  # Handle brace-expansion globs like *.{ts,tsx}
  if echo "$GLOB_FIELD" | grep -q '{.*}'; then
    _BRACE_CONTENT=$(echo "$GLOB_FIELD" | sed 's/.*{\(.*\)}.*/\1/')
    IFS=',' read -ra _EXTS <<< "$_BRACE_CONTENT"
    for _EXT in "${_EXTS[@]}"; do
      if _is_code_file "file.$_EXT"; then _GLOB_MATCHED=true; break; fi
    done
  fi
  # Standard glob: extract extension suffix
  if [ "$_GLOB_MATCHED" = false ]; then
    _GLOB_SUFFIX="${GLOB_FIELD##*\*}"
    if [ -n "$_GLOB_SUFFIX" ] && [ "$_GLOB_SUFFIX" != "$GLOB_FIELD" ]; then
      _is_code_file "file${_GLOB_SUFFIX}" && _GLOB_MATCHED=true
    fi
  fi
  if [ "$_GLOB_MATCHED" = true ]; then
    SHOULD_BLOCK=true
    BLOCK_TARGET="glob='$GLOB_FIELD'"
  fi
fi

# --- Check type field for code types ---
if [ "$SHOULD_BLOCK" = false ] && [ -n "$TYPE_FIELD" ]; then
  case "$TYPE_FIELD" in
    py|python|go|js|jsx|ts|tsx|rust|java|cpp|c|cs|csharp|php|lua|scala|kotlin|\
    rb|ruby|sh|bash|zsh|zig|elixir|haskell|swift|dart|perl|groovy|erlang|r|\
    clojure|fsharp|julia|elisp|cuda|sql|vue|svelte|graphql|protobuf|ocaml|\
    objc|nix|elm|lean|fortran|verilog|glsl)
      SHOULD_BLOCK=true
      BLOCK_TARGET="type='$TYPE_FIELD'" ;;
  esac
fi

# --- Check path field for specific code file (only if glob/type not set) ---
if [ "$SHOULD_BLOCK" = false ] && [ -z "$GLOB_FIELD" ] && [ -z "$TYPE_FIELD" ] && [ -n "$PATH_FIELD" ]; then
  if _is_code_file "$PATH_FIELD"; then
    SHOULD_BLOCK=true
    BLOCK_TARGET="path='$(basename "$PATH_FIELD")'"
  fi
fi

# --- Allow if no code target detected ---
[ "$SHOULD_BLOCK" = false ] && exit 0

# --- Block: Redirect to CMM search tools (stderr, exit 2) ---
cat >&2 <<EOF
BLOCKED: Use CMM tools instead of Grep for code search on $BLOCK_TARGET.
  - Symbol search:  mcp__codebase-memory-mcp__search_graph(name_pattern="...")
  - Text search:    mcp__codebase-memory-mcp__search_code(query="...")
  - Trace callers:  mcp__codebase-memory-mcp__trace_call_path
  Grep is allowed for: non-code files (JSON, YAML, Markdown, config, env)
EOF

# --- Block Counter ---
bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "grep" 2>/dev/null || true

exit 2
