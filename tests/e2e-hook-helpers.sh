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
