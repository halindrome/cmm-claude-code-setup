#!/bin/bash
# test-index-root-gate.sh — Tests for index-root-gate.sh PreToolUse hard-block on index_repository
# Usage: bash tests/test-index-root-gate.sh
# Exit: 0 = all pass, 1 = any failure
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/project/index-root-gate.sh"

PASS=0; FAIL=0

# _assert_exit LABEL EXPECTED_EXIT JSON RUN_DIR [EXTRA_ENV]
# Runs the hook in a subshell cd'd to RUN_DIR so $PWD (and git root) is correct.
_assert_exit() {
    local label="$1" expected="$2" json="$3" run_dir="$4" extra_env="${5:-}"
    local actual=0
    if [ -n "$extra_env" ]; then
        (cd "$run_dir" && echo "$json" | env $extra_env bash "$HOOK" >/dev/null 2>&1) || actual=$?
    else
        (cd "$run_dir" && echo "$json" | bash "$HOOK" >/dev/null 2>&1) || actual=$?
    fi
    if [ "$actual" -eq "$expected" ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (expected exit $expected, got $actual)"
        FAIL=$((FAIL+1))
    fi
}

# _assert_stderr_grep LABEL JSON RUN_DIR REGEX [EXTRA_ENV]
# Passes when stderr matches REGEX (via grep -E).
_assert_stderr_grep() {
    local label="$1" json="$2" run_dir="$3" regex="$4" extra_env="${5:-}"
    local err
    if [ -n "$extra_env" ]; then
        err=$((cd "$run_dir" && echo "$json" | env $extra_env bash "$HOOK" 2>&1 >/dev/null) || true)
    else
        err=$((cd "$run_dir" && echo "$json" | bash "$HOOK" 2>&1 >/dev/null) || true)
    fi
    if echo "$err" | grep -Eq "$regex"; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (stderr did not match: $regex)"
        echo "    stderr: $err"
        FAIL=$((FAIL+1))
    fi
}

# --- Fixture setup ---
TMPDIR_ROOT=$(mktemp -d)

# Primary test project: git repo with CMM registered in root
PROJ="$TMPDIR_ROOT/monorepo"
mkdir -p "$PROJ/apps/rest-api"
git -C "$PROJ" init -q
git -C "$PROJ" config user.email "test@test.com"
git -C "$PROJ" config user.name "Test"
echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"}}}' > "$PROJ/.mcp.json"

# Canonicalize PROJ (on macOS /var -> /private/var)
PROJ_CANON=$(cd "$PROJ" && pwd -P)
PROJ_PARENT=$(dirname "$PROJ_CANON")

# Second project: no CMM registration
PROJ_NO_CMM="$TMPDIR_ROOT/proj-no-cmm"
mkdir -p "$PROJ_NO_CMM/src"
git -C "$PROJ_NO_CMM" init -q
echo '{"mcpServers":{"some-other-mcp":{"command":"npx"}}}' > "$PROJ_NO_CMM/.mcp.json"
PROJ_NO_CMM_CANON=$(cd "$PROJ_NO_CMM" && pwd -P)

# Fake CLAUDE_CONFIG_DIR — suppresses global fallback CMM detection
FAKE_CONFIG="$TMPDIR_ROOT/fake-claude-config"
mkdir -p "$FAKE_CONFIG"
echo '{"hooks":{}}' > "$FAKE_CONFIG/settings.json"
ENV_NO_GLOBAL="CLAUDE_CONFIG_DIR=$FAKE_CONFIG HOME=$TMPDIR_ROOT"

# Cleanup on exit
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Bail out early if hook is missing
if [ ! -f "$HOOK" ]; then
    echo "NOTE: $HOOK does not exist yet."
    echo "Results: $PASS passed, $FAIL failed"
    exit 1
fi

# --- Tests ---

echo "--- 1: descendant repo_path blocked (exit 2) ---"
_assert_exit "descendant path exits 2" 2 \
    "{\"tool_input\":{\"repo_path\":\"${PROJ_CANON}/apps/rest-api\"}}" \
    "$PROJ_CANON" \
    "$ENV_NO_GLOBAL"

echo "--- 2: descendant path emits BLOCKED header in stderr ---"
_assert_stderr_grep "descendant stderr [index-root-gate] BLOCKED" \
    "{\"tool_input\":{\"repo_path\":\"${PROJ_CANON}/apps/rest-api\"}}" \
    "$PROJ_CANON" \
    '\[index-root-gate\] BLOCKED' \
    "$ENV_NO_GLOBAL"

echo "--- 3: descendant stderr names PROJECT_ROOT ---"
_assert_stderr_grep "descendant stderr names project root" \
    "{\"tool_input\":{\"repo_path\":\"${PROJ_CANON}/apps/rest-api\"}}" \
    "$PROJ_CANON" \
    "$PROJ_CANON" \
    "$ENV_NO_GLOBAL"

echo "--- 4: descendant stderr names corrective instruction (re-issue at root) ---"
_assert_stderr_grep "descendant stderr corrective instruction" \
    "{\"tool_input\":{\"repo_path\":\"${PROJ_CANON}/apps/rest-api\"}}" \
    "$PROJ_CANON" \
    'Re-issue.*index_repository' \
    "$ENV_NO_GLOBAL"

echo "--- 5: root path (repo_path == PROJECT_ROOT) allowed (exit 0) ---"
_assert_exit "root path allowed" 0 \
    "{\"tool_input\":{\"repo_path\":\"${PROJ_CANON}\"}}" \
    "$PROJ_CANON" \
    "$ENV_NO_GLOBAL"

echo "--- 6: parent/ancestor path allowed (exit 0) ---"
_assert_exit "parent path allowed" 0 \
    "{\"tool_input\":{\"repo_path\":\"${PROJ_PARENT}\"}}" \
    "$PROJ_CANON" \
    "$ENV_NO_GLOBAL"

echo "--- 7: CMM absent fail-open (exit 0) ---"
# repo_path is a descendant but CMM not registered — must fail open
_assert_exit "CMM absent fail-open" 0 \
    "{\"tool_input\":{\"repo_path\":\"${PROJ_NO_CMM_CANON}/src\"}}" \
    "$PROJ_NO_CMM_CANON" \
    "$ENV_NO_GLOBAL"

echo "--- 8: unresolved PROJECT_ROOT fail-open (stub project-root.sh returns empty) ---"
# Create a hook copy with a stub lib/ that exports PROJECT_ROOT=""
STUB_DIR="$TMPDIR_ROOT/stub-hook"
mkdir -p "$STUB_DIR/lib"
cp "$HOOK" "$STUB_DIR/index-root-gate-stub.sh"
chmod +x "$STUB_DIR/index-root-gate-stub.sh"
cat > "$STUB_DIR/lib/project-root.sh" <<'STUB'
#!/bin/bash
PROJECT_ROOT=""
PROJECT_HASH=""
export PROJECT_ROOT PROJECT_HASH
_PROJECT_ROOT_LOADED=1
STUB
# Place a .mcp.json in stub dir so CMM probe passes (if we get that far)
echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"}}}' > "$STUB_DIR/.mcp.json"
actual_stub=0
(cd "$STUB_DIR" && \
    echo "{\"tool_input\":{\"repo_path\":\"${STUB_DIR}/sub\"}}" | \
    env CLAUDE_CONFIG_DIR="$FAKE_CONFIG" HOME="$TMPDIR_ROOT" \
    bash "$STUB_DIR/index-root-gate-stub.sh" >/dev/null 2>&1) || actual_stub=$?
if [ "$actual_stub" -eq 0 ]; then
    echo "PASS: unresolved PROJECT_ROOT fail-open (exit 0)"
    PASS=$((PASS+1))
else
    echo "FAIL: unresolved PROJECT_ROOT fail-open (expected 0, got $actual_stub)"
    FAIL=$((FAIL+1))
fi

echo "--- 9: empty stdin fail-open (exit 0) ---"
actual=0
(cd "$PROJ_CANON" && env $ENV_NO_GLOBAL bash "$HOOK" < /dev/null >/dev/null 2>&1) || actual=$?
if [ "$actual" -eq 0 ]; then
    echo "PASS: empty stdin fail-open"
    PASS=$((PASS+1))
else
    echo "FAIL: empty stdin fail-open (got $actual)"
    FAIL=$((FAIL+1))
fi

echo "--- 10: malformed JSON fail-open (exit 0) ---"
_assert_exit "malformed JSON fail-open" 0 \
    "this-is-not-json" \
    "$PROJ_CANON" \
    "$ENV_NO_GLOBAL"

echo "--- 11: empty repo_path fail-open (exit 0) ---"
_assert_exit "empty repo_path fail-open" 0 \
    '{"tool_input":{"repo_path":""}}' \
    "$PROJ_CANON" \
    "$ENV_NO_GLOBAL"

echo "--- 12: CLAUDE_TOOL_INPUT env var takes precedence over stdin ---"
actual=0
(cd "$PROJ_CANON" && \
    env $ENV_NO_GLOBAL \
    "CLAUDE_TOOL_INPUT={\"tool_input\":{\"repo_path\":\"${PROJ_CANON}/apps/rest-api\"}}" \
    bash "$HOOK" < /dev/null >/dev/null 2>&1) || actual=$?
if [ "$actual" -eq 2 ]; then
    echo "PASS: CLAUDE_TOOL_INPUT env var used (exit 2)"
    PASS=$((PASS+1))
else
    echo "FAIL: CLAUDE_TOOL_INPUT env var not used (expected 2, got $actual)"
    FAIL=$((FAIL+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
