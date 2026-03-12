#!/bin/bash
# cmm-session-gate.sh — PreToolUse:* hook (BLOCKING: gates all tools until CMM index is refreshed)
#
# Purpose: Blocks ALL tool calls until the CMM index sentinel exists for this session.
#          This ensures the codebase knowledge graph is refreshed before any work begins.
#
# Install: cp hooks/project/cmm-session-gate.sh .claude/hooks/ && chmod +x .claude/hooks/cmm-session-gate.sh
# Register in .claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "*", "hooks": [{"type": "command", "command": "bash .claude/hooks/cmm-session-gate.sh"}] }] }
# Matcher: PreToolUse:*

# --- Input Parsing ---
INPUT=$(cat)
TOOL=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")

# --- Allow-list: tools needed to create the sentinel ---
case "$TOOL" in
  mcp__codebase-memory-mcp__index_repository|mcp__codebase-memory-mcp__index_status|ToolSearch)
    exit 0
    ;;
esac

# --- Sentinel Check ---
SENTINEL="/tmp/cmm-session-ready-${PPID}"

if [ -f "$SENTINEL" ]; then
  exit 0
fi

# --- Sentinel missing: block and explain ---
cat <<'BLOCKED'
BLOCKED: CMM index not refreshed for this session.

Run this first:
  mcp__codebase-memory-mcp__index_repository

This refreshes the codebase knowledge graph. Once complete, all tools will be unblocked for this session.
BLOCKED
exit 2
