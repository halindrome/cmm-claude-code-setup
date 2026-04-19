#!/bin/bash
# grep-cmm-gate.sh — PreToolUse:Grep hook (hard-block source-code Grep in indexed CMM repos with machine-readable REPLACE WITH: advisory)
# BLOCKING: exits 2 for code-targeted Grep when CMM is registered AND the project is indexed (sentinel present); otherwise exits 0.
#
# Install: cp hooks/project/grep-cmm-gate.sh .claude/hooks/ && chmod +x .claude/hooks/grep-cmm-gate.sh
# Register in .claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "Grep", "hooks": [{"type": "command", "command": "bash .claude/hooks/grep-cmm-gate.sh"}] }] }
# Matcher: PreToolUse:Grep
#
# Coexists with hooks/global/cmm-grep-nudge.sh (global soft advisory). Hook order: global soft first, project hard second.

# --- Input Parsing ---
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

PARSED=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get('tool_name',''))
ti = d.get('tool_input',{}) or {}
print(ti.get('pattern','') or '')
print(ti.get('type','') or '')
print(ti.get('glob','') or '')
print(ti.get('path','') or '')
print(d.get('cwd','') or '')
" 2>/dev/null)

# Malformed JSON or parse failure → fail open
[ -z "$PARSED" ] && exit 0

TOOL_NAME=$(echo "$PARSED" | sed -n '1p')
PATTERN_FIELD=$(echo "$PARSED" | sed -n '2p')
TYPE_FIELD=$(echo "$PARSED" | sed -n '3p')
GLOB_FIELD=$(echo "$PARSED" | sed -n '4p')
PATH_FIELD=$(echo "$PARSED" | sed -n '5p')
CWD_FIELD=$(echo "$PARSED" | sed -n '6p')

# Only match Grep — every other tool is a no-op
[ "$TOOL_NAME" != "Grep" ] && exit 0

# --- Exempt fast paths ---

# Bypass marker in pattern
if echo "$PATTERN_FIELD" | grep -q '# cmm-exempt'; then
    exit 0
fi

# Explicit non-code type → allow
case "$TYPE_FIELD" in
  yaml|yml|json|toml|md|markdown|lock|xml|ini|cfg|conf|txt|html|css|env)
    exit 0 ;;
esac

# Explicit non-code glob → allow
case "$GLOB_FIELD" in
  *.yml|*.yaml|*.json|*.md|*.markdown|*.toml|*.lock|*.xml|*.ini|*.cfg|*.conf|*.txt|*.html|*.css|*.env)
    exit 0 ;;
esac

# Planning/config path exemptions (parity with cmm-grep-nudge.sh)
case "$PATH_FIELD" in
  */.vbw-planning/*|*/.planning/*|*/.claude/*|*/node_modules/*|*/.git/*) exit 0 ;;
esac

# --- Determine repo root (walk upward from path or cwd) ---
REPO_ROOT=""
if [ -n "$PATH_FIELD" ] && [ -d "$PATH_FIELD" ]; then
    REPO_ROOT=$(git -C "$PATH_FIELD" rev-parse --show-toplevel 2>/dev/null)
elif [ -n "$PATH_FIELD" ] && [ -f "$PATH_FIELD" ]; then
    REPO_ROOT=$(git -C "$(dirname "$PATH_FIELD")" rev-parse --show-toplevel 2>/dev/null)
fi
if [ -z "$REPO_ROOT" ] && [ -n "$CWD_FIELD" ] && [ -d "$CWD_FIELD" ]; then
    REPO_ROOT=$(git -C "$CWD_FIELD" rev-parse --show-toplevel 2>/dev/null)
    [ -z "$REPO_ROOT" ] && REPO_ROOT="$CWD_FIELD"
fi
[ -z "$REPO_ROOT" ] && exit 0

# --- Small-file exemption: specific file under 50 lines ---
if [ -n "$PATH_FIELD" ] && [ -f "$PATH_FIELD" ]; then
    _LINES=$(wc -l < "$PATH_FIELD" 2>/dev/null || echo 9999)
    if [ "${_LINES:-9999}" -lt 50 ] 2>/dev/null; then
        exit 0
    fi
fi

# --- CMM availability check (.mcp.json cascade, parity with cmm-nudge.sh / cmm-grep-nudge.sh) ---
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
# If CMM not registered anywhere, fail open
[ "$CMM_FOUND" = false ] && exit 0

# --- Indexed-repo sentinel probe (parity with ctx-execute-enforcer.sh md5 pattern) ---
PROJECT_HASH=$(echo "$REPO_ROOT" | md5 -q 2>/dev/null || echo "$REPO_ROOT" | md5sum 2>/dev/null | awk '{print $1}')
[ -z "$PROJECT_HASH" ] && exit 0
CMM_SENTINEL="/tmp/cmm-session-ready-${PROJECT_HASH}"
# If project not yet indexed for this session, fail open (same deadlock-prevention posture as ctx-execute-enforcer)
[ ! -f "$CMM_SENTINEL" ] && exit 0

# --- Block-trigger decision tree ---
SHOULD_BLOCK=false

# (a) type is a CMM-indexed language
case "$TYPE_FIELD" in
  go|py|python|js|ts|tsx|jsx|sh|bash|rs|rust|java|rb|ruby|c|cpp|h|hpp|swift|kt|kotlin|php|cs|csharp|scala|lua|zig|ex|exs|elixir|hs|haskell|dart|pl|perl|pm|groovy|erl|erlang|r|clj|clojure|fs|fsharp|jl|julia|el|elisp|cu|cuda|sql|vue|svelte|graphql|proto|protobuf|ml|ocaml|m|mm|objc|nix|elm|lean|f90|f95|f03|f08|fortran|v|sv|verilog|glsl|frag|vert)
    SHOULD_BLOCK=true ;;
esac

# (b) glob matches a code extension
if [ "$SHOULD_BLOCK" = false ] && [ -n "$GLOB_FIELD" ]; then
    case "$GLOB_FIELD" in
      *.go|*.py|*.js|*.jsx|*.ts|*.tsx|*.sh|*.bash|*.rs|*.java|*.rb|*.c|*.cc|*.cpp|*.cxx|*.h|*.hpp|*.swift|*.kt|*.php|*.cs|*.scala|*.lua|*.zig|*.ex|*.exs|*.hs|*.dart|*.pl|*.pm|*.groovy|*.erl|*.r|*.R|*.clj|*.fs|*.jl|*.el|*.cu|*.sql|*.vue|*.svelte|*.graphql|*.proto|*.ml|*.m|*.mm|*.nix|*.elm|*.lean|*.f90|*.f95|*.f03|*.f08|*.cuh|*.v|*.sv|*.glsl|*.frag|*.vert)
        SHOULD_BLOCK=true ;;
      *\{*\}*)
        # Brace expansion like *.{ts,tsx} — inspect each alternative
        _BRACE=$(echo "$GLOB_FIELD" | sed 's/.*{\(.*\)}.*/\1/')
        IFS=',' read -ra _EXTS <<< "$_BRACE"
        for _E in "${_EXTS[@]}"; do
            case ".${_E}" in
              .go|.py|.js|.jsx|.ts|.tsx|.sh|.bash|.rs|.java|.rb|.c|.cc|.cpp|.cxx|.h|.hpp|.swift|.kt|.php|.cs|.scala|.lua|.zig|.ex|.exs|.hs|.dart|.pl|.pm|.groovy|.erl|.r|.R|.clj|.fs|.jl|.el|.cu|.sql|.vue|.svelte|.graphql|.proto|.ml|.m|.mm|.nix|.elm|.lean|.f90|.f95|.f03|.f08|.cuh|.v|.sv|.glsl|.frag|.vert)
                SHOULD_BLOCK=true; break ;;
            esac
        done ;;
    esac
fi

# (c) neither type nor glob is set AND path is inside an indexed repo
if [ "$SHOULD_BLOCK" = false ] && [ -z "$TYPE_FIELD" ] && [ -z "$GLOB_FIELD" ]; then
    # Single-file path with a non-code extension → allow (QA M4). The explicit-glob
    # allowlist above never fires in the path-only branch because GLOB_FIELD is empty,
    # so re-check the file's own extension here before blocking Grep on README.md etc.
    # Case-insensitive match so README.MD, Config.YAML, etc. are also allowed (QA n3).
    if [ -n "$PATH_FIELD" ] && [ -f "$PATH_FIELD" ]; then
        shopt -s nocasematch
        case "$PATH_FIELD" in
          *.yml|*.yaml|*.json|*.md|*.markdown|*.toml|*.lock|*.xml|*.ini|*.cfg|*.conf|*.txt|*.html|*.css|*.env)
            shopt -u nocasematch
            exit 0 ;;
        esac
        shopt -u nocasematch
    fi
    # We already confirmed CMM is registered + sentinel present above
    SHOULD_BLOCK=true
fi

[ "$SHOULD_BLOCK" = false ] && exit 0

# --- REPLACE WITH classifier (6-line bash regex; per 46-CONTEXT.md) ---
# Identifier = matches ^[A-Za-z_][A-Za-z0-9_]{2,63}$ AND contains NO regex metacharacters
IS_IDENTIFIER=false
if [[ "$PATTERN_FIELD" =~ ^[A-Za-z_][A-Za-z0-9_]{2,63}$ ]]; then
    # Length already bounded 3..64 by regex; also guard no metacharacters (belt-and-suspenders)
    case "$PATTERN_FIELD" in
      *\|*|*.*|*\**|*\+*|*\?*|*\[*|*\(*|*\)*|*\\*|*\^*|*\$*) ;;
      *) IS_IDENTIFIER=true ;;
    esac
fi

if [ "$IS_IDENTIFIER" = true ]; then
    FIRST_LINE="REPLACE WITH: mcp__codebase-memory-mcp__search_graph(name_pattern=\"${PATTERN_FIELD}\")"
    SECOND_LINE="OR:           mcp__codebase-memory-mcp__search_code(query=\"${PATTERN_FIELD}\")"
else
    FIRST_LINE="REPLACE WITH: mcp__codebase-memory-mcp__search_code(query=\"${PATTERN_FIELD}\")"
    SECOND_LINE="OR:           mcp__codebase-memory-mcp__search_graph(name_pattern=\"${PATTERN_FIELD}\")"
fi

# --- Block message (stderr, exit 2) ---
cat >&2 <<EOF
[grep-cmm-gate] BLOCKED -- source-code search in indexed repo.
${FIRST_LINE}
${SECOND_LINE}
Bypass: add '# cmm-exempt' to your pattern, or use an explicit non-code type/glob.
EOF

# --- Block counter (best-effort, parity with cmm-grep-nudge.sh) ---
bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "grep" 2>/dev/null || true

exit 2
