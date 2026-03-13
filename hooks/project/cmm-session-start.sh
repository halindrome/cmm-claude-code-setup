#!/bin/bash
# cmm-session-start.sh — SessionStart hook (CMM index enforcement)
# Deletes stale sentinel and injects mandatory first-action prompt.
# Spawned agents receive a richer prompt explaining the gate, allow-list, and task location.
# Always exits 0.
#
# Install: cp hooks/project/cmm-session-start.sh .claude/hooks/ && chmod +x .claude/hooks/cmm-session-start.sh
# Register in .claude/settings.json:
#   "hooks": { "SessionStart": [{ "hooks": [{"type": "command", "command": "bash .claude/hooks/cmm-session-start.sh"}] }] }
#
# Matcher: SessionStart (no matcher needed — fires on every session start)

# --- Sentinel Deletion ---
SENTINEL="/tmp/cmm-session-ready-$(echo "$PWD" | tr '/' '-')"
rm -f "$SENTINEL"

# --- Session Type Detection ---
if [ -n "${CLAUDE_AGENT_ID:-}" ] || [ -n "${CLAUDE_PARENT_SESSION_ID:-}" ]; then
  IS_AGENT=1
else
  IS_AGENT=0
fi

if [ "$IS_AGENT" -eq 1 ]; then
  # --- Rich initialization prompt for spawned agents ---
  cat <<'PROMPT'
**SPAWNED AGENT — Read this before using any tools:**

## CMM Session Gate

`cmm-session-gate.sh` (PreToolUse:*) blocks ALL tools until the CMM index sentinel exists.
You must open the gate first — all Read/Grep/Glob/Bash calls will fail until you do.

**Step 1 — Open the gate (choose one):**
- `index_status` — fast check; opens gate automatically if CMM server is up
- `index_repository` — full re-index; use if index is stale

**Allow-listed tools (bypass gate before sentinel exists):**
- `mcp__codebase-memory-mcp__index_repository` — creates sentinel
- `mcp__codebase-memory-mcp__index_status` — fast check
- `mcp__codebase-memory-mcp__delete_project` — safe pre-index
- `ToolSearch` — schema fetch (catch-22 escape)
- `SendMessage` — inter-agent coordination (never gated)

**If CMM server is unavailable**, create the sentinel manually:
  touch "/tmp/cmm-session-ready-$(echo "$PWD" | tr '/' '-')"

## Finding Your Task

Check `.vbw-planning/STATE.md` to find the active phase and current plan, then read the
corresponding `.vbw-planning/phases/<phase>/<plan>.md` file for your task list.

## CMM Tool Workflow

Prefer CMM tools over Read/Grep for code navigation:
  `search_graph` → `trace_call_path` → `get_code_snippet`
PROMPT
else
  # --- Minimal prompt for human sessions ---
  cat <<'PROMPT'
**MANDATORY FIRST ACTION — Do this before responding to the user:**

1. Run `index_status` to check if the codebase-memory-mcp graph is current.
2. If the index is stale, missing, or has never been built, run `index_repository` to refresh it.
3. Only after the index is confirmed current, proceed with the user's request.

Do NOT skip this step. The session gate will block all other tools until indexing is complete.
PROMPT
fi

exit 0
