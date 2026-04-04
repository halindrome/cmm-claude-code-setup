#!/bin/bash
# test-agent-gate-blocking.sh — Tests for agent-cmm-gate.sh keyword enforcement
# Usage: bash tests/test-agent-gate-blocking.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/project/agent-cmm-gate.sh"

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

# Note: the gate exempts prompts <300 chars with no code signals.
# Blocked tests use prompts with code signals (file/function/class/etc.) but no CMM keywords.

echo "--- Test 1: Prompt with code signals but no CMM keywords -> blocked (exit 2) ---"
_assert_exit "Test 1: code signals, no CMM keywords blocked" 2 \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"dev","prompt":"Please review the function in this file and refactor the class method to fix the debug issue in the module"}}'

echo "--- Test 2: search_graph keyword -> allowed (exit 0) ---"
_assert_exit "Test 2: search_graph allowed" 0 \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"dev","prompt":"Use search_graph to find the Handler class in the codebase"}}'

echo "--- Test 3: trace_call_path keyword -> allowed (exit 0) ---"
_assert_exit "Test 3: trace_call_path allowed" 0 \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"scout","prompt":"Run trace_call_path on the main function to see callers"}}'

echo "--- Test 4: get_code_snippet keyword -> allowed (exit 0) ---"
_assert_exit "Test 4: get_code_snippet allowed" 0 \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"qa","prompt":"Use get_code_snippet to read the SessionGate function source"}}'

echo "--- Test 5: index_repository keyword -> allowed (exit 0) ---"
_assert_exit "Test 5: index_repository allowed" 0 \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"dev","prompt":"Call index_repository first to ensure the graph is current for this file"}}'

echo "--- Test 6: get_architecture keyword -> allowed (exit 0) ---"
_assert_exit "Test 6: get_architecture allowed" 0 \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"dev","prompt":"Start by calling get_architecture to orient yourself in the codebase"}}'

echo "--- Test 7: detect_changes keyword -> allowed (exit 0) ---"
_assert_exit "Test 7: detect_changes allowed" 0 \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"dev","prompt":"Run detect_changes to see the blast radius before modifying the function"}}'

echo "--- Test 8: Explore with code signals but no CMM keywords -> blocked (exit 2) ---"
_assert_exit "Test 8: Explore blocked without CMM keywords" 2 \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","prompt":"Look at the function in this file and refactor the class method"}}'

echo "--- Test 9: Plan with code signals but no CMM keywords -> blocked (exit 2) ---"
_assert_exit "Test 9: Plan blocked without CMM keywords" 2 \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"Plan","prompt":"Plan the refactor of the function and class in this module"}}'

echo "--- Test 10: Explore with CMM keywords -> allowed (exit 0) ---"
_assert_exit "Test 10: Explore with get_architecture allowed" 0 \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","prompt":"Use get_architecture to understand the codebase structure and search_graph to find the function"}}'

echo "--- Test 11: Plan with CMM keywords -> allowed (exit 0) ---"
_assert_exit "Test 11: Plan with trace_call_path allowed" 0 \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"Plan","prompt":"Use trace_call_path and get_architecture to analyze dependencies before planning the refactor"}}'

echo "--- Test 12: VBW agent type still exempt (exit 0) ---"
_assert_exit "Test 12: vbw:vbw-dev exempt" 0 \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"vbw:vbw-dev","prompt":"Look at the function in this file and refactor the class method"}}'

echo "--- Test 13: claude-code-guide still exempt (exit 0) ---"
_assert_exit "Test 13: claude-code-guide exempt" 0 \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"claude-code-guide","prompt":"How do I configure hooks for this function in the file"}}'

echo "--- Test 14: cmm-exempt marker -> allowed regardless (exit 0) ---"
_assert_exit "Test 14: cmm-exempt marker bypasses gate" 0 \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"dev","prompt":"Help me write a function to process the file class method # cmm-exempt"}}'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
