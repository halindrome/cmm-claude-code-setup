#!/bin/bash
# webfetch-nudge.sh — PreToolUse:WebFetch hook (nudge toward context-mode ctx_fetch_and_index)
# BLOCKING: exits 2 when Context Mode is available, redirecting to ctx_fetch_and_index / ctx_search.
# No-op when Context Mode is not installed — fail-open on every uncertainty.
#
# Install: cp hooks/global/webfetch-nudge.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/webfetch-nudge.sh
#   (or: setup.sh --project also copies to .claude/hooks/webfetch-nudge.sh for agent frontmatter hooks)
# Register in ~/.claude/settings.json (or per-agent frontmatter):
#   "hooks": { "PreToolUse": [{ "matcher": "WebFetch", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/webfetch-nudge.sh"}] }] }

# --- Input Parsing (dual-form: tool_input.url + top-level fallback; also cwd) ---
INPUT=$(cat)
PARSED=$(echo "$INPUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ti=d.get('tool_input',{})
url=ti.get('url','') or d.get('url','')
cwd=d.get('cwd','')
print(url)
print(cwd)
" 2>/dev/null)

URL=$(echo "$PARSED" | sed -n '1p')
CWD=$(echo "$PARSED" | sed -n '2p')

# Fail-open: empty URL or parse failure -> let WebFetch through
[ -z "$URL" ] && exit 0

# --- Project Root Derivation (from cwd -> git toplevel -> cwd itself) ---
REPO_ROOT=$(git -C "${CWD:-.}" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="${CWD:-$(pwd)}"
fi

# --- PROJECT_HASH (md5 of REPO_ROOT — same algorithm as ctx-execute-enforcer.sh) ---
PROJECT_HASH=$(echo "$REPO_ROOT" | md5 -q 2>/dev/null || echo "$REPO_ROOT" | md5sum 2>/dev/null | awk '{print $1}')

# --- Context Mode Availability Check (cached) ---
# Cache result in /tmp/ctx-webfetch-avail-<hash> to avoid repeated python3 JSON parsing per WebFetch call.
# NOTE: This hook does NOT require /tmp/context-mode-ready-<hash> sentinel — WebFetch nudge has no
# bootstrap deadlock risk (ctx_fetch_and_index can run before any ctx_execute has ever run).
CTX_CACHE="/tmp/ctx-webfetch-avail-${PROJECT_HASH}"
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

# Fail-open: Context Mode not installed -> allow WebFetch through silently
if [ "$CONTEXT_MODE_INSTALLED" -eq 0 ]; then
    exit 0
fi

# --- Block: Redirect to Context Mode tools (stderr, exit 2) ---
cat >&2 <<EOF
BLOCKED: Use Context Mode instead of WebFetch for '$URL'.
  - Fetch + index: mcp__context-mode__ctx_fetch_and_index(url="$URL")
  - Query cached:  mcp__context-mode__ctx_search(query="...")
  ctx_fetch_and_index retrieves the URL, detects content type, and stores it in
  SQLite FTS5 so later ctx_search calls can query the same content without
  re-fetching — saving context tokens across the session.

  If this is a one-off fetch or live-data validation, retry WebFetch with the
  same URL -- this nudge fires once per URL/cache window, not repeatedly.
EOF

# --- Block Counter (best-effort; sibling script installed by setup.sh) ---
bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "webfetch" 2>/dev/null || true

exit 2
