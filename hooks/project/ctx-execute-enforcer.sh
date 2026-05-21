#!/bin/bash
# ctx-execute-enforcer.sh — PreToolUse:Bash hook (allowlist enforcer; plugin-form and MCP-server-form coverage)
# BLOCKING: exits 2 for test runners, package installs, linters, and log viewers; redirects to ctx_execute.
# No-op when Context Mode is not installed (neither plugin-form NOR MCP-server-form detected)
# or not yet initialized for this session.
# Phase 57 G3: availability probe checks both install forms — ${CLAUDE_PLUGIN_ROOT} and
# ${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/cache/<marketplace>/context-mode/.claude-plugin/plugin.json (plugin form)
# as a fast-path before falling through to the legacy .mcp.json probe.
#
# Install: cp hooks/project/ctx-execute-enforcer.sh .claude/hooks/ && chmod +x .claude/hooks/ctx-execute-enforcer.sh
# Register in .claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/ctx-execute-enforcer.sh"}] }] }
# Matcher: PreToolUse:Bash
# 47-02: git log/diff/show bare forms and echo/printf removed from exempt list.

# --- Project root detection (shared library with /tmp cache) ---
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" 2>/dev/null && pwd -P)"
if [ -f "$_LIB_DIR/project-root.sh" ]; then
  source "$_LIB_DIR/project-root.sh"
else
  # Fallback: inline detection (pre-optimization installs)
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$PROJECT_ROOT" ]; then
      _WALK="$PROJECT_ROOT"
      while true; do
          _PARENT="$(git -C "$_WALK" rev-parse --show-superproject-working-tree 2>/dev/null)"
          [ -z "$_PARENT" ] && break
          _WALK="$_PARENT"
      done
      PROJECT_ROOT="$_WALK"
  fi
  if [ -z "$PROJECT_ROOT" ]; then
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
      PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
  fi
  if [ -n "$PROJECT_ROOT" ]; then
      _GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --git-dir 2>/dev/null)"
      _GIT_COMMON="$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null)"
      [ "${_GIT_DIR:0:1}" != "/" ]    && _GIT_DIR="$PROJECT_ROOT/$_GIT_DIR"
      [ "${_GIT_COMMON:0:1}" != "/" ] && _GIT_COMMON="$PROJECT_ROOT/$_GIT_COMMON"
      if [ "$_GIT_DIR" != "$_GIT_COMMON" ]; then
          _MAIN_ROOT="$(cd "$_GIT_COMMON/.." 2>/dev/null && pwd -P)"
          [ -n "$_MAIN_ROOT" ] && PROJECT_ROOT="$_MAIN_ROOT"
      fi
  fi
  PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')
fi

# --- Path Integrity Check ---
# Hooks are registered with absolute paths by setup.sh. If the project was moved or
# cloned without re-running setup.sh, BASH_SOURCE points to the old location while
# git resolves the actual current root — catch this mismatch early.
_SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P 2>/dev/null)"
if [ -n "$_SCRIPT_ROOT" ] && [ -n "$PROJECT_ROOT" ] && [ "$_SCRIPT_ROOT" != "$PROJECT_ROOT" ]; then
    echo "cmm-hooks: path mismatch — hooks registered for '$_SCRIPT_ROOT' but git root is '$PROJECT_ROOT'."
    echo "Project was moved or cloned. Re-run: bash setup.sh --project --force"
    exit 2
fi

# --- Input Parsing ---
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# If parsing failed or command is empty, do not block — fail open to avoid spurious hook errors
[ -z "$COMMAND" ] && exit 0

# --- Context Mode Detection (cached, dual-form per Phase 57 G3) ---
# Cache result in /tmp/ctx-enforcer-<hash> to avoid repeated python3 JSON parsing on every Bash call.
# Probe order: plugin-form fast-path (CLAUDE_PLUGIN_ROOT env / ~/.claude/plugins/cache scan)
# FIRST per G3 ordering; legacy MCP-server-form probe second.
CTX_CACHE="/tmp/ctx-enforcer-${PROJECT_HASH}"
if [ -f "$CTX_CACHE" ]; then
    CONTEXT_MODE_INSTALLED=$(cat "$CTX_CACHE" 2>/dev/null)
    CONTEXT_MODE_INSTALLED="${CONTEXT_MODE_INSTALLED:-0}"
else
    CONTEXT_MODE_INSTALLED=0

    # 1. Plugin-form fast-path (canonical, listed first per G3).
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && \
       [ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] && \
       grep -q '"name"[[:space:]]*:[[:space:]]*"context-mode"' \
         "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null; then
        CONTEXT_MODE_INSTALLED=1
    else
        # Scan ${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/cache/<marketplace>/context-mode/ for an installed plugin.
        if [ -d "${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/plugins/cache" ]; then
            for _ctx_pl in "${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/plugins/cache"/*/context-mode/.claude-plugin/plugin.json; do
                [ -f "$_ctx_pl" ] || continue
                if grep -q '"name"[[:space:]]*:[[:space:]]*"context-mode"' "$_ctx_pl" 2>/dev/null; then
                    CONTEXT_MODE_INSTALLED=1
                    break
                fi
            done
        fi
    fi

    # 2. MCP-server-form probe (legacy, listed second per G3).
    if [ "$CONTEXT_MODE_INSTALLED" -eq 0 ]; then
        if python3 -c "
import json, os, sys
# 1. Project .mcp.json
try:
    with open('${PROJECT_ROOT}/.mcp.json') as f:
        if 'context-mode' in json.load(f).get('mcpServers', {}):
            sys.exit(0)
except Exception: pass
# 2. Global Claude Code settings
for d in [os.environ.get('CLAUDE_CONFIG_DIR',''), os.path.expanduser('~/.config/claude-code'), os.path.expanduser('~/.claude')]:
    if not d: continue
    try:
        with open(os.path.join(d, 'settings.json')) as f:
            if 'context-mode' in json.load(f).get('mcpServers', {}):
                sys.exit(0)
    except Exception: pass
sys.exit(1)
" 2>/dev/null; then
            CONTEXT_MODE_INSTALLED=1
        fi
    fi

    # Also activate if a session DB already exists (context-mode was used here before)
    [ -f "${PROJECT_ROOT}/.claude/context-mode.db" ] && CONTEXT_MODE_INSTALLED=1
    # Write cache
    echo "$CONTEXT_MODE_INSTALLED" > "$CTX_CACHE" 2>/dev/null || true
fi

# No-op if Context Mode is not installed
if [ "$CONTEXT_MODE_INSTALLED" -eq 0 ]; then
    exit 0
fi

# --- Context Mode Sentinel Check (deadlock prevention) ---
# If ctx_execute is not ready yet, allowing Bash through avoids a catch-22 where
# Claude cannot call ctx_execute to initialize Context Mode.
CONTEXT_MODE_SENTINEL="/tmp/context-mode-ready-${PROJECT_HASH}"
if [ ! -f "$CONTEXT_MODE_SENTINEL" ]; then
    exit 0
fi

# --- Bypass Marker ---
# Internal bypass marker — undocumented, for operator use only.
if echo "$COMMAND" | grep -q "ctx-exempt"; then
    exit 0
fi

# --- Exempt Patterns (always allow, exit 0) ---
# Each exempt group increments a bash-exempt counter via track-hook-blocks.sh
# for audit instrumentation (47-02). Non-blocking; exit-0 outcome unchanged.
_track_exempt() {
  bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "bash-exempt" "$1" 2>/dev/null || true
}

# Git write operations (state-changing, bounded output, required for workflow)
case "$COMMAND" in
  git\ commit*|git\ add*|git\ push*|git\ pull*|git\ fetch*)  _track_exempt git-write; exit 0 ;;
  git\ checkout*|git\ switch*|git\ branch*|git\ tag*)         _track_exempt git-write; exit 0 ;;
  git\ rebase*|git\ merge*|git\ cherry-pick*|git\ reset*)     _track_exempt git-write; exit 0 ;;
  git\ stash*|git\ worktree*|git\ remote*)                    _track_exempt git-write; exit 0 ;;
  git\ config*|git\ init*)                                    _track_exempt git-write; exit 0 ;;
esac

# Git bounded read operations (output is short and predictable)
case "$COMMAND" in
  git\ status|git\ status\ *)                                                _track_exempt git-bounded-read; exit 0 ;;
  git\ diff\ --stat*|git\ log\ --oneline\ -*)                                _track_exempt git-bounded-read; exit 0 ;;
  git\ log\ --name-only*|git\ log\ --stat*|git\ show\ --name-only*)          _track_exempt git-bounded-read; exit 0 ;;
  git\ show\ --stat*|git\ rev-parse\ *|git\ rev-list\ --count*)              _track_exempt git-bounded-read; exit 0 ;;
esac

# Filesystem mutations (no stdout flood)
case "$COMMAND" in
  mkdir\ *|rmdir\ *|rm\ *|mv\ *|cp\ *|ln\ *|chmod\ *|chown\ *)  _track_exempt filesystem; exit 0 ;;
  touch\ *|install\ -m*|mktemp*)                                 _track_exempt filesystem; exit 0 ;;
esac

# Navigation and short queries (output is bounded)
case "$COMMAND" in
  cd\ *|pwd|which\ *|type\ *|command\ -v\ *)     _track_exempt navigation; exit 0 ;;
  date*|uname*|whoami|hostname)                  _track_exempt navigation; exit 0 ;;
esac

# Short-read utilities (bounded output)
case "$COMMAND" in
  wc\ *|head\ *|tail\ -[0-9]*|tail\ -n\ [0-9]*)  _track_exempt short-reads; exit 0 ;;
esac

# Remote commands (output belongs to remote context, not local CTX store)
case "$COMMAND" in
  ssh\ *|scp\ *|rsync\ *|sftp\ *)                _track_exempt remote; exit 0 ;;
esac

# VBW/planning scripts (must not break planning workflows)
case "$COMMAND" in
  */.vbw-planning/*|*/tmp/.vbw-plugin-root-link-*)                            _track_exempt vbw-planning; exit 0 ;;
  bash\ */.vbw-planning/*|bash\ */tmp/.vbw-plugin-root-link-*)                _track_exempt vbw-planning; exit 0 ;;
esac

# Package version queries (bounded output)
case "$COMMAND" in
  *--version|*\ -v|*\ -V)   _track_exempt version; exit 0 ;;
esac

# --- Default: block everything not explicitly exempt ---
# Allowlist model: only commands matching exempt patterns above pass through.
# Everything else must go through ctx_execute for output sandboxing.
bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "bash" 2>/dev/null || true

cat >&2 <<BLOCKED
BLOCKED: Route this command through ctx_execute for output sandboxing.

Replace:
  Bash("$COMMAND")
With (plugin form):
  mcp__plugin_context-mode_context-mode__ctx_execute(language="shell", code="$COMMAND")
Or (MCP-server form, legacy):
  mcp__context-mode__ctx_execute(language="shell", code="$COMMAND")

Context Mode captures only the relevant output portion, preventing context bloat.
If this is a source-code search, prefer search_code / search_graph (CMM) over ctx_execute.
See skill \`ctx-rules\` for the full protocol.
BLOCKED
exit 2
