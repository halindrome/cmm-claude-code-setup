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
mkdir -p "$PROJ/src"
git -C "$PROJ" init -q
echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"}}}' > "$PROJ/.mcp.json"

# Create a code file for path-based tests
echo 'print("hello")' > "$PROJ/src/main.py"

# Planning path fixture
mkdir -p "$PROJ/.vbw-planning/phases"
echo 'plan content' > "$PROJ/.vbw-planning/phases/plan.py"

# .claude path fixture
mkdir -p "$PROJ/.claude/hooks"
echo 'hook content' > "$PROJ/.claude/hooks/some-hook.sh"

# Second project: CMM NOT in .mcp.json
PROJ_NO_CMM="$TMPDIR_ROOT/proj-no-cmm"
mkdir -p "$PROJ_NO_CMM"
git -C "$PROJ_NO_CMM" init -q
echo '{"mcpServers":{"some-other-mcp":{"command":"npx"}}}' > "$PROJ_NO_CMM/.mcp.json"

# Fake CLAUDE_CONFIG_DIR without CMM — suppresses global fallback
FAKE_CONFIG="$TMPDIR_ROOT/fake-claude-config"
mkdir -p "$FAKE_CONFIG"
echo '{"hooks":{}}' > "$FAKE_CONFIG/settings.json"

# --- Tests ---

echo "--- Test 1: Grep with glob=*.py blocked (exit 2) ---"
_assert_exit "Test 1: glob=*.py blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"def handler\",\"glob\":\"*.py\",\"path\":\"$PROJ\"}}"

echo "--- Test 2: Grep with glob=*.ts blocked (exit 2) ---"
_assert_exit "Test 2: glob=*.ts blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"export\",\"glob\":\"*.ts\",\"path\":\"$PROJ\"}}"

echo "--- Test 3: Grep with type=sh blocked (exit 2) ---"
_assert_exit "Test 3: type=sh blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"function\",\"type\":\"sh\",\"path\":\"$PROJ\"}}"

echo "--- Test 4: Grep with glob=*.json allowed (exit 0) ---"
_assert_exit "Test 4: glob=*.json allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"version\",\"glob\":\"*.json\",\"path\":\"$PROJ\"}}"

echo "--- Test 5: Grep with glob=*.md allowed (exit 0) ---"
_assert_exit "Test 5: glob=*.md allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"TODO\",\"glob\":\"*.md\",\"path\":\"$PROJ\"}}"

echo "--- Test 6: Grep with glob=*.yaml allowed (exit 0) ---"
_assert_exit "Test 6: glob=*.yaml allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"port\",\"glob\":\"*.yaml\",\"path\":\"$PROJ\"}}"

echo "--- Test 7: Grep targeting .vbw-planning/ allowed (exit 0) ---"
_assert_exit "Test 7: .vbw-planning path allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"plan\",\"glob\":\"*.py\",\"path\":\"$PROJ/.vbw-planning/phases\"}}"

echo "--- Test 8: Grep targeting .claude/ allowed (exit 0) ---"
_assert_exit "Test 8: .claude path allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"hook\",\"glob\":\"*.sh\",\"path\":\"$PROJ/.claude/hooks\"}}"

echo "--- Test 9: Grep with no glob/type/path allowed (exit 0) ---"
_assert_exit "Test 9: bare pattern allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"something\"}}"

echo "--- Test 10: Grep without CMM allowed (exit 0) ---"
_assert_exit "Test 10: no CMM glob=*.py allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"def handler\",\"glob\":\"*.py\",\"path\":\"$PROJ_NO_CMM\"}}" \
    "CLAUDE_CONFIG_DIR=$FAKE_CONFIG"

echo "--- Test 11: Grep on code file path blocked (exit 2) ---"
_assert_exit "Test 11: code file path blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"TODO\",\"path\":\"$PROJ/src/main.py\"}}"

echo "--- Test 12: Grep with glob=*.tsx blocked (exit 2) ---"
_assert_exit "Test 12: glob=*.tsx blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"import\",\"glob\":\"*.tsx\",\"path\":\"$PROJ\"}}"

# --- Bash navigation block tests (c1-c5) ---
# The Bash block requires the CMM sentinel to be present (indexed state).
# Compute the sentinel path using the normalized (realpath) form — the hook
# resolves symlinks via `cd ... && pwd -P` before hashing (macOS /var/folders fix).
PROJ_REAL=$(cd "$PROJ" && pwd -P)
PROJ_HASH=$(echo "$PROJ_REAL" | md5 -q 2>/dev/null || echo "$PROJ_REAL" | md5sum | awk '{print $1}')
BASH_SENTINEL="/tmp/cmm-session-ready-${PROJ_HASH}"
# Create sentinel (mark as ready)
echo "ready" > "$BASH_SENTINEL"
trap 'rm -rf "$TMPDIR_ROOT" "$BASH_SENTINEL"' EXIT

echo "--- Test c1: Bash grep against src/ + CMM ready -> exit 2 (BLOCKED) ---"
_assert_exit "c1: Bash grep src/ blocked" 2 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep -r 'parse' src/\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c2: Bash grep with # cmm-exempt -> exit 0 (bypass) ---"
_assert_exit "c2: Bash grep src/ cmm-exempt allowed" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep -r 'parse' src/ # cmm-exempt\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c3: Bash find against hooks/ -> exit 2 (BLOCKED) ---"
_assert_exit "c3: Bash find hooks/ blocked" 2 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"find hooks/ -name '*.sh'\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c4: Bash echo (non-navigation) -> exit 0 ---"
_assert_exit "c4: Bash echo allowed" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hello\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c5: Bash grep against src/ with CMM absent -> exit 0 (fail-open) ---"
# Remove sentinel so CMM appears not indexed
rm -f "$BASH_SENTINEL"
_assert_exit "c5: Bash grep src/ CMM absent allowed" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep -r 'parse' src/\"},\"cwd\":\"$PROJ_NO_CMM\"}" \
    "CLAUDE_CONFIG_DIR=$FAKE_CONFIG"
# Restore sentinel for any subsequent tests
echo "ready" > "$BASH_SENTINEL"

# --- Write / heredoc false-positive tests (c6-c9) ---
# Regression: a write (output redirection > / >> or a heredoc <<) is NOT code
# navigation. The gate must inspect only the command HEAD (before the first
# redirection), so write targets and heredoc bodies cannot trip it — even when
# the body contains a source-path token. Previously `cat > x.gd <<EOF ... EOF`
# false-positived because `cat` matched the verb and a path token in the body
# matched the source-path regex.

echo "--- Test c6: Bash heredoc write with src path in body -> exit 0 (ALLOW) ---"
_assert_exit "c6: heredoc write allowed" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat > /tmp/dump_desk.gd <<'EOF'\nextends Node\nscripts/foo\nEOF\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c7: Bash grep src/ with output redirected -> exit 2 (BLOCKED) ---"
_assert_exit "c7: redirected grep src/ still blocked" 2 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep -rn foo src/ > /tmp/out\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c8: Bash cat of a source file -> exit 2 (BLOCKED) ---"
_assert_exit "c8: cat src file still blocked" 2 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat src/main.py\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c9: Bash bare heredoc (no redirect) with lib path in body -> exit 0 (ALLOW) ---"
_assert_exit "c9: bare heredoc allowed" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat <<'EOF'\nlib/ helpers\nEOF\"},\"cwd\":\"$PROJ_REAL\"}"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
