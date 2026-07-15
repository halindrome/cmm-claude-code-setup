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

# --- Project root detection (shared library with /tmp cache) ---
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" 2>/dev/null && pwd -P)"
if [ -f "$_LIB_DIR/project-root.sh" ]; then
  source "$_LIB_DIR/project-root.sh"
else
  # Fallback: inline detection (pre-optimization installs)
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
  if [ -n "$PROJECT_ROOT" ]; then
      _GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --git-dir 2>/dev/null)"
      _GIT_COMMON="$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null)"
      [ "${_GIT_DIR:0:1}" != "/" ]    && _GIT_DIR="$PROJECT_ROOT/$_GIT_DIR"
      [ "${_GIT_COMMON:0:1}" != "/" ] && _GIT_COMMON="$PROJECT_ROOT/$_GIT_COMMON"
      if [ "$_GIT_DIR" != "$_GIT_COMMON" ]; then
          _MAIN_ROOT="$(cd "$_GIT_COMMON/.." 2>/dev/null && pwd -P)"
          [ -n "$_MAIN_ROOT" ] && PROJECT_ROOT="$_MAIN_ROOT"
      fi
  fi
  PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')
fi

# --- Path Integrity Check ---
_SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P 2>/dev/null)"
if [ -n "$_SCRIPT_ROOT" ] && [ -n "$PROJECT_ROOT" ] && [ "$_SCRIPT_ROOT" != "$PROJECT_ROOT" ]; then
    echo "cmm-hooks: path mismatch — hooks registered for '$_SCRIPT_ROOT' but git root is '$PROJECT_ROOT'."
    echo "Project was moved or cloned. Re-run: bash setup.sh --project --force"
fi

# --- Sentinel Deletion ---
# Delete both CMM and Context Mode sentinels to force re-initialization each session
rm -f "/tmp/cmm-session-ready-${PROJECT_HASH}"
rm -f "/tmp/context-mode-ready-${PROJECT_HASH}"

# --- Fail-open-while-indexing marker ---
# Mark that a CMM index refresh is pending for this session. While this marker is
# present and fresh, session-gate.sh fails OPEN with an advisory instead of hard-
# blocking, so a slow first index of a large codebase does not freeze the session.
# cmm-sentinel-writer.sh removes this marker (and writes the ready sentinel) once
# index_repository/index_status completes. `touch` (re)sets the mtime each session
# so the gate's TTL safety valve measures age from this session start, not an older
# orphaned marker.
touch "/tmp/cmm-indexing-${PROJECT_HASH}"

# --- Context Mode Bootstrap ---
# If Context Mode is installed, write its sentinel at session start.
# This eliminates the manual ctx_stats call that was previously required.
# The sentinel is advisory: if the MCP server is down, ctx_* tool calls will
# fail with a clear MCP error (not a gate block), which is acceptable UX.
#
# ORDERING GUARANTEE: SessionStart hooks run synchronously before any
# PreToolUse hooks fire. This means the sentinel written below at
# /tmp/context-mode-ready-${PROJECT_HASH} is guaranteed to exist before
# ctx-execute-enforcer.sh checks for it on the first tool call. The
# delete-then-recreate pattern (lines 55-56 delete, lines 87-89 recreate)
# is safe because no PreToolUse hook can interleave between them.
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

`session-gate.sh` (PreToolUse:*) blocks write/network tools until the CMM index sentinel is created.
CMM tools, Bash, Read, Grep, and Glob bypass the gate — but Edit, Write, WebFetch, etc. are blocked.
Run `index_repository` first to create the sentinel and unblock everything.

If the sentinel is marked STALE (after a recent git commit): tools remain open — you are NOT blocked.
You may see an advisory note after CMM query calls. Call `index_repository` when you need current graph data.

**Step 1 — Open the gate:**
- `index_repository` — ensures graph is current (incremental, fast when already indexed); opens gate automatically

**Allow-listed tools (bypass gate before sentinel exists):**
- `mcp__codebase-memory-mcp__*` — ALL CMM tools pass Phase 2 unconditionally
- `Bash`, `Read`, `Grep`, `Glob` — read-only file tools
- `ToolSearch` — schema fetch (catch-22 escape)
- `SendMessage` — inter-agent coordination (never gated)

**If CMM server is unavailable**, create the sentinel manually:
  touch "/tmp/cmm-session-ready-${PROJECT_HASH}"

## Context Mode Auto-Initialization

If Context Mode is installed, its sentinel is written automatically at session start.
You do NOT need to call `ctx_stats` manually — the gate is already open.

**If the Context Mode MCP server is unavailable** (sentinel missing despite auto-init):
  touch "/tmp/context-mode-ready-${PROJECT_HASH}"
PROMPT

  # --- Optional VBW task-location guidance ---
  # VBW is an optional add-on. Only surface planning-file guidance when a VBW
  # planning directory actually exists in this project; a CMM-only or
  # CMM+context-mode project has no .vbw-planning/ and should not be told to
  # read files that do not exist.
  if [ -n "$PROJECT_ROOT" ] && [ -d "$PROJECT_ROOT/.vbw-planning" ]; then
    cat <<'PROMPT'

## Finding Your Task

Check `.vbw-planning/STATE.md` to find the active phase and current plan, then read the
corresponding `.vbw-planning/phases/<phase>/<plan>.md` file for your task list.
PROMPT
  fi

  cat <<'PROMPT'

## CMM Tool Decision Table

Prefer CMM tools over Read/Grep for code navigation:

  Unfamiliar area / package map                             -> get_architecture
  Find by name (function, class, module)                    -> search_graph
  Source of a specific symbol                               -> get_code_snippet
  Who calls X / what does X call                            -> trace_path
  Cross-service or graph-wide queries (Cypher)              -> query_graph
  Text search in code (string literals, error msgs, TODOs)  -> search_code

Orient first: `get_architecture` -> `search_graph` -> `get_code_snippet`.
PROMPT
else
  # --- Minimal prompt for human sessions ---
  # Build the index_repository instruction: include the resolved PROJECT_ROOT path when available,
  # fall back to the path-agnostic form so no regression occurs when PROJECT_ROOT is empty.
  if [ -n "$PROJECT_ROOT" ]; then
    _INDEX_INSTRUCTION="1. Say one short line AND call \`index_repository(repo_path=\"${PROJECT_ROOT}\")\` in the same turn — the index is incremental and fast when already indexed. Always pass repo_path=\"${PROJECT_ROOT}\" (the resolved monorepo root); never a subdirectory."
  else
    _INDEX_INSTRUCTION="1. Say one short line AND call \`index_repository\` in the same turn — the index is incremental and fast when already indexed."
  fi
  cat <<PROMPT
**MANDATORY FIRST ACTION — Do this alongside your first reply:**

In your very first assistant turn, output exactly one short acknowledgment line
(e.g. "Refreshing CMM index…") **in the same turn** as the \`index_repository\` tool call.
NEVER emit an empty text block before the tool call — the Anthropic API rejects turns
whose text content is empty, and that 400 error poisons the rest of the session.

${_INDEX_INSTRUCTION}
2. Only after the index is confirmed current, proceed with the user's request.
3. Invoke \`Skill('cmm-rules')\` and \`Skill('ctx-rules')\` via the Skill tool so their protocols
   load into context: CMM orient-first navigation (get_architecture → search_graph → get_code_snippet)
   for source code; ctx_stats / ctx_search before re-running commands.

Do NOT skip these steps. Until the sentinel is created, write and network tools are blocked (Edit, Write, WebFetch, etc.).
A stale index (after a recent commit) does not block tools — you'll see an advisory note on CMM queries.
PROMPT
fi

exit 0
