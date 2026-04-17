#!/bin/bash
# ctx-search-nudge.sh — PostToolUse:context-mode indexing tools (ctx_search retrieval advisory)
# Non-blocking: prints a stderr advisory after qualifying context-mode indexing calls,
# reminding the model that indexed content can be retrieved via ctx_search(queries=[...])
# before re-indexing a similar topic. Always exits 0 — fail-open on every parse path.
#
# Install: cp hooks/global/ctx-search-nudge.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/ctx-search-nudge.sh
#   (or: setup.sh --project also copies to .claude/hooks/ctx-search-nudge.sh for agent frontmatter hooks)
# Register in ~/.claude/settings.json (or per-agent frontmatter):
#   "hooks": { "PostToolUse": [{ "matcher": "mcp__context-mode__ctx_(execute|index|fetch_and_index|batch_execute)",
#                                 "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/ctx-search-nudge.sh"}] }] }
# Matcher: PostToolUse:mcp__context-mode__ctx_(execute|index|fetch_and_index|batch_execute)

# --- Input Parsing (fail-open on every parse path) ---
INPUT=$(cat 2>/dev/null)
# Empty stdin -> silent no-op
[ -z "$INPUT" ] && exit 0

# Extract: tool_name, tool_input.intent (ctx_execute), tool_input.steps[*].intent (ctx_batch_execute),
# and cwd. Python base64-encodes each field so embedded newlines (or any other control chars)
# in intent/step_intent do not shift subsequent fields. Fields are separated by a single newline;
# each field is base64 of the UTF-8 bytes of the original string.
PARSED=$(echo "$INPUT" | python3 -c "
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
intent = ti.get('intent', '') or ''
if not isinstance(intent, str):
    intent = ''
# First non-empty-after-strip step intent for ctx_batch_execute
step_intent = ''
steps = ti.get('steps', []) or []
if isinstance(steps, list):
    for s in steps:
        if isinstance(s, dict):
            si = s.get('intent', '') or ''
            if isinstance(si, str) and si.strip():
                step_intent = si
                break
cwd = d.get('cwd', '') or ''
if not isinstance(cwd, str):
    cwd = ''
print(enc(tn))
print(enc(intent))
print(enc(step_intent))
print(enc(cwd))
" 2>/dev/null)

# Parse failure -> silent no-op
[ -z "$PARSED" ] && exit 0

# Decode each base64-encoded field. Base64 output never contains newlines in a single field
# (Python's b64encode is single-line), so sed -n 'Np' selects exactly one field.
TOOL_NAME=$(printf '%s\n' "$PARSED" | sed -n '1p' | base64 --decode 2>/dev/null)
INTENT=$(printf '%s\n' "$PARSED" | sed -n '2p' | base64 --decode 2>/dev/null)
STEP_INTENT=$(printf '%s\n' "$PARSED" | sed -n '3p' | base64 --decode 2>/dev/null)
CWD=$(printf '%s\n' "$PARSED" | sed -n '4p' | base64 --decode 2>/dev/null)

# Missing tool_name -> silent no-op
[ -z "$TOOL_NAME" ] && exit 0

# --- Match only the four context-mode indexing tools ---
case "$TOOL_NAME" in
    mcp__context-mode__ctx_execute|mcp__context-mode__ctx_index|mcp__context-mode__ctx_fetch_and_index|mcp__context-mode__ctx_batch_execute)
        ;;
    *)
        exit 0
        ;;
esac

# --- Trigger logic per 45-CONTEXT.md ---
# Determine the representative intent to echo into the advisory.
# Strip whitespace for emptiness check; preserve the original (trimmed) string for display.
REP_INTENT=""
case "$TOOL_NAME" in
    mcp__context-mode__ctx_index|mcp__context-mode__ctx_fetch_and_index)
        # Fire unconditionally. Use intent if supplied, else an empty representative.
        TRIMMED=$(printf '%s' "$INTENT" | awk '{$1=$1;print}')
        REP_INTENT="$TRIMMED"
        FIRE=1
        ;;
    mcp__context-mode__ctx_execute)
        # Fire only when intent is a non-empty string (after strip).
        TRIMMED=$(printf '%s' "$INTENT" | awk '{$1=$1;print}')
        if [ -n "$TRIMMED" ]; then
            REP_INTENT="$TRIMMED"
            FIRE=1
        else
            FIRE=0
        fi
        ;;
    mcp__context-mode__ctx_batch_execute)
        # Fire when at least one child step has a non-empty intent.
        TRIMMED=$(printf '%s' "$STEP_INTENT" | awk '{$1=$1;print}')
        if [ -n "$TRIMMED" ]; then
            REP_INTENT="$TRIMMED"
            FIRE=1
        else
            FIRE=0
        fi
        ;;
esac

if [ "${FIRE:-0}" -ne 1 ]; then
    exit 0
fi

# --- Project Root Derivation (from cwd -> git toplevel -> cwd itself) ---
REPO_ROOT=$(git -C "${CWD:-.}" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
    REPO_ROOT="${CWD:-$(pwd)}"
fi

# --- PROJECT_HASH (md5 of REPO_ROOT — same algorithm as ctx-execute-enforcer.sh) ---
PROJECT_HASH=$(echo "$REPO_ROOT" | md5 -q 2>/dev/null || echo "$REPO_ROOT" | md5sum 2>/dev/null | awk '{print $1}')

# --- Context Mode Availability Check (cached) ---
# Cache result in /tmp/ctx-search-avail-<hash> to avoid repeated python3 JSON parsing.
# Silently no-op when context-mode is not registered anywhere.
CTX_CACHE="/tmp/ctx-search-avail-${PROJECT_HASH}"
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

# --- Emit advisory to stderr (verbatim intent echo per 45-CONTEXT.md decision) ---
printf '[ctx-search-nudge] Content indexed (intent="%s"). Before the next ctx_execute or Read/Grep on a similar topic, try: ctx_search(queries=["%s"]). The FTS5 store persists for the session -- retrieval is cheaper than re-fetching.\n' "$REP_INTENT" "$REP_INTENT" >&2

exit 0
