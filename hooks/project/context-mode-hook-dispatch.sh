#!/bin/bash
# context-mode-hook-dispatch.sh — dispatch a Claude Code hook event to context-mode
#
# Why this exists:
#   `npx -y context-mode@latest hook claude-code <event>` is NOT safe under
#   concurrent invocation. With many tool calls firing PreToolUse+PostToolUse
#   in rapid succession, parallel npx calls race to refresh the @latest cache
#   and fail with ENOTEMPTY (filesystem atomic-rename collision during
#   ~/.npm/_npx/<hash>/ updates). The failing hook is non-blocking (harness
#   continues) but its capture/redirect is silently skipped, so an unknown
#   percentage of events never reach the context-mode session DB.
#
#   This dispatcher short-circuits to a globally-installed `context-mode`
#   binary when present, entirely bypassing npx for most users (eliminating
#   the race). Falls back to npx only when no global install exists.
#
# Install: copied to .claude/hooks/ by setup.sh --project (phase 51+).
# Register: .claude/settings.json command field:
#   "bash /abs/path/to/.claude/hooks/context-mode-hook-dispatch.sh <event>"
# Events: posttooluse | pretooluse | precompact | sessionstart | userpromptsubmit
#
# Behavior:
#   - Global install present  → exec context-mode hook claude-code <event>
#   - No global install        → exec npx -y context-mode@latest hook claude-code <event>
#   - No event arg             → exit 0 (fail-open; hook is non-blocking anyway)
#
# Input: Claude Code passes the hook payload JSON on stdin. `exec` replaces
# this shell with the target binary, so stdin passes through unmodified.

set -euo pipefail

event="${1:-}"
if [ -z "$event" ]; then
  echo "context-mode-hook-dispatch: missing event arg" >&2
  exit 0
fi

if command -v context-mode >/dev/null 2>&1; then
  exec context-mode hook claude-code "$event"
else
  exec npx -y context-mode@latest hook claude-code "$event"
fi
