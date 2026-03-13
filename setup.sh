#!/usr/bin/env bash
set -euo pipefail

# setup.sh — Automated installer for codebase-memory-mcp Claude Code hooks
#
# Usage:
#   ./setup.sh [--global] [--project] [--all] [--force] [--dry-run]
#
# Flags:
#   --global     Install global hooks to ~/.claude/hooks/ and merge into ~/.claude/settings.json
#   --project    Install project hooks to .claude/hooks/, rules to .claude/rules/,
#                create .mcp.json, and merge into .claude/settings.json
#   --all        Install both global and project hooks
#   --force      Overwrite existing files (default: skip existing)
#   --dry-run    Show what would be done without making changes
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
# check_prerequisites
# ---------------------------------------------------------------------------

check_prerequisites() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] python3 is required but not found on PATH." >&2
    exit 1
  fi

  if ! command -v codebase-memory-mcp >/dev/null 2>&1; then
    echo "Warning: codebase-memory-mcp not found on PATH. Install it before using hooks." >&2
  fi

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
  echo "============================================================"
}

# ---------------------------------------------------------------------------
# parse_args
# ---------------------------------------------------------------------------

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --global)   INSTALL_GLOBAL=true ;;
      --project)  INSTALL_PROJECT=true ;;
      --all)      INSTALL_GLOBAL=true; INSTALL_PROJECT=true ;;
      --force)    FORCE=true ;;
      --dry-run)  DRY_RUN=true ;;
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

  if [ "$INSTALL_GLOBAL" = true ]; then
    install_global
  fi

  if [ "$INSTALL_PROJECT" = true ]; then
    install_project
  fi

  if [ "$DRY_RUN" = false ]; then
    print_next_steps
  fi
}

main "$@"
