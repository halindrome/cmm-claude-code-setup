#!/bin/bash
# test-session-gate-earlyexit.sh — Tests session-gate bypass exits without git traversal
# Verifies that CMM, Agent, Bash, and other allow-listed tools exit 0 immediately,
# while Write/Edit are correctly gated by sentinel presence.
# Usage: bash tests/test-session-gate-earlyexit.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/project/session-gate.sh"

PASS=0; FAIL=0
_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Setup: fake git repo for sentinel path computation
FAKE_ROOT=$(mktemp -d /tmp/cmm-test-root-XXXXXX)
git -C "$FAKE_ROOT" init -q
git -C "$FAKE_ROOT" commit --allow-empty -q -m "init"

# Copy the hook into the fake root so the path integrity check passes.
# session-gate.sh checks BASH_SOURCE/../.. against git rev-parse --show-toplevel.
# Placing it in <root>/hooks/project/ satisfies both paths.
mkdir -p "$FAKE_ROOT/hooks/project"
cp "$HOOK" "$FAKE_ROOT/hooks/project/session-gate.sh"
HOOK="$FAKE_ROOT/hooks/project/session-gate.sh"

# Compute hash the same way the hook does
RESOLVED_ROOT="$(cd "$FAKE_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"
if command -v md5sum >/dev/null 2>&1; then
    HASH=$(echo "$RESOLVED_ROOT" | md5sum | awk '{print $1}')
else
    HASH=$(echo "$RESOLVED_ROOT" | md5 -q)
fi
SENTINEL="/tmp/cmm-session-ready-${HASH}"

# --- Test 1: CMM tool call -> exit 0 (bypass) ---
echo "--- Test 1: CMM tool call -> exit 0 (bypass) ---"
rm -f "$SENTINEL"
EXIT_CODE=0
echo '{"tool_name": "mcp__codebase-memory-mcp__search_graph"}' | (cd "$FAKE_ROOT" && bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    _pass "Test 1: CMM tool exits 0 without sentinel"
else
    _fail "Test 1: CMM tool should exit 0 (got $EXIT_CODE)"
fi

# --- Test 2: Agent tool -> exit 0 (Phase 1 bypass) ---
echo "--- Test 2: Agent tool -> exit 0 (Phase 1 bypass) ---"
rm -f "$SENTINEL"
EXIT_CODE=0
echo '{"tool_name": "Agent"}' | (cd "$FAKE_ROOT" && bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    _pass "Test 2: Agent exits 0 without sentinel"
else
    _fail "Test 2: Agent should exit 0 (got $EXIT_CODE)"
fi

# --- Test 3: Bash tool -> exit 0 (Phase 2 bypass) ---
echo "--- Test 3: Bash tool -> exit 0 (Phase 2 bypass) ---"
rm -f "$SENTINEL"
EXIT_CODE=0
echo '{"tool_name": "Bash"}' | (cd "$FAKE_ROOT" && bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    _pass "Test 3: Bash exits 0 without sentinel"
else
    _fail "Test 3: Bash should exit 0 (got $EXIT_CODE)"
fi

# --- Test 4: ToolSearch -> exit 0 (Phase 1 bypass) ---
echo "--- Test 4: ToolSearch -> exit 0 (Phase 1 bypass) ---"
rm -f "$SENTINEL"
EXIT_CODE=0
echo '{"tool_name": "ToolSearch"}' | (cd "$FAKE_ROOT" && bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    _pass "Test 4: ToolSearch exits 0 without sentinel"
else
    _fail "Test 4: ToolSearch should exit 0 (got $EXIT_CODE)"
fi

# --- Test 5: SendMessage -> exit 0 (Phase 1 bypass) ---
echo "--- Test 5: SendMessage -> exit 0 (Phase 1 bypass) ---"
rm -f "$SENTINEL"
EXIT_CODE=0
echo '{"tool_name": "SendMessage"}' | (cd "$FAKE_ROOT" && bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    _pass "Test 5: SendMessage exits 0 without sentinel"
else
    _fail "Test 5: SendMessage should exit 0 (got $EXIT_CODE)"
fi

# --- Test 6: Context Mode tool -> exit 0 (Phase 2 bypass) ---
echo "--- Test 6: Context Mode tool -> exit 0 (Phase 2 bypass) ---"
rm -f "$SENTINEL"
EXIT_CODE=0
echo '{"tool_name": "mcp__context-mode__ctx_execute"}' | (cd "$FAKE_ROOT" && bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    _pass "Test 6: Context Mode tool exits 0 without sentinel"
else
    _fail "Test 6: Context Mode tool should exit 0 (got $EXIT_CODE)"
fi

# --- Test 7: Read tool -> exit 0 (Phase 2 bypass) ---
echo "--- Test 7: Read tool -> exit 0 (Phase 2 bypass) ---"
rm -f "$SENTINEL"
EXIT_CODE=0
echo '{"tool_name": "Read"}' | (cd "$FAKE_ROOT" && bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    _pass "Test 7: Read exits 0 without sentinel"
else
    _fail "Test 7: Read should exit 0 (got $EXIT_CODE)"
fi

# --- Test 8: Grep tool -> exit 0 (Phase 2 bypass) ---
echo "--- Test 8: Grep tool -> exit 0 (Phase 2 bypass) ---"
rm -f "$SENTINEL"
EXIT_CODE=0
echo '{"tool_name": "Grep"}' | (cd "$FAKE_ROOT" && bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    _pass "Test 8: Grep exits 0 without sentinel"
else
    _fail "Test 8: Grep should exit 0 (got $EXIT_CODE)"
fi

# --- Test 9: Write tool WITHOUT sentinel -> exit 2 (blocked) ---
echo "--- Test 9: Write tool WITHOUT sentinel -> exit 2 (blocked) ---"
rm -f "$SENTINEL"
EXIT_CODE=0
echo '{"tool_name": "Write"}' | (cd "$FAKE_ROOT" && bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 2 ]; then
    _pass "Test 9: Write blocked (exit 2) without sentinel"
else
    _fail "Test 9: Write should exit 2 without sentinel (got $EXIT_CODE)"
fi

# --- Test 10: Write tool WITH sentinel -> exit 0 (allowed) ---
echo "--- Test 10: Write tool WITH sentinel -> exit 0 (allowed) ---"
echo "ready" > "$SENTINEL"
EXIT_CODE=0
echo '{"tool_name": "Write"}' | (cd "$FAKE_ROOT" && bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    _pass "Test 10: Write allowed (exit 0) with sentinel"
else
    _fail "Test 10: Write should exit 0 with sentinel (got $EXIT_CODE)"
fi

# --- Test 11: Edit tool WITHOUT sentinel -> exit 2 (blocked) ---
echo "--- Test 11: Edit tool WITHOUT sentinel -> exit 2 (blocked) ---"
rm -f "$SENTINEL"
EXIT_CODE=0
echo '{"tool_name": "Edit"}' | (cd "$FAKE_ROOT" && bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 2 ]; then
    _pass "Test 11: Edit blocked (exit 2) without sentinel"
else
    _fail "Test 11: Edit should exit 2 without sentinel (got $EXIT_CODE)"
fi

# Cleanup
rm -rf "$FAKE_ROOT"
rm -f "$SENTINEL"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
