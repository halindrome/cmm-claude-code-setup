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

# --- Stable Sentinel Path Computation ---
# Walk the git superproject chain to find the outermost project root.
# Handles arbitrarily nested submodules — each iteration climbs one level until there is
# no further superproject. Falls back to BASH_SOURCE traversal for non-git environments.
# Git worktrees are handled separately below (they are not submodules).
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -n "$PROJECT_ROOT" ]; then
    _WALK="$PROJECT_ROOT"
    while true; do
        _PARENT="$(git -C "$_WALK" rev-parse --show-superproject-working-tree 2>/dev/null)"
        [ -z "$_PARENT" ] && break
        _WALK="$_PARENT"
    done
    PROJECT_ROOT="$_WALK"
fi
if [ -z "$PROJECT_ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
fi

# --- Git Worktree Detection ---
# git worktrees share the main repo but show-superproject-working-tree returns empty
# (worktrees are not submodules). Detect via git-common-dir: in a worktree it points
# to the main .git dir, while git-dir points into .git/worktrees/<name>.
# Use the main project root so sentinel hashes are stable across worktree sessions.
if [ -n "$PROJECT_ROOT" ]; then
    _GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --git-dir 2>/dev/null)"
    _GIT_COMMON="$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null)"
    # Resolve relative paths (git may return relative paths in the main working tree)
    [ "${_GIT_DIR:0:1}" != "/" ]    && _GIT_DIR="$PROJECT_ROOT/$_GIT_DIR"
    [ "${_GIT_COMMON:0:1}" != "/" ] && _GIT_COMMON="$PROJECT_ROOT/$_GIT_COMMON"
    if [ "$_GIT_DIR" != "$_GIT_COMMON" ]; then
        _MAIN_ROOT="$(cd "$_GIT_COMMON/.." 2>/dev/null && pwd -P)"
        [ -n "$_MAIN_ROOT" ] && PROJECT_ROOT="$_MAIN_ROOT"
    fi
fi

# --- Path Integrity Check ---
_SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P 2>/dev/null)"
if [ -n "$_SCRIPT_ROOT" ] && [ -n "$PROJECT_ROOT" ] && [ "$_SCRIPT_ROOT" != "$PROJECT_ROOT" ]; then
    echo "cmm-hooks: path mismatch — hooks registered for '$_SCRIPT_ROOT' but git root is '$PROJECT_ROOT'."
    echo "Project was moved or cloned. Re-run: bash setup.sh --project --force"
fi

PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')

# --- Sentinel Deletion ---
# Delete both CMM and Context Mode sentinels to force re-initialization each session
rm -f "/tmp/cmm-session-ready-${PROJECT_HASH}"
rm -f "/tmp/context-mode-ready-${PROJECT_HASH}"

# --- Context Mode Bootstrap ---
# If Context Mode is installed, write its sentinel at session start.
# This eliminates the manual ctx_stats call that was previously required.
# The sentinel is advisory: if the MCP server is down, ctx_* tool calls will
# fail with a clear MCP error (not a gate block), which is acceptable UX.
CONTEXT_MODE_INSTALLED=0
if python3 -c "
import json, os, sys
# 1. Project .mcp.json
try:
    with open('${PROJECT_ROOT}/.mcp.json') as f:
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
[ -f "${PROJECT_ROOT}/.claude/context-mode.db" ] && CONTEXT_MODE_INSTALLED=1

if [ "$CONTEXT_MODE_INSTALLED" -eq 1 ]; then
  echo "ready" > "/tmp/context-mode-ready-${PROJECT_HASH}"
fi

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

`session-gate.sh` (PreToolUse:*) blocks ALL tools until the CMM index sentinel exists.
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
  touch "/tmp/cmm-session-ready-${PROJECT_HASH}"

## Context Mode Auto-Initialization

If Context Mode is installed, its sentinel is written automatically at session start.
You do NOT need to call `ctx_stats` manually — the gate is already open.

**If the Context Mode MCP server is unavailable** (sentinel missing despite auto-init):
  touch "/tmp/context-mode-ready-${PROJECT_HASH}"

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
