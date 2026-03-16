#!/bin/bash
# cmm-sentinel-writer.sh — PostToolUse hook (index_repository OR index_status)
# NON-BLOCKING: always exits 0 (writes sentinel to unblock session gate)
#
# Purpose: Writes the session sentinel file after index_repository or index_status
#          completes, unblocking all tools gated by session-gate.sh.
#
# Install: cp hooks/project/cmm-sentinel-writer.sh .claude/hooks/
#          chmod +x .claude/hooks/cmm-sentinel-writer.sh
# Register in .claude/settings.json:
#   "hooks": { "PostToolUse": [{ "matcher": "mcp__codebase-memory-mcp__index_repository|mcp__codebase-memory-mcp__index_status", "hooks": [{"type": "command", "command": "bash .claude/hooks/cmm-sentinel-writer.sh"}] }] }

# --- Stable Sentinel Path Computation ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')
SENTINEL="/tmp/cmm-session-ready-${PROJECT_HASH}"

# Write sentinel to unblock session gate
echo "ready" > "$SENTINEL"

exit 0
