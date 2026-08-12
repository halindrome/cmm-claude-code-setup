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

# _cmm_config_dir — byte-for-byte mirror of setup.sh's detect_config_dir().
# Duplicated rather than imported because hooks must not source setup.sh. If
# that function changes, change this one: a divergence here silently narrows
# the probe set, which is how a legacy ~/.claude-only install ended up
# unprobed while the installer happily registered CMM there.
_cmm_config_dir() {
    if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
        printf '%s' "$CLAUDE_CONFIG_DIR"
    elif [ -d "$HOME/.config/claude-code" ]; then
        printf '%s' "$HOME/.config/claude-code"
    else
        printf '%s' "$HOME/.claude"
    fi
}

# cmm_is_registered <repo_root>
#   Returns 0 when codebase-memory-mcp is registered as an MCP server in any
#   location Claude Code actually reads, else 1. Never writes, never blocks.
#
# ONE python3 spawn, not one per candidate path. This runs on every Grep and
# Bash tool call via PreToolUse; an interpreter start is ~16ms on a normal dev
# machine, so a path-at-a-time loop cost ~32ms of pure startup per tool call
# for a check that reads at most four small files.
cmm_is_registered() {
    local _root="${1:-}"
    local _cfg
    _cfg="$(_cmm_config_dir)"

    # Exactly the set setup.sh probes: the resolved config dir's settings.json
    # and .claude.json, the user-scope ~/.claude.json that `claude mcp add`
    # writes, and the project .mcp.json.
    CMM_ROOT="$_root" CMM_CFG="$_cfg" python3 -c '
import json, os, sys

root = os.environ.get("CMM_ROOT", "")
cfg = os.environ.get("CMM_CFG", "")
home = os.path.expanduser("~")

paths = []
if root:
    paths.append(os.path.join(root, ".mcp.json"))
if cfg:
    paths.append(os.path.join(cfg, "settings.json"))
    paths.append(os.path.join(cfg, ".claude.json"))
paths.append(os.path.join(home, ".claude.json"))

for p in paths:
    try:
        with open(p) as f:
            d = json.load(f)
    except Exception:
        # Missing, unreadable, a directory, or not JSON — never fatal.
        continue
    if not isinstance(d, dict):
        continue
    servers = d.get("mcpServers")
    if isinstance(servers, dict) and "codebase-memory-mcp" in servers:
        sys.exit(0)
sys.exit(1)
' 2>/dev/null
}
