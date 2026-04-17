#!/bin/bash
# test-grep-cmm-gate.sh — Tests for grep-cmm-gate.sh PreToolUse hard-block on Grep
# Usage: bash tests/test-grep-cmm-gate.sh
# Exit: 0 = all pass, 1 = any failure
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/project/grep-cmm-gate.sh"

PASS=0; FAIL=0

# _md5 STRING — echo md5 hex for STRING, portable across macOS/Linux
_md5() {
    # Match hook's hashing: `echo "$REPO_ROOT" | md5 -q` (trailing newline included).
    if command -v md5 >/dev/null 2>&1; then
        echo "$1" | md5 -q
    else
        echo "$1" | md5sum | awk '{print $1}'
    fi
}

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

# _assert_stderr_grep LABEL JSON REGEX [ENV_PREFIX]
# Passes when stderr matches REGEX (via grep -E).
_assert_stderr_grep() {
    local label="$1" json="$2" regex="$3" env_prefix="${4:-}"
    local err
    if [ -n "$env_prefix" ]; then
        err=$(echo "$json" | env $env_prefix bash "$HOOK" 2>&1 >/dev/null || true)
    else
        err=$(echo "$json" | bash "$HOOK" 2>&1 >/dev/null || true)
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

# _assert_stderr_order LABEL JSON FIRST_REGEX SECOND_REGEX
# Passes when FIRST_REGEX line appears before SECOND_REGEX in stderr.
_assert_stderr_order() {
    local label="$1" json="$2" first="$3" second="$4"
    local err first_ln second_ln
    err=$(echo "$json" | bash "$HOOK" 2>&1 >/dev/null || true)
    first_ln=$(echo "$err" | grep -nE "$first" | head -1 | cut -d: -f1)
    second_ln=$(echo "$err" | grep -nE "$second" | head -1 | cut -d: -f1)
    if [ -n "$first_ln" ] && [ -n "$second_ln" ] && [ "$first_ln" -lt "$second_ln" ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (first='$first_ln' second='$second_ln')"
        echo "    stderr: $err"
        FAIL=$((FAIL+1))
    fi
}

# --- Fixture setup ---
TMPDIR_ROOT=$(mktemp -d)

# Primary test project: CMM registered + sentinel present (indexed)
PROJ="$TMPDIR_ROOT/proj"
mkdir -p "$PROJ/src"
git -C "$PROJ" init -q
echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"}}}' > "$PROJ/.mcp.json"
# Code file used in path-only tests + small-file exemption
cat > "$PROJ/src/main.py" <<PY
def foo():
    return 1

def bar():
    return 2
PY
# Large file (>=50 lines) for cases where small-file exemption must NOT apply
{ for i in $(seq 1 80); do echo "line $i"; done; } > "$PROJ/src/large.py"

# Compute sentinel hash for $PROJ (must match hook's md5(REPO_ROOT)).
# The hook derives REPO_ROOT via `git rev-parse --show-toplevel`, which returns the
# canonical path (on macOS /var → /private/var). Canonicalize here so sentinels match.
PROJ_CANON=$(cd "$PROJ" && pwd -P)
PROJ_HASH=$(_md5 "$PROJ_CANON")
PROJ_SENTINEL="/tmp/cmm-session-ready-${PROJ_HASH}"
touch "$PROJ_SENTINEL"

# Second project: CMM NOT registered (.mcp.json lacks codebase-memory-mcp)
PROJ_NO_CMM="$TMPDIR_ROOT/proj-no-cmm"
mkdir -p "$PROJ_NO_CMM/src"
git -C "$PROJ_NO_CMM" init -q
echo '{"mcpServers":{"some-other-mcp":{"command":"npx"}}}' > "$PROJ_NO_CMM/.mcp.json"
echo 'print("hi")' > "$PROJ_NO_CMM/src/main.py"

# Fake CLAUDE_CONFIG_DIR — suppresses global fallback CMM detection
FAKE_CONFIG="$TMPDIR_ROOT/fake-claude-config"
mkdir -p "$FAKE_CONFIG"
echo '{"hooks":{}}' > "$FAKE_CONFIG/settings.json"
ENV_NO_GLOBAL="CLAUDE_CONFIG_DIR=$FAKE_CONFIG"

# Third project: CMM registered but NO sentinel (not indexed yet)
PROJ_NO_SENT="$TMPDIR_ROOT/proj-no-sent"
mkdir -p "$PROJ_NO_SENT/src"
git -C "$PROJ_NO_SENT" init -q
echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"}}}' > "$PROJ_NO_SENT/.mcp.json"
echo 'print("hi")' > "$PROJ_NO_SENT/src/main.py"
# Deliberately NO sentinel

# Cleanup on exit
trap 'rm -rf "$TMPDIR_ROOT"; rm -f "$PROJ_SENTINEL"' EXIT

# Bail out early if hook is missing
if [ ! -f "$HOOK" ]; then
    echo "NOTE: $HOOK does not exist yet."
    echo "Results: $PASS passed, $FAIL failed"
    exit 1
fi

# --- Tests ---

echo "--- 1: tool_name != Grep → exit 0 (no-op) ---"
_assert_exit "non-Grep tool_name no-op" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"cwd\":\"$PROJ\"}" \
    "$ENV_NO_GLOBAL"

echo "--- 2: code-language type blocks (exit 2) ---"
_assert_exit "Grep type=go blocked" 2 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"MyFunc\",\"type\":\"go\"},\"cwd\":\"$PROJ\"}" \
    "$ENV_NO_GLOBAL"

echo "--- 3: code-language type emits BLOCKED header ---"
_assert_stderr_grep "Grep type=go stderr BLOCKED" \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"MyFunc\",\"type\":\"go\"},\"cwd\":\"$PROJ\"}" \
    '\[grep-cmm-gate\] BLOCKED' \
    "$ENV_NO_GLOBAL"

echo "--- 4: code-extension glob blocks (exit 2) ---"
_assert_exit "Grep glob=*.py blocked" 2 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"foo\",\"glob\":\"*.py\"},\"cwd\":\"$PROJ\"}" \
    "$ENV_NO_GLOBAL"

echo "--- 5: non-code type allowed (exit 0) ---"
_assert_exit "Grep type=json allowed" 0 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"version\",\"type\":\"json\"},\"cwd\":\"$PROJ\"}" \
    "$ENV_NO_GLOBAL"

echo "--- 6: non-code type=md allowed ---"
_assert_exit "Grep type=md allowed" 0 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"TODO\",\"type\":\"md\"},\"cwd\":\"$PROJ\"}" \
    "$ENV_NO_GLOBAL"

echo "--- 7: non-code glob=*.md allowed ---"
_assert_exit "Grep glob=*.md allowed" 0 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"TODO\",\"glob\":\"*.md\"},\"cwd\":\"$PROJ\"}" \
    "$ENV_NO_GLOBAL"

echo "--- 8: non-code glob=*.yml allowed ---"
_assert_exit "Grep glob=*.yml allowed" 0 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"port\",\"glob\":\"*.yml\"},\"cwd\":\"$PROJ\"}" \
    "$ENV_NO_GLOBAL"

echo "--- 9: CMM not registered → fail-open (exit 0) ---"
_assert_exit "no-CMM glob=*.py allowed" 0 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"foo\",\"glob\":\"*.py\"},\"cwd\":\"$PROJ_NO_CMM\"}" \
    "$ENV_NO_GLOBAL"

echo "--- 10: CMM registered but no sentinel → fail-open (exit 0) ---"
_assert_exit "no-sentinel type=go allowed" 0 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"foo\",\"type\":\"go\"},\"cwd\":\"$PROJ_NO_SENT\"}" \
    "$ENV_NO_GLOBAL"

echo "--- 11: '# cmm-exempt' in pattern bypasses (exit 0) ---"
_assert_exit "cmm-exempt bypass" 0 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"secret # cmm-exempt\",\"type\":\"go\"},\"cwd\":\"$PROJ\"}" \
    "$ENV_NO_GLOBAL"

echo "--- 12: path-only (no type, no glob) in indexed repo → blocks ---"
_assert_exit "path-only indexed blocked" 2 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"foo\",\"path\":\"$PROJ/src\"},\"cwd\":\"$PROJ\"}" \
    "$ENV_NO_GLOBAL"

echo "--- 13: small file (<50 lines) exempted ---"
_assert_exit "small file exempted" 0 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"foo\",\"path\":\"$PROJ/src/main.py\"},\"cwd\":\"$PROJ\"}" \
    "$ENV_NO_GLOBAL"

echo "--- 14: identifier pattern → search_graph first, search_code second ---"
_assert_stderr_order "identifier MyClassName order" \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"MyClassName\",\"type\":\"go\"},\"cwd\":\"$PROJ\"}" \
    'REPLACE WITH: mcp__codebase-memory-mcp__search_graph' \
    'OR:.*mcp__codebase-memory-mcp__search_code'

echo "--- 15: identifier pattern MyFunc — pattern appears verbatim in first line ---"
_assert_stderr_grep "MyFunc name_pattern verbatim" \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"MyFunc\",\"type\":\"go\"},\"cwd\":\"$PROJ\"}" \
    'search_graph\(name_pattern="MyFunc"\)' \
    "$ENV_NO_GLOBAL"

echo "--- 16: regex pattern with alternation → search_code first, search_graph second ---"
_assert_stderr_order "regex alternation order" \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"password|PASSWORD|db_pass\",\"type\":\"go\"},\"cwd\":\"$PROJ\"}" \
    'REPLACE WITH: mcp__codebase-memory-mcp__search_code' \
    'OR:.*mcp__codebase-memory-mcp__search_graph'

echo "--- 17: short pattern 'go' → search_code first (too short for identifier) ---"
_assert_stderr_order "short pattern order" \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"go\",\"type\":\"go\"},\"cwd\":\"$PROJ\"}" \
    'REPLACE WITH: mcp__codebase-memory-mcp__search_code' \
    'OR:.*mcp__codebase-memory-mcp__search_graph'

echo "--- 18: multi-word pattern 'foo bar' → search_code first ---"
_assert_stderr_order "multi-word order" \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"foo bar\",\"type\":\"go\"},\"cwd\":\"$PROJ\"}" \
    'REPLACE WITH: mcp__codebase-memory-mcp__search_code' \
    'OR:.*mcp__codebase-memory-mcp__search_graph'

echo "--- 19: pattern with dot metacharacter → search_code first ---"
_assert_stderr_order "dot metachar order" \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"foo.bar\",\"type\":\"go\"},\"cwd\":\"$PROJ\"}" \
    'REPLACE WITH: mcp__codebase-memory-mcp__search_code' \
    'OR:.*mcp__codebase-memory-mcp__search_graph'

echo "--- 20: malformed JSON → fail-open (exit 0) ---"
_assert_exit "malformed JSON no-op" 0 \
    "this-is-not-json" \
    "$ENV_NO_GLOBAL"

echo "--- 21: empty stdin → fail-open (exit 0) ---"
actual=0
bash "$HOOK" < /dev/null >/dev/null 2>&1 || actual=$?
if [ "$actual" -eq 0 ]; then
    echo "PASS: empty stdin fail-open"
    PASS=$((PASS+1))
else
    echo "FAIL: empty stdin fail-open (got $actual)"
    FAIL=$((FAIL+1))
fi

echo "--- 22: code-extension glob=*.ts blocked ---"
_assert_exit "Grep glob=*.ts blocked" 2 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"export\",\"glob\":\"*.ts\"},\"cwd\":\"$PROJ\"}" \
    "$ENV_NO_GLOBAL"

echo "--- 23: brace-expansion glob *.{ts,tsx} blocked ---"
_assert_exit "brace glob blocked" 2 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"export\",\"glob\":\"*.{ts,tsx}\"},\"cwd\":\"$PROJ\"}" \
    "$ENV_NO_GLOBAL"

echo "--- 24: large code file (>=50 lines) blocked by path-only ---"
_assert_exit "large code file blocked" 2 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"line\",\"path\":\"$PROJ/src/large.py\"},\"cwd\":\"$PROJ\"}" \
    "$ENV_NO_GLOBAL"

echo "--- 25: path-only on non-code file (README.md) allowed (QA M4) ---"
# Seed a large README.md so the small-file exemption does not apply.
{ for i in $(seq 1 80); do echo "# heading $i"; done; } > "$PROJ/README.md"
_assert_exit "Grep path=README.md (no type/glob) allowed" 0 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"heading\",\"path\":\"$PROJ/README.md\"},\"cwd\":\"$PROJ\"}" \
    "$ENV_NO_GLOBAL"
{ for i in $(seq 1 80); do echo "name: v$i"; done; } > "$PROJ/config.yml"
_assert_exit "Grep path=config.yml (no type/glob) allowed" 0 \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"name\",\"path\":\"$PROJ/config.yml\"},\"cwd\":\"$PROJ\"}" \
    "$ENV_NO_GLOBAL"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
