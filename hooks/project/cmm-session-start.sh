#!/bin/bash
# cmm-session-start.sh — SessionStart hook (CMM index enforcement)
# Deletes stale sentinel and injects mandatory first-action prompt.
# Always exits 0.
#
# Install: cp hooks/project/cmm-session-start.sh .claude/hooks/ && chmod +x .claude/hooks/cmm-session-start.sh
# Register in .claude/settings.json:
#   "hooks": { "SessionStart": [{ "hooks": [{"type": "command", "command": "bash .claude/hooks/cmm-session-start.sh"}] }] }
#
# Matcher: SessionStart (no matcher needed — fires on every session start)

# --- Sentinel Deletion ---
SENTINEL="/tmp/cmm-session-ready-${PPID}"
rm -f "$SENTINEL"

# --- Mandatory First-Action Prompt ---
cat <<'PROMPT'
**MANDATORY FIRST ACTION — Do this before responding to the user:**

1. Run `index_status` to check if the codebase-memory-mcp graph is current.
2. If the index is stale, missing, or has never been built, run `index_repository` to refresh it.
3. Only after the index is confirmed current, proceed with the user's request.

Do NOT skip this step. The session gate will block all other tools until indexing is complete.
PROMPT

exit 0
