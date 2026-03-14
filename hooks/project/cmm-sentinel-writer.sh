#!/bin/bash
# cmm-sentinel-writer.sh — PostToolUse hook (index_repository OR index_status)
# NON-BLOCKING: always exits 0 (writes sentinel to unblock session gate)
#
# Purpose: Writes the session sentinel file after index_repository or index_status
#          completes, unblocking all tools gated by cmm-session-gate.sh.
#
# Install: cp hooks/project/cmm-sentinel-writer.sh .claude/hooks/
#          chmod +x .claude/hooks/cmm-sentinel-writer.sh
# Register in .claude/settings.json:
#   "hooks": { "PostToolUse": [{ "matcher": "mcp__codebase-memory-mcp__index_repository|mcp__codebase-memory-mcp__index_status", "hooks": [{"type": "command", "command": "bash .claude/hooks/cmm-sentinel-writer.sh"}] }] }

SENTINEL="/tmp/cmm-session-ready-$(echo "$PWD" | tr '/' '-')"

# Write sentinel to unblock session gate
echo "ready" > "$SENTINEL"

exit 0
