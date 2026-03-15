#!/usr/bin/env bash
set -euo pipefail

# setup.sh — Automated installer for codebase-memory-mcp Claude Code hooks
#
# Usage:
#   ./setup.sh [--global] [--project] [--all] [--force] [--dry-run] [--skip-mcp-check] [--skip-statusline]
#
# Flags:
#   --global          Install global hooks to ~/.claude/hooks/ and merge into ~/.claude/settings.json
#   --project         Install project hooks to .claude/hooks/, rules to .claude/rules/,
#                     create .mcp.json, and merge into .claude/settings.json
#   --all             Install both global and project hooks
#   --force           Overwrite existing files (default: skip existing)
#   --dry-run         Show what would be done without making changes
#   --skip-mcp-check  Bypass all MCP availability checks (CMM binary, registration,
#                     tool allowlist, context-mode). Useful for CI/automation.
#
# No flags: interactive prompt asking which to install.
#
# Prerequisites:
#   - python3 (required — used for JSON merging)
#   - codebase-memory-mcp (optional — warns if not found on PATH)
#
# Run from the repo root (the directory containing this script).
# chmod +x setup.sh before first run.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE=false
DRY_RUN=false
INSTALL_GLOBAL=false
INSTALL_PROJECT=false
SKIP_MCP_CHECK=false
SKIP_STATUSLINE=false

# Detect Claude Code config directory at runtime.
# Priority: $CLAUDE_CONFIG_DIR (set by Claude Code) > ~/.config/claude-code (XDG) > ~/.claude (legacy)
detect_config_dir() {
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    echo "$CLAUDE_CONFIG_DIR"
  elif [ -d "$HOME/.config/claude-code" ]; then
    echo "$HOME/.config/claude-code"
  else
    echo "$HOME/.claude"
  fi
}

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

copy_file() {
  local src="$1"
  local dest="$2"
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY RUN] Would copy $(basename "$src") -> $dest"
    return
  fi
  if [ -e "$dest" ] && [ "$FORCE" != true ]; then
    echo "  [skip] $(basename "$dest") already exists (use --force to overwrite)"
    return
  fi
  cp "$src" "$dest"
  echo "  [ok] Copied $(basename "$dest")"
}

set_executable() {
  local file="$1"
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY RUN] Would chmod +x $file"
    return
  fi
  chmod +x "$file"
}

# ---------------------------------------------------------------------------
# interactive_prompt
# ---------------------------------------------------------------------------

interactive_prompt() {
  while true; do
    echo ""
    echo "Which hooks would you like to install?"
    echo "  g) Global hooks only ($(detect_config_dir)/hooks/)"
    echo "  p) Project hooks only (.claude/hooks/)"
    echo "  a) Both global and project"
    echo "  q) Quit"
    echo ""
    printf "Choice [a]: "
    read -r choice
    choice="${choice:-a}"
    case "$choice" in
      g) INSTALL_GLOBAL=true; break ;;
      p) INSTALL_PROJECT=true; break ;;
      a) INSTALL_GLOBAL=true; INSTALL_PROJECT=true; break ;;
      q) exit 0 ;;
      *) echo "Invalid choice: '$choice'. Please enter g, p, a, or q." ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# detect_cmm_binary
# ---------------------------------------------------------------------------

# Status variable populated by detect_cmm_binary(); read by print_preflight_summary()
CMM_BINARY_STATUS="unknown"
CMM_BINARY_PATH=""

detect_cmm_binary() {
  if [ "$SKIP_MCP_CHECK" = true ]; then
    CMM_BINARY_STATUS="skip"
    return 0
  fi

  # 1. PATH lookup (fastest, most reliable)
  if command -v codebase-memory-mcp >/dev/null 2>&1; then
    CMM_BINARY_PATH="$(command -v codebase-memory-mcp)"
    CMM_BINARY_STATUS="ok"
    return 0
  fi

  # 2-4. Fallback paths
  local fallback
  for fallback in \
    "$HOME/.local/bin/codebase-memory-mcp" \
    "$HOME/go/bin/codebase-memory-mcp" \
    "/usr/local/bin/codebase-memory-mcp"
  do
    if [ -x "$fallback" ]; then
      CMM_BINARY_PATH="$fallback"
      CMM_BINARY_STATUS="ok"
      echo "  [info] Found codebase-memory-mcp at $fallback (not on PATH)"
      echo "  [info] Consider adding $(dirname "$fallback") to your PATH."
      return 0
    fi
  done

  # Not found anywhere
  CMM_BINARY_STATUS="warn"
  echo ""
  echo "  [warn] codebase-memory-mcp binary not found on PATH or common install paths."
  echo "  [info] Install it first:"
  echo "         Releases: https://github.com/DeusData/codebase-memory-mcp/releases/latest"
  echo "         One-liner (copy and run):"
  echo "           curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/scripts/setup.sh | bash"
  echo ""
  printf "  Continue without CMM binary? [y/N]: "
  read -r choice
  choice="${choice:-n}"
  if [ "$choice" != "y" ] && [ "$choice" != "Y" ]; then
    echo "Aborting. Install codebase-memory-mcp and re-run setup.sh." >&2
    exit 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# detect_cmm_registration
# ---------------------------------------------------------------------------

# Status variable populated by detect_cmm_registration(); read by print_preflight_summary()
CMM_REGISTRATION_STATUS="unknown"

detect_cmm_registration() {
  if [ "$SKIP_MCP_CHECK" = true ]; then
    CMM_REGISTRATION_STATUS="skip"
    return 0
  fi

  # 1. Project .mcp.json
  if [ -f ".mcp.json" ] && grep -q "codebase-memory-mcp" ".mcp.json"; then
    CMM_REGISTRATION_STATUS="ok"
    echo "  [ok] CMM registered (project .mcp.json)"
    return 0
  fi

  # 2. Global settings.json
  local config_dir
  config_dir=$(detect_config_dir)
  if grep -q "codebase-memory-mcp" "${config_dir}/settings.json" 2>/dev/null; then
    CMM_REGISTRATION_STATUS="ok"
    echo "  [ok] CMM registered (global settings.json)"
    return 0
  fi

  # Not registered
  CMM_REGISTRATION_STATUS="warn"
  echo ""
  echo "  [warn] CMM not registered with Claude Code."
  echo "  [info] Register it by running (copy and run):"
  echo "           codebase-memory-mcp install"
  echo "  [info] Or manually add to .mcp.json:"
  echo '           { "mcpServers": { "codebase-memory-mcp": { "command": "codebase-memory-mcp", "args": [], "type": "stdio" } } }'
  echo ""
  printf "  Continue without registering CMM? [y/N]: "
  read -r choice
  choice="${choice:-n}"
  if [ "$choice" != "y" ] && [ "$choice" != "Y" ]; then
    echo "Aborting. Register CMM and re-run setup.sh." >&2
    exit 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# detect_cmm_tools_allowed
# ---------------------------------------------------------------------------

# Status variable populated by detect_cmm_tools_allowed(); read by print_preflight_summary()
CMM_TOOLS_STATUS="unknown"
CMM_TOOLS_COUNT=0

detect_cmm_tools_allowed() {
  if [ "$SKIP_MCP_CHECK" = true ]; then
    CMM_TOOLS_STATUS="skip"
    return 0
  fi

  local settings_file=".claude/settings.local.json"

  if [ ! -f "$settings_file" ]; then
    CMM_TOOLS_STATUS="missing"
    echo ""
    echo "  [warn] .claude/settings.local.json not found — CMM tools not allowlisted."
    _print_cmm_tools_snippet
    printf "  Acknowledged? [Enter to continue]: "
    read -r _ack
    return 0
  fi

  # Count mcp__codebase-memory-mcp__ entries in permissions.allow
  CMM_TOOLS_COUNT=$(python3 - "$settings_file" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    allow = data.get("permissions", {}).get("allow", [])
    count = sum(1 for t in allow if "mcp__codebase-memory-mcp__" in str(t))
    print(count)
except Exception:
    print(0)
PYEOF
)

  if [ "$CMM_TOOLS_COUNT" -ge 14 ]; then
    CMM_TOOLS_STATUS="ok"
    echo "  [ok] All 14 CMM tools allowlisted in $settings_file"
    return 0
  fi

  CMM_TOOLS_STATUS="warn"
  echo ""
  echo "  [warn] Only ${CMM_TOOLS_COUNT}/14 CMM tools in $settings_file"
  _print_cmm_tools_snippet
  printf "  Acknowledged? [Enter to continue]: "
  read -r _ack
  return 0
}

_print_cmm_tools_snippet() {
  echo "  [info] Add the following to .claude/settings.local.json under permissions.allow:"
  echo '  {'
  echo '    "permissions": {'
  echo '      "allow": ['
  echo '        "mcp__codebase-memory-mcp__index_repository",'
  echo '        "mcp__codebase-memory-mcp__index_status",'
  echo '        "mcp__codebase-memory-mcp__list_projects",'
  echo '        "mcp__codebase-memory-mcp__delete_project",'
  echo '        "mcp__codebase-memory-mcp__get_architecture",'
  echo '        "mcp__codebase-memory-mcp__get_graph_schema",'
  echo '        "mcp__codebase-memory-mcp__search_graph",'
  echo '        "mcp__codebase-memory-mcp__search_code",'
  echo '        "mcp__codebase-memory-mcp__query_graph",'
  echo '        "mcp__codebase-memory-mcp__get_code_snippet",'
  echo '        "mcp__codebase-memory-mcp__trace_call_path",'
  echo '        "mcp__codebase-memory-mcp__detect_changes",'
  echo '        "mcp__codebase-memory-mcp__manage_adr",'
  echo '        "mcp__codebase-memory-mcp__ingest_traces"'
  echo '      ]'
  echo '    }'
  echo '  }'
}

# ---------------------------------------------------------------------------
# detect_context_mode
# ---------------------------------------------------------------------------

# Status variable populated by detect_context_mode(); read by print_preflight_summary()
CONTEXT_MODE_STATUS="skip"

detect_context_mode() {
  if [ "$SKIP_MCP_CHECK" = true ]; then
    CONTEXT_MODE_STATUS="skip"
    return 0
  fi

  # Only runs for project installs
  if [ "$INSTALL_PROJECT" != true ]; then
    CONTEXT_MODE_STATUS="skip"
    return 0
  fi

  # Detection: binary or existing db
  if command -v context-mode >/dev/null 2>&1 || [ -f ".claude/context-mode.db" ]; then
    CONTEXT_MODE_STATUS="ok"
    echo "  [ok] context-mode detected"
    return 0
  fi

  # Not detected: prompt interactively when stdin is a tty, otherwise warn non-interactively
  CONTEXT_MODE_STATUS="warn"
  echo ""
  if [ -t 0 ]; then
    printf "  Use Context Mode integration? [y/N]: "
    read -r choice
    choice="${choice:-n}"
    if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
      echo "  [info] Install Context Mode:"
      echo "           npm install -g context-mode"
      if [ "$INSTALL_PROJECT" = true ]; then
        echo "  [info] Register with Claude Code (project-scoped):"
        echo "           claude mcp add --scope project context-mode -- npx -y context-mode"
      else
        echo "  [info] Register with Claude Code (globally):"
        echo "           claude mcp add context-mode -- npx -y context-mode"
        echo "  [info] Or project-scoped (recommended — run from project dir):"
        echo "           claude mcp add --scope project context-mode -- npx -y context-mode"
      fi
      echo "  [info] Docs: https://github.com/mksglu/context-mode"
    fi
  else
    echo "  [warn] context-mode not detected."
    echo "  [info] Install Context Mode:"
    echo "           npm install -g context-mode"
    if [ "$INSTALL_PROJECT" = true ]; then
      echo "  [info] Register with Claude Code (project-scoped):"
      echo "           claude mcp add --scope project context-mode -- npx -y context-mode"
    else
      echo "  [info] Register with Claude Code:"
      echo "           claude mcp add context-mode -- npx -y context-mode"
    fi
    echo "  [info] Docs: https://github.com/mksglu/context-mode"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# print_preflight_summary
# ---------------------------------------------------------------------------

print_preflight_summary() {
  local binary_line reg_line tools_line ctx_line

  # CMM binary line
  case "$CMM_BINARY_STATUS" in
    ok)
      if [ -n "$CMM_BINARY_PATH" ]; then
        binary_line="[ok]   CMM binary found at $CMM_BINARY_PATH"
      else
        binary_line="[ok]   CMM binary found on PATH"
      fi
      ;;
    warn)   binary_line="[warn] CMM binary not found on PATH or common install paths" ;;
    skip)   binary_line="[skip] CMM binary check (--skip-mcp-check)" ;;
    *)      binary_line="[skip] CMM binary check (not run)" ;;
  esac

  # CMM registration line
  case "$CMM_REGISTRATION_STATUS" in
    ok)   reg_line="[ok]   CMM registered in .mcp.json or global settings.json" ;;
    warn) reg_line="[warn] CMM not registered in .mcp.json or global settings.json" ;;
    skip) reg_line="[skip] CMM registration check (--skip-mcp-check)" ;;
    *)    reg_line="[skip] CMM registration check (not run)" ;;
  esac

  # CMM tools line
  case "$CMM_TOOLS_STATUS" in
    ok)      tools_line="[ok]   All 14 CMM tools allowlisted in .claude/settings.local.json" ;;
    warn)    tools_line="[warn] ${CMM_TOOLS_COUNT}/14 CMM tools in .claude/settings.local.json" ;;
    missing) tools_line="[warn] .claude/settings.local.json not found — CMM tools not allowlisted" ;;
    skip)    tools_line="[skip] CMM tools check (--skip-mcp-check)" ;;
    *)       tools_line="[skip] CMM tools check (not run)" ;;
  esac

  # Context-mode line
  case "$CONTEXT_MODE_STATUS" in
    ok)   ctx_line="[ok]   context-mode detected" ;;
    warn) ctx_line="[warn] context-mode not detected" ;;
    skip) ctx_line="[skip] context-mode check (not applicable)" ;;
    *)    ctx_line="[skip] context-mode check (not run)" ;;
  esac

  echo "============================================================"
  echo "Pre-flight check summary:"
  echo "  $binary_line"
  echo "  $reg_line"
  echo "  $tools_line"
  echo "  $ctx_line"
  echo "============================================================"
  echo ""
}

# ---------------------------------------------------------------------------
# check_mcp_availability
# ---------------------------------------------------------------------------

check_mcp_availability() {
  if [ "$SKIP_MCP_CHECK" = true ]; then
    return 0
  fi

  echo "[MCP PRE-FLIGHT CHECKS]"
  detect_cmm_registration
  detect_cmm_tools_allowed
  detect_context_mode
  print_preflight_summary
}

# ---------------------------------------------------------------------------
# check_prerequisites
# ---------------------------------------------------------------------------

check_prerequisites() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] python3 is required but not found on PATH." >&2
    exit 1
  fi

  detect_cmm_binary

  if [ ! -d "$SCRIPT_DIR/hooks" ]; then
    echo "[ERROR] hooks/ directory not found in $SCRIPT_DIR" >&2
    exit 1
  fi

  if [ "$INSTALL_PROJECT" = true ] && [ ! -d "$SCRIPT_DIR/rules" ]; then
    echo "[ERROR] rules/ directory not found in $SCRIPT_DIR" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# merge_settings_json <target_file> <mode>
# ---------------------------------------------------------------------------

merge_settings_json() {
  local target_file="$1"
  local mode="$2"

  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY RUN] Would merge hooks into $target_file"
    return
  fi

  if [ -f "$target_file" ]; then
    cp "$target_file" "${target_file}.backup"
    echo "  [ok] Backed up $(basename "$target_file") -> $(basename "$target_file").backup"
  fi

  mkdir -p "$(dirname "$target_file")"

  local NEW_HOOKS_JSON
  if [ "$mode" = "global" ]; then
    NEW_HOOKS_JSON=$(cat <<'HOOKJSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [{"type": "command", "command": "bash \"${CLAUDE_CONFIG_DIR}/hooks/cmm-nudge.sh\""}]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{"type": "command", "command": "bash \"${CLAUDE_CONFIG_DIR}/hooks/reindex-after-edit.sh\""}]
      }
    ]
  }
}
HOOKJSON
)
  else
    NEW_HOOKS_JSON=$(cat "$SCRIPT_DIR/rules/project-settings-example.json")
  fi

  python3 -c '
import json, os, sys
target_file = sys.argv[1]
new_json_str = sys.argv[2]
try:
    with open(target_file, "r") as f:
        existing = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    existing = {}
new_data = json.loads(new_json_str)
if "hooks" not in existing:
    existing["hooks"] = {}
for hook_type, entries in new_data.get("hooks", {}).items():
    if hook_type not in existing["hooks"]:
        existing["hooks"][hook_type] = []
    existing_cmds = {json.dumps(h, sort_keys=True) for group in existing["hooks"][hook_type] for h in group.get("hooks", [])}
    for entry in entries:
        new_cmds = {json.dumps(h, sort_keys=True) for h in entry.get("hooks", [])}
        if not new_cmds.issubset(existing_cmds):
            existing["hooks"][hook_type].append(entry)
            existing_cmds |= new_cmds
        else:
            # Hook commands already present — update matcher if it changed
            new_matcher = entry.get("matcher", "")
            if new_matcher:
                for existing_entry in existing["hooks"][hook_type]:
                    entry_cmds = {json.dumps(h, sort_keys=True) for h in existing_entry.get("hooks", [])}
                    if new_cmds == entry_cmds and existing_entry.get("matcher", "") != new_matcher:
                        existing_entry["matcher"] = new_matcher
tmp = target_file + ".tmp"
with open(tmp, "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")
os.replace(tmp, target_file)
' "$target_file" "$NEW_HOOKS_JSON"

  if python3 -m json.tool "$target_file" >/dev/null 2>&1; then
    echo "  [ok] Merged hooks into $(basename "$target_file")"
    echo "  [ok] JSON validated"
  else
    echo "[ERROR] JSON validation failed for $target_file" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# install_global
# ---------------------------------------------------------------------------

install_global() {
  echo "[GLOBAL INSTALL]"

  local config_dir
  config_dir=$(detect_config_dir)
  echo "  [info] Config dir: $config_dir"

  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY RUN] Would create ${config_dir}/hooks/"
  else
    mkdir -p "${config_dir}/hooks"
  fi

  shopt -s nullglob
  for file in "$SCRIPT_DIR/hooks/global/"*.sh; do
    copy_file "$file" "${config_dir}/hooks/$(basename "$file")"
    set_executable "${config_dir}/hooks/$(basename "$file")"
  done
  shopt -u nullglob

  merge_settings_json "${config_dir}/settings.json" "global"

  echo ""
}

# ---------------------------------------------------------------------------
# install_project
# ---------------------------------------------------------------------------

install_project() {
  echo "[PROJECT INSTALL]"

  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY RUN] Would create .claude/hooks/"
    echo "  [DRY RUN] Would create .claude/rules/"
  else
    mkdir -p .claude/hooks
    mkdir -p .claude/rules
  fi

  shopt -s nullglob
  for file in "$SCRIPT_DIR/hooks/project/"*.sh; do
    copy_file "$file" ".claude/hooks/$(basename "$file")"
    set_executable ".claude/hooks/$(basename "$file")"
  done
  shopt -u nullglob

  shopt -s nullglob
  for file in "$SCRIPT_DIR/rules/"*; do
    copy_file "$file" ".claude/rules/$(basename "$file")"
  done
  shopt -u nullglob

  copy_file "$SCRIPT_DIR/rules/mcp-example.json" ".mcp.json"

  merge_settings_json ".claude/settings.json" "project"

  echo ""
}

# ---------------------------------------------------------------------------
# install_statusline
# ---------------------------------------------------------------------------

install_statusline() {
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY RUN] Would offer to install statusline-cmm.sh and merge statusLine into settings.local.json"
    return
  fi

  _run_install_statusline_for_target() {
    local target_config_dir="$1"
    local mode="$2"

    # statusLine is personal/machine-specific, so it belongs in settings.local.json
    # (gitignored, per Claude Code docs). We check both files for existing entries.
    local target_settings="${target_config_dir}/settings.local.json"
    local shared_settings="${target_config_dir}/settings.json"

    # Detect existing statusLine entry in settings.local.json OR settings.json
    local has_statusline=false
    local found_in=""
    for check_file in "$target_settings" "$shared_settings"; do
      if [ -f "$check_file" ]; then
        if python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    sys.exit(0 if 'statusLine' in data else 1)
except Exception:
    sys.exit(1)
" "$check_file" 2>/dev/null; then
          has_statusline=true
          found_in="$check_file"
          break
        fi
      fi
    done

    if [ "$has_statusline" = true ]; then
      if [ "$FORCE" = true ]; then
        echo "  [info] Overwriting existing statusLine config in ${found_in} (--force)"
      else
        echo "  [warn] Existing statusLine config found in ${found_in}"
        if [ ! -t 0 ]; then
          # Non-interactive: skip silently, do not overwrite
          return
        fi
        printf "  Existing statusLine detected. Overwrite with CMM statusline? [y/N] "
        read -r overwrite_reply
        case "$overwrite_reply" in
          y|Y) ;;
          *) echo "  [skip] Statusline installation skipped"; return ;;
        esac
      fi
    else
      if [ "$FORCE" != true ]; then
        if [ ! -t 0 ]; then
          # Non-interactive: skip silently, no default install
          return
        fi
        printf "  Install CMM call stats statusline? [y/N] "
        read -r install_reply
        case "$install_reply" in
          y|Y) ;;
          *) echo "  [skip] Statusline installation skipped"; return ;;
        esac
      fi
    fi

    # Create hooks dir if needed
    mkdir -p "${target_config_dir}/hooks"

    local script_path="${target_config_dir}/hooks/statusline-cmm.sh"

    if [ "$mode" = "global" ]; then
      # GLOBAL MODE — Generate standalone statusline-cmm.sh
      cat > "$script_path" <<'STATUSLINE_SCRIPT'
#!/bin/bash
# statusline-cmm.sh — Display CMM call stats in Claude Code statusline
CACHE="$HOME/.cache/codebase-memory-mcp/_call-counts.json"
if [ ! -f "$CACHE" ]; then echo "CMM:0"; exit 0; fi
TOTAL=$(jq -r '.total_calls // 0' "$CACHE" 2>/dev/null || echo 0)
SEARCH=$(jq -r '.by_tool["mcp__codebase-memory-mcp__search_graph"] // 0' "$CACHE" 2>/dev/null || echo 0)
SNIPPET=$(jq -r '.by_tool["mcp__codebase-memory-mcp__get_code_snippet"] // 0' "$CACHE" 2>/dev/null || echo 0)
TRACE=$(jq -r '.by_tool["mcp__codebase-memory-mcp__trace_call_path"] // 0' "$CACHE" 2>/dev/null || echo 0)
echo "CMM:${TOTAL} (sg:${SEARCH} cs:${SNIPPET} tr:${TRACE})"
STATUSLINE_SCRIPT
    else
      # PROJECT MODE — Generate wrapper statusline-cmm.sh
      # Wrapper: runs user's global statusline, appends CMM stats
      cat > "$script_path" <<'WRAPPER_SCRIPT'
#!/bin/bash
# statusline-cmm.sh — Wrapper: runs user's global statusline, appends CMM stats
#
# Reads the user's global statusLine.command from global settings.json,
# runs it, and appends CMM call stats with a pipe separator.
# Falls back to CMM-only output when no global statusline is configured.

# --- Discover user's existing global statusline command ---
# Check settings.local.json first (higher precedence), then settings.json
GLOBAL_CMD=""
for config_dir in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do
  [ -z "$config_dir" ] && continue
  for settings_file in "${config_dir}/settings.local.json" "${config_dir}/settings.json"; do
    [ -f "$settings_file" ] || continue
    GLOBAL_CMD=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        cmd = json.load(f).get('statusLine', {}).get('command', '')
        print(cmd)
except Exception:
    pass
" "$settings_file" 2>/dev/null)
    [ -n "$GLOBAL_CMD" ] && break 2
  done
done

# --- CMM stats ---
CMM_OUTPUT=""
CACHE="$HOME/.cache/codebase-memory-mcp/_call-counts.json"
if [ -f "$CACHE" ]; then
  TOTAL=$(jq -r '.total_calls // 0' "$CACHE" 2>/dev/null || echo 0)
  SEARCH=$(jq -r '.by_tool["mcp__codebase-memory-mcp__search_graph"] // 0' "$CACHE" 2>/dev/null || echo 0)
  SNIPPET=$(jq -r '.by_tool["mcp__codebase-memory-mcp__get_code_snippet"] // 0' "$CACHE" 2>/dev/null || echo 0)
  TRACE=$(jq -r '.by_tool["mcp__codebase-memory-mcp__trace_call_path"] // 0' "$CACHE" 2>/dev/null || echo 0)
  CMM_OUTPUT="CMM:${TOTAL} (sg:${SEARCH} cs:${SNIPPET} tr:${TRACE})"
else
  CMM_OUTPUT="CMM:0"
fi

# --- Combine: run global statusline, append CMM stats ---
# Skip if the global command is itself a CMM statusline (avoids double output with --all)
case "$GLOBAL_CMD" in
  *statusline-cmm.sh*) GLOBAL_CMD="" ;;
esac
if [ -n "$GLOBAL_CMD" ]; then
  EXISTING=$(bash -c "$GLOBAL_CMD" 2>/dev/null)
  if [ -n "$EXISTING" ]; then
    echo "${EXISTING} | ${CMM_OUTPUT}"
  else
    echo "$CMM_OUTPUT"
  fi
else
  echo "$CMM_OUTPUT"
fi
WRAPPER_SCRIPT
    fi

    chmod +x "$script_path"
    echo "  [ok] Generated ${script_path}"

    # Warn if jq is not found on PATH
    if ! command -v jq &>/dev/null; then
      echo "  [warn] jq not found — statusline-cmm.sh requires jq to display call counts"
      echo "         Install with: brew install jq  (macOS) or apt install jq  (Linux)"
    fi

    # Merge statusLine into target settings.json
    if python3 - "$target_settings" "$script_path" <<'PYEOF'
import json, os, sys

settings_path = sys.argv[1]
script_path = sys.argv[2]

try:
    with open(settings_path) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

settings['statusLine'] = {
    'type': 'command',
    'command': 'bash "' + script_path + '"'
}

tmp_path = settings_path + '.tmp'
os.makedirs(os.path.dirname(settings_path) if os.path.dirname(settings_path) else '.', exist_ok=True)
with open(tmp_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
os.replace(tmp_path, settings_path)
print('  [ok] statusLine merged into ' + os.path.basename(settings_path))
PYEOF
    then
      # Validate the written JSON
      python3 -m json.tool "$target_settings" > /dev/null 2>&1 || \
        echo "  [warn] JSON validation failed for ${target_settings}"
    else
      echo "  [warn] Failed to merge statusLine into ${target_settings}"
    fi
  }

  if [ "$INSTALL_GLOBAL" = true ]; then
    local global_config_dir
    global_config_dir=$(detect_config_dir)
    echo "[STATUSLINE — global]"
    _run_install_statusline_for_target "$global_config_dir" "global"
    echo ""
  fi

  if [ "$INSTALL_PROJECT" = true ]; then
    echo "[STATUSLINE — project]"
    _run_install_statusline_for_target ".claude" "project"
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# print_next_steps
# ---------------------------------------------------------------------------

print_next_steps() {
  echo "============================================================"
  echo "Installation complete!"
  echo ""
  echo "Next steps:"
  echo "  1. Restart Claude Code to activate hooks"
  echo "  2. If project hooks installed: run 'index_repository' on first session"
  echo "  3. If global hooks installed: hooks fire automatically on Read/Write/Edit"
  echo "  4. Review .claude/settings.json to confirm hook entries"
  echo "  5. If statusline installed: restart Claude Code to see CMM stats in the status bar"
  echo "============================================================"
}

# ---------------------------------------------------------------------------
# parse_args
# ---------------------------------------------------------------------------

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --global)          INSTALL_GLOBAL=true ;;
      --project)         INSTALL_PROJECT=true ;;
      --all)             INSTALL_GLOBAL=true; INSTALL_PROJECT=true ;;
      --force)           FORCE=true ;;
      --dry-run)         DRY_RUN=true ;;
      --skip-mcp-check)  SKIP_MCP_CHECK=true ;;
      --skip-statusline) SKIP_STATUSLINE=true ;;
      --help|-h)
        cat <<'HELP'
setup.sh — Installer for codebase-memory-mcp + Context Mode Claude Code hooks

Installs hooks, rules, and settings for two complementary MCP servers:
  - codebase-memory-mcp (CMM): code knowledge graph, ~99% token reduction on code exploration
  - Context Mode MCP (optional): execution sandboxing + SQLite session persistence, ~98% context reduction

Usage:
  ./setup.sh [--global] [--project] [--all] [--force] [--dry-run] [--skip-mcp-check] [--skip-statusline]

Flags:
  --global          Install global hooks to ~/.claude/hooks/ and merge into ~/.claude/settings.json
  --project         Install project hooks to .claude/hooks/, rules to .claude/rules/,
                    create .mcp.json, and merge into .claude/settings.json
  --all             Install both global and project hooks
  --force           Overwrite existing files (default: skip existing)
  --dry-run         Show what would be done without making changes
  --skip-mcp-check  Bypass all MCP availability checks (useful for CI/automation)
  --skip-statusline Skip the CMM statusline installation offer
  --help, -h        Show this help message

MCP pre-flight checks (run automatically unless --skip-mcp-check):
  - CMM binary       detected via PATH and common install locations
  - CMM registration checked in .mcp.json and global MCP config
  - Tool allowlist   verified in .claude/settings.local.json (14 CMM tools)
  - Context Mode     optional; prompts to install if not detected

Context Mode hooks (context-mode-*.sh) are always installed but gracefully
no-op when Context Mode is not present — you can enable it later without
re-running setup.

Examples:
  bash setup.sh --project             # Install project hooks into current directory
  bash setup.sh --global              # Install global hooks for all projects
  bash setup.sh --all --force         # Install everything, overwriting existing files
  bash setup.sh --dry-run --project   # Preview project install without making changes
  bash setup.sh --project --skip-mcp-check  # Install without MCP availability checks
HELP
        exit 0
        ;;
      *)
        echo "Unknown flag: $1" >&2
        exit 1
        ;;
    esac
    shift
  done

  if [ "$INSTALL_GLOBAL" = false ] && [ "$INSTALL_PROJECT" = false ]; then
    interactive_prompt
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

main() {
  parse_args "$@"
  check_prerequisites
  check_mcp_availability

  if [ "$INSTALL_GLOBAL" = true ]; then
    install_global
  fi

  if [ "$INSTALL_PROJECT" = true ]; then
    install_project
  fi

  if [ "$SKIP_STATUSLINE" = false ]; then
    install_statusline
  fi

  if [ "$DRY_RUN" = false ]; then
    print_next_steps
  fi
}

main "$@"
