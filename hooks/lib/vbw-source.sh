#!/bin/bash
# vbw-source.sh — Shared VBW plugin-tree resolver library (source, don't execute)
#
# Usage:
#   source hooks/lib/vbw-source.sh && resolve_vbw_source && echo "$VBW_AGENTS_DIR"
#
# Exported vars (after resolve_vbw_source returns 0):
#   VBW_AGENTS_DIR   — absolute path to the agents/ directory of the active VBW tree
#   VBW_SOURCE_TYPE  — one of: local-symlink | marketplace | dev-checkout | vbw2 | absent
#                      (vbw2 = vbw-marketplace/vbw/2.x; returns 1 — use resolve_vbw2 for VBW 2)
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
# Use ${var:-} to tolerate callers that set -u before sourcing this lib.
[ -n "${_VBW_SOURCE_LOADED:-}" ] && return 0

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
# _vbw2_pick <config_dir> — pick the VBW 2.x plugin tree Claude Code loads
# Sets _V2_DIR and _V2_VER (version from the tree's VERSION file); returns 1 if none.
# Order: first 2.x entry of installed_plugins.json whose installPath exists,
# else the highest semver 2.x directory in the plugin cache.
# ---------------------------------------------------------------------------
_vbw2_pick() {
  local base="${1}/plugins/cache/vbw-marketplace/vbw" dir="" d v
  _V2_DIR=""
  _V2_VER=""
  if [ -f "${1}/plugins/installed_plugins.json" ] && command -v python3 >/dev/null 2>&1; then
    dir=$(python3 -c "
import json, os, sys
try:
    d = json.load(open(sys.argv[1]))
    for e in d.get('plugins', {}).get('vbw@vbw-marketplace', []):
        if str(e.get('version', '')).startswith('2.') and os.path.isdir(e.get('installPath', '')):
            print(e['installPath']); break
except Exception:
    pass
" "${1}/plugins/installed_plugins.json" 2>/dev/null)
  fi
  if [ -z "$dir" ]; then
    d=$(for v in "$base"/2.*; do [ -d "$v" ] && basename "$v"; done 2>/dev/null | sort -V | tail -n 1)
    [ -n "$d" ] && dir="$base/$d"
  fi
  [ -n "$dir" ] || return 1
  v=$(head -n 1 "$dir/VERSION" 2>/dev/null | tr -d '[:space:]')
  _V2_DIR="$dir"
  _V2_VER="${v:-$(basename "$dir")}"
}

# ---------------------------------------------------------------------------
# resolve_vbw2 — locate the VBW 2 plugin tree; independent of resolve_vbw_source
# Returns 0 and exports VBW2_VERSION (and VBW2_DIR), or 1 when no VBW 2 is installed.
# ---------------------------------------------------------------------------
resolve_vbw2() {
  local config_dir
  VBW2_VERSION=""
  VBW2_DIR=""
  config_dir=$(_vbw_config_dir) || return 1
  _vbw2_pick "$config_dir" || return 1
  VBW2_DIR="$_V2_DIR"
  VBW2_VERSION="$_V2_VER"
  export VBW2_DIR VBW2_VERSION
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

  # --- Disabledness check (between Case 1 and Case 2) ---
  # If enabledPlugins["vbw@vbw-marketplace"] is explicitly false AND no local symlink
  # exists, the plugin was uninstalled; treat as absent immediately.
  # Key absent from enabledPlugins = --plugin-dir mode (not the same as disabled).
  if [ -f "$plugins_json" ] && command -v python3 >/dev/null 2>&1; then
    local enabled_state
    enabled_state=$(python3 -c "
import json
try:
    with open('$plugins_json') as f:
        d = json.load(f)
    ep = d.get('enabledPlugins', {})
    if '$plugin_key' in ep:
        print('false' if ep['$plugin_key'] is False else 'true')
    else:
        print('absent')
except Exception:
    print('absent')
" 2>/dev/null)
    if [ "$enabled_state" = "false" ]; then
      # Explicitly disabled and no local-symlink override (already checked above).
      echo "[vbw-source] VBW plugin is explicitly disabled (enabledPlugins[\"$plugin_key\"] = false)" >&2
      VBW_SOURCE_TYPE="absent"
      VBW_VERSION="absent"
      VBW_AGENTS_DIR=""
      export VBW_AGENTS_DIR VBW_SOURCE_TYPE VBW_VERSION
      return 1
    fi
  fi

  # --- VBW 2 (vbw-marketplace/vbw/2.x): its own source type, never "marketplace" ---
  # Taken when the active (first) registry entry is 2.x, or when there is no
  # registry entry at all but a 2.x tree is cached. Returns 1 (VBW 1 callers
  # treat it as absent and fail open); callers wanting VBW 2 use resolve_vbw2.
  local first_ver=""
  if [ -f "$plugins_json" ] && command -v python3 >/dev/null 2>&1; then
    first_ver=$(python3 -c "
import json, sys
try:
    e = json.load(open(sys.argv[1])).get('plugins', {}).get('$plugin_key', [])
    print(e[0].get('version', '') if e else '')
except Exception:
    pass
" "$plugins_json" 2>/dev/null)
  fi
  if [ -z "$first_ver" ] || [ "${first_ver#2.}" != "$first_ver" ]; then
    if _vbw2_pick "$config_dir"; then
      VBW_AGENTS_DIR="${_V2_DIR}/agents"
      VBW_SOURCE_TYPE="vbw2"
      VBW_VERSION="$_V2_VER"
      export VBW_AGENTS_DIR VBW_SOURCE_TYPE VBW_VERSION
      return 1
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
