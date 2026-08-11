#!/bin/bash
# cmm-registered.sh — shared "is codebase-memory-mcp actually registered?" probe.
#
# Install: copied to <base>/hooks/lib/cmm-registered.sh by setup.sh.
# Register: not a hook; sourced by the gate/nudge hooks below.
#
# WHY THIS EXISTS
# ---------------
# Six availability cascades across five hooks each hand-rolled this check, and
# they drifted. Two defects came out of that drift:
#
#   1. They probed exactly ONE global location —
#      "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" — while setup.sh
#      probes THREE. A user-scope `claude mcp add` writes to .claude.json, so a
#      perfectly normal install registered CMM somewhere no hook ever looked and
#      every gate silently took its fail-open exit. That is the enforcement this
#      stack exists to provide, absent, with no error.
#
#   2. Grepping for the bare string 'codebase-memory-mcp' anywhere in a settings
#      file is NOT a registration test. A permissions allowlist
#      ("mcp__codebase-memory-mcp__search_graph") contains that string, and so
#      does a rule DENYING those tools. Matching it turns a fail-open bug into a
#      fail-CLOSED one: the user's Grep/Bash get hard-blocked because they
#      mentioned CMM. Fail-closed is strictly worse than fail-open here, because
#      the remedy is a tool call the block itself forbids.
#
# So: probe the same KEY, in the same PLACES, as setup.sh (see its
# _probe_paths list) — mcpServers.codebase-memory-mcp, never a substring.
#
# Usage:
#   source "<lib>/cmm-registered.sh"
#   cmm_is_registered "$REPO_ROOT" && ...   # 0 = registered, 1 = not

# cmm_is_registered <repo_root>
#   Returns 0 when codebase-memory-mcp is registered as an MCP server in any
#   location Claude Code actually reads, else 1. Never writes, never blocks.
cmm_is_registered() {
    local _root="${1:-}"
    local _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.config/claude-code}"

    # Project scope first (cheapest, most specific), then the three global
    # locations setup.sh probes. Order does not affect the result.
    local _p
    for _p in \
        "${_root}/.mcp.json" \
        "${_cfg}/settings.json" \
        "${_cfg}/.claude.json" \
        "${HOME}/.claude.json" \
        "${HOME}/.claude/settings.json"
    do
        [ -n "$_p" ] || continue
        [ -f "$_p" ] || continue
        if P="$_p" python3 -c '
import json, os, sys
try:
    with open(os.environ["P"]) as f:
        d = json.load(f)
except Exception:
    sys.exit(1)
servers = d.get("mcpServers") if isinstance(d, dict) else None
sys.exit(0 if isinstance(servers, dict) and "codebase-memory-mcp" in servers else 1)
' 2>/dev/null; then
            return 0
        fi
    done
    return 1
}
