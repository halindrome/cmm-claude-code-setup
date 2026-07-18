#!/bin/bash
# context-mode-detect.sh — shared Context Mode availability probe for hooks.
#
# Source this, then call:  detect_context_mode <root> [cache_file]
# Sets CONTEXT_MODE_INSTALLED to 1 (usable) or 0 (absent/broken → fail open).
#
# WHY THIS EXISTS
# ---------------
# Six hooks previously each carried their own inline copy of this probe, and all
# six shared two defects that could wedge a session with no escape hatch:
#
#   1. `[ -f "<root>/.claude/context-mode.db" ] && CONTEXT_MODE_INSTALLED=1`
#      A session DB is a PERMANENT LATCH: once context-mode has ever run in a
#      repo, the file remains forever. Uninstall the plugin and every blocking
#      hook still fires, redirecting to ctx_* tools that no longer exist.
#
#   2. Presence-of-files was treated as proof-of-registration. The probe scanned
#      the plugin cache directory, but Claude Code loads a plugin through the
#      `installPath` recorded in plugins/installed_plugins.json. When that path
#      does not resolve on this filesystem, the plugin never loads and no ctx_*
#      tool is registered — while the cache directory sits right there on disk,
#      convincing the probe everything is fine.
#
#      The real-world trigger is a VS Code devcontainer that bind-mounts the
#      host config dir, e.g.
#        source=${localEnv:HOME}/.config/claude-code,target=/home/vscode/.config/claude-code
#      with CLAUDE_CONFIG_DIR=/home/vscode/.config/claude-code. The container and
#      the host see the SAME registry file at TWO different absolute paths. Any
#      absolute path written from inside the container is unresolvable on the
#      host, so a single container session permanently breaks context-mode for
#      every host session — and the blocking hooks keep enforcing it.
#
# The rule this library enforces: fail open unless context-mode is not merely
# present on disk but actually loadable. A hook that cannot prove the tool
# exists must not mandate its use.

# LOCATING THIS LIBRARY
# ---------------------
# Two layouts must both work:
#   installed:  hooks live at <base>/hooks/,        lib at <base>/hooks/lib/
#   repo:       hooks live at hooks/project|global/, lib at hooks/lib/
# so callers resolve "<dir>/lib" first, then "<dir>/../lib":
#
#   _CM_LIB=""
#   for _d in "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
#     [ -f "$_d/context-mode-detect.sh" ] && { _CM_LIB="$_d/context-mode-detect.sh"; break; }
#   done

# detect_context_mode <root> [cache_file]
#   <root>       repo/project root (used for .mcp.json lookup)
#   [cache_file] optional /tmp cache path; auto-invalidated when any input file
#                is newer than the cache, so a repaired registry takes effect
#                without a manual cache purge.
detect_context_mode() {
    local _root="$1"
    local _cache="$2"

    if [ -n "$_cache" ] && [ -f "$_cache" ]; then
        # Cache is valid only if it is newer than every file the probe reads.
        # A stale `1` written before the registry was repaired would otherwise
        # keep the session wedged until /tmp was cleared by hand.
        local _newer
        _newer=$(find \
            "${_root}/.mcp.json" \
            "${CLAUDE_CONFIG_DIR:-${HOME}/.config/claude-code}/settings.json" \
            "${CLAUDE_CONFIG_DIR:-${HOME}/.config/claude-code}/plugins/installed_plugins.json" \
            "${HOME}/.claude/settings.json" \
            "${HOME}/.claude/plugins/installed_plugins.json" \
            -newer "$_cache" 2>/dev/null | head -1)
        if [ -z "$_newer" ]; then
            CONTEXT_MODE_INSTALLED=$(cat "$_cache" 2>/dev/null)
            CONTEXT_MODE_INSTALLED="${CONTEXT_MODE_INSTALLED:-0}"
            return 0
        fi
    fi

    CONTEXT_MODE_INSTALLED=0
    if ROOT="$_root" python3 <<'PY' 2>/dev/null
import json, os, sys

root = os.environ.get("ROOT", "")

config_dirs = [
    os.environ.get("CLAUDE_CONFIG_DIR", ""),
    os.path.expanduser("~/.config/claude-code"),
    os.path.expanduser("~/.claude"),
]
config_dirs = [d for d in config_dirs if d]


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def plugin_loadable():
    """True only if a context-mode plugin entry has a resolvable installPath.

    installPath is what Claude Code's plugin loader actually spawns from. A
    path recorded by a devcontainer (/home/vscode/...) does not exist on the
    host, so the plugin silently fails to load and registers no MCP tools.
    Returns None when no registry entry exists at all (unknown, not broken),
    so a plain mcpServers install is still detected below.
    """
    seen_entry = False
    for d in config_dirs:
        reg = load(os.path.join(d, "plugins", "installed_plugins.json"))
        if not isinstance(reg, dict):
            continue
        plugins = reg.get("plugins")
        if not isinstance(plugins, dict):
            continue
        enabled = reg.get("enabledPlugins")
        enabled = enabled if isinstance(enabled, dict) else {}
        for key, entries in plugins.items():
            if key.split("@", 1)[0] != "context-mode":
                continue
            if enabled.get(key) is False:
                continue  # explicit user opt-out
            if not isinstance(entries, list):
                continue
            for entry in entries:
                if not isinstance(entry, dict):
                    continue
                path = entry.get("installPath")
                if not isinstance(path, str) or not path:
                    continue
                seen_entry = True
                # The decisive check: does the recorded path exist HERE?
                if os.path.isdir(path):
                    return True
    return False if seen_entry else None


verdict = plugin_loadable()
if verdict is True:
    sys.exit(0)
if verdict is False:
    # A registry entry exists but points nowhere reachable on this filesystem.
    # The plugin cannot load; do not let hooks mandate its tools.
    sys.exit(1)

# No plugin registry entry — fall back to a classic mcpServers registration.
mcp = load(os.path.join(root, ".mcp.json"))
if isinstance(mcp, dict) and "context-mode" in (mcp.get("mcpServers") or {}):
    sys.exit(0)
for d in config_dirs:
    cfg = load(os.path.join(d, "settings.json"))
    if isinstance(cfg, dict) and "context-mode" in (cfg.get("mcpServers") or {}):
        sys.exit(0)

sys.exit(1)
PY
    then
        CONTEXT_MODE_INSTALLED=1
    fi

    # NOTE: deliberately NO `<root>/.claude/context-mode.db` fallback. See the
    # permanent-latch defect documented at the top of this file.

    if [ -n "$_cache" ]; then
        echo "$CONTEXT_MODE_INSTALLED" > "$_cache" 2>/dev/null || true
    fi
    return 0
}
