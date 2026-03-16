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

# If parsing failed, do not block — fail open to avoid spurious hook errors
[ -z "$TOOL" ] && exit 0

# --- Allow-list ---
# Tools allowed through unconditionally, before the sentinel exists:
case "$TOOL" in
  mcp__codebase-memory-mcp__index_repository)  # creates sentinel via cmm-sentinel-writer.sh
    exit 0 ;;
  mcp__codebase-memory-mcp__index_status)      # fast check; sentinel writer fires on success
    exit 0 ;;
  mcp__codebase-memory-mcp__delete_project)    # safe pre-index; needed for forced re-index
    exit 0 ;;
  Agent)                                        # subagents run in their own session with their own gate
    exit 0 ;;
  ToolSearch)                                   # schema fetch needed to escape the catch-22
    exit 0 ;;
  SendMessage)                                  # inter-agent coordination; must never be gated
    exit 0 ;;
  mcp__context-mode__*)                          # context-mode gate fires after CMM gate; avoid deadlock
    exit 0 ;;
esac

# --- Sentinel Check ---
SENTINEL="/tmp/cmm-session-ready-$(echo "$PWD" | tr '/' '-')"

if [ -f "$SENTINEL" ]; then
  exit 0
fi

# --- Sentinel missing: block and explain ---
cat >&2 <<'BLOCKED'
BLOCKED: CMM index not refreshed for this session.

Run one of these first:
  mcp__codebase-memory-mcp__index_status       (fast check — opens gate if server is up)
  mcp__codebase-memory-mcp__index_repository   (full reindex)

If the CMM server is unavailable, create the bypass sentinel in your terminal:
  touch "/tmp/cmm-session-ready-$(echo "$PWD" | tr '/' '-')"
BLOCKED
exit 2
