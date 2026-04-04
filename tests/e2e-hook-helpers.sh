# e2e-hook-helpers.sh — Reusable helper library for E2E hook testing
# Sourced (not executed). No shebang.
#
# Callers MUST set these before sourcing:
#   E2E_FIXTURE_DIR — path to the fixture project directory (a git repo)
#   E2E_FAKE_CONFIG — path to a fake CLAUDE_CONFIG_DIR
#
# Callers MUST define these functions before sourcing:
#   pass(description) — record a passing test
#   fail(description) — record a failing test

# Guard against double-sourcing
[[ -n "${_E2E_HOOK_HELPERS_LOADED:-}" ]] && return 0
_E2E_HOOK_HELPERS_LOADED=1

# ─── Hash Computation ────────────────────────────────────────────────────
# Compute macOS-safe project hash from a git repo path.
# On macOS, /var/folders -> /private/var/folders via pwd -P, so we must
# resolve the canonical path the same way hooks do.
# Usage: hash=$(_e2e_compute_hash "/path/to/repo")
_e2e_compute_hash() {
  local repo_path="$1"
  local canonical
  canonical=$(cd "$repo_path" && git rev-parse --show-toplevel 2>/dev/null || pwd -P)
  echo "$canonical" | md5 -q 2>/dev/null || echo "$canonical" | md5sum | awk '{print $1}'
}

# ─── Sentinel Management ────────────────────────────────────────────────
# Create all 3 sentinel files for a given project hash.
# This unblocks session-gate, ctx-execute-enforcer, and Context Mode checks.
_e2e_create_sentinels() {
  local hash="$1"
  echo "ready" > "/tmp/cmm-session-ready-${hash}"
  touch "/tmp/context-mode-ready-${hash}"
  echo "1" > "/tmp/ctx-enforcer-${hash}"
}

# Remove all 3 sentinel files for a given project hash.
_e2e_cleanup_sentinels() {
  local hash="$1"
  rm -f "/tmp/cmm-session-ready-${hash}" \
        "/tmp/context-mode-ready-${hash}" \
        "/tmp/ctx-enforcer-${hash}"
}

# Remove only the CMM sentinel (for testing session-gate blocking without sentinel).
_e2e_remove_cmm_sentinel() {
  local hash="$1"
  rm -f "/tmp/cmm-session-ready-${hash}"
}

# Remove only the Context Mode sentinel.
_e2e_remove_ctx_sentinel() {
  local hash="$1"
  rm -f "/tmp/context-mode-ready-${hash}"
}

# ─── JSON Payload Generators ────────────────────────────────────────────
# Generate PreToolUse Read JSON payload.
# Usage: json=$(_e2e_read_payload "/path/to/file")
#        json=$(_e2e_read_payload "/path/to/file" 10 50)  # with offset and limit
_e2e_read_payload() {
  local file_path="$1"
  local offset="${2:-}"
  local limit="${3:-}"
  if [[ -n "$offset" && -n "$limit" ]]; then
    printf '{"tool_name":"Read","tool_input":{"file_path":"%s","offset":%s,"limit":%s}}' \
      "$file_path" "$offset" "$limit"
  else
    printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$file_path"
  fi
}

# Generate PreToolUse Bash JSON payload.
# Usage: json=$(_e2e_bash_payload "npm test")
_e2e_bash_payload() {
  local command="$1"
  # Use python3 with stdin for safe JSON encoding of arbitrary command strings
  echo "$command" | python3 -c "
import json, sys
cmd = sys.stdin.read().rstrip('\n')
print(json.dumps({'tool_name':'Bash','tool_input':{'command':cmd}}))" 2>/dev/null \
    || printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$command"
}

# Generate PreToolUse JSON for an arbitrary tool.
# Usage: json=$(_e2e_tool_payload "Edit")
#        json=$(_e2e_tool_payload "Edit" '{"file_path":"/tmp/f","old_string":"a","new_string":"b"}')
_e2e_tool_payload() {
  local tool_name="$1"
  local input_json="${2:-"{}"}"
  printf '{"tool_name":"%s","tool_input":%s}' "$tool_name" "$input_json"
}
