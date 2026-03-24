#!/bin/bash
# test-team-mode-bypass.sh — Tests team-mode suppression and SUBAGENT_COMMIT=1 override
# Usage: bash tests/test-team-mode-bypass.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/project/reindex-after-commit.sh"

PASS=0; FAIL=0
_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Setup: fake config dir and a git repo for project root resolution
FAKE_CONFIG=$(mktemp -d /tmp/cmm-test-config-XXXXXX)
FAKE_ROOT=$(mktemp -d /tmp/cmm-test-root-XXXXXX)

# Init a minimal git repo so git rev-parse works in the hook
git -C "$FAKE_ROOT" init -q
git -C "$FAKE_ROOT" commit --allow-empty -q -m "init"

# Compute hash the same way the hook does (PROJECT_ROOT from git rev-parse, no -n)
RESOLVED_ROOT="$(cd "$FAKE_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"
if command -v md5sum >/dev/null 2>&1; then
    HASH=$(echo "$RESOLVED_ROOT" | md5sum | awk '{print $1}')
else
    HASH=$(echo "$RESOLVED_ROOT" | md5 -q)
fi
SENTINEL="/tmp/cmm-session-ready-${HASH}"

# Mock commit JSON that passes all guards in the hook
COMMIT_JSON='{"tool_input":{"command":"git commit -m \"test\""},"tool_output":{"stdout":"[main abc1234] test\n 1 file changed"}}'

echo "--- Test 1: Normal mode (no team directory) -> sentinel written as stale ---"
rm -f "$SENTINEL"
echo "$COMMIT_JSON" | (cd "$FAKE_ROOT" && CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$HOOK") 2>/dev/null || true
if [ "$(cat "$SENTINEL" 2>/dev/null)" = "stale" ]; then
    _pass "Test 1: Sentinel written as stale in normal mode"
else
    _fail "Test 1: Sentinel not written as stale in normal mode (got: '$(cat "$SENTINEL" 2>/dev/null)')"
fi

echo "--- Test 2: Team-mode active -> sentinel NOT written as stale ---"
mkdir -p "$FAKE_CONFIG/teams/vbw-test-team"
rm -f "$SENTINEL"
echo "$COMMIT_JSON" | (cd "$FAKE_ROOT" && CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$HOOK") 2>/dev/null || true
if [ "$(cat "$SENTINEL" 2>/dev/null)" != "stale" ]; then
    _pass "Test 2: Sentinel NOT written as stale in team-mode"
else
    _fail "Test 2: Sentinel was incorrectly written as stale in team-mode"
fi

echo "--- Test 3: Team-mode + SUBAGENT_COMMIT=1 -> sentinel IS written as stale ---"
rm -f "$SENTINEL"
echo "$COMMIT_JSON" | (cd "$FAKE_ROOT" && CLAUDE_CONFIG_DIR="$FAKE_CONFIG" SUBAGENT_COMMIT=1 bash "$HOOK") 2>/dev/null || true
if [ "$(cat "$SENTINEL" 2>/dev/null)" = "stale" ]; then
    _pass "Test 3: Sentinel written as stale with SUBAGENT_COMMIT=1 override"
else
    _fail "Test 3: SUBAGENT_COMMIT=1 override did not write sentinel as stale"
fi

# Cleanup
rm -rf "$FAKE_CONFIG" "$FAKE_ROOT"
rm -f "$SENTINEL"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
