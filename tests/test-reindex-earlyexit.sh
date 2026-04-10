#!/bin/bash
# test-reindex-earlyexit.sh — Tests reindex-after-commit pre-traversal early exit
# Verifies fast exit for non-commit Bash calls and correct handling of git commit variants.
# Usage: bash tests/test-reindex-earlyexit.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/project/reindex-after-commit.sh"

PASS=0; FAIL=0
_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Setup: fake git repo and sentinel
FAKE_ROOT=$(mktemp -d /tmp/cmm-test-root-XXXXXX)
FAKE_CONFIG=$(mktemp -d /tmp/cmm-test-config-XXXXXX)
git -C "$FAKE_ROOT" init -q
git -C "$FAKE_ROOT" commit --allow-empty -q -m "init"

# Copy hook into fake root for path integrity
mkdir -p "$FAKE_ROOT/hooks/project"
cp "$HOOK" "$FAKE_ROOT/hooks/project/reindex-after-commit.sh"
HOOK="$FAKE_ROOT/hooks/project/reindex-after-commit.sh"

# Compute hash the same way the hook does
RESOLVED_ROOT="$(cd "$FAKE_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"
if command -v md5sum >/dev/null 2>&1; then
    HASH=$(echo "$RESOLVED_ROOT" | md5sum | awk '{print $1}')
else
    HASH=$(echo "$RESOLVED_ROOT" | md5 -q)
fi
SENTINEL="/tmp/cmm-session-ready-${HASH}"

# --- Test 1: git status -> exit 0 (fast path, no commit) ---
echo "--- Test 1: git status -> exit 0 (fast path) ---"
EXIT_CODE=0
echo '{"tool_input":{"command":"git status"},"tool_output":{"stdout":"On branch main"}}' | (cd "$FAKE_ROOT" && CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    _pass "Test 1: git status exits 0 (fast path)"
else
    _fail "Test 1: git status should exit 0 (got $EXIT_CODE)"
fi

# --- Test 2: ls -la -> exit 0 (fast path, no commit) ---
echo "--- Test 2: ls -la -> exit 0 (fast path) ---"
EXIT_CODE=0
echo '{"tool_input":{"command":"ls -la"},"tool_output":{"stdout":"total 0"}}' | (cd "$FAKE_ROOT" && CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    _pass "Test 2: ls -la exits 0 (fast path)"
else
    _fail "Test 2: ls -la should exit 0 (got $EXIT_CODE)"
fi

# --- Test 3: cat file.txt -> exit 0 (fast path) ---
echo "--- Test 3: cat file.txt -> exit 0 (fast path) ---"
EXIT_CODE=0
echo '{"tool_input":{"command":"cat file.txt"},"tool_output":{"stdout":"hello"}}' | (cd "$FAKE_ROOT" && CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    _pass "Test 3: cat exits 0 (fast path)"
else
    _fail "Test 3: cat should exit 0 (got $EXIT_CODE)"
fi

# --- Test 4: git commit -m test -> sentinel marked stale ---
echo "--- Test 4: git commit -m test -> sentinel marked stale ---"
echo "ready" > "$SENTINEL"
EXIT_CODE=0
echo '{"tool_input":{"command":"git commit -m test"},"tool_output":{"stdout":"[main abc1234] test 1 file changed"}}' | (cd "$FAKE_ROOT" && CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$(cat "$SENTINEL" 2>/dev/null)" = "stale" ]; then
    _pass "Test 4: git commit marks sentinel stale"
else
    _fail "Test 4: git commit should mark sentinel stale (got: '$(cat "$SENTINEL" 2>/dev/null)')"
fi

# --- Test 5: git commit --amend -> sentinel marked stale ---
echo "--- Test 5: git commit --amend -> sentinel marked stale ---"
echo "ready" > "$SENTINEL"
EXIT_CODE=0
echo '{"tool_input":{"command":"git commit --amend --no-edit"},"tool_output":{"stdout":"[main abc1234] amended 1 file changed"}}' | (cd "$FAKE_ROOT" && CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$(cat "$SENTINEL" 2>/dev/null)" = "stale" ]; then
    _pass "Test 5: git commit --amend marks sentinel stale"
else
    _fail "Test 5: git commit --amend should mark sentinel stale (got: '$(cat "$SENTINEL" 2>/dev/null)')"
fi

# --- Test 6: git diff -> exit 0 (fast path, "git" present but not "git commit") ---
echo "--- Test 6: git diff -> exit 0 (fast path) ---"
EXIT_CODE=0
echo '{"tool_input":{"command":"git diff HEAD~1"},"tool_output":{"stdout":"+added line"}}' | (cd "$FAKE_ROOT" && CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    _pass "Test 6: git diff exits 0 (fast path)"
else
    _fail "Test 6: git diff should exit 0 (got $EXIT_CODE)"
fi

# --- Test 7: npm run build -> exit 0 (fast path, no commit substring) ---
echo "--- Test 7: npm run build -> exit 0 (fast path) ---"
EXIT_CODE=0
echo '{"tool_input":{"command":"npm run build"},"tool_output":{"stdout":"done"}}' | (cd "$FAKE_ROOT" && CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    _pass "Test 7: npm run build exits 0 (fast path)"
else
    _fail "Test 7: npm run build should exit 0 (got $EXIT_CODE)"
fi

# --- Test 8: git log --oneline -> exit 0 (has "git" but not "git commit") ---
echo "--- Test 8: git log -> exit 0 (fast path) ---"
EXIT_CODE=0
echo '{"tool_input":{"command":"git log --oneline -5"},"tool_output":{"stdout":"abc1234 test"}}' | (cd "$FAKE_ROOT" && CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    _pass "Test 8: git log exits 0 (fast path)"
else
    _fail "Test 8: git log should exit 0 (got $EXIT_CODE)"
fi

# --- Test 9: "nothing to commit" output -> exit 0 (false positive guard) ---
echo "--- Test 9: nothing to commit -> exit 0 (false positive guard) ---"
echo "ready" > "$SENTINEL"
EXIT_CODE=0
echo '{"tool_input":{"command":"git commit -m test"},"tool_output":{"stdout":"nothing to commit, working tree clean"}}' | (cd "$FAKE_ROOT" && CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$HOOK") 2>/dev/null || EXIT_CODE=$?
if [ "$(cat "$SENTINEL" 2>/dev/null)" = "ready" ]; then
    _pass "Test 9: nothing-to-commit preserves sentinel"
else
    _fail "Test 9: nothing-to-commit should not mark stale (got: '$(cat "$SENTINEL" 2>/dev/null)')"
fi

# Cleanup
rm -rf "$FAKE_ROOT" "$FAKE_CONFIG"
rm -f "$SENTINEL"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
