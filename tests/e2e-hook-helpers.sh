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
