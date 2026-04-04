#!/bin/bash
# test-agent-hook-overrides.sh — Verify agent override files have correct CMM hook registrations
# Usage: bash tests/test-agent-hook-overrides.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
AGENTS_DIR="$SCRIPT_DIR/../agents"

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# --- Test 1: All four override files exist ---
echo "--- Test 1: Agent override files exist ---"
for agent in vbw-dev vbw-scout vbw-qa vbw-debugger; do
  if [ -f "$AGENTS_DIR/$agent.md" ]; then
    pass "$agent.md exists"
  else
    fail "$agent.md missing"
  fi
done

# --- Test 2: All overrides have cmm-nudge.sh Read hook ---
echo ""
echo "--- Test 2: PreToolUse:Read cmm-nudge.sh registered ---"
for agent in vbw-dev vbw-scout vbw-qa vbw-debugger; do
  if grep -q 'cmm-nudge.sh' "$AGENTS_DIR/$agent.md" 2>/dev/null; then
    pass "$agent.md has cmm-nudge.sh"
  else
    fail "$agent.md missing cmm-nudge.sh"
  fi
done

# --- Test 3: Dev/QA/Debugger have ctx-execute-enforcer.sh Bash hook ---
echo ""
echo "--- Test 3: PreToolUse:Bash ctx-execute-enforcer.sh (dev/qa/debugger only) ---"
for agent in vbw-dev vbw-qa vbw-debugger; do
  if grep -q 'ctx-execute-enforcer.sh' "$AGENTS_DIR/$agent.md" 2>/dev/null; then
    pass "$agent.md has ctx-execute-enforcer.sh"
  else
    fail "$agent.md missing ctx-execute-enforcer.sh"
  fi
done

# Scout should NOT have ctx-execute-enforcer (Bash is disallowed for scout)
if grep -q 'ctx-execute-enforcer.sh' "$AGENTS_DIR/vbw-scout.md" 2>/dev/null; then
  fail "vbw-scout.md should NOT have ctx-execute-enforcer.sh (Bash disallowed)"
else
  pass "vbw-scout.md correctly omits ctx-execute-enforcer.sh"
fi

# --- Test 4: All overrides have track-cmm-calls.sh PostToolUse hook ---
echo ""
echo "--- Test 4: PostToolUse track-cmm-calls.sh registered ---"
for agent in vbw-dev vbw-scout vbw-qa vbw-debugger; do
  if grep -q 'track-cmm-calls.sh' "$AGENTS_DIR/$agent.md" 2>/dev/null; then
    pass "$agent.md has track-cmm-calls.sh"
  else
    fail "$agent.md missing track-cmm-calls.sh"
  fi
done

# --- Test 5: Dev and Debugger have SUBAGENT_COMMIT reindex hook ---
echo ""
echo "--- Test 5: SUBAGENT_COMMIT reindex hook (dev/debugger only) ---"
for agent in vbw-dev vbw-debugger; do
  if grep -q 'SUBAGENT_COMMIT=1' "$AGENTS_DIR/$agent.md" 2>/dev/null; then
    pass "$agent.md has SUBAGENT_COMMIT reindex"
  else
    fail "$agent.md missing SUBAGENT_COMMIT reindex"
  fi
done

# Scout and QA should NOT have SUBAGENT_COMMIT (they don't commit)
for agent in vbw-scout vbw-qa; do
  if grep -q 'SUBAGENT_COMMIT=1' "$AGENTS_DIR/$agent.md" 2>/dev/null; then
    fail "$agent.md should NOT have SUBAGENT_COMMIT"
  else
    pass "$agent.md correctly omits SUBAGENT_COMMIT"
  fi
done

# --- Test 6: Correct name: field in frontmatter ---
echo ""
echo "--- Test 6: Frontmatter name: matches filename ---"
for agent in vbw-dev vbw-scout vbw-qa vbw-debugger; do
  NAME=$(grep -m1 '^name:' "$AGENTS_DIR/$agent.md" 2>/dev/null | sed 's/^name: *//')
  if [ "$NAME" = "$agent" ]; then
    pass "$agent.md name: $NAME matches"
  else
    fail "$agent.md name: '$NAME' does not match expected '$agent'"
  fi
done

# --- Test 7: All overrides have stale advisory hook ---
echo ""
echo "--- Test 7: PostToolUse cmm-query-stale-advisory.sh registered ---"
for agent in vbw-dev vbw-scout vbw-qa vbw-debugger; do
  if grep -q 'cmm-query-stale-advisory.sh' "$AGENTS_DIR/$agent.md" 2>/dev/null; then
    pass "$agent.md has cmm-query-stale-advisory.sh"
  else
    fail "$agent.md missing cmm-query-stale-advisory.sh"
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
