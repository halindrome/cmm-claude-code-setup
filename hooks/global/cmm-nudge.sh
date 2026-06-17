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
print(fp)
print(has_offset)
print(limit)
" 2>/dev/null)

FILE_PATH=$(echo "$PARSED" | sed -n '1p')
HAS_OFFSET=$(echo "$PARSED" | sed -n '2p')
READ_LIMIT=$(echo "$PARSED" | sed -n '3p')

[ -z "$FILE_PATH" ] && exit 0



# --- Exception: Targeted Read with offset+limit (sliced edit workflow) ---
# Phase 47 Finding B: exemption is gated on a recent CMM call (sentinel < 60s).
# The offset+limit<=100 guard is NECESSARY but no longer SUFFICIENT.
if [ "$HAS_OFFSET" = "1" ] && [ "${READ_LIMIT:-0}" -le 100 ] 2>/dev/null; then
  # Operator bypass marker (mirrors ctx-exempt in ctx-execute-enforcer.sh).
  if echo "$FILE_PATH" | grep -q '# cmm-exempt'; then
    exit 0
  fi
  # Resolve project root + hash. Anchor on FILE_PATH's git toplevel, then walk the
  # superproject chain to the outermost root, then re-anchor on the main project
  # root if FILE_PATH lives inside a `git worktree add`-created worktree. This MUST
  # match track-cmm-calls.sh's PROJECT_HASH derivation (lib/project-root.sh) so the
  # sentinel writer and reader agree on the hash.
  #
  # The walk + worktree detection is intentionally INLINED rather than sourced from
  # lib/project-root.sh because the lib derives its cache key from $(pwd) and would
  # mis-resolve when the test harness invokes the hook from an unrelated tmp dir
  # (regresses tests 12/17). Keep this block in lockstep with project-root.sh's
  # superproject walk + git-common-dir worktree branch.
  _CN_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$_CN_ROOT" ]; then
    _CN_WALK="$_CN_ROOT"
    while true; do
      _CN_PARENT="$(git -C "$_CN_WALK" rev-parse --show-superproject-working-tree 2>/dev/null)"
      [ -z "$_CN_PARENT" ] && break
      _CN_WALK="$_CN_PARENT"
    done
    _CN_ROOT="$_CN_WALK"
    # Worktree detection: worktrees are NOT submodules — show-superproject-working-tree
    # returns empty for them. Detect via git-common-dir != git-dir and re-anchor on
    # the main project root (parent of the common .git dir).
    _CN_GIT_DIR="$(git -C "$_CN_ROOT" rev-parse --git-dir 2>/dev/null)"
    _CN_GIT_COMMON="$(git -C "$_CN_ROOT" rev-parse --git-common-dir 2>/dev/null)"
    [ -n "$_CN_GIT_DIR" ] && [ "${_CN_GIT_DIR:0:1}" != "/" ]       && _CN_GIT_DIR="$_CN_ROOT/$_CN_GIT_DIR"
    [ -n "$_CN_GIT_COMMON" ] && [ "${_CN_GIT_COMMON:0:1}" != "/" ] && _CN_GIT_COMMON="$_CN_ROOT/$_CN_GIT_COMMON"
    if [ -n "$_CN_GIT_DIR" ] && [ -n "$_CN_GIT_COMMON" ] && [ "$_CN_GIT_DIR" != "$_CN_GIT_COMMON" ]; then
      _CN_MAIN="$(cd "$_CN_GIT_COMMON/.." 2>/dev/null && pwd -P)"
      [ -n "$_CN_MAIN" ] && _CN_ROOT="$_CN_MAIN"
    fi
  fi
  if [ -z "$_CN_ROOT" ]; then
    _CN_CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
    _CN_ROOT="${_CN_CWD:-}"
  fi
  if [ -n "$_CN_ROOT" ]; then
    _CN_HASH=$(echo "$_CN_ROOT" | md5 -q 2>/dev/null || echo "$_CN_ROOT" | md5sum 2>/dev/null | awk '{print $1}')
  fi
  if [ -z "${_CN_HASH:-}" ]; then
    exit 0  # fail-open: cannot derive hash
  fi
  _CN_SENTINEL="/tmp/cmm-recent-${_CN_HASH}"
  _CN_MTIME=$(date -r "$_CN_SENTINEL" +%s 2>/dev/null)
  if [ -n "$_CN_MTIME" ] && [ "$(( $(date +%s) - _CN_MTIME ))" -lt 60 ]; then
    exit 0
  fi
  # Sentinel missing or stale: fall through to normal code-file block.
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

# --- Code Extension Check (inline list + project extra_extensions) ---
_IS_CODE=false
case "$FILE_PATH" in
  *.py|*.go|*.js|*.jsx|*.ts|*.tsx|*.rs|*.java|*.cpp|*.cc|*.cxx|*.c|*.h|*.hpp|\
  *.cs|*.php|*.lua|*.scala|*.kt|*.rb|*.sh|*.bash|*.zsh|*.zig|*.ex|*.exs|*.hs|\
  *.swift|*.dart|*.pl|*.pm|*.groovy|*.erl|*.r|*.R|*.clj|*.fs|*.jl|*.el|*.cu|\
  *.sql|*.vue|*.svelte|*.graphql|*.proto|*.ml|*.m|*.mm|*.nix|*.elm|*.lean|\
  *.f90|*.f95|*.f03|*.f08|*.cuh|*.v|*.sv|*.glsl|*.frag|*.vert)
    _IS_CODE=true ;;
esac
# Check project extra_extensions from .codebase-memory.json
if [ "$_IS_CODE" = false ] && [ -n "$REPO_ROOT" ]; then
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
  if [ -s "$_EXT_CACHE" ]; then
    _BASENAME=$(basename "$FILE_PATH")
    while IFS= read -r _ext; do
      case "$_BASENAME" in *"$_ext") _IS_CODE=true; break ;; esac
    done < "$_EXT_CACHE"
  fi
fi
[ "$_IS_CODE" = false ] && exit 0

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
  - Trace callers: mcp__codebase-memory-mcp__trace_path
  - Edit workflow: search_graph -> get_code_snippet (line range) -> Read(offset=N, limit=M) -> Edit
  Full Read is allowed when:
    - targeted read with offset+limit (<=100 lines), right after a CMM call (within 60s)
    - editing 6+ functions in same file
    - need imports/globals/module-level init
    - file < 50 lines
    - non-code files (JSON, YAML, Markdown, config)
See skill \`cmm-rules\` for the full protocol.
EOF

# --- Block Counter ---
bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "read" 2>/dev/null || true

exit 2
