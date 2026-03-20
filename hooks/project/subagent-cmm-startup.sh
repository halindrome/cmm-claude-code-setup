#!/bin/bash
# subagent-cmm-startup.sh — SubagentStart hook (CMM state context injection)
# Fires in the PARENT session when a VBW subagent starts. Injects CMM index state
# into the subagent's context via additionalContext JSON output so the agent knows
# whether to call index_repository before querying the graph.
#
# Install: cp hooks/project/subagent-cmm-startup.sh .claude/hooks/ && chmod +x .claude/hooks/subagent-cmm-startup.sh
# Register in .claude/settings.json under SubagentStart (see rules/project-settings-example.json)
# Matcher: * (all subagents)

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

PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')
CMM_SENTINEL="/tmp/cmm-session-ready-${PROJECT_HASH}"

# --- Context Injection ---
# Inject CMM index state into the subagent via additionalContext JSON.
# SubagentStart hooks output: {"hookSpecificOutput": {"hookEventName": "SubagentStart", "additionalContext": "..."}}
# Always exit 0 — this hook is advisory only, never blocking.
if [ ! -f "$CMM_SENTINEL" ] || grep -q '^stale$' "$CMM_SENTINEL"; then
    ADVISORY="⚠ CMM index is stale or uninitialized. Call index_repository before using search_graph, get_code_snippet, trace_call_path, or query_graph — results will be incomplete or absent until the graph is rebuilt."
else
    ADVISORY="CMM index is ready. Use search_graph, get_code_snippet, trace_call_path, and query_graph as the primary method for code exploration."
fi

printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"%s"}}\n' \
    "$(printf '%s' "$ADVISORY" | sed 's/"/\\"/g')"

exit 0
