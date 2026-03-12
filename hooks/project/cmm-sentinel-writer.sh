#!/bin/bash
# cmm-sentinel-writer.sh — PostToolUse:mcp__codebase-memory-mcp__index_repository hook
# NON-BLOCKING: always exits 0 (writes sentinel to unblock session gate)
#
# Purpose: Writes the session sentinel file after index_repository completes,
#          unblocking all tools gated by cmm-session-gate.sh.
#
# Install: cp hooks/project/cmm-sentinel-writer.sh .claude/hooks/
#          chmod +x .claude/hooks/cmm-sentinel-writer.sh
# Register in .claude/settings.json:
#   "hooks": { "PostToolUse": [{ "matcher": "mcp__codebase-memory-mcp__index_repository", "hooks": [{"type": "command", "command": "bash .claude/hooks/cmm-sentinel-writer.sh"}] }] }

SENTINEL="/tmp/cmm-session-ready-${PPID}"

# Write sentinel to unblock session gate
echo "ready" > "$SENTINEL"

echo "CMM index refreshed. Session unblocked — all tools now available."
exit 0
