#!/bin/bash
# subagent-ctx-startup.sh — SubagentStart hook (context-mode ctx_stats orientation injection)
# Fires in the PARENT session when a subagent starts. When context-mode is registered for the
# project, emits a concise instruction telling the subagent to call mcp__context-mode__ctx_stats
# itself before issuing new indexing operations. Does NOT shell out to any ctx_stats CLI — this
# hook only prints the instruction; the subagent makes the MCP call.
#
# Silent no-op when context-mode is not registered. Fail-open on every parse path.
#
# Install: cp hooks/global/subagent-ctx-startup.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/subagent-ctx-startup.sh
#   (or: setup.sh --project also copies to .claude/hooks/subagent-ctx-startup.sh)
# Register in ~/.claude/settings.json (or per-project .claude/settings.json):
#   "hooks": { "SubagentStart": [{ "matcher": "*",
#                                   "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/subagent-ctx-startup.sh"}] }] }
# Matcher: SubagentStart:*

# --- Input Parsing (fail-open on every parse path) ---
INPUT=$(cat 2>/dev/null)
# Empty stdin -> silent no-op
[ -z "$INPUT" ] && exit 0

# Extract cwd from the SubagentStart payload.
CWD=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)
cwd = d.get('cwd', '') or ''
if not isinstance(cwd, str):
    cwd = ''
print(cwd)
" 2>/dev/null)

# Parse failure or missing cwd -> silent no-op (we need a cwd to probe .mcp.json)
[ -z "$CWD" ] && exit 0

# --- Project Root Derivation (cwd -> git toplevel -> cwd itself) ---
REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
    REPO_ROOT="$CWD"
fi

# --- PROJECT_HASH (md5 of REPO_ROOT — same algorithm as ctx-execute-enforcer.sh) ---
PROJECT_HASH=$(echo "$REPO_ROOT" | md5 -q 2>/dev/null || echo "$REPO_ROOT" | md5sum 2>/dev/null | awk '{print $1}')

# --- Context Mode Availability Check (cached) ---
# Cache result in /tmp/ctx-subagent-avail-<hash> to avoid repeated python3 JSON parsing.
# Silently no-op when context-mode is not registered anywhere.
CTX_CACHE="/tmp/ctx-subagent-avail-${PROJECT_HASH}"
if [ -f "$CTX_CACHE" ]; then
    CONTEXT_MODE_INSTALLED=$(cat "$CTX_CACHE" 2>/dev/null)
    CONTEXT_MODE_INSTALLED="${CONTEXT_MODE_INSTALLED:-0}"
else
    CONTEXT_MODE_INSTALLED=0
    if python3 -c "
import json, os, sys
# 1. Project .mcp.json
try:
    with open('${REPO_ROOT}/.mcp.json') as f:
        if 'context-mode' in json.load(f).get('mcpServers', {}):
            sys.exit(0)
except Exception: pass
# 2. Global Claude Code settings (CLAUDE_CONFIG_DIR, ~/.config/claude-code, ~/.claude)
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
    [ -f "${REPO_ROOT}/.claude/context-mode.db" ] && CONTEXT_MODE_INSTALLED=1
    # Write cache (best-effort)
    echo "$CONTEXT_MODE_INSTALLED" > "$CTX_CACHE" 2>/dev/null || true
fi

# Fail-silent: context-mode not installed -> exit 0 without advisory
if [ "$CONTEXT_MODE_INSTALLED" -eq 0 ]; then
    exit 0
fi

# --- Emit orientation instruction as JSON SubagentStart envelope ---
# Matches the documented Claude Code SubagentStart hook contract:
#   {"hookSpecificOutput": {"hookEventName": "SubagentStart", "additionalContext": "..."}}
# Marker [ctx-startup] preserved for test assertions. Full protocol in ctx-rules skill.
NUDGE_TEXT="[ctx-startup] Context-mode is active. Invoke Skill('ctx-rules') via the Skill tool now, then follow its retrieval protocol: call ctx_stats first, and ctx_search before re-running any command."
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":sys.argv[1]}}))' \
    "$NUDGE_TEXT"

exit 0
