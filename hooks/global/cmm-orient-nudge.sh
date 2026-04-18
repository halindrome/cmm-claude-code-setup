#!/bin/bash
# cmm-orient-nudge.sh — PostToolUse:mcp__codebase-memory-mcp__search_graph one-shot orientation nudge
# On the FIRST search_graph call of a session, emits hookSpecificOutput.additionalContext
# suggesting get_architecture / trace_call_path / query_graph for the three underused CMM tools.
# Session-scoped sentinel dedups subsequent calls. Always exits 0 (fail-open on every path).
#
# Install: cp hooks/global/cmm-orient-nudge.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/cmm-orient-nudge.sh
# Register in ~/.claude/settings.json (or per-agent frontmatter):
#   "hooks": { "PostToolUse": [{ "matcher": "mcp__codebase-memory-mcp__search_graph",
#                                 "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/cmm-orient-nudge.sh"}] }] }
# Matcher: PostToolUse:mcp__codebase-memory-mcp__search_graph
# Bypass: include literal '# cmm-exempt' anywhere in the tool_input payload.

# --- Input Parsing (fail-open on every path) ---
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

# Base64-encode fields so embedded control chars (newlines, quotes) don't shift positions.
PARSED=$(printf '%s' "$INPUT" | python3 -c "
import sys, json, base64
def enc(s):
    return base64.b64encode(s.encode('utf-8')).decode('ascii')
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)
tn = d.get('tool_name', '') or ''
sid = d.get('session_id', '') or ''
ti = d.get('tool_input', {}) or {}
if not isinstance(ti, dict):
    ti = {}
try:
    ti_json = json.dumps(ti)
except Exception:
    ti_json = ''
cwd = d.get('cwd', '') or ''
if not isinstance(cwd, str):
    cwd = ''
if not isinstance(sid, str):
    sid = ''
print(enc(tn))
print(enc(sid))
print(enc(ti_json))
print(enc(cwd))
" 2>/dev/null)

[ -z "$PARSED" ] && exit 0

TOOL_NAME=$(printf '%s\n' "$PARSED" | sed -n '1p' | base64 --decode 2>/dev/null)
SESSION_ID=$(printf '%s\n' "$PARSED" | sed -n '2p' | base64 --decode 2>/dev/null)
TOOL_INPUT_JSON=$(printf '%s\n' "$PARSED" | sed -n '3p' | base64 --decode 2>/dev/null)
CWD=$(printf '%s\n' "$PARSED" | sed -n '4p' | base64 --decode 2>/dev/null)

[ -z "$TOOL_NAME" ] && exit 0

# Match only search_graph (not other CMM tools).
case "$TOOL_NAME" in
    mcp__codebase-memory-mcp__search_graph)
        ;;
    *)
        exit 0
        ;;
esac

# --- Bypass Marker ---
if printf '%s' "$TOOL_INPUT_JSON" | grep -q "cmm-exempt"; then
    exit 0
fi

# --- Project Hash + Session-Scoped Sentinel ---
REPO_ROOT=$(git -C "${CWD:-.}" rev-parse --show-toplevel 2>/dev/null)
[ -z "$REPO_ROOT" ] && REPO_ROOT="${CWD:-$(pwd)}"
PROJECT_HASH=$(printf '%s' "$REPO_ROOT" | md5 -q 2>/dev/null || printf '%s' "$REPO_ROOT" | md5sum 2>/dev/null | awk '{print $1}')

SENTINEL=""
if [ -n "$PROJECT_HASH" ] && [ -n "$SESSION_ID" ]; then
    SENTINEL="/tmp/cmm-orient-nudged-${PROJECT_HASH}-${SESSION_ID}"
    if [ -f "$SENTINEL" ]; then
        exit 0
    fi
fi

# --- Advisory Message (architect voice; terse; imperative) ---
# Names the three under-promoted tools by name: get_architecture, query_graph, trace_call_path.
read -r -d '' MSG <<'EOF'
First search_graph call this session. If you do not yet know this codebase, run get_architecture next for the package map. For cross-service or edge-level questions use query_graph (Cypher). To trace callers/callees of any symbol use trace_call_path(direction="both").
EOF

# --- Emit JSON envelope via python3 json.dumps (handles quotes/backslashes/newlines correctly) ---
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":sys.argv[1]}}))' "$MSG" 2>/dev/null || exit 0

# --- Touch session sentinel (best-effort; never cleaned up here — /tmp TTL or reboot GCs orphans) ---
if [ -n "$SENTINEL" ]; then
    touch "$SENTINEL" 2>/dev/null || true
fi

exit 0
