#!/bin/bash
# cmm-nudge.sh — PreToolUse:Read hook (soft per-file read budget; advisory, NEVER blocks)
#
# NON-BLOCKING: always exits 0. For code files (>=50 lines) in CMM-configured repos it
# maintains a session-scoped per-file read counter. Under the budget it is completely
# silent. Past the budget it emits an advisory nudge (hookSpecificOutput.additionalContext)
# suggesting get_code_snippet / search_graph, on a BACK-OFF cadence — every read from
# (READ_BUDGET+1) through NUDGE_CONSECUTIVE_UNTIL (4,5,6,7,8), then only at successive
# powers of two (16, 32, 64, …). The read always proceeds; the cadence applies escalating
# pressure on a genuine re-read loop while keeping the per-read token cost bounded.
#
# Why soft, not a hard block (replaces the former exit-2 gate + 60s cmm-recent recency
# gate): transcript mining showed the hard Read gate was the costliest gate and that the
# 60s recency exemption mostly TAXED already-bounded targeted reads (which are already
# token-cheap) while being trivially gameable — net token-negative. A post-hoc block on a
# single read also can't un-inject bytes, so it saves nothing; only a FORWARD-looking
# nudge on repeated access of the same file (the pagination pattern Finding B actually
# cared about) can change behavior and save tokens. So: nudge on repetition, never block.
#
# Install: cp hooks/global/cmm-nudge.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/cmm-nudge.sh
#   (or: setup.sh --project also copies to .claude/hooks/cmm-nudge.sh for agent frontmatter hooks)
# Register in ~/.claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "Read", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/cmm-nudge.sh"}] }] }

READ_BUDGET=3              # silent for the first N reads of a file per session
NUDGE_CONSECUTIVE_UNTIL=8  # past the budget, nudge EVERY read up to here, then back off to powers of two

# --- Input Parsing (dual-form: tool_input.file_path + top-level fallback) ---
INPUT=$(cat)
PARSED=$(echo "$INPUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ti=d.get('tool_input',{})
fp=ti.get('file_path','') or d.get('file_path','')
sid=d.get('session_id','') or ''
print(fp)
print(sid)
" 2>/dev/null)

FILE_PATH=$(echo "$PARSED" | sed -n '1p')
SESSION_ID=$(echo "$PARSED" | sed -n '2p')

[ -z "$FILE_PATH" ] && exit 0

# Operator bypass marker (mirrors ctx-exempt in ctx-execute-enforcer.sh).
if echo "$FILE_PATH" | grep -q '# cmm-exempt'; then
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

# --- CMM Availability Check (safety valve — don't nudge if CMM isn't configured) ---
REPO_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
  CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
  REPO_ROOT="${CWD:-.}"
fi

_CMMREG_LIB=""
for _d in "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
  [ -f "$_d/cmm-registered.sh" ] && { _CMMREG_LIB="$_d/cmm-registered.sh"; break; }
done
# Cannot determine availability -> stay silent. Never nudge on our own absence.
[ -n "$_CMMREG_LIB" ] || exit 0
# shellcheck disable=SC1090
source "$_CMMREG_LIB"

CMM_FOUND=false
cmm_is_registered "$REPO_ROOT" && CMM_FOUND=true
# If CMM not found anywhere, stay silent (fail open)
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

# --- Per-file soft budget (session-scoped, advisory, NEVER blocks) ---
# Count reads of THIS file in THIS session. Under budget: silent allow. Past the
# budget, nudge with a back-off cadence: EVERY read from (READ_BUDGET+1) through
# NUDGE_CONSECUTIVE_UNTIL (i.e. 4,5,6,7,8), then only at successive powers of two
# (16, 32, 64, …). This keeps escalating pressure exactly where waste is happening
# (repeated reads of one file — the pagination pattern) while the cost stays
# bounded: a single or a few targeted reads are never taxed, and a runaway loop is
# reminded with diminishing frequency rather than on every read forever. The counter
# key is (session_id, file_path) so it never accumulates across sessions and there is
# no project-root hash to diverge (the old cmm-recent submodule/worktree hash-mismatch
# bug class cannot occur here).
_SID="${SESSION_ID:-nosession}"
_FHASH=$(echo -n "$FILE_PATH" | md5 -q 2>/dev/null || echo -n "$FILE_PATH" | md5sum 2>/dev/null | awk '{print $1}')
_CFILE="/tmp/cmm-reads-${_SID}-${_FHASH}"
_CNT=$(cat "$_CFILE" 2>/dev/null || echo 0)
case "$_CNT" in ''|*[!0-9]*) _CNT=0 ;; esac
_CNT=$((_CNT + 1))
echo "$_CNT" > "$_CFILE" 2>/dev/null || true

# Back-off cadence: nudge on every read in [READ_BUDGET+1 .. NUDGE_CONSECUTIVE_UNTIL],
# then only when the count is a power of two (16, 32, 64, …). The power-of-two test is
# `n & (n-1) == 0` (true only for powers of two); gated on > NUDGE_CONSECUTIVE_UNTIL so
# 8 is covered by the consecutive range, not double-counted.
_NUDGE=false
if [ "$_CNT" -ge "$((READ_BUDGET + 1))" ] && [ "$_CNT" -le "$NUDGE_CONSECUTIVE_UNTIL" ]; then
  _NUDGE=true
elif [ "$_CNT" -gt "$NUDGE_CONSECUTIVE_UNTIL" ] && [ "$(( _CNT & (_CNT - 1) ))" -eq 0 ]; then
  _NUDGE=true
fi
if [ "$_NUDGE" = true ]; then
  _MSG="You've read '${BASENAME}' ${_CNT} times this session. For repeated lookups, mcp__codebase-memory-mcp__get_code_snippet(qualified_name=...) or search_graph is usually cheaper than re-reading the whole file. (advisory — this read is allowed)"
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":sys.argv[1]}}))' "$_MSG" 2>/dev/null || true
fi

exit 0
