#!/bin/bash
# test-analyze-skill-compliance.sh — Fixture-based test for analyze-skill-compliance.sh
# Usage: bash tests/test-analyze-skill-compliance.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT="$SCRIPT_DIR/../scripts/analyze-skill-compliance.sh"
FIXTURES="$SCRIPT_DIR/fixtures/skill-compliance"

PASS=0; FAIL=0

_assert_contains() {
    local label="$1" expected="$2" actual="$3"
    if echo "$actual" | grep -qF "$expected"; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label — expected output to contain: '$expected'"
        echo "  Actual output:"
        echo "$actual" | sed 's/^/    /'
        FAIL=$((FAIL+1))
    fi
}

_assert_exit() {
    local label="$1" expected_exit="$2" actual_exit="$3"
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "PASS: $label (exit $actual_exit)"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label — expected exit $expected_exit, got $actual_exit"
        FAIL=$((FAIL+1))
    fi
}

if [ ! -f "$SCRIPT" ]; then
    echo "ERROR: Script not found: $SCRIPT"
    exit 1
fi

if [ ! -d "$FIXTURES" ]; then
    echo "ERROR: Fixtures dir not found: $FIXTURES"
    exit 1
fi

echo "--- Running analyze-skill-compliance.sh against fixtures ---"
OUTPUT=$("$SCRIPT" "$FIXTURES" 2>&1)
ACTUAL_EXIT=$?

echo "--- Test 1: script exits 0 ---"
_assert_exit "exit code 0" 0 "$ACTUAL_EXIT"

echo "--- Test 2: output contains cmm-rules activation rate ---"
_assert_contains "output contains 'cmm-rules activation rate'" "cmm-rules activation rate" "$OUTPUT"

echo "--- Test 3: output contains ctx-rules activation rate ---"
_assert_contains "output contains 'ctx-rules activation rate'" "ctx-rules activation rate" "$OUTPUT"

echo "--- Test 4: agent2 shows 0 ctx-rules activations ---"
# agent2.jsonl has no Skill calls at all — ctx column should be 0
AGENT2_LINE=$(echo "$OUTPUT" | grep "agent2" || true)
if echo "$AGENT2_LINE" | grep -qE 'agent2\s.*\s0\s'; then
    echo "PASS: agent2 shows 0 ctx-rules invocations"
    PASS=$((PASS+1))
else
    echo "FAIL: agent2 ctx-rules check — line: '$AGENT2_LINE'"
    FAIL=$((FAIL+1))
fi

echo "--- Test 5: output contains Bash:CMM ratio ---"
_assert_contains "output contains 'Bash:CMM ratio'" "Bash:CMM ratio" "$OUTPUT"

echo "--- Test 6: empty directory -> exit 0, no crash ---"
EMPTY_DIR=$(mktemp -d)
trap 'rm -rf "$EMPTY_DIR"' EXIT
EMPTY_OUT=$("$SCRIPT" "$EMPTY_DIR" 2>&1)
EMPTY_EXIT=$?
_assert_exit "empty dir -> exit 0" 0 "$EMPTY_EXIT"

echo ""
echo "=============================================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================================="
[ "$FAIL" -eq 0 ]
