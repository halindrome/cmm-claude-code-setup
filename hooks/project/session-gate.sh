#!/bin/bash
# session-gate.sh — PreToolUse:* hook (unified CMM + Context Mode session gate)
# BLOCKING: gates all tools until CMM index is refreshed and (if installed) Context Mode is initialized
#
# Purpose: Single merged gate replacing cmm-session-gate.sh and context-mode-session-gate.sh.
#          Sentinel path uses git-aware root detection (show-superproject-working-tree) so
#          the hash is stable whether the session CWD is the project root, a git submodule,
#          or a git worktree.
#
# Install: cp hooks/project/session-gate.sh .claude/hooks/ && chmod +x .claude/hooks/session-gate.sh
# Register in .claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "*", "hooks": [{"type": "command", "command": "bash .claude/hooks/session-gate.sh"}] }] }
# Matcher: PreToolUse:*

# --- Input Capture ---
# stdin can only be read once — capture it immediately for all subsequent parsing
INPUT=$(cat)

# --- Lightweight Tool Extraction ---
# Use bash-only grep/sed to extract tool_name without python3 overhead.
# Fall back to python3 if the lightweight parse fails (malformed JSON, etc.)
TOOL=$(echo "$INPUT" | grep -o '"tool_name": *"[^"]*"' | head -1 | sed 's/.*: *"//;s/"//')
if [ -z "$TOOL" ]; then
    TOOL=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")
fi

# If parsing failed, do not block — fail open to avoid spurious hook errors
[ -z "$TOOL" ] && exit 0

# --- Phase 1: Universal Allow-list (before any git traversal) ---
# These tools never need gating — exit immediately with zero subprocess overhead
case "$TOOL" in
  Agent)        exit 0 ;;  # subagents run in their own session with their own gate
  ToolSearch)   exit 0 ;;  # schema fetch needed to escape the catch-22
  SendMessage)  exit 0 ;;  # inter-agent coordination; must never be gated
esac

# --- Phase 2: CMM/CTX/Read-only Bypass (before any git traversal) ---
# These tools are safe to run without sentinel checks — bypass the expensive git chain walk
case "$TOOL" in
  mcp__codebase-memory-mcp__*)  # all CMM tools bypass CMM sentinel check unconditionally
    exit 0 ;;
  mcp__context-mode__*)         # Context Mode tools: full bypass (both CMM and CM gates)
    exit 0 ;;
  Bash|Read|Grep|Glob)          # read-only tools; safe to run in parallel with index_status
    exit 0 ;;
esac

# --- Project root detection (shared library with /tmp cache) ---
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" 2>/dev/null && pwd -P)"
if [ -f "$_LIB_DIR/project-root.sh" ]; then
  source "$_LIB_DIR/project-root.sh"
else
  # Fallback: inline detection (pre-optimization installs) — matches hooks/lib/project-root.sh
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
      PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
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
  # Legacy orphaned .git/modules/<name>/ recovery (matches hooks/lib/project-root.sh)
  if [ -n "$PROJECT_ROOT" ]; then
      case "$PROJECT_ROOT" in
        */.git/*)
          _MODULES_OWNER="${PROJECT_ROOT%%/.git/*}"
          if [ -n "$_MODULES_OWNER" ] && [ -d "$_MODULES_OWNER" ]; then
              _CANDIDATE="$(cd "$_MODULES_OWNER" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)"
              case "$_CANDIDATE" in
                */.git/*|"") : ;;
                *) PROJECT_ROOT="$_CANDIDATE" ;;
              esac
          fi
          ;;
      esac
  fi
  PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')
  CONTEXT_MODE_SENTINEL="/tmp/context-mode-ready-${PROJECT_HASH}"
fi
CMM_SENTINEL="/tmp/cmm-session-ready-${PROJECT_HASH}"

# --- Path Integrity Check ---
_SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P 2>/dev/null)"
if [ -n "$_SCRIPT_ROOT" ] && [ -n "$PROJECT_ROOT" ] && [ "$_SCRIPT_ROOT" != "$PROJECT_ROOT" ]; then
    echo "cmm-hooks: path mismatch — hooks registered for '$_SCRIPT_ROOT' but git root is '$PROJECT_ROOT'." >&2
    echo "Project was moved or cloned. Re-run: bash setup.sh --project --force" >&2
    exit 2
fi

# Check CMM sentinel
if [ ! -f "$CMM_SENTINEL" ]; then
  cat >&2 <<BLOCKED
BLOCKED: CMM index not refreshed for this session.

Run this to open the gate:
  mcp__codebase-memory-mcp__index_repository   (incremental — fast when already indexed)

You can still use these tools without opening the gate:
  mcp__codebase-memory-mcp__*  Bash, Read, Grep, Glob, ToolSearch, Agent, SendMessage

If the CMM server is unavailable, create the bypass sentinel in your terminal:
  touch "/tmp/cmm-session-ready-${PROJECT_HASH}"
BLOCKED
  exit 2
fi

# Stale sentinel: warn but do not block. The CMM server's file watcher will
# auto-reindex after a commit (typically within 5–60s). Blocking here adds
# friction without improving correctness — index_status doesn't trigger a
# reindex, only the watcher does.
if grep -q '^stale$' "$CMM_SENTINEL"; then
  cat >&2 <<WARN
CMM note: index may lag recent commit. The server watcher will reindex automatically (5–60s).
Call mcp__codebase-memory-mcp__index_repository now if you need graph data to be current immediately.
WARN
fi

# --- Phase 3: Context Mode Gate (only if installed) ---
# Detection: check project .mcp.json and global Claude Code settings, then session DB
CONTEXT_MODE_INSTALLED=0
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
# Also activate if a session DB already exists (context-mode was used here before)
[ -f "${PROJECT_ROOT}/.claude/context-mode.db" ] && CONTEXT_MODE_INSTALLED=1

if [ "$CONTEXT_MODE_INSTALLED" -eq 0 ]; then
  exit 0
fi

# Context Mode allow-list (bypass Context Mode sentinel check)
case "$TOOL" in
  mcp__context-mode__*)  exit 0 ;;
  ctx_execute)           exit 0 ;;
  ctx_search)            exit 0 ;;
  ctx_index)             exit 0 ;;
  ctx_fetch_and_index)   exit 0 ;;
  ctx_batch_execute)     exit 0 ;;
  ctx_execute_file)      exit 0 ;;
  ctx_stats)             exit 0 ;;
  ctx_doctor)            exit 0 ;;
  ctx_upgrade)           exit 0 ;;
  mcp__codebase-memory-mcp__*)  exit 0 ;;
esac

# Check Context Mode sentinel (CONTEXT_MODE_SENTINEL exported by project-root.sh; fallback sets it inline)
if [ ! -f "$CONTEXT_MODE_SENTINEL" ]; then
  cat >&2 <<BLOCKED
BLOCKED: Context Mode is installed but not yet initialized for this session.

Run one of these to initialize:
  ctx_stats          (fast check — initializes Context Mode for this session)
  ctx_execute        (run any command through the sandbox to initialize)

If you want to bypass the gate temporarily, create the sentinel in your terminal:
  touch "/tmp/context-mode-ready-${PROJECT_HASH}"
BLOCKED
  exit 2
fi

# Stale Context Mode sentinel: warn only (consistent with CMM stale behavior).
# Nothing currently writes "stale" to the CM sentinel, but guard defensively.
if grep -q '^stale$' "$CONTEXT_MODE_SENTINEL" 2>/dev/null; then
  echo "Context Mode note: sentinel is stale. Run ctx_stats to reinitialize." >&2
fi

exit 0
