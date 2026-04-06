#!/bin/bash
# test-cmm-nudge-blocking.sh — Tests for cmm-nudge.sh hard-blocking Read gate
# Usage: bash tests/test-cmm-nudge-blocking.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/global/cmm-nudge.sh"

PASS=0; FAIL=0
# _assert_exit LABEL EXPECTED_EXIT JSON [ENV_PREFIX]
# ENV_PREFIX is optional; if set, it is prepended to the bash invocation
# (e.g. "CLAUDE_CONFIG_DIR=/tmp/fake" to override global settings lookup)
_assert_exit() {
    local label="$1" expected="$2" json="$3" env_prefix="${4:-}"
    local actual=0
    if [ -n "$env_prefix" ]; then
        echo "$json" | env $env_prefix bash "$HOOK" >/dev/null 2>&1 || actual=$?
    else
        echo "$json" | bash "$HOOK" >/dev/null 2>&1 || actual=$?
    fi
    if [ "$actual" -eq "$expected" ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (expected exit $expected, got $actual)"
        FAIL=$((FAIL+1))
    fi
}

# --- Fixture Setup ---
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Primary test project: CMM installed, git repo
PROJ="$TMPDIR_ROOT/proj"
mkdir -p "$PROJ"
git -C "$PROJ" init -q
echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"}}}' > "$PROJ/.mcp.json"

# Large code file (>50 lines) — will be blocked
for i in $(seq 1 60); do echo "line $i"; done > "$PROJ/big.py"

# Large .ts file (>50 lines) — will be blocked
for i in $(seq 1 60); do echo "// line $i"; done > "$PROJ/big.ts"

# Small code file (<50 lines) — will be allowed
echo 'print("hello")' > "$PROJ/small.py"

# Config file — should never be blocked
echo '{}' > "$PROJ/config.json"

# Markdown file — should never be blocked
echo '# Some doc' > "$PROJ/some-doc.md"

# CLAUDE.md — basename exempt
echo '# CLAUDE.md' > "$PROJ/CLAUDE.md"

# Planning path fixture
mkdir -p "$PROJ/.vbw-planning/phases/01"
for i in $(seq 1 60); do echo "plan line $i"; done > "$PROJ/.vbw-planning/phases/01/big-plan.py"

# .claude path fixture
mkdir -p "$PROJ/.claude/hooks"
for i in $(seq 1 60); do echo "hook line $i"; done > "$PROJ/.claude/hooks/some-hook.sh"

# Second project: CMM NOT in .mcp.json
PROJ_NO_CMM="$TMPDIR_ROOT/proj-no-cmm"
mkdir -p "$PROJ_NO_CMM"
git -C "$PROJ_NO_CMM" init -q
echo '{"mcpServers":{"some-other-mcp":{"command":"npx"}}}' > "$PROJ_NO_CMM/.mcp.json"
for i in $(seq 1 60); do echo "line $i"; done > "$PROJ_NO_CMM/big.py"

# Third project: No .mcp.json at all
PROJ_NO_MCP="$TMPDIR_ROOT/proj-no-mcp"
mkdir -p "$PROJ_NO_MCP"
git -C "$PROJ_NO_MCP" init -q
for i in $(seq 1 60); do echo "line $i"; done > "$PROJ_NO_MCP/big.py"

# Fake CLAUDE_CONFIG_DIR without CMM — used by tests 9+10 to suppress global fallback
FAKE_CONFIG="$TMPDIR_ROOT/fake-claude-config"
mkdir -p "$FAKE_CONFIG"
echo '{"hooks":{}}' > "$FAKE_CONFIG/settings.json"

# --- Tests ---

echo "--- Test 1: Large .py file blocked (exit 2) ---"
_assert_exit "Test 1: large .py blocked" 2 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\"}}"

echo "--- Test 2: Large .ts file blocked (exit 2) ---"
_assert_exit "Test 2: large .ts blocked" 2 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.ts\"}}"

echo "--- Test 3: Small .py file allowed (exit 0) ---"
_assert_exit "Test 3: small .py allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/small.py\"}}"

echo "--- Test 4: Config file (.json) allowed (exit 0) ---"
_assert_exit "Test 4: config .json allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/config.json\"}}"

echo "--- Test 5: Markdown file (.md) allowed (exit 0) ---"
_assert_exit "Test 5: markdown .md allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/some-doc.md\"}}"

echo "--- Test 6: CLAUDE.md basename exempt (exit 0) ---"
_assert_exit "Test 6: CLAUDE.md exempt" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/CLAUDE.md\"}}"

echo "--- Test 7: Planning path exempt (exit 0) ---"
_assert_exit "Test 7: .vbw-planning path exempt" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/.vbw-planning/phases/01/big-plan.py\"}}"

echo "--- Test 8: .claude/ path exempt (exit 0) ---"
_assert_exit "Test 8: .claude path exempt" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/.claude/hooks/some-hook.sh\"}}"

echo "--- Test 9: CMM not in .mcp.json -> allowed (exit 0) ---"
_assert_exit "Test 9: no CMM in .mcp.json allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ_NO_CMM/big.py\"}}" \
    "CLAUDE_CONFIG_DIR=$FAKE_CONFIG"

echo "--- Test 10: No .mcp.json at all -> allowed (exit 0) ---"
_assert_exit "Test 10: no .mcp.json allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ_NO_MCP/big.py\"}}" \
    "CLAUDE_CONFIG_DIR=$FAKE_CONFIG"

echo "--- Test 11: Top-level file_path fallback (exit 2) ---"
_assert_exit "Test 11: top-level file_path blocked" 2 \
    "{\"file_path\":\"$PROJ/big.py\"}"

echo "--- Test 12: Targeted Read with offset+limit -> allowed (exit 0) ---"
_assert_exit "Test 12: offset+limit allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":100,\"limit\":20}}"

echo "--- Test 13: Non-existent file -> allowed (exit 0) ---"
_assert_exit "Test 13: non-existent file allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/does-not-exist.py\"}}"

echo "--- Test 14: Large offset+limit (>100 lines) -> blocked (exit 2) ---"
_assert_exit "Test 14: large limit still blocked" 2 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":0,\"limit\":500}}"

echo "--- Test 15: Offset only (no limit) -> blocked (exit 2) ---"
_assert_exit "Test 15: offset-only still blocked" 2 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":10}}"

echo "--- Test 16: Limit only (no offset) -> blocked (exit 2) ---"
_assert_exit "Test 16: limit-only still blocked" 2 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"limit\":20}}"

echo "--- Test 17: offset=0, limit=100 on large .py -> blocked (primary bypass closed) ---"
_assert_exit "Test 17: offset=0 limit=100 blocked" 2 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":0,\"limit\":100}}"

echo "--- Test 18: offset=0, limit=50 on large .py -> blocked (secondary bypass closed) ---"
_assert_exit "Test 18: offset=0 limit=50 blocked" 2 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":0,\"limit\":50}}"

echo "--- Test 19: offset=0, limit=30 on large .py -> allowed (imports/headers) ---"
_assert_exit "Test 19: offset=0 limit=30 allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":0,\"limit\":30}}"

echo "--- Test 20: offset=50, limit=40 on large .py -> allowed (legitimate targeted read) ---"
_assert_exit "Test 20: offset=50 limit=40 allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":50,\"limit\":40}}"

echo "--- Test 21: offset=0, limit=5 on large .py -> allowed (shebang/header read) ---"
_assert_exit "Test 21: offset=0 limit=5 allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":0,\"limit\":5}}"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
