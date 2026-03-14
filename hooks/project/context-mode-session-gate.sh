#!/bin/bash
# context-mode-session-gate.sh — PreToolUse:* hook (gates all tools until Context Mode session is initialized)
#
# Purpose: When Context Mode MCP is installed, blocks tool calls until the context-mode sentinel
#          exists for this session. Gracefully no-ops if Context Mode is not installed.
#          Intentionally fires AFTER cmm-session-gate.sh (see hook ordering in settings.json).
#
# Install: cp hooks/project/context-mode-session-gate.sh .claude/hooks/ && chmod +x .claude/hooks/context-mode-session-gate.sh
# Register in .claude/settings.json (after cmm-session-gate entry):
#   "hooks": { "PreToolUse": [{ "matcher": "*", "hooks": [{"type": "command", "command": "bash .claude/hooks/context-mode-session-gate.sh"}] }] }
# Matcher: PreToolUse:*

# --- Context Mode Presence Check ---
# No-op gracefully if context-mode MCP is not registered for this project.
# Checks project .mcp.json and global Claude Code settings — NOT the global binary,
# which would falsely trigger after `npm install -g context-mode` in unrelated projects.
CONTEXT_MODE_INSTALLED=0
if python3 -c "
import json, os, sys
checked = []
# 1. Project .mcp.json
try:
    with open('.mcp.json') as f:
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
[ -f ".claude/context-mode.db" ] && CONTEXT_MODE_INSTALLED=1

if [ "$CONTEXT_MODE_INSTALLED" -eq 0 ]; then
  exit 0
fi

# --- Input Parsing ---
INPUT=$(cat)
TOOL=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")

# If parsing failed, do not block — fail open to avoid spurious hook errors
[ -z "$TOOL" ] && exit 0

# --- Allow-list ---
# Context Mode tools allowed through unconditionally (they initialize the session).
# Claude Code passes the full MCP tool name (mcp__context-mode__ctx_stats), not the short name.
# Match both forms for safety.
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
esac

# CMM tools must still work before this gate (CMM gate fires first anyway):
case "$TOOL" in
  mcp__codebase-memory-mcp__*)
    exit 0 ;;
esac

# Inter-agent coordination must never be gated:
case "$TOOL" in
  Agent)        exit 0 ;;  # subagents run in their own session with their own gate
  SendMessage)  exit 0 ;;
  ToolSearch)   exit 0 ;;
esac

# --- Sentinel Check ---
SENTINEL="/tmp/context-mode-ready-$(echo "$PWD" | tr '/' '-')"

if [ -f "$SENTINEL" ]; then
  exit 0
fi

# --- Sentinel missing: block and explain ---
cat >&2 <<BLOCKED
BLOCKED: Context Mode is installed but not yet initialized for this session.

Run one of these to initialize:
  ctx_stats          (fast check — initializes Context Mode for this session)
  ctx_execute        (run any command through the sandbox to initialize)

If you want to bypass the gate temporarily, create the sentinel in your terminal:
  touch "/tmp/context-mode-ready-$(echo "$PWD" | tr '/' '-')"
BLOCKED
exit 2
