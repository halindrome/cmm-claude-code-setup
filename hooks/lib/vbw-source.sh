#!/bin/bash
# vbw-source.sh — Shared VBW plugin-tree resolver library (source, don't execute)
#
# Usage:
#   source hooks/lib/vbw-source.sh && resolve_vbw_source && echo "$VBW_AGENTS_DIR"
#
# Exported vars (after resolve_vbw_source returns 0):
#   VBW_AGENTS_DIR   — absolute path to the agents/ directory of the active VBW tree
#   VBW_SOURCE_TYPE  — one of: local-symlink | marketplace | dev-checkout | absent
#   VBW_VERSION      — version string (e.g. "1.37.1", "local", "dev") or "absent"
#
# Exit codes from resolve_vbw_source():
#   0  → VBW found; VBW_AGENTS_DIR, VBW_SOURCE_TYPE, VBW_VERSION are exported
#   1  → VBW absent or disabled; caller MUST fail-open (do not block Claude)
#
# Caller contract:
#   "fail-open" means: proceed without generating agent overrides — do NOT block
#   Claude Code when VBW is absent. The caller checks the return code and skips
#   override generation silently; it never exits 2 based solely on VBW absence.
#
# Resolution order (first match wins):
#   1. local-symlink  — plugins/cache/<mkt>/vbw/local → dev worktree (--plugin-dir mode)
#   2. marketplace    — plugins/cache/<mkt>/vbw/<version>/agents/ (published install)
#   3. dev-checkout   — ~/Sources/vibe-better-with-claude-code-vbw/agents/ (bare git clone)
#   4. absent         — none of the above found; VBW_SOURCE_TYPE=absent, returns 1
#
# Design notes — CLAUDE_CONFIG_DIR layout (researched from live system):
#
#   CONFIG_DIR resolution chain:
#     $CLAUDE_CONFIG_DIR              (env var set by Claude Code or user)
#     → $HOME/.config/claude-code     (XDG-style default used by Claude Code v1.0+)
#     → $HOME/.claude                 (legacy fallback)
#
#   installed_plugins.json schema (format version 2):
#     Top-level keys:
#       .version                                   — format version (integer, currently 2)
#       .plugins["<plugin>@<marketplace>"]         — array of install records
#         [0].installPath                          — "$CONFIG_DIR/plugins/cache/$mkt/$plugin/$version"
#         [0].version                              — semver string (e.g. "1.37.1")
#         [0].scope                                — "user" or "project"
#       .enabledPlugins["<plugin>@<marketplace>"]  — true|false (key absent = no explicit state)
#
#   VBW plugin key: "vbw@vbw-marketplace"
#   Published install path:   $CONFIG_DIR/plugins/cache/vbw-marketplace/vbw/<version>/
#   Local symlink (dev-mode): $CONFIG_DIR/plugins/cache/vbw-marketplace/vbw/local -> <worktree>
#     created by: claude --plugin-dir <path>
#
#   settings.json enabledPlugins["vbw@vbw-marketplace"]:
#     true    → explicitly enabled via marketplace install
#     false   → explicitly disabled (uninstalled but entry may remain in plugins.json)
#     absent  → loaded via --plugin-dir (local symlink); NOT the same as absent/disabled
#
#   Disabledness rule:
#     Plugin is effectively disabled ONLY when enabledPlugins["vbw@vbw-marketplace"] = false
#     AND no local symlink exists at plugins/cache/vbw-marketplace/vbw/local.
#     If the key is absent from enabledPlugins (the --plugin-dir case), VBW may still
#     be active via the local symlink — check the symlink first before concluding absent.
#
# Mirrors the sourceable-lib pattern of hooks/lib/project-root.sh.

# --- Idempotent guard ---
[ -n "$_VBW_SOURCE_LOADED" ] && return 0

# ---------------------------------------------------------------------------
# _vbw_config_dir — resolve the active Claude Code config directory
# Prints absolute path to stdout; returns 1 if none found.
# Honors CLAUDE_CONFIG_DIR env var; falls back to ~/.config/claude-code then ~/.claude.
# ---------------------------------------------------------------------------
_vbw_config_dir() {
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ -d "$CLAUDE_CONFIG_DIR" ]; then
    echo "$CLAUDE_CONFIG_DIR"
    return 0
  fi
  if [ -d "$HOME/.config/claude-code" ]; then
    echo "$HOME/.config/claude-code"
    return 0
  fi
  if [ -d "$HOME/.claude" ]; then
    echo "$HOME/.claude"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# resolve_vbw_source — locate the active VBW plugin tree and export vars
#
# Resolution order: local-symlink > marketplace > dev-checkout > absent
# Returns 0 on success (VBW found), 1 on absent/disabled (caller must fail-open).
# ---------------------------------------------------------------------------
resolve_vbw_source() {
  local config_dir marketplace plugin_key install_path version
  local agents_dir symlink_target

  # Reset exported vars in case of re-source
  VBW_AGENTS_DIR=""
  VBW_SOURCE_TYPE=""
  VBW_VERSION=""

  # --- Resolve CONFIG_DIR ---
  config_dir=$(_vbw_config_dir) || {
    echo "[vbw-source] Cannot locate Claude Code config directory" >&2
    VBW_SOURCE_TYPE="absent"
    VBW_VERSION="absent"
    export VBW_AGENTS_DIR VBW_SOURCE_TYPE VBW_VERSION
    return 1
  }

  marketplace="vbw-marketplace"
  plugin_key="vbw@${marketplace}"
  local plugins_json="${config_dir}/plugins/installed_plugins.json"
  local vbw_cache_base="${config_dir}/plugins/cache/${marketplace}/vbw"

  # --- Case 1: local-symlink (--plugin-dir dev mode, takes priority) ---
  # plugins/cache/vbw-marketplace/vbw/local is a symlink → dev worktree
  local local_link="${vbw_cache_base}/local"
  if [ -L "$local_link" ]; then
    symlink_target=$(readlink -f "$local_link" 2>/dev/null)
    if [ -n "$symlink_target" ] && [ -d "${symlink_target}/agents" ]; then
      VBW_AGENTS_DIR="${symlink_target}/agents"
      VBW_SOURCE_TYPE="local-symlink"
      VBW_VERSION="local"
      export VBW_AGENTS_DIR VBW_SOURCE_TYPE VBW_VERSION
      return 0
    fi
  fi

  # --- Case 2: marketplace published version ---
  # Read installPath from installed_plugins.json
  if [ -f "$plugins_json" ] && command -v python3 >/dev/null 2>&1; then
    install_path=$(python3 -c "
import json, sys
try:
    with open('$plugins_json') as f:
        d = json.load(f)
    entries = d.get('plugins', {}).get('$plugin_key', [])
    if entries and isinstance(entries, list):
        print(entries[0].get('installPath', ''))
except Exception:
    pass
" 2>/dev/null)
    version=$(python3 -c "
import json, sys
try:
    with open('$plugins_json') as f:
        d = json.load(f)
    entries = d.get('plugins', {}).get('$plugin_key', [])
    if entries and isinstance(entries, list):
        print(entries[0].get('version', ''))
except Exception:
    pass
" 2>/dev/null)

    if [ -n "$install_path" ] && [ -n "$version" ]; then
      agents_dir="${install_path}/agents"
      if [ -d "$agents_dir" ]; then
        VBW_AGENTS_DIR="$agents_dir"
        VBW_SOURCE_TYPE="marketplace"
        VBW_VERSION="$version"
        export VBW_AGENTS_DIR VBW_SOURCE_TYPE VBW_VERSION
        return 0
      fi
    fi
  fi

  # --- Case 3: dev checkout fallback ---
  # Bare git clone at the known dev checkout path (no plugin-dir or marketplace install).
  local dev_checkout_agents="$HOME/Sources/vibe-better-with-claude-code-vbw/agents"
  if [ -d "$dev_checkout_agents" ]; then
    VBW_AGENTS_DIR="$dev_checkout_agents"
    VBW_SOURCE_TYPE="dev-checkout"
    VBW_VERSION="dev"
    export VBW_AGENTS_DIR VBW_SOURCE_TYPE VBW_VERSION
    return 0
  fi

  # --- Case 4: absent — all cases exhausted ---
  echo "[vbw-source] VBW plugin not found (no local-symlink, marketplace install, or dev checkout)" >&2
  VBW_SOURCE_TYPE="absent"
  VBW_VERSION="absent"
  VBW_AGENTS_DIR=""
  export VBW_AGENTS_DIR VBW_SOURCE_TYPE VBW_VERSION
  return 1
}

_VBW_SOURCE_LOADED=1
