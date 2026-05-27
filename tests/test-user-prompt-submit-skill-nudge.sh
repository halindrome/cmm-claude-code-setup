#!/bin/bash
# test-user-prompt-submit-skill-nudge.sh — Tests for user-prompt-submit-skill-nudge.sh
# Usage: bash tests/test-user-prompt-submit-skill-nudge.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/global/user-prompt-submit-skill-nudge.sh"

PASS=0; FAIL=0

# _assert LABEL EXPECTED_EXIT EXPECTED_STDOUT_CONTAINS EXPECT_STDOUT_EMPTY JSON
_assert() {
    local label="$1" expected_exit="$2" expected_contains="$3" expect_empty="$4" json="$5"
    local actual_exit=0 stdout_out=""
    stdout_out=$(echo "$json" | bash "$HOOK" 2>/dev/null) || actual_exit=$?
    if [ "$actual_exit" -ne "$expected_exit" ]; then
        echo "FAIL: $label — exit $actual_exit (expected $expected_exit)"
        FAIL=$((FAIL+1))
        return
    fi
    if [ "$expect_empty" = "1" ]; then
        if [ -n "$stdout_out" ]; then
            echo "FAIL: $label — expected empty stdout, got: $stdout_out"
            FAIL=$((FAIL+1))
        else
            echo "PASS: $label"
            PASS=$((PASS+1))
        fi
    else
        if echo "$stdout_out" | grep -qF "$expected_contains"; then
            echo "PASS: $label"
            PASS=$((PASS+1))
        else
            echo "FAIL: $label — expected stdout to contain '$expected_contains', got: $stdout_out"
            FAIL=$((FAIL+1))
        fi
    fi
}

# Bail out early if hook is missing
if [ ! -f "$HOOK" ]; then
    echo "ERROR: Hook not found: $HOOK"
    exit 1
fi

echo "--- Test a: code-navigation prompt 'find the function' -> emits Invoke Skill ---"
_assert "a) 'find the function' -> stdout contains Invoke Skill" \
    0 "Invoke Skill" 0 \
    '{"prompt":"find the function that parses tokens"}'

echo "--- Test b: code-navigation prompt 'what calls parse' -> emits Invoke Skill ---"
_assert "b) 'what calls parse' -> stdout contains Invoke Skill" \
    0 "Invoke Skill" 0 \
    '{"prompt":"what calls parse in this codebase"}'

echo "--- Test c: non-navigation prompt 'update the README' -> stdout empty ---"
_assert "c) 'update the README' -> stdout empty" \
    0 "" 1 \
    '{"prompt":"update the README with the new install steps"}'

echo "--- Test d: empty stdin -> exit 0, no output ---"
_assert "d) empty stdin -> silent exit 0" \
    0 "" 1 \
    ""

echo "--- Test e: malformed JSON -> exit 0, no output ---"
_assert "e) malformed JSON -> silent exit 0" \
    0 "" 1 \
    "not json at all"

echo ""
echo "=============================================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================================="
[ "$FAIL" -eq 0 ]
