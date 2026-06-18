#!/bin/bash
# index-root-gate.sh — PreToolUse:mcp__codebase-memory-mcp__index_repository hook (hard-block subtree indexing in monorepo)
# BLOCKING: exits 2 when repo_path is a strict descendant of PROJECT_ROOT; exits 0 (fail open) when CMM absent, PROJECT_ROOT unresolvable, or repo_path equals root.
#
# Install: cp hooks/project/index-root-gate.sh .claude/hooks/ && chmod +x .claude/hooks/index-root-gate.sh
# Register in .claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "mcp__codebase-memory-mcp__index_repository", "hooks": [{"type": "command", "command": "bash .claude/hooks/index-root-gate.sh"}] }] }
# Matcher: PreToolUse:mcp__codebase-memory-mcp__index_repository

# --- Read repo_path from hook JSON payload ---
# Claude Code passes the tool input as JSON on stdin; CLAUDE_TOOL_INPUT env var is tried first
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [ -z "$INPUT" ]; then
    INPUT=$(cat 2>/dev/null)
fi
[ -z "$INPUT" ] && exit 0

REPO_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = d.get('tool_input', d) or {}
print(ti.get('repo_path', '') or '')
" 2>/dev/null)

# Fail open if repo_path is empty or parse failed
[ -z "$REPO_PATH" ] && exit 0

# --- Project root detection (shared library with /tmp cache) ---
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" 2>/dev/null && pwd -P)"
if [ -f "$_LIB_DIR/project-root.sh" ]; then
    source "$_LIB_DIR/project-root.sh"
else
    # Fallback: inline detection for pre-optimization installs
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
fi

# Fail open if PROJECT_ROOT is empty or unresolvable
[ -z "$PROJECT_ROOT" ] && exit 0

# --- CMM availability check (.mcp.json probe, using resolved PROJECT_ROOT) ---
# Matches grep-cmm-gate.sh / cmm-nudge.sh convention: probe PROJECT_ROOT/.mcp.json first,
# then fall back to global Claude Code settings.
CMM_FOUND=false
if [ -f "${PROJECT_ROOT}/.mcp.json" ] && grep -q 'codebase-memory-mcp' "${PROJECT_ROOT}/.mcp.json" 2>/dev/null; then
    CMM_FOUND=true
fi
if [ "$CMM_FOUND" = false ]; then
    CLAUDE_SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
    if [ -f "$CLAUDE_SETTINGS" ] && grep -q 'codebase-memory-mcp' "$CLAUDE_SETTINGS" 2>/dev/null; then
        CMM_FOUND=true
    fi
fi
# Fail open if CMM is not registered anywhere
[ "$CMM_FOUND" = false ] && exit 0

# --- Resolve repo_path to absolute path ---
# Handle relative paths by resolving against $PWD
if [ "${REPO_PATH:0:1}" != "/" ]; then
    REPO_PATH="${PWD}/${REPO_PATH}"
fi
# Canonicalize (collapse .., symlinks) so string comparison is reliable
REPO_PATH_CANON="$(cd "$REPO_PATH" 2>/dev/null && pwd -P)" || REPO_PATH_CANON="$REPO_PATH"
PROJECT_ROOT_CANON="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P)" || PROJECT_ROOT_CANON="$PROJECT_ROOT"

# Fail open if canonicalization failed for either path
[ -z "$REPO_PATH_CANON" ] && exit 0
[ -z "$PROJECT_ROOT_CANON" ] && exit 0

# --- Path comparison ---
# Allow: repo_path equals the project root exactly
[ "$REPO_PATH_CANON" = "$PROJECT_ROOT_CANON" ] && exit 0

# Hard block: repo_path is a strict descendant of PROJECT_ROOT
# A descendant starts with PROJECT_ROOT_CANON/ (note trailing slash to avoid partial basename matches)
if [[ "$REPO_PATH_CANON" == "${PROJECT_ROOT_CANON}/"* ]]; then
    cat >&2 <<EOF
[index-root-gate] BLOCKED — subtree indexing in monorepo is not allowed.
  Attempted repo_path : $REPO_PATH_CANON
  Project root        : $PROJECT_ROOT_CANON
  Action required     : Re-issue index_repository with repo_path="$PROJECT_ROOT_CANON"
  Reason              : Indexing a subdirectory creates a stray CMM project that does not
                        match the monorepo root index; the sentinel gate will pass silently
                        while the wrong-scope index is used for all subsequent queries.
EOF
    exit 2
fi

# Allow: any other path (parent, unrelated — all non-descendant cases)
exit 0
