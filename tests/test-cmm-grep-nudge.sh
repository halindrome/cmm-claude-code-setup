#!/bin/bash
# test-cmm-grep-nudge.sh — Tests for cmm-grep-nudge.sh hard-blocking Grep gate
# Usage: bash tests/test-cmm-grep-nudge.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/global/cmm-grep-nudge.sh"

PASS=0; FAIL=0
# _assert_exit LABEL EXPECTED_EXIT JSON [ENV_PREFIX]
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

# A real Python file (for single-file path tests)
echo 'def foo(): pass' > "$PROJ/module.py"

# Fake CLAUDE_CONFIG_DIR without CMM — suppresses global fallback
FAKE_CONFIG="$TMPDIR_ROOT/fake-claude-config"
mkdir -p "$FAKE_CONFIG"
echo '{"hooks":{}}' > "$FAKE_CONFIG/settings.json"

# Project without CMM
PROJ_NO_CMM="$TMPDIR_ROOT/proj-no-cmm"
mkdir -p "$PROJ_NO_CMM"
git -C "$PROJ_NO_CMM" init -q
echo '{"mcpServers":{"some-other-mcp":{"command":"npx"}}}' > "$PROJ_NO_CMM/.mcp.json"

# Project with no .mcp.json
PROJ_NO_MCP="$TMPDIR_ROOT/proj-no-mcp"
mkdir -p "$PROJ_NO_MCP"
git -C "$PROJ_NO_MCP" init -q

# --- Tests ---

echo "--- Test 1: Unscoped Grep (no path, no glob) -> blocked ---"
_assert_exit "Test 1: unscoped Grep blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"def foo\"}}"

echo "--- Test 2: Grep with code glob *.py -> blocked ---"
_assert_exit "Test 2: *.py glob blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"def foo\",\"glob\":\"*.py\"}}"

echo "--- Test 3: Grep with code glob *.ts -> blocked ---"
_assert_exit "Test 3: *.ts glob blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"export\",\"glob\":\"*.ts\"}}"

echo "--- Test 4: Grep with non-code glob *.json -> allowed ---"
_assert_exit "Test 4: *.json glob allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"key\",\"glob\":\"*.json\"}}"

echo "--- Test 5: Grep with non-code glob *.md -> allowed ---"
_assert_exit "Test 5: *.md glob allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"TODO\",\"glob\":\"*.md\"}}"

echo "--- Test 6: Grep with path pointing to a directory -> blocked ---"
_assert_exit "Test 6: directory path blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"def foo\",\"path\":\"$PROJ\"}}"

echo "--- Test 7: Grep with path pointing to a specific .py file -> allowed ---"
_assert_exit "Test 7: single-file path allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"def foo\",\"path\":\"$PROJ/module.py\"}}"

echo "--- Test 8: Grep in .vbw-planning/ path -> allowed ---"
_assert_exit "Test 8: .vbw-planning path allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"phase\",\"path\":\"$PROJ/.vbw-planning/phases\"}}"

echo "--- Test 9: Grep with type=python (code type) -> blocked ---"
_assert_exit "Test 9: type=python blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"def foo\",\"type\":\"python\"}}"

echo "--- Test 10: Grep with type=json (non-code type) -> allowed ---"
_assert_exit "Test 10: type=json allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"key\",\"type\":\"json\"}}"

echo "--- Test 11: CMM not in .mcp.json -> allowed (fail open) ---"
_assert_exit "Test 11: no CMM in .mcp.json allowed" 0 \
    "{\"cwd\":\"$PROJ_NO_CMM\",\"tool_input\":{\"pattern\":\"def foo\"}}" \
    "CLAUDE_CONFIG_DIR=$FAKE_CONFIG"

echo "--- Test 12: No .mcp.json at all -> allowed (fail open) ---"
_assert_exit "Test 12: no .mcp.json allowed" 0 \
    "{\"cwd\":\"$PROJ_NO_MCP\",\"tool_input\":{\"pattern\":\"def foo\"}}" \
    "CLAUDE_CONFIG_DIR=$FAKE_CONFIG"

echo "--- Test 13: Empty pattern -> allowed (fail open) ---"
_assert_exit "Test 13: empty pattern allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"\"}}"

echo "--- Test 14: path containing node_modules/ -> allowed ---"
_assert_exit "Test 14: node_modules path allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"require\",\"path\":\"$PROJ/node_modules/lodash\"}}"

echo "--- Test 15: Grep with code glob *.sh -> blocked ---"
_assert_exit "Test 15: *.sh glob blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"exit 2\",\"glob\":\"*.sh\"}}"

echo "--- Test 16: Grep with non-code glob *.yaml -> allowed ---"
_assert_exit "Test 16: *.yaml glob allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"version\",\"glob\":\"*.yaml\"}}"

echo "--- Test 17: Grep with *.rb (is-cmm-ext language) -> blocked ---"
_assert_exit "Test 17: *.rb glob blocked (is-cmm-ext coverage)" 2 \
    "{\"tool_input\":{\"pattern\":\"def \",\"glob\":\"*.rb\"}}"

echo "--- Test 18: Grep with *.kt (Kotlin, is-cmm-ext language) -> blocked ---"
_assert_exit "Test 18: *.kt glob blocked (is-cmm-ext coverage)" 2 \
    "{\"tool_input\":{\"pattern\":\"fun \",\"glob\":\"*.kt\"}}"

echo "--- Test 19: Grep with *.log (not a CMM language) -> allowed ---"
_assert_exit "Test 19: *.log glob allowed (not a CMM language)" 0 \
    "{\"tool_input\":{\"pattern\":\"ERROR\",\"glob\":\"*.log\"}}"

echo "--- Test 20: Grep with nested glob src/**/*.ts -> blocked ---"
_assert_exit "Test 20: src/**/*.ts blocked (nested glob)" 2 \
    "{\"tool_input\":{\"pattern\":\"export\",\"glob\":\"src/**/*.ts\"}}"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
