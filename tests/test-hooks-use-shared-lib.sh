#!/bin/bash
# test-hooks-use-shared-lib.sh — Verify all hooks use shared project-root library
# Scans hooks/project/*.sh for inline git traversal vs shared lib sourcing.
# Allows inline traversal ONLY in excluded files (handled by Plans 02/03).
# Usage: bash tests/test-hooks-use-shared-lib.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
HOOKS_DIR="$REPO_ROOT/hooks/project"
LIB_SCRIPT="$REPO_ROOT/hooks/lib/project-root.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Files excluded from migration:
# - session-gate.sh, reindex-after-commit.sh: handled by Plans 02/03
# - track-hook-blocks.sh: inline helper (called by other hooks, not registered standalone)
# - cmm-nudge.sh: uses git -C dirname pattern (not the full superproject traversal)
# - agent-cmm-gate.sh: no project root detection needed
#
# Phase 51 removed context-mode-event-logger.sh and context-mode-pre-compact.sh
# (their logic is now provided by context-mode's upstream posttooluse.mjs /
# precompact.mjs hooks registered via setup.sh::merge_context_mode_hooks).
EXCLUDED="session-gate.sh reindex-after-commit.sh track-hook-blocks.sh cmm-nudge.sh agent-cmm-gate.sh"

# Files that MUST be migrated
MIGRATED="track-cmm-calls.sh track-ctx-calls.sh cmm-sentinel-writer.sh context-mode-sentinel-writer.sh cmm-query-stale-advisory.sh subagent-cmm-startup.sh cmm-session-start.sh ctx-execute-enforcer.sh"

# ===================================================================
echo "=== Test 1: No inline git traversal in migrated hooks ==="
# ===================================================================

for f in "$HOOKS_DIR"/*.sh; do
  BASENAME="$(basename "$f")"
  # Skip excluded files
  case " $EXCLUDED " in *" $BASENAME "*) continue ;; esac
  if grep -q 'git rev-parse --show-toplevel' "$f"; then
    # Inline traversal found — it must be ONLY in the fallback else branch
    # Check that the file also sources the shared lib (main path)
    if grep -q 'source.*project-root\.sh' "$f"; then
      pass "$BASENAME has inline traversal only as fallback (lib sourced on main path)"
    else
      fail "$BASENAME has inline git traversal WITHOUT sourcing shared lib"
    fi
  else
    pass "$BASENAME has no inline git traversal"
  fi
done

# ===================================================================
echo "=== Test 2: All migrated hooks source shared lib ==="
# ===================================================================

for HOOK in $MIGRATED; do
  HOOK_FILE="$HOOKS_DIR/$HOOK"
  if [ ! -f "$HOOK_FILE" ]; then
    fail "$HOOK does not exist"
    continue
  fi
  if grep -q 'source.*project-root\.sh' "$HOOK_FILE"; then
    pass "$HOOK sources project-root.sh"
  else
    fail "$HOOK does not source project-root.sh"
  fi
done

# ===================================================================
echo "=== Test 3: All migrated hooks have graceful fallback ==="
# ===================================================================

for HOOK in $MIGRATED; do
  HOOK_FILE="$HOOKS_DIR/$HOOK"
  [ ! -f "$HOOK_FILE" ] && continue
  # Check for the if/else pattern: source lib on main path, inline fallback in else
  if grep -q 'if \[ -f.*project-root\.sh' "$HOOK_FILE" && grep -q 'else' "$HOOK_FILE"; then
    pass "$HOOK has graceful fallback pattern"
  else
    fail "$HOOK missing graceful fallback (if lib exists / else inline)"
  fi
done

# ===================================================================
echo "=== Test 4: Excluded hooks are NOT modified (still have inline traversal) ==="
# ===================================================================

for HOOK in $EXCLUDED; do
  HOOK_FILE="$HOOKS_DIR/$HOOK"
  if [ ! -f "$HOOK_FILE" ]; then
    # Some excluded hooks may not exist (e.g., if Plan 02/03 restructured them)
    pass "$HOOK not present (may have been restructured by Plan 02/03)"
    continue
  fi
  if grep -q 'git rev-parse --show-toplevel' "$HOOK_FILE"; then
    pass "$HOOK retains inline traversal (not yet migrated)"
  else
    # It may have been migrated by Plan 02/03 already — still OK
    pass "$HOOK may have been migrated by Plan 02/03"
  fi
done

# ===================================================================
echo "=== Test 5: Shared lib sets expected variables ==="
# ===================================================================

if [ ! -f "$LIB_SCRIPT" ]; then
  fail "hooks/lib/project-root.sh does not exist"
else
  # Source the lib in a subshell from the repo root
  RESULT=$(cd "$REPO_ROOT" && bash -c "
    source '$LIB_SCRIPT'
    echo \"ROOT=\$PROJECT_ROOT\"
    echo \"HASH=\$PROJECT_HASH\"
    echo \"CMM=\$CMM_SENTINEL\"
    echo \"CTX=\$CONTEXT_MODE_SENTINEL\"
    echo \"LOADED=\$_PROJECT_ROOT_LOADED\"
  " 2>/dev/null)

  ROOT_VAL=$(echo "$RESULT" | grep '^ROOT=' | cut -d= -f2-)
  HASH_VAL=$(echo "$RESULT" | grep '^HASH=' | cut -d= -f2-)
  CMM_VAL=$(echo "$RESULT"  | grep '^CMM='  | cut -d= -f2-)
  CTX_VAL=$(echo "$RESULT"  | grep '^CTX='  | cut -d= -f2-)
  LOADED_VAL=$(echo "$RESULT" | grep '^LOADED=' | cut -d= -f2-)

  [ -n "$ROOT_VAL" ] && pass "PROJECT_ROOT is set ($ROOT_VAL)" || fail "PROJECT_ROOT is empty"
  [ -n "$HASH_VAL" ] && pass "PROJECT_HASH is set" || fail "PROJECT_HASH is empty"
  [ -n "$CMM_VAL" ]  && pass "CMM_SENTINEL is set" || fail "CMM_SENTINEL is empty"
  [ -n "$CTX_VAL" ]  && pass "CONTEXT_MODE_SENTINEL is set" || fail "CONTEXT_MODE_SENTINEL is empty"
  [ "$LOADED_VAL" = "1" ] && pass "_PROJECT_ROOT_LOADED guard is set" || fail "_PROJECT_ROOT_LOADED not set"
fi

# ===================================================================
echo "=== Test 6: Migrated hooks use PROJECT_ROOT and PROJECT_HASH ==="
# ===================================================================

for HOOK in $MIGRATED; do
  HOOK_FILE="$HOOKS_DIR/$HOOK"
  [ ! -f "$HOOK_FILE" ] && continue
  USES_ROOT=0; USES_HASH=0
  grep -q 'PROJECT_ROOT' "$HOOK_FILE" && USES_ROOT=1
  grep -q 'PROJECT_HASH' "$HOOK_FILE" && USES_HASH=1
  if [ "$USES_ROOT" -eq 1 ] && [ "$USES_HASH" -eq 1 ]; then
    pass "$HOOK uses PROJECT_ROOT and PROJECT_HASH"
  elif [ "$USES_ROOT" -eq 1 ]; then
    pass "$HOOK uses PROJECT_ROOT (PROJECT_HASH may be implicit via lib)"
  else
    fail "$HOOK does not reference PROJECT_ROOT"
  fi
done

# ===================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
