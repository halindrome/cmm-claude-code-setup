#!/bin/bash
# ctx-annotate-nudge.sh — PostToolUse:context-mode retrieval/summarize advisory (additionalContext channel)
# After qualifying ctx_* calls, emits a single-line JSON envelope on stdout via
# hookSpecificOutput.additionalContext so the reminder reaches Claude's next-turn reasoning
# verbatim. Combines Phase 45 retrieval-protocol guidance with the summarize-before-next-call
# instruction. 120s project-scoped cooldown prevents nudge fatigue. Always exits 0.
#
# Install: cp hooks/global/ctx-annotate-nudge.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/ctx-annotate-nudge.sh
# Register in ~/.claude/settings.json (or per-agent frontmatter):
#   "hooks": { "PostToolUse": [{ "matcher": "mcp__context-mode__ctx_(execute|search|index|fetch_and_index)",
#                                 "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/ctx-annotate-nudge.sh"}] }] }
# Matcher: PostToolUse:mcp__context-mode__ctx_(execute|search|index|fetch_and_index)
# Bypass: include literal '# ctx-exempt' anywhere in the tool_input payload.

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
print(enc(tn))
print(enc(ti_json))
print(enc(cwd))
" 2>/dev/null)

[ -z "$PARSED" ] && exit 0

TOOL_NAME=$(printf '%s\n' "$PARSED" | sed -n '1p' | base64 --decode 2>/dev/null)
TOOL_INPUT_JSON=$(printf '%s\n' "$PARSED" | sed -n '2p' | base64 --decode 2>/dev/null)
CWD=$(printf '%s\n' "$PARSED" | sed -n '3p' | base64 --decode 2>/dev/null)

[ -z "$TOOL_NAME" ] && exit 0

# Match only the four context-mode tools in scope (explicitly excludes ctx_stats, ctx_batch_execute).
case "$TOOL_NAME" in
    mcp__context-mode__ctx_execute|mcp__context-mode__ctx_search|mcp__context-mode__ctx_index|mcp__context-mode__ctx_fetch_and_index)
        ;;
    *)
        exit 0
        ;;
esac

# --- Bypass Marker ---
if printf '%s' "$TOOL_INPUT_JSON" | grep -q "ctx-exempt"; then
    exit 0
fi

# --- Project Hash + 120s Cooldown ---
REPO_ROOT=$(git -C "${CWD:-.}" rev-parse --show-toplevel 2>/dev/null)
[ -z "$REPO_ROOT" ] && REPO_ROOT="${CWD:-$(pwd)}"
PROJECT_HASH=$(printf '%s' "$REPO_ROOT" | md5 -q 2>/dev/null || printf '%s' "$REPO_ROOT" | md5sum 2>/dev/null | awk '{print $1}')

SENTINEL=""
if [ -n "$PROJECT_HASH" ]; then
    SENTINEL="/tmp/ctx-nudge-${PROJECT_HASH}"
    if [ -f "$SENTINEL" ]; then
        MTIME=$(date -r "$SENTINEL" +%s 2>/dev/null)
        NOW=$(date +%s 2>/dev/null)
        if [ -n "$MTIME" ] && [ -n "$NOW" ] && [ "$((NOW - MTIME))" -lt 120 ]; then
            exit 0
        fi
    fi
fi

# --- Advisory Message (intra-turn guidance; terse; imperative) ---
# Framed as intra-turn guidance (NOT a turn boundary) so an LLM cannot misread
# this reminder as a session/turn-end directive. Avoid leading ALLCAPS imperatives
# like "STOP" / "HALT" anywhere in the message.
# Contains the three load-bearing phrases: "state in ONE sentence",
# "do NOT run another ctx_* call", "try ctx_search".
read -r -d '' MSG <<'EOF'
Intra-turn reminder (not a turn boundary): before your next ctx_* tool call, state in ONE sentence what this ctx_* result told you, then continue the current task. If the result already answers the user, answer directly -- do NOT run another ctx_* call. For a topic you have indexed this session, try ctx_search(queries=[...]) before re-running ctx_execute / ctx_fetch_and_index.
EOF

# --- Emit JSON envelope via python3 json.dumps (handles quotes/backslashes/newlines correctly) ---
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":sys.argv[1]}}))' "$MSG" 2>/dev/null || exit 0

# --- Touch cooldown sentinel (best-effort) ---
if [ -n "$SENTINEL" ]; then
    touch "$SENTINEL" 2>/dev/null || true
fi

exit 0
