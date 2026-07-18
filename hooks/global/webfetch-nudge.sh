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
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" 2>/dev/null && pwd -P)"
if [ -f "$_LIB_DIR/context-mode-detect.sh" ]; then
    source "$_LIB_DIR/context-mode-detect.sh"
    detect_context_mode "$REPO_ROOT" "/tmp/ctx-webfetch-avail-${PROJECT_HASH}"
else
    # Partial install (lib missing) — fail open rather than block WebFetch blindly.
    exit 0
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

  This nudge fires on every WebFetch call while Context Mode is installed in
  this project (cache is keyed on project, not URL). For one-off fetches or
  live-data validation where Context Mode is genuinely inappropriate, the
  redirect here is advisory only — retry does not bypass the block. Use
  ctx_fetch_and_index for the fetch, or ctx_search if the URL is already
  indexed.
EOF

# --- Block Counter (best-effort; sibling script installed by setup.sh) ---
bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "webfetch" 2>/dev/null || true

exit 2
