#!/usr/bin/env bash
set -euo pipefail

# setup.sh — Automated installer for codebase-memory-mcp Claude Code hooks
#
# Usage:
#   ./setup.sh [--global] [--project] [--all] [--force] [--dry-run] [--skip-mcp-check] [--skip-statusline] [--verify]
#
# Flags:
#   --global          Install global hooks and rules to ~/.claude/ and merge into ~/.claude/settings.json
#   --project         Install project hooks to .claude/hooks/, rules to .claude/rules/,
#                     create .mcp.json, and merge into .claude/settings.json
#   --all             Install both global and project hooks
#   --force           Overwrite existing files without prompting (default: detect drift and prompt)
#   --dry-run         Show what would be done without making changes
#   --skip-mcp-check  Bypass all MCP availability checks (CMM binary, registration,
#                     tool allowlist, context-mode). Useful for CI/automation.
#   --skip-statusline Skip the CMM statusline installation offer
#   --verify          After installing hooks, verify file integrity against CHECKSUMS.sha256
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
VERIFY=false
YES_FLAG=false
RECONFIGURE_STATUSLINE=false

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
    # Drift detection: compare content first
    if cmp -s "$src" "$dest"; then
      echo "  [ok] $(basename "$dest") unchanged"
      return
    fi
    # Files differ — show mtime direction context
    echo "  [warn] $(basename "$dest") differs from source"
    if [ "$src" -nt "$dest" ]; then
      echo "         (source is newer — upstream update available)"
    elif [ "$dest" -nt "$src" ]; then
      echo "         (installed is newer — local modifications present)"
    else
      echo "         (same timestamp — content differs)"
    fi
    # Interactive per-file prompt gated on tty
    if [ -t 0 ]; then
      printf "  Overwrite %s? [y/N]: " "$(basename "$dest")"
      local _drift_choice
      read -r _drift_choice || true
      case "${_drift_choice:-}" in
        y|Y) ;;
        *) echo "  [skip] Kept existing $(basename "$dest")"; return ;;
      esac
    else
      echo "  [skip] Non-interactive — kept existing $(basename "$dest")"
      return
    fi
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

# scan_drift_summary — Read-only pre-scan of copy_file-managed files.
# Prints a single summary line: "  Scanning N file(s): X unchanged, Y changed, Z new"
# Args: dest_dir src_file [src_file ...]
# Only runs when FORCE!=true and DRY_RUN!=true.
scan_drift_summary() {
  local dest_dir="$1"
  shift
  if [ "$FORCE" = true ] || [ "$DRY_RUN" = true ]; then
    return
  fi
  if [ "$#" -eq 0 ]; then
    return
  fi
  local unchanged=0 changed=0 new_files=0 src
  for src in "$@"; do
    local dest="${dest_dir}/$(basename "$src")"
    if [ ! -e "$dest" ]; then
      new_files=$((new_files + 1))
    elif cmp -s "$src" "$dest"; then
      unchanged=$((unchanged + 1))
    else
      changed=$((changed + 1))
    fi
  done
  local total=$((unchanged + changed + new_files))
  echo "  Scanning ${total} file(s): ${unchanged} unchanged, ${changed} changed, ${new_files} new"
}

# ---------------------------------------------------------------------------
# verify_repo_remote
# ---------------------------------------------------------------------------

# Checks that setup.sh is being run from a repo with an expected git remote.
# Non-blocking: warns and prompts for confirmation if remote looks unexpected.
# Skips silently if no .git directory is present (e.g. zip extract, CI).
verify_repo_remote() {
  if [ ! -d "$SCRIPT_DIR/.git" ]; then
    return 0
  fi
  local remote_url
  remote_url=$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || echo "")
  if [ -z "$remote_url" ]; then
    return 0
  fi
  local expected_pattern="github\.com[/:].*cmm.*setup|github\.com[/:].*codebase-memory"
  if ! echo "$remote_url" | grep -qE "$expected_pattern"; then
    echo "" >&2
    echo "  [WARN] Unexpected git remote: $remote_url" >&2
    echo "  [WARN] Expected a github.com/*/cmm-claude-code-setup remote." >&2
    echo "  [WARN] This may indicate you cloned from an unofficial source." >&2
    printf "  Continue anyway? [y/N]: " >&2
    read -r choice
    if [ "$choice" != "y" ] && [ "$choice" != "Y" ]; then
      echo "Aborting. Clone from the official repo and re-run setup.sh." >&2
      exit 1
    fi
  fi
}

# ---------------------------------------------------------------------------
# verify_installation
# ---------------------------------------------------------------------------

# Validates installed file integrity against CHECKSUMS.sha256 when --verify is set.
# Non-blocking if CHECKSUMS.sha256 is absent: prints a warning and returns.
# Exits non-zero if checksums are present but files fail verification.
verify_installation() {
  if [ "$VERIFY" != true ]; then
    return 0
  fi

  local checksum_file="$SCRIPT_DIR/CHECKSUMS.sha256"
  if [ ! -f "$checksum_file" ]; then
    echo "  [warn] CHECKSUMS.sha256 not found — skipping verification" >&2
    return 0
  fi

  echo ""
  echo "Verifying file integrity..."
  local failures=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local expected file full actual
    expected=$(echo "$line" | cut -c1-64)
    file=$(echo "$line" | cut -c67-)
    full="$SCRIPT_DIR/$file"
    if [ ! -f "$full" ]; then
      echo "  [?] $file (not installed — skipped)" >&2
      continue
    fi
    actual=$(shasum -a 256 "$full" 2>/dev/null | cut -c1-64 || sha256sum "$full" 2>/dev/null | cut -c1-64)
    if [ "$actual" != "$expected" ]; then
      echo "  [✗] $file (checksum mismatch)" >&2
      failures=$((failures + 1))
    else
      echo "  [✓] $file"
    fi
  done < "$checksum_file"

  if [ "$failures" -gt 0 ]; then
    echo "" >&2
    echo "  [ERROR] $failures file(s) failed integrity check." >&2
    echo "  [ERROR] Your installation may be corrupted or tampered with." >&2
    exit 1
  fi
  echo "  All files verified."
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

  # Not registered yet
  if [ "$INSTALL_PROJECT" = true ] || [ "$INSTALL_GLOBAL" = true ]; then
    # setup.sh will register CMM in .mcp.json during install — no need to abort
    CMM_REGISTRATION_STATUS="ok"
    echo "  [info] CMM not yet registered — setup will add it to .mcp.json"
    return 0
  fi

  # Neither --project nor --global: warn and offer to abort
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

  local settings_file=".claude/settings.json"

  if [ ! -f "$settings_file" ]; then
    CMM_TOOLS_STATUS="missing"
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
    return 0
  fi

  CMM_TOOLS_STATUS="warn"
  return 0
}

# ---------------------------------------------------------------------------
# detect_context_mode
# ---------------------------------------------------------------------------

# Status variable populated by detect_context_mode(); read by print_preflight_summary()
CONTEXT_MODE_STATUS="skip"
# Whether to register context-mode in .mcp.json (set by detect_context_mode)
# Default: register context-mode (flip to false only when --skip-context-mode is passed).
INSTALL_CONTEXT_MODE=true
# Set by --skip-context-mode. When true, detect_context_mode forces INSTALL_CONTEXT_MODE=false
# so context-mode registration is skipped entirely (fresh installs only — existing entries
# in .mcp.json are preserved by the idempotency guard in install_project).
SKIP_CONTEXT_MODE=false

detect_context_mode() {
  # --skip-context-mode wins unconditionally — opt out of context-mode registration.
  if [ "$SKIP_CONTEXT_MODE" = true ]; then
    CONTEXT_MODE_STATUS="skip"
    INSTALL_CONTEXT_MODE=false
    # Surface existing registration so the user knows the webfetch-nudge hook
    # will continue to block WebFetch based on project-level context-mode state.
    if [ "$INSTALL_PROJECT" = true ] && [ -f ".mcp.json" ] && \
       grep -q "context-mode" ".mcp.json" 2>/dev/null; then
      echo "  [info] --skip-context-mode set; existing context-mode entry in .mcp.json preserved"
      echo "  [info] webfetch-nudge will continue to block WebFetch while context-mode remains registered"
    fi
    # Invalidate the webfetch-nudge availability cache so stale /tmp state does
    # not keep the hook blocking after context-mode is removed from .mcp.json.
    if [ "$DRY_RUN" != true ]; then
      rm -f /tmp/ctx-webfetch-avail-* 2>/dev/null || true
    fi
    return 0
  fi

  # Only runs for project installs (context-mode is registered in project .mcp.json)
  if [ "$INSTALL_PROJECT" != true ]; then
    CONTEXT_MODE_STATUS="skip"
    INSTALL_CONTEXT_MODE=false
    return 0
  fi

  # Default-on: register context-mode. INSTALL_CONTEXT_MODE is already true from
  # initialization (and will only be flipped false by --skip-context-mode above).
  # Idempotency: the install_project MCP merge block guards with
  # `if "context-mode" not in data["mcpServers"]` — re-running setup preserves
  # existing context-mode entries and user customizations.
  INSTALL_CONTEXT_MODE=true

  # If .mcp.json already has context-mode, surface that in the pre-flight summary.
  if [ -f ".mcp.json" ] && grep -q "context-mode" ".mcp.json" 2>/dev/null; then
    CONTEXT_MODE_STATUS="ok"
    echo "  [ok] context-mode detected (already registered in .mcp.json)"
  else
    CONTEXT_MODE_STATUS="ok"
    echo "  [info] context-mode will be registered in .mcp.json (use --skip-context-mode to opt out)"
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
    ok)      tools_line="[ok]   All 14 CMM tools allowlisted in .claude/settings.json" ;;
    warn)    tools_line="[warn] ${CMM_TOOLS_COUNT}/14 CMM tools in .claude/settings.json" ;;
    missing) tools_line="[warn] .claude/settings.json not found — CMM tools not allowlisted" ;;
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

  if { [ "$INSTALL_PROJECT" = true ] || [ "$INSTALL_GLOBAL" = true ]; } && [ ! -d "$SCRIPT_DIR/rules" ]; then
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
      },
      {
        "matcher": "Grep",
        "hooks": [{"type": "command", "command": "bash \"${CLAUDE_CONFIG_DIR}/hooks/cmm-grep-nudge.sh\""}]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{"type": "command", "command": "bash \"${CLAUDE_CONFIG_DIR}/hooks/reindex-after-edit.sh\""}]
      },
      {
        "matcher": "mcp__codebase-memory-mcp__*",
        "hooks": [{"type": "command", "command": "bash \"${CLAUDE_CONFIG_DIR}/hooks/track-cmm-calls.sh\""}]
      },
      {
        "matcher": "mcp__context-mode__*",
        "hooks": [{"type": "command", "command": "bash \"${CLAUDE_CONFIG_DIR}/hooks/track-ctx-calls.sh\""}]
      }
    ]
  }
}
HOOKJSON
)
  else
    # Rewrite hook commands to use absolute paths so hooks are found regardless of
    # the session CWD (e.g. when Claude Code is opened from inside a git submodule).
    local abs_hook_dir
    abs_hook_dir="$(pwd -P)/.claude/hooks"
    NEW_HOOKS_JSON=$(python3 -c "
import sys
content = open(sys.argv[1]).read()
sys.stdout.write(content.replace('bash .claude/hooks/', 'bash ' + sys.argv[2] + '/'))
" "$SCRIPT_DIR/rules/project-settings-example.json" "$abs_hook_dir")
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
    # Also track basenames for path-normalized dedup (prevents relative + absolute duplicates)
    existing_basenames = {h.get("command","").split("/")[-1] for group in existing["hooks"][hook_type] for h in group.get("hooks", [])}
    for entry in entries:
        new_cmds = {json.dumps(h, sort_keys=True) for h in entry.get("hooks", [])}
        new_basenames = {h.get("command","").split("/")[-1] for h in entry.get("hooks", [])}
        if new_basenames.issubset(existing_basenames):
            # Script already registered (possibly under different path form) — update command + matcher
            new_matcher = entry.get("matcher", "")
            for existing_entry in existing["hooks"][hook_type]:
                entry_basenames = {h.get("command","").split("/")[-1] for h in existing_entry.get("hooks", [])}
                if new_basenames == entry_basenames:
                    # Update command to new form (e.g. relative -> absolute)
                    for new_h in entry.get("hooks", []):
                        for ex_h in existing_entry.get("hooks", []):
                            if new_h.get("command","").split("/")[-1] == ex_h.get("command","").split("/")[-1]:
                                ex_h["command"] = new_h["command"]
                    if new_matcher and existing_entry.get("matcher", "") != new_matcher:
                        existing_entry["matcher"] = new_matcher
        elif not new_cmds.issubset(existing_cmds):
            existing["hooks"][hook_type].append(entry)
            existing_cmds |= new_cmds
            existing_basenames |= new_basenames
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
# merge_context_mode_hooks
# ---------------------------------------------------------------------------
# Registers context-mode's five upstream hooks (PostToolUse, PreToolUse,
# PreCompact, SessionStart, UserPromptSubmit) in the target settings.json
# using the CLI dispatcher form `context-mode hook claude-code <event>`.
#
# Dedup strategy differs from merge_settings_json: this function uses a
# SUBSTRING match on the command string (`context-mode hook claude-code
# <event>`) rather than basename-split. Basename dedup would false-match any
# unrelated hook whose command ends with `/posttooluse`, `/precompact`, etc.
#
# Idempotent: re-running heals matcher drift but does not duplicate entries.
# Fail-open: if python3 exits non-zero (corrupt JSON, missing python3), we
# print a warning and return 0 so setup.sh continues.
#
# Only called from install_project() guarded by INSTALL_CONTEXT_MODE=true.
merge_context_mode_hooks() {
  local target_file="$1"

  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY RUN] Would merge context-mode upstream hooks into $target_file"
    return 0
  fi

  mkdir -p "$(dirname "$target_file")"

  if ! python3 - "$target_file" <<'PY'
import json, os, sys

target = sys.argv[1]

# Hardcoded upstream hook registration block. Commands use the CLI dispatcher
# form `context-mode hook claude-code <event>` — correct for MCP-server installs
# (npx -y context-mode@latest) where CLAUDE_PLUGIN_ROOT is unset.
#
# The PreToolUse matcher for context-mode's own MCP tools uses the MCP-server
# form `mcp__context-mode__*` NOT the plugin form `mcp__plugin_context-mode_*`
# because setup.sh installs context-mode as an MCP server (via npx), not as a
# Claude Code plugin.
expected = {
    "PostToolUse": {
        "matcher": "Bash|Read|Write|Edit|NotebookEdit|Glob|Grep|TodoWrite|TaskCreate|TaskUpdate|EnterPlanMode|ExitPlanMode|Skill|Agent|AskUserQuestion|EnterWorktree|mcp__",
        "command": "context-mode hook claude-code posttooluse",
    },
    "PreToolUse": {
        "matcher": "Bash|WebFetch|Read|Grep|Agent|mcp__context-mode__ctx_execute|mcp__context-mode__ctx_execute_file|mcp__context-mode__ctx_batch_execute",
        "command": "context-mode hook claude-code pretooluse",
    },
    "PreCompact": {
        "matcher": "",
        "command": "context-mode hook claude-code precompact",
    },
    "SessionStart": {
        "matcher": "",
        "command": "context-mode hook claude-code sessionstart",
    },
    "UserPromptSubmit": {
        "matcher": "",
        "command": "context-mode hook claude-code userpromptsubmit",
    },
}

# Read existing settings.json — fail-open to {} on any read or parse error so
# we always produce a valid file.
try:
    with open(target) as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except (FileNotFoundError, json.JSONDecodeError, OSError):
    data = {}

if "hooks" not in data or not isinstance(data.get("hooks"), dict):
    data["hooks"] = {}

for event, spec in expected.items():
    want_matcher = spec["matcher"]
    want_cmd = spec["command"]
    sentinel = want_cmd  # substring we search for in existing commands

    if event not in data["hooks"] or not isinstance(data["hooks"].get(event), list):
        data["hooks"][event] = []

    # Substring search across all command entries in the event's list.
    found = False
    for group in data["hooks"][event]:
        if not isinstance(group, dict):
            continue
        for h in group.get("hooks", []) or []:
            if not isinstance(h, dict):
                continue
            cmd = h.get("command", "")
            if isinstance(cmd, str) and sentinel in cmd:
                # Heal matcher drift — update matcher to expected; leave cmd
                # untouched so a user who edited the command (e.g. to add
                # --verbose) keeps their edit.
                if group.get("matcher", "") != want_matcher:
                    group["matcher"] = want_matcher
                found = True
                break
        if found:
            break

    if found:
        print(f"  [ok] context-mode {event} hook already present")
    else:
        # Append at END of the event array so existing project hooks (ours)
        # stay at lower indices and fire first.
        data["hooks"][event].append({
            "matcher": want_matcher,
            "hooks": [{"type": "command", "command": want_cmd}],
        })
        print(f"  [ok] Registered context-mode {event} hook")

tmp = target + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, target)
PY
  then
    echo "  [warn] merge_context_mode_hooks: python3 failed; upstream context-mode hooks not registered"
    return 0
  fi

  if python3 -m json.tool "$target_file" >/dev/null 2>&1; then
    :
  else
    echo "  [warn] JSON validation failed for $target_file after context-mode hook merge" >&2
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
    echo "  [DRY RUN] Would create ${config_dir}/hooks/lib/"
    echo "  [DRY RUN] Would create ${config_dir}/rules/"
  else
    mkdir -p "${config_dir}/hooks"
    mkdir -p "${config_dir}/hooks/lib"
    mkdir -p "${config_dir}/rules"
  fi

  # Pre-scan: report drift summary before per-file prompts
  # shellcheck disable=SC2046
  scan_drift_summary "${config_dir}/hooks/lib" $( ls "$SCRIPT_DIR/hooks/lib/"*.sh 2>/dev/null )
  # shellcheck disable=SC2046
  scan_drift_summary "${config_dir}/hooks" $( ls "$SCRIPT_DIR/hooks/global/"*.sh 2>/dev/null )
  # shellcheck disable=SC2046
  scan_drift_summary "${config_dir}/rules" $( ls "$SCRIPT_DIR/rules/"*.md 2>/dev/null )

  # Install shared libraries first (sourced by hooks at runtime)
  shopt -s nullglob
  for file in "$SCRIPT_DIR/hooks/lib/"*.sh; do
    copy_file "$file" "${config_dir}/hooks/lib/$(basename "$file")"
  done

  for file in "$SCRIPT_DIR/hooks/global/"*.sh; do
    copy_file "$file" "${config_dir}/hooks/$(basename "$file")"
    set_executable "${config_dir}/hooks/$(basename "$file")"
  done
  shopt -u nullglob

  # Copy track-hook-blocks.sh alongside global hooks — cmm-nudge.sh calls it
  # via BASH_SOURCE dirname resolution when running from the global hooks dir
  if [ -f "$SCRIPT_DIR/hooks/project/track-hook-blocks.sh" ]; then
    copy_file "$SCRIPT_DIR/hooks/project/track-hook-blocks.sh" "${config_dir}/hooks/track-hook-blocks.sh"
    set_executable "${config_dir}/hooks/track-hook-blocks.sh"
  fi

  # Install rules (global rules apply to all projects)
  shopt -s nullglob
  for file in "$SCRIPT_DIR/rules/"*.md; do
    copy_file "$file" "${config_dir}/rules/$(basename "$file")"
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
    echo "  [DRY RUN] Would create .claude/hooks/lib/"
    echo "  [DRY RUN] Would create .claude/rules/"
  else
    mkdir -p .claude/hooks
    mkdir -p .claude/hooks/lib
    mkdir -p .claude/rules
  fi

  # Pre-scan: report drift summary before per-file prompts
  # shellcheck disable=SC2046
  scan_drift_summary ".claude/hooks/lib" $( ls "$SCRIPT_DIR/hooks/lib/"*.sh 2>/dev/null )
  # shellcheck disable=SC2046
  scan_drift_summary ".claude/hooks" $( ls "$SCRIPT_DIR/hooks/project/"*.sh 2>/dev/null )
  # shellcheck disable=SC2046
  scan_drift_summary ".claude/rules" $( ls "$SCRIPT_DIR/rules/"* 2>/dev/null )

  # Install shared libraries first (sourced by hooks at runtime)
  shopt -s nullglob
  for file in "$SCRIPT_DIR/hooks/lib/"*.sh; do
    copy_file "$file" ".claude/hooks/lib/$(basename "$file")"
  done
  shopt -u nullglob

  # Invalidate project-root cache for this directory so hooks re-detect after reinstall
  _PR_CACHE_KEY=$(echo -n "$(pwd)" | md5 -q 2>/dev/null || echo -n "$(pwd)" | md5sum 2>/dev/null | cut -d' ' -f1)
  if [ -n "$_PR_CACHE_KEY" ] && [ -f "/tmp/cmm-project-root-${_PR_CACHE_KEY}" ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "  [DRY RUN] Would invalidate project-root cache"
    else
      rm -f "/tmp/cmm-project-root-${_PR_CACHE_KEY}"
      echo "  [ok] Invalidated project-root cache for $(pwd)"
    fi
  fi

  shopt -s nullglob
  # Copies all hooks/project/*.sh to .claude/hooks/, including:
  #   reindex-after-commit.sh — PostToolUse:Bash hook that marks CMM sentinel stale after git commits
  #   subagent-cmm-startup.sh — SubagentStart advisory hook (injects CMM state into all subagents via additionalContext)
  #   grep-cmm-gate.sh — PreToolUse:Grep hard-block for source-code search in indexed repos (phase 46)
  #   ctx-execute-cmm-nudge.sh — PreToolUse:mcp__context-mode__ctx_execute hard-block for grep-laundered code search (phase 46)
  # Registration of these hooks is handled via rules/project-settings-example.json merged into .claude/settings.json.
  #
  # NOTE: VBW agent override files (agents/*.md) ARE copied by setup.sh --project to
  # .claude/agents/. These shadow VBW plugin agents to inject CMM enforcement hooks
  # via frontmatter (the only mechanism that fires inside subagents).
  # The existing .claude/agents/dev.md is project-specific and NOT managed by setup.sh.
  # Users installing this hook layer into their own project should create their own
  # .claude/agents/ overrides if they want agent-level hook behavior.
  for file in "$SCRIPT_DIR/hooks/project/"*.sh; do
    copy_file "$file" ".claude/hooks/$(basename "$file")"
    set_executable ".claude/hooks/$(basename "$file")"
  done
  shopt -u nullglob

  # Copy cmm-nudge.sh from hooks/global/ to .claude/hooks/ — needed by agent frontmatter
  # hooks (in .claude/agents/) that reference cmm-nudge.sh via project-relative paths
  # (e.g., "bash .claude/hooks/cmm-nudge.sh"). Without this, project installs that skip
  # --global would lack the file at the expected location.
  if [ -f "$SCRIPT_DIR/hooks/global/cmm-nudge.sh" ]; then
    copy_file "$SCRIPT_DIR/hooks/global/cmm-nudge.sh" ".claude/hooks/cmm-nudge.sh"
    set_executable ".claude/hooks/cmm-nudge.sh"
  fi

  # Copy cmm-grep-nudge.sh from hooks/global/ to .claude/hooks/
  if [ -f "$SCRIPT_DIR/hooks/global/cmm-grep-nudge.sh" ]; then
    copy_file "$SCRIPT_DIR/hooks/global/cmm-grep-nudge.sh" ".claude/hooks/cmm-grep-nudge.sh"
    set_executable ".claude/hooks/cmm-grep-nudge.sh"
  fi

  # Copy webfetch-nudge.sh from hooks/global/ to .claude/hooks/
  # Registered by vbw-scout/vbw-lead/vbw-dev agent frontmatter as PreToolUse:WebFetch hook.
  if [ -f "$SCRIPT_DIR/hooks/global/webfetch-nudge.sh" ]; then
    copy_file "$SCRIPT_DIR/hooks/global/webfetch-nudge.sh" ".claude/hooks/webfetch-nudge.sh"
    set_executable ".claude/hooks/webfetch-nudge.sh"
  fi

  # Copy ctx-annotate-nudge.sh from hooks/global/ to .claude/hooks/
  # PostToolUse additionalContext nudge for context-mode tools (replaces the
  # retired ctx-search-nudge.sh — see phase 47). Emits a summarize-before-next-call
  # instruction via hookSpecificOutput.additionalContext with a 120s cooldown.
  # No-ops when context-mode is not installed thanks to the hook's built-in probe.
  if [ -f "$SCRIPT_DIR/hooks/global/ctx-annotate-nudge.sh" ]; then
    copy_file "$SCRIPT_DIR/hooks/global/ctx-annotate-nudge.sh" ".claude/hooks/ctx-annotate-nudge.sh"
    set_executable ".claude/hooks/ctx-annotate-nudge.sh"
  fi

  # Copy cmm-orient-nudge.sh from hooks/global/ to .claude/hooks/
  # One-shot-per-session PostToolUse nudge after the first search_graph call —
  # suggests get_architecture / trace_call_path / query_graph for unfamiliar areas.
  # No-ops when CMM is not installed thanks to the hook's built-in probe.
  if [ -f "$SCRIPT_DIR/hooks/global/cmm-orient-nudge.sh" ]; then
    copy_file "$SCRIPT_DIR/hooks/global/cmm-orient-nudge.sh" ".claude/hooks/cmm-orient-nudge.sh"
    set_executable ".claude/hooks/cmm-orient-nudge.sh"
  fi

  # Copy subagent-ctx-startup.sh from hooks/global/ to .claude/hooks/
  # SubagentStart injector — emits a one-line instruction nudging spawned subagents
  # to call ctx_stats before indexing more content. No-ops when context-mode is not
  # installed thanks to the hook's built-in absence probe.
  if [ -f "$SCRIPT_DIR/hooks/global/subagent-ctx-startup.sh" ]; then
    copy_file "$SCRIPT_DIR/hooks/global/subagent-ctx-startup.sh" ".claude/hooks/subagent-ctx-startup.sh"
    set_executable ".claude/hooks/subagent-ctx-startup.sh"
  fi


  # --- Agent override files (frontmatter hooks for VBW subagents) ---
  # Project-level .claude/agents/ overrides shadow VBW plugin agent definitions
  # to inject CMM enforcement hooks (cmm-nudge.sh, ctx-execute-enforcer.sh,
  # track-cmm-calls.sh) into subagent execution contexts. Plugin agents ignore
  # hooks: fields, so this override is the only enforcement path.
  if [ -d "$SCRIPT_DIR/agents" ]; then
    mkdir -p ".claude/agents"
    for agent_file in "$SCRIPT_DIR"/agents/*.md; do
      [ -f "$agent_file" ] || continue
      copy_file "$agent_file" ".claude/agents/$(basename "$agent_file")"
    done
  fi

  # Purge deprecated hook files and their settings.json entries (unconditional).
  # When hooks are renamed or merged, stale files in .claude/hooks/ that remain
  # registered in settings.json can deadlock the session (e.g. old cmm-session-gate.sh
  # blocking Context Mode tools after session-gate.sh merge). This runs on every
  # --project install, not just --force, because leaving superseded hooks causes
  # functional breakage (circular dependency between gate hooks).
  # IMPORTANT: Only delete hooks on this explicit list — never delete unknown hooks,
  # as they may be user-created or generated by other install steps (e.g. statusline-cmm.sh).
  deprecated_hooks=(
    "cmm-session-gate.sh"
    "context-mode-session-gate.sh"
    "ctx-search-nudge.sh"
    "context-mode-event-logger.sh"
    "context-mode-pre-compact.sh"
  )

  stale_hooks=()
  for name in "${deprecated_hooks[@]}"; do
    installed=".claude/hooks/$name"
    if [ -f "$installed" ]; then
      stale_hooks+=("$name")
      if [ "$DRY_RUN" = true ]; then
        echo "  [DRY RUN] Would remove deprecated hook: $name"
      else
        rm "$installed"
        echo "  [removed] Deprecated hook: $name"
      fi
    fi
  done

  if [ "${#stale_hooks[@]}" -gt 0 ] && [ "$DRY_RUN" = false ] && [ -f ".claude/settings.json" ]; then
    python3 -c '
import json, os, sys
target = sys.argv[1]
stale = set(sys.argv[2].split())
try:
    with open(target) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    sys.exit(0)
changed = False
for hook_type in list(data.get("hooks", {})):
    before = len(data["hooks"][hook_type])
    data["hooks"][hook_type] = [
        entry for entry in data["hooks"][hook_type]
        if not any(
            os.path.basename(h.get("command", "").split()[-1]) in stale
            for h in entry.get("hooks", [])
        )
    ]
    if len(data["hooks"][hook_type]) < before:
        changed = True
if changed:
    tmp = target + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, target)
    print("  [ok] Pruned deprecated hook entries from settings.json")
' ".claude/settings.json" "${stale_hooks[*]}"
  fi

  # Copies all runtime rule files from rules/ to .claude/rules/, including
  # cmm-rules.md (CMM tool guidance) and ctx-rules.md (Context Mode retrieval
  # protocol). Reference/example files (project-settings-example.json,
  # allowed-tools.txt, mcp-example.json) are skipped below.
  shopt -s nullglob
  for file in "$SCRIPT_DIR/rules/"*; do
    # Skip reference/example files that are not runtime rule files
    case "$(basename "$file")" in
      project-settings-example.json|allowed-tools.txt|mcp-example.json) continue ;;
    esac
    copy_file "$file" ".claude/rules/$(basename "$file")"
  done
  shopt -u nullglob

  # Clean up legacy rule files from earlier installs
  local _legacy_files="global-claude-md.md allowed-tools.txt mcp-example.json project-settings-example.json"
  local _found_legacy=()
  for _lf in $_legacy_files; do
    [ -f ".claude/rules/$_lf" ] && _found_legacy+=("$_lf")
  done
  if [ ${#_found_legacy[@]} -gt 0 ]; then
    echo ""
    echo "  Found ${#_found_legacy[@]} legacy rule file(s) from earlier installs:"
    for _lf in "${_found_legacy[@]}"; do
      echo "    - .claude/rules/$_lf"
    done
    if [ "$DRY_RUN" = true ]; then
      echo "  [DRY RUN] Would remove ${#_found_legacy[@]} legacy rule file(s)"
    elif [ "$FORCE" = true ]; then
      for _lf in "${_found_legacy[@]}"; do
        rm -f ".claude/rules/$_lf"
      done
      echo "  [ok] Removed legacy rule files (--force)"
    else
      printf "  Remove them? [Y/n] "
      read -r _answer </dev/tty 2>/dev/null || _answer="y"
      case "$_answer" in
        [Nn]*) echo "  [skip] Keeping legacy rule files" ;;
        *)
          for _lf in "${_found_legacy[@]}"; do
            rm -f ".claude/rules/$_lf"
          done
          echo "  [ok] Removed legacy rule files"
          ;;
      esac
    fi
  fi

  # Merge MCP servers into .mcp.json (creates if missing, preserves existing servers)
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY RUN] Would merge CMM into .mcp.json"
    if [ "$INSTALL_CONTEXT_MODE" = true ]; then
      echo "  [DRY RUN] Would merge context-mode into .mcp.json"
    fi
  else
    if python3 - ".mcp.json" "$INSTALL_CONTEXT_MODE" <<'MCPEOF'
import json, os, sys

mcp_path = sys.argv[1]
install_ctx = sys.argv[2] == "true"

try:
    with open(mcp_path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}

if "mcpServers" not in data:
    data["mcpServers"] = {}

# Always ensure CMM is registered
if "codebase-memory-mcp" not in data["mcpServers"]:
    data["mcpServers"]["codebase-memory-mcp"] = {
        "command": "codebase-memory-mcp",
        "args": [],
        "type": "stdio"
    }
    print("  [ok] Registered codebase-memory-mcp in .mcp.json")
else:
    print("  [skip] codebase-memory-mcp already in .mcp.json")

# Register context-mode if requested.
# We pin `context-mode@latest` so `npx` re-resolves against the npm registry on
# every launch. Without `@latest`, npx resolves to whatever global install the
# user has cached and silently stops picking up new releases.
#
# Idempotency + user-customization rule:
# - New entry → write the `@latest` pin.
# - Existing entry whose args match the OLD default exactly (`["-y", "context-mode"]`)
#   → auto-upgrade to `@latest`. This case is known to be an unmodified pre-pin
#   install, so rewriting it is safe.
# - Existing entry with any other command/args → preserve untouched (user-customized).
if install_ctx:
    pinned_args = ["-y", "context-mode@latest"]
    old_default_args = ["-y", "context-mode"]
    if "context-mode" not in data["mcpServers"]:
        data["mcpServers"]["context-mode"] = {
            "command": "npx",
            "args": pinned_args,
            "type": "stdio"
        }
        print("  [ok] Registered context-mode in .mcp.json (pinned @latest)")
    else:
        existing = data["mcpServers"]["context-mode"]
        if existing.get("command") == "npx" and existing.get("args") == old_default_args:
            existing["args"] = pinned_args
            print("  [ok] Upgraded context-mode in .mcp.json to @latest pin")
        elif existing.get("command") == "npx" and existing.get("args") == pinned_args:
            print("  [skip] context-mode already in .mcp.json (already pinned @latest)")
        else:
            print("  [skip] context-mode already in .mcp.json (user-customized; left untouched)")

tmp = mcp_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, mcp_path)
MCPEOF
    then
      python3 -m json.tool ".mcp.json" > /dev/null 2>&1 || \
        echo "  [warn] JSON validation failed for .mcp.json"
    else
      echo "  [warn] Failed to merge MCP servers into .mcp.json"
    fi
  fi

  merge_settings_json ".claude/settings.json" "project"

  # Register upstream context-mode hooks via the CLI dispatcher form.
  # Guarded by INSTALL_CONTEXT_MODE=true (flipped false by --skip-context-mode).
  # The five upstream hooks (PostToolUse/PreToolUse/PreCompact/SessionStart/
  # UserPromptSubmit) use their own substring-dedup merge (merge_context_mode_hooks),
  # separate from the basename-dedup used for project hook scripts above, so there
  # is no dedup collision between the two merges.
  if [ "$INSTALL_CONTEXT_MODE" = true ]; then
    merge_context_mode_hooks ".claude/settings.json"
  fi

  echo ""
}

# ---------------------------------------------------------------------------
# _prompt_with_default
# ---------------------------------------------------------------------------
# Prompt for a boolean with a current value as the default.
#   $1 — prompt text (without the [Y/n]/[y/N] hint)
#   $2 — current value: "true" or "false"
# Prints the prompt to stderr (to avoid polluting stdout), reads one line
# from stdin, and echoes "true" or "false" on stdout.
# Mapping: y|Y -> true, n|N -> false, empty (Enter) -> current, other -> current.
_prompt_with_default() {
  local prompt_text="$1"
  local current="$2"
  local hint reply
  if [ "$current" = "true" ]; then
    hint="Y/n"
  else
    hint="y/N"
  fi
  printf "%s [%s] " "$prompt_text" "$hint" >&2
  read -r reply
  case "$reply" in
    y|Y) echo true ;;
    n|N) echo false ;;
    *)   echo "$current" ;;
  esac
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

    # --- Statusline component config ---
    # Determine config file path based on mode.
    # IMPORTANT: this resolution MUST match the generated statusline-cmm.sh reader
    # (below, PROJECT_ROOT section) exactly, otherwise the writer and reader hash
    # different strings and the re-prompt values silently never take effect.
    # The reader: (1) starts from git rev-parse --show-toplevel (or pwd), (2)
    # walks superproject, (3) escapes worktrees via _GIT_COMMON/.. — so we do
    # the same here.
    local sl_config_path
    if [ "$mode" = "project" ]; then
      local _project_root
      # IMPORTANT: fallback uses bare `pwd` (not `pwd -P`) to match the
      # emitted statusline-cmm.sh reader on symlinked non-git paths.
      _project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
      if [ -n "$_project_root" ]; then
        local _walk="$_project_root"
        while true; do
          local _parent
          _parent="$(git -C "$_walk" rev-parse --show-superproject-working-tree 2>/dev/null)"
          [ -z "$_parent" ] && break
          _walk="$_parent"
        done
        _project_root="$_walk"
        local _git_dir _git_common
        _git_dir="$(git -C "$_project_root" rev-parse --git-dir 2>/dev/null)"
        _git_common="$(git -C "$_project_root" rev-parse --git-common-dir 2>/dev/null)"
        [ "${_git_dir:0:1}" != "/" ]    && _git_dir="$_project_root/$_git_dir"
        [ "${_git_common:0:1}" != "/" ] && _git_common="$_project_root/$_git_common"
        if [ "$_git_dir" != "$_git_common" ]; then
          local _main_root
          _main_root="$(cd "$_git_common/.." 2>/dev/null && pwd -P)"
          [ -n "$_main_root" ] && _project_root="$_main_root"
        fi
      fi
      local _project_hash
      _project_hash=$(echo "$_project_root" | md5 -q 2>/dev/null || echo "$_project_root" | md5sum | awk '{print $1}')
      sl_config_path="$HOME/.cache/codebase-memory-mcp/_statusline-config-${_project_hash}.json"
    else
      sl_config_path="$HOME/.cache/codebase-memory-mcp/_statusline-config-default.json"
    fi

    # Write config. Three branches:
    #   1. Non-interactive (--yes, --force, or no TTY): preserve existing config
    #      if present, otherwise write all-true defaults. No prompts.
    #   2. Fresh install (no config file), interactive: prompt with [Y/n]
    #      defaults (all true).
    #   3. Already-installed, interactive (or --reconfigure-statusline): re-prompt
    #      with the current values as the defaults for each of the six keys.
    mkdir -p "$(dirname "$sl_config_path")"

    # Read existing values (if any) so we can offer them as defaults.
    local return_from_phase2=false
    local cur_cmm_total=true cur_cmm_details=true cur_blocks_total=true
    local cur_block_details=true cur_ctx_total=true cur_ctx_details=true
    if [ -f "$sl_config_path" ]; then
      local _sl_read
      _sl_read=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    keys = ['cmm_total','cmm_details','blocks_total','block_details','ctx_total','ctx_details']
    print(' '.join('true' if d.get(k, True) else 'false' for k in keys))
except Exception:
    print('true true true true true true')
" "$sl_config_path" 2>/dev/null || echo "true true true true true true")
      read -r cur_cmm_total cur_cmm_details cur_blocks_total cur_block_details cur_ctx_total cur_ctx_details <<<"$_sl_read"
    fi

    local sl_cmm_total sl_cmm_details sl_blocks_total sl_block_details sl_ctx_total sl_ctx_details

    if [ "$YES_FLAG" = true ] || [ "$FORCE" = true ] || [ ! -t 0 ]; then
      # Branch 1: non-interactive. Preserve existing config file if present; else write defaults.
      if [ -f "$sl_config_path" ] && [ "$RECONFIGURE_STATUSLINE" = false ]; then
        echo "  [info] Statusline config preserved: ${sl_config_path}"
        return_from_phase2=true
      else
        sl_cmm_total=$cur_cmm_total
        sl_cmm_details=$cur_cmm_details
        sl_blocks_total=$cur_blocks_total
        sl_block_details=$cur_block_details
        sl_ctx_total=$cur_ctx_total
        sl_ctx_details=$cur_ctx_details
        return_from_phase2=false
      fi
    else
      # Branch 2 or 3: interactive. Re-prompt in both cases; defaults differ by source.
      echo ""
      if [ -f "$sl_config_path" ] || [ "$RECONFIGURE_STATUSLINE" = true ]; then
        echo "  Statusline component selection (press Enter to keep current value):"
      else
        echo "  Statusline component selection (press Enter for default):"
      fi
      sl_cmm_total=$(_prompt_with_default "    Show CMM total (CMM:N)?" "$cur_cmm_total")
      sl_cmm_details=$(_prompt_with_default "    Show CMM details (sg:X cs:Y tr:Z)?" "$cur_cmm_details")
      sl_blocks_total=$(_prompt_with_default "    Show Blocks total (Blk:N)?" "$cur_blocks_total")
      sl_block_details=$(_prompt_with_default "    Show Block details (R:X/B:Y)?" "$cur_block_details")
      sl_ctx_total=$(_prompt_with_default "    Show Context Mode total (CTX:N)?" "$cur_ctx_total")
      sl_ctx_details=$(_prompt_with_default "    Show Context Mode details (ex:X bex:Y sr:Z)?" "$cur_ctx_details")
      return_from_phase2=false
    fi

    if [ "$return_from_phase2" != true ]; then
      # Atomic write: tmp + mv.
      cat > "${sl_config_path}.tmp" <<SLCFG
{
  "cmm_total": ${sl_cmm_total},
  "cmm_details": ${sl_cmm_details},
  "blocks_total": ${sl_blocks_total},
  "block_details": ${sl_block_details},
  "ctx_total": ${sl_ctx_total},
  "ctx_details": ${sl_ctx_details}
}
SLCFG
      mv "${sl_config_path}.tmp" "$sl_config_path"
      echo "  [ok] Statusline config written: ${sl_config_path}"
    fi

    # Create hooks dir if needed
    mkdir -p "${target_config_dir}/hooks"

    local script_path="${target_config_dir}/hooks/statusline-cmm.sh"

    if [ "$mode" = "global" ]; then
      # GLOBAL MODE — Generate standalone statusline-cmm.sh
      cat > "$script_path" <<'STATUSLINE_SCRIPT'
#!/bin/bash
# statusline-cmm.sh — Display CMM call stats in Claude Code statusline
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [ -n "$PROJECT_ROOT" ]; then
    _WALK="$PROJECT_ROOT"
    while true; do
        _PARENT="$(git -C "$_WALK" rev-parse --show-superproject-working-tree 2>/dev/null)"
        [ -z "$_PARENT" ] && break
        _WALK="$_PARENT"
    done
    PROJECT_ROOT="$_WALK"
fi
if [ -n "$PROJECT_ROOT" ]; then
    _GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --git-dir 2>/dev/null)"
    _GIT_COMMON="$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null)"
    [ "${_GIT_DIR:0:1}" != "/" ]    && _GIT_DIR="$PROJECT_ROOT/$_GIT_DIR"
    [ "${_GIT_COMMON:0:1}" != "/" ] && _GIT_COMMON="$PROJECT_ROOT/$_GIT_COMMON"
    if [ "$_GIT_DIR" != "$_GIT_COMMON" ]; then
        _MAIN_ROOT="$(cd "$_GIT_COMMON/.." 2>/dev/null && pwd -P)"
        [ -n "$_MAIN_ROOT" ] && PROJECT_ROOT="$_MAIN_ROOT"
    fi
fi
PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')
# --- Config reading ---
SL_CONFIG="$HOME/.cache/codebase-memory-mcp/_statusline-config-${PROJECT_HASH}.json"
[ -f "$SL_CONFIG" ] || SL_CONFIG="$HOME/.cache/codebase-memory-mcp/_statusline-config-default.json"
SHOW_CMM_TOTAL=$(jq -r 'if has("cmm_total") then .cmm_total else true end' "$SL_CONFIG" 2>/dev/null || echo true)
SHOW_CMM_DETAILS=$(jq -r 'if has("cmm_details") then .cmm_details else true end' "$SL_CONFIG" 2>/dev/null || echo true)
SHOW_BLOCKS_TOTAL=$(jq -r 'if has("blocks_total") then .blocks_total else true end' "$SL_CONFIG" 2>/dev/null || echo true)
SHOW_BLOCK_DETAILS=$(jq -r 'if has("block_details") then .block_details else true end' "$SL_CONFIG" 2>/dev/null || echo true)
SHOW_CTX_TOTAL=$(jq -r 'if has("ctx_total") then .ctx_total else true end' "$SL_CONFIG" 2>/dev/null || echo true)
SHOW_CTX_DETAILS=$(jq -r 'if has("ctx_details") then .ctx_details else true end' "$SL_CONFIG" 2>/dev/null || echo true)
# --- CMM counts ---
CACHE="$HOME/.cache/codebase-memory-mcp/_call-counts-${PROJECT_HASH}.json"
CMM_OUTPUT=""
if [ -f "$CACHE" ]; then
  TOTAL=$(jq -r '.total_calls // 0' "$CACHE" 2>/dev/null || echo 0)
  SEARCH=$(jq -r '.by_tool["mcp__codebase-memory-mcp__search_graph"] // 0' "$CACHE" 2>/dev/null || echo 0)
  SNIPPET=$(jq -r '.by_tool["mcp__codebase-memory-mcp__get_code_snippet"] // 0' "$CACHE" 2>/dev/null || echo 0)
  TRACE=$(jq -r '.by_tool["mcp__codebase-memory-mcp__trace_call_path"] // 0' "$CACHE" 2>/dev/null || echo 0)
  if [ "$SHOW_CMM_TOTAL" = "true" ]; then
    CMM_OUTPUT="CMM:${TOTAL}"
    if [ "$SHOW_CMM_DETAILS" = "true" ]; then
      CMM_OUTPUT="${CMM_OUTPUT} (sg:${SEARCH} cs:${SNIPPET} tr:${TRACE})"
    fi
  fi
else
  if [ "$SHOW_CMM_TOTAL" = "true" ]; then
    CMM_OUTPUT="CMM:0"
  fi
fi
# --- CTX counts ---
CTX_CACHE="$HOME/.cache/codebase-memory-mcp/_ctx-call-counts-${PROJECT_HASH}.json"
if [ -f "$CTX_CACHE" ]; then
  CTX_TOTAL=$(jq -r '.total_calls // 0' "$CTX_CACHE" 2>/dev/null || echo 0)
  CTX_EXEC=$(jq -r '.by_tool["mcp__context-mode__ctx_execute"] // 0' "$CTX_CACHE" 2>/dev/null || echo 0)
  CTX_BATCH=$(jq -r '.by_tool["mcp__context-mode__ctx_batch_execute"] // 0' "$CTX_CACHE" 2>/dev/null || echo 0)
  CTX_SEARCH=$(jq -r '.by_tool["mcp__context-mode__ctx_search"] // 0' "$CTX_CACHE" 2>/dev/null || echo 0)
  if [ "$CTX_TOTAL" -gt 0 ] 2>/dev/null; then
    if [ "$SHOW_CTX_TOTAL" = "true" ]; then
      CTX_OUTPUT="CTX:${CTX_TOTAL}"
      if [ "$SHOW_CTX_DETAILS" = "true" ]; then
        CTX_OUTPUT="${CTX_OUTPUT} (ex:${CTX_EXEC} bex:${CTX_BATCH} sr:${CTX_SEARCH})"
      fi
      CMM_OUTPUT="${CMM_OUTPUT:+${CMM_OUTPUT} }${CTX_OUTPUT}"
    fi
  fi
fi
# --- Block counts ---
BLOCK_CACHE="$HOME/.cache/codebase-memory-mcp/_block-counts-${PROJECT_HASH}.json"
if [ -f "$BLOCK_CACHE" ]; then
  READ_BLOCKS=$(jq -r '.read_blocks // 0' "$BLOCK_CACHE" 2>/dev/null || echo 0)
  BASH_BLOCKS=$(jq -r '.bash_blocks // 0' "$BLOCK_CACHE" 2>/dev/null || echo 0)
  if [ "$SHOW_BLOCKS_TOTAL" = "true" ]; then
    if [ "$READ_BLOCKS" -gt 0 ] 2>/dev/null || [ "$BASH_BLOCKS" -gt 0 ] 2>/dev/null; then
      if [ "$SHOW_BLOCK_DETAILS" = "true" ]; then
        CMM_OUTPUT="${CMM_OUTPUT:+${CMM_OUTPUT} }Blk:R${READ_BLOCKS}/B${BASH_BLOCKS}"
      else
        BLOCK_SUM=$((READ_BLOCKS + BASH_BLOCKS))
        CMM_OUTPUT="${CMM_OUTPUT:+${CMM_OUTPUT} }Blk:${BLOCK_SUM}"
      fi
    fi
  fi
fi
[ -n "$CMM_OUTPUT" ] && echo "$CMM_OUTPUT" || echo "CMM:0"
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
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [ -n "$PROJECT_ROOT" ]; then
    _WALK="$PROJECT_ROOT"
    while true; do
        _PARENT="$(git -C "$_WALK" rev-parse --show-superproject-working-tree 2>/dev/null)"
        [ -z "$_PARENT" ] && break
        _WALK="$_PARENT"
    done
    PROJECT_ROOT="$_WALK"
fi
if [ -n "$PROJECT_ROOT" ]; then
    _GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --git-dir 2>/dev/null)"
    _GIT_COMMON="$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null)"
    [ "${_GIT_DIR:0:1}" != "/" ]    && _GIT_DIR="$PROJECT_ROOT/$_GIT_DIR"
    [ "${_GIT_COMMON:0:1}" != "/" ] && _GIT_COMMON="$PROJECT_ROOT/$_GIT_COMMON"
    if [ "$_GIT_DIR" != "$_GIT_COMMON" ]; then
        _MAIN_ROOT="$(cd "$_GIT_COMMON/.." 2>/dev/null && pwd -P)"
        [ -n "$_MAIN_ROOT" ] && PROJECT_ROOT="$_MAIN_ROOT"
    fi
fi
PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')
# --- Config reading ---
SL_CONFIG="$HOME/.cache/codebase-memory-mcp/_statusline-config-${PROJECT_HASH}.json"
[ -f "$SL_CONFIG" ] || SL_CONFIG="$HOME/.cache/codebase-memory-mcp/_statusline-config-default.json"
SHOW_CMM_TOTAL=$(jq -r 'if has("cmm_total") then .cmm_total else true end' "$SL_CONFIG" 2>/dev/null || echo true)
SHOW_CMM_DETAILS=$(jq -r 'if has("cmm_details") then .cmm_details else true end' "$SL_CONFIG" 2>/dev/null || echo true)
SHOW_BLOCKS_TOTAL=$(jq -r 'if has("blocks_total") then .blocks_total else true end' "$SL_CONFIG" 2>/dev/null || echo true)
SHOW_BLOCK_DETAILS=$(jq -r 'if has("block_details") then .block_details else true end' "$SL_CONFIG" 2>/dev/null || echo true)
SHOW_CTX_TOTAL=$(jq -r 'if has("ctx_total") then .ctx_total else true end' "$SL_CONFIG" 2>/dev/null || echo true)
SHOW_CTX_DETAILS=$(jq -r 'if has("ctx_details") then .ctx_details else true end' "$SL_CONFIG" 2>/dev/null || echo true)
# --- CMM counts ---
CACHE="$HOME/.cache/codebase-memory-mcp/_call-counts-${PROJECT_HASH}.json"
if [ -f "$CACHE" ]; then
  TOTAL=$(jq -r '.total_calls // 0' "$CACHE" 2>/dev/null || echo 0)
  SEARCH=$(jq -r '.by_tool["mcp__codebase-memory-mcp__search_graph"] // 0' "$CACHE" 2>/dev/null || echo 0)
  SNIPPET=$(jq -r '.by_tool["mcp__codebase-memory-mcp__get_code_snippet"] // 0' "$CACHE" 2>/dev/null || echo 0)
  TRACE=$(jq -r '.by_tool["mcp__codebase-memory-mcp__trace_call_path"] // 0' "$CACHE" 2>/dev/null || echo 0)
  if [ "$SHOW_CMM_TOTAL" = "true" ]; then
    CMM_OUTPUT="CMM:${TOTAL}"
    if [ "$SHOW_CMM_DETAILS" = "true" ]; then
      CMM_OUTPUT="${CMM_OUTPUT} (sg:${SEARCH} cs:${SNIPPET} tr:${TRACE})"
    fi
  fi
else
  if [ "$SHOW_CMM_TOTAL" = "true" ]; then
    CMM_OUTPUT="CMM:0"
  fi
fi
# --- CTX counts ---
CTX_CACHE="$HOME/.cache/codebase-memory-mcp/_ctx-call-counts-${PROJECT_HASH}.json"
if [ -f "$CTX_CACHE" ]; then
  CTX_TOTAL=$(jq -r '.total_calls // 0' "$CTX_CACHE" 2>/dev/null || echo 0)
  CTX_EXEC=$(jq -r '.by_tool["mcp__context-mode__ctx_execute"] // 0' "$CTX_CACHE" 2>/dev/null || echo 0)
  CTX_BATCH=$(jq -r '.by_tool["mcp__context-mode__ctx_batch_execute"] // 0' "$CTX_CACHE" 2>/dev/null || echo 0)
  CTX_SEARCH=$(jq -r '.by_tool["mcp__context-mode__ctx_search"] // 0' "$CTX_CACHE" 2>/dev/null || echo 0)
  if [ "$CTX_TOTAL" -gt 0 ] 2>/dev/null; then
    if [ "$SHOW_CTX_TOTAL" = "true" ]; then
      CTX_OUTPUT="CTX:${CTX_TOTAL}"
      if [ "$SHOW_CTX_DETAILS" = "true" ]; then
        CTX_OUTPUT="${CTX_OUTPUT} (ex:${CTX_EXEC} bex:${CTX_BATCH} sr:${CTX_SEARCH})"
      fi
      CMM_OUTPUT="${CMM_OUTPUT:+${CMM_OUTPUT} }${CTX_OUTPUT}"
    fi
  fi
fi
# --- Block counts ---
BLOCK_CACHE="$HOME/.cache/codebase-memory-mcp/_block-counts-${PROJECT_HASH}.json"
if [ -f "$BLOCK_CACHE" ]; then
  READ_BLOCKS=$(jq -r '.read_blocks // 0' "$BLOCK_CACHE" 2>/dev/null || echo 0)
  BASH_BLOCKS=$(jq -r '.bash_blocks // 0' "$BLOCK_CACHE" 2>/dev/null || echo 0)
  if [ "$SHOW_BLOCKS_TOTAL" = "true" ]; then
    if [ "$READ_BLOCKS" -gt 0 ] 2>/dev/null || [ "$BASH_BLOCKS" -gt 0 ] 2>/dev/null; then
      if [ "$SHOW_BLOCK_DETAILS" = "true" ]; then
        CMM_OUTPUT="${CMM_OUTPUT:+${CMM_OUTPUT} }Blk:R${READ_BLOCKS}/B${BASH_BLOCKS}"
      else
        BLOCK_SUM=$((READ_BLOCKS + BASH_BLOCKS))
        CMM_OUTPUT="${CMM_OUTPUT:+${CMM_OUTPUT} }Blk:${BLOCK_SUM}"
      fi
    fi
  fi
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
    local project_root
    project_root=$(pwd)
    echo "[STATUSLINE — project]"
    _run_install_statusline_for_target "${project_root}/.claude" "project"
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
# install_allowlist
# ---------------------------------------------------------------------------
# Offer to write the CMM tool allowlist (and optionally context-mode tools)
# into .claude/settings.json under permissions.allow.
# Tool allowlist is project-level (not personal), so it belongs in the committed
# settings.json — this ensures worktree sessions inherit the allowlist automatically.
# Only runs for project installs. Follows the same prompt pattern as
# install_statusline: detect current state, prompt, merge on yes.

install_allowlist() {
  if [ "$INSTALL_PROJECT" != true ]; then
    return 0
  fi

  echo "[ALLOWLIST]"

  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY RUN] Would offer to write CMM tool allowlist to .claude/settings.json"
    [ "$INSTALL_CONTEXT_MODE" = true ] && \
      echo "  [DRY RUN] Would include context-mode tools (INSTALL_CONTEXT_MODE=true)"
    echo ""
    return 0
  fi

  local settings_file=".claude/settings.json"

  # Determine if CMM tools already fully present
  if [ "$CMM_TOOLS_STATUS" = "ok" ] && [ "$FORCE" != true ]; then
    echo "  [ok] CMM tool allowlist already configured in $settings_file"
    if [ "$INSTALL_CONTEXT_MODE" = true ]; then
      # Check if context-mode tools are also present
      local ctx_count
      ctx_count=$(python3 - "$settings_file" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    allow = data.get("permissions", {}).get("allow", [])
    count = sum(1 for t in allow if "mcp__context-mode__" in str(t))
    print(count)
except Exception:
    print(0)
PYEOF
)
      if [ "$ctx_count" -ge 9 ]; then
        echo "  [ok] context-mode tool allowlist already configured"
        echo ""
        return 0
      else
        echo "  [warn] context-mode tools not yet allowlisted (${ctx_count}/9)"
      fi
    else
      echo ""
      return 0
    fi
  fi

  # Build prompt describing what will be written
  local prompt_msg="  Write CMM tool allowlist to ${settings_file}? [y/N] "
  if [ "$INSTALL_CONTEXT_MODE" = true ]; then
    prompt_msg="  Write CMM + context-mode tool allowlist to ${settings_file}? [y/N] "
  fi
  if [ "$CMM_TOOLS_STATUS" = "warn" ]; then
    echo "  [warn] Only ${CMM_TOOLS_COUNT}/14 CMM tools currently allowlisted"
  elif [ "$CMM_TOOLS_STATUS" = "missing" ]; then
    echo "  [warn] ${settings_file} not found — CMM tools not allowlisted"
  elif [ "$FORCE" = true ] && [ "$CMM_TOOLS_STATUS" = "ok" ]; then
    echo "  [info] Overwriting existing CMM allowlist (--force)"
  fi

  printf "%s" "$prompt_msg"
  local answer
  read -r answer
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "  [skip] Allowlist not written"
    echo ""
    return 0
  fi

  # Merge CMM tools (and optionally context-mode tools) into permissions.allow
  local include_ctx="false"
  [ "$INSTALL_CONTEXT_MODE" = true ] && include_ctx="true"

  python3 - "$settings_file" "$include_ctx" <<'PYEOF'
import json, os, sys

settings_path = sys.argv[1]
include_ctx = sys.argv[2] == "true"

CMM_TOOLS = [
    "mcp__codebase-memory-mcp__index_repository",
    "mcp__codebase-memory-mcp__index_status",
    "mcp__codebase-memory-mcp__list_projects",
    "mcp__codebase-memory-mcp__delete_project",
    "mcp__codebase-memory-mcp__get_architecture",
    "mcp__codebase-memory-mcp__get_graph_schema",
    "mcp__codebase-memory-mcp__search_graph",
    "mcp__codebase-memory-mcp__search_code",
    "mcp__codebase-memory-mcp__query_graph",
    "mcp__codebase-memory-mcp__get_code_snippet",
    "mcp__codebase-memory-mcp__trace_call_path",
    "mcp__codebase-memory-mcp__detect_changes",
    "mcp__codebase-memory-mcp__manage_adr",
    "mcp__codebase-memory-mcp__ingest_traces",
]

CTX_TOOLS = [
    "mcp__context-mode__ctx_execute",
    "mcp__context-mode__ctx_search",
    "mcp__context-mode__ctx_index",
    "mcp__context-mode__ctx_fetch_and_index",
    "mcp__context-mode__ctx_batch_execute",
    "mcp__context-mode__ctx_execute_file",
    "mcp__context-mode__ctx_stats",
    "mcp__context-mode__ctx_doctor",
    "mcp__context-mode__ctx_upgrade",
]

try:
    with open(settings_path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}

allow = data.setdefault("permissions", {}).setdefault("allow", [])
existing = set(allow)

to_add = CMM_TOOLS[:]
if include_ctx:
    to_add += CTX_TOOLS

added = [t for t in to_add if t not in existing]
allow.extend(added)

tmp = settings_path + ".tmp"
os.makedirs(os.path.dirname(settings_path) if os.path.dirname(settings_path) else ".", exist_ok=True)
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, settings_path)

print(f"  [ok] Added {len(added)} tool(s) to permissions.allow in {os.path.basename(settings_path)}")
if include_ctx:
    ctx_added = [t for t in CTX_TOOLS if t in added]
    cmm_added = [t for t in CMM_TOOLS if t in added]
    print(f"       CMM: {len(cmm_added)} added, context-mode: {len(ctx_added)} added")
PYEOF

  # Validate written JSON
  python3 -m json.tool "$settings_file" > /dev/null 2>&1 || \
    echo "  [warn] JSON validation failed for ${settings_file}"

  echo ""
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
      --skip-context-mode) SKIP_CONTEXT_MODE=true ;;
      --skip-statusline) SKIP_STATUSLINE=true ;;
      --reconfigure-statusline) RECONFIGURE_STATUSLINE=true ;;
      --yes|-y)          YES_FLAG=true ;;
      --verify)          VERIFY=true ;;
      --help|-h)
        cat <<'HELP'
setup.sh — Installer for codebase-memory-mcp + Context Mode Claude Code hooks

Installs hooks, rules, and settings for two complementary MCP servers:
  - codebase-memory-mcp (CMM): code knowledge graph, ~99% token reduction on code exploration
  - Context Mode MCP (optional): execution sandboxing + SQLite session persistence, ~98% context reduction

Usage:
  ./setup.sh [--global] [--project] [--all] [--force] [--dry-run] [--skip-mcp-check] [--skip-context-mode] [--skip-statusline] [--verify]

Flags:
  --global          Install global hooks and rules to ~/.claude/ and merge into ~/.claude/settings.json
  --project         Install project hooks to .claude/hooks/, rules to .claude/rules/,
                    create .mcp.json, and merge into .claude/settings.json
  --all             Install both global and project hooks
  --force           Overwrite existing files without prompting (default: detect drift and prompt)
  --dry-run         Show what would be done without making changes
  --skip-mcp-check  Bypass all MCP availability checks (useful for CI/automation).
                    Note: this does NOT skip context-mode registration — use --skip-context-mode for that.
  --skip-context-mode  Skip registering context-mode in .mcp.json (default: register context-mode).
                    Existing context-mode entries in .mcp.json are preserved regardless.
  --skip-statusline Skip the CMM statusline installation offer
  --reconfigure-statusline  Re-prompt for statusline component selection (overwrite existing config)
  --yes, -y         Non-interactive mode: accept all defaults without prompting
  --verify          After installing hooks, verify file integrity against CHECKSUMS.sha256
  --help, -h        Show this help message

MCP pre-flight checks (run automatically unless --skip-mcp-check):
  - CMM binary       detected via PATH and common install locations
  - CMM registration checked in .mcp.json and global MCP config
  - Tool allowlist   verified in .claude/settings.json (14 CMM tools)
  - Context Mode     optional; prompts to install if not detected

Context Mode hooks (context-mode-*.sh) are always installed but gracefully
no-op when Context Mode is not present — you can enable it later without
re-running setup.

Examples:
  bash setup.sh --project             # Install project hooks; on re-run, drifted files prompt to overwrite
  bash setup.sh --global              # Install global hooks for all projects
  bash setup.sh --all --force         # Install everything, overwriting existing files
  bash setup.sh --dry-run --project   # Preview project install without making changes
  bash setup.sh --project --force     # Re-install everything, overwriting all existing files
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
  verify_repo_remote
  check_prerequisites
  check_mcp_availability

  if [ "$INSTALL_GLOBAL" = true ]; then
    install_global
  fi

  if [ "$INSTALL_PROJECT" = true ]; then
    install_project
  fi

  verify_installation

  if [ "$SKIP_STATUSLINE" = false ]; then
    install_statusline
  fi

  install_allowlist

  if [ "$DRY_RUN" = false ]; then
    print_next_steps
  fi
}

main "$@"
