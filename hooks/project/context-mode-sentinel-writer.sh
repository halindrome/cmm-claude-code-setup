#!/bin/bash
# context-mode-sentinel-writer.sh — PostToolUse hook (writes Context Mode session sentinel)
# NON-BLOCKING: always exits 0 (writes sentinel to unblock session-gate.sh Context Mode check)
#
# Purpose: Writes the Context Mode sentinel file after any ctx_* initialization tool
#          completes, unblocking tools gated by the Context Mode phase in session-gate.sh.
#
# Install: cp hooks/project/context-mode-sentinel-writer.sh .claude/hooks/
#          chmod +x .claude/hooks/context-mode-sentinel-writer.sh
# Register in .claude/settings.json:
#   PostToolUse matcher: mcp__context-mode__ctx_execute|...|mcp__context-mode__ctx_stats

# --- Stable Sentinel Path Computation ---
# Use git to find the true project root (submodule-aware). When CWD is inside a git submodule,
# show-superproject-working-tree returns the parent project (where .claude/ lives).
_SUPERPROJECT="$(git rev-parse --show-superproject-working-tree 2>/dev/null)"
if [ -n "$_SUPERPROJECT" ]; then
    PROJECT_ROOT="$_SUPERPROJECT"
else
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
fi
if [ -z "$PROJECT_ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi
PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')

# --- Context Mode Presence Check ---
CONTEXT_MODE_INSTALLED=0
if python3 -c "
import json, os, sys
try:
    with open('${PROJECT_ROOT}/.mcp.json') as f:
        if 'context-mode' in json.load(f).get('mcpServers', {}):
            sys.exit(0)
except Exception: pass
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
[ -f "${PROJECT_ROOT}/.claude/context-mode.db" ] && CONTEXT_MODE_INSTALLED=1

if [ "$CONTEXT_MODE_INSTALLED" -eq 0 ]; then
  exit 0
fi

# Write sentinel to unblock session gate
echo "ready" > "/tmp/context-mode-ready-${PROJECT_HASH}"

exit 0
