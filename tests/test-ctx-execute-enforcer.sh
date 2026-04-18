#!/bin/bash
# test-ctx-execute-enforcer.sh — Tests for ctx-execute-enforcer.sh large-output blocking
# Usage: bash tests/test-ctx-execute-enforcer.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/project/ctx-execute-enforcer.sh"

PASS=0; FAIL=0
_assert_exit() {
    local label="$1" expected="$2" json="$3"
    local actual=0
    echo "$json" | bash "$HOOK" >/dev/null 2>&1 || actual=$?
    if [ "$actual" -eq "$expected" ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (expected exit $expected, got $actual)"
        FAIL=$((FAIL+1))
    fi
}

# --- Sentinel simulation setup ---
# Compute the same PROJECT_HASH the hook uses: md5 of canonical project root path
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
if command -v md5 >/dev/null 2>&1; then
    PROJECT_HASH="$(echo "$PROJECT_ROOT" | md5 -q)"
else
    PROJECT_HASH="$(echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')"
fi

CM_CACHE="/tmp/ctx-enforcer-${PROJECT_HASH}"
CM_SENTINEL="/tmp/context-mode-ready-${PROJECT_HASH}"

# Register cleanup on exit
trap 'rm -f "$CM_CACHE" "$CM_SENTINEL"' EXIT

# Create sentinels to simulate Context Mode installed and ready
echo "1" > "$CM_CACHE"
touch "$CM_SENTINEL"

# Bail out early with a clear message if hook doesn't exist yet
if [ ! -f "$HOOK" ]; then
    echo ""
    echo "NOTE: $HOOK does not exist yet."
    echo "This test suite is complete but requires Plan 32-01 to be merged first."
    echo "Run again after hooks/project/ctx-execute-enforcer.sh is created."
    echo ""
    echo "Results: $PASS passed, $FAIL failed (hook not yet available)"
    exit 0
fi

# --- Blocked command tests (expect exit 2, sentinels present) ---
echo "--- Blocked command tests (sentinels present, expect exit 2) ---"

_assert_exit "npm test command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'

_assert_exit "npx jest command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"npx jest"}}'

_assert_exit "pip install command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"pip install requests"}}'

_assert_exit "eslint command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"eslint src/"}}'

_assert_exit "tail -f command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"tail -f /var/log/syslog"}}'

_assert_exit "npm run test blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"npm run test"}}'

_assert_exit "yarn run test blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"yarn run test"}}'

_assert_exit "npx mocha blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"npx mocha"}}'

_assert_exit "bun test blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"bun test"}}'

_assert_exit "deno test blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"deno test"}}'

_assert_exit "node --test blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"node --test"}}'

_assert_exit "pnpm run test blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"pnpm run test"}}'

# --- Exempt command tests (expect exit 0, sentinels present) ---
echo ""
echo "--- Exempt command tests (sentinels present, expect exit 0) ---"

_assert_exit "git commit exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: add hook\""}}'

_assert_exit "mkdir exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"mkdir -p .claude/hooks"}}'

_assert_exit "date exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"date"}}'

_assert_exit "git status exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git status"}}'

# --- Allowlist: previously-unblocked commands now blocked (expect exit 2) ---
echo ""
echo "--- Allowlist: previously-unblocked commands now blocked (expect exit 2) ---"

_assert_exit "cat command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"cat README.md"}}'

_assert_exit "find command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"find . -name \"*.sh\""}}'

_assert_exit "grep command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"grep -r TODO src/"}}'

_assert_exit "ls command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'

_assert_exit "curl command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"curl https://example.com"}}'

_assert_exit "node command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"node -e \"console.log(1)\""}}'

_assert_exit "python3 command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"python3 script.py"}}'

_assert_exit "sed command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"sed -i s/foo/bar/ file.txt"}}'

# --- VBW/planning exempt tests (expect exit 0) ---
echo ""
echo "--- VBW/planning exempt tests (expect exit 0) ---"

_assert_exit "vbw planning script exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"bash /Users/dev/project/.vbw-planning/scripts/resolve.sh"}}'

_assert_exit "vbw plugin root link exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"bash /tmp/.vbw-plugin-root-link-abc123/scripts/run.sh"}}'

# --- Version query exempt tests (expect exit 0) ---
echo ""
echo "--- Version query exempt tests (expect exit 0) ---"

_assert_exit "version flag exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"node --version"}}'

# --- Git log/diff exempt tests (expect exit 0) ---
echo ""
echo "--- Git log/diff exempt tests (expect exit 0) ---"

_assert_exit "git log --oneline exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git log --oneline -10"}}'

_assert_exit "git diff --stat exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git diff --stat"}}'

# --- 47-02: bare git log/diff/show now blocked (expect exit 2) ---
echo ""
echo "--- 47-02: bare git log/diff/show blocked (expect exit 2) ---"

_assert_exit "bare git log blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git log"}}'

_assert_exit "git log with numeric flag blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git log -20"}}'

_assert_exit "git diff with ref blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git diff HEAD~3"}}'

_assert_exit "git show with sha blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"git show abc123"}}'

_assert_exit "echo command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'

_assert_exit "printf command blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"printf %s\\n foo"}}'

# --- 47-02: new bounded git variants exempt (expect exit 0) ---
echo ""
echo "--- 47-02: bounded git variants exempt (expect exit 0) ---"

_assert_exit "git log --name-only exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git log --name-only -5"}}'

_assert_exit "git log --stat exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git log --stat -10"}}'

_assert_exit "git show --name-only exempt" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git show --name-only HEAD"}}'

# --- Bypass marker test (expect exit 0 even for blocked command) ---
echo ""
echo "--- Bypass marker tests (expect exit 0) ---"

_assert_exit "ctx-exempt marker bypasses npm test" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"npm test # ctx-exempt"}}'

# --- Missing Context Mode sentinel test (expect exit 0) ---
echo ""
echo "--- Missing sentinel tests (expect exit 0, deadlock prevention) ---"

# Remove sentinel to simulate Context Mode not yet initialized
rm -f "$CM_SENTINEL"

_assert_exit "missing sentinel allows npm test" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'

# Restore sentinel for remaining tests
touch "$CM_SENTINEL"

# --- Context Mode not installed test (expect exit 0) ---
echo ""
echo "--- Context Mode not installed test (expect exit 0) ---"

# Write "0" to cache to simulate Context Mode not detected
echo "0" > "$CM_CACHE"

_assert_exit "no CM install allows npm test" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'

# Restore cache for any subsequent tests
echo "1" > "$CM_CACHE"

# --- Fail-open tests (expect exit 0) ---
echo ""
echo "--- Fail-open tests (empty/malformed JSON, expect exit 0) ---"

_assert_exit "empty JSON fail-open" 0 \
    '{}'

_assert_exit "malformed JSON fail-open" 0 \
    'not-json'

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
