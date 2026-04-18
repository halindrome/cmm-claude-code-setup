#!/bin/bash
# test-ctx-annotate-nudge.sh — Tests for ctx-annotate-nudge.sh PostToolUse additionalContext hook
# Usage: bash tests/test-ctx-annotate-nudge.sh
# Exit: 0 = all pass, 1 = any failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/global/ctx-annotate-nudge.sh"

PASS=0; FAIL=0

if [ ! -f "$HOOK" ]; then
    echo "FATAL: $HOOK not found"
    exit 1
fi

# Compute project hash for the /tmp cwd used in test payloads so we can reset the sentinel.
if command -v md5 >/dev/null 2>&1; then
    TMP_HASH="$(printf '%s' '/tmp' | md5 -q)"
else
    TMP_HASH="$(printf '%s' '/tmp' | md5sum | awk '{print $1}')"
fi
TMP_SENTINEL="/tmp/ctx-nudge-${TMP_HASH}"

_reset_cooldown() {
    rm -f "$TMP_SENTINEL" 2>/dev/null || true
    # Also remove any sentinel derived from a fresh git toplevel (if /tmp happens to be inside a repo)
    rm -f /tmp/ctx-nudge-* 2>/dev/null || true
}

cleanup() {
    rm -f "$TMP_SENTINEL" 2>/dev/null || true
}
trap cleanup EXIT

_assert_emits() {
    local label="$1" json="$2"
    _reset_cooldown
    local out
    out=$(printf '%s' "$json" | bash "$HOOK" 2>/dev/null)
    local exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        echo "FAIL: $label (exit=$exit_code, expected 0)"
        FAIL=$((FAIL+1)); return
    fi
    if [ -z "$out" ]; then
        echo "FAIL: $label (expected stdout envelope, got empty)"
        FAIL=$((FAIL+1)); return
    fi
    # Validate JSON envelope shape and required phrase
    if printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
hso = d["hookSpecificOutput"]
assert hso["hookEventName"] == "PostToolUse"
ac = hso["additionalContext"]
assert "state in ONE sentence" in ac
assert "do NOT run another ctx_* call" in ac
assert "try ctx_search" in ac
' 2>/dev/null; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (envelope invalid or missing required phrases)"
        echo "  stdout: $out"
        FAIL=$((FAIL+1))
    fi
}

_assert_silent() {
    local label="$1" json="$2"
    _reset_cooldown_flag="${3:-1}"
    if [ "$_reset_cooldown_flag" = "1" ]; then
        _reset_cooldown
    fi
    local out
    out=$(printf '%s' "$json" | bash "$HOOK" 2>/dev/null)
    local exit_code=$?
    if [ "$exit_code" -eq 0 ] && [ -z "$out" ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (exit=$exit_code, stdout=[$out], expected exit 0 silent)"
        FAIL=$((FAIL+1))
    fi
}

echo "--- Case 1: ctx_execute with intent emits envelope ---"
_assert_emits "1) ctx_execute emits additionalContext envelope" \
    '{"tool_name":"mcp__context-mode__ctx_execute","tool_input":{"intent":"test"},"cwd":"/tmp"}'

echo "--- Case 2: ctx_search emits envelope ---"
_assert_emits "2) ctx_search emits additionalContext envelope" \
    '{"tool_name":"mcp__context-mode__ctx_search","tool_input":{"queries":["x"]},"cwd":"/tmp"}'

echo "--- Case 3: ctx_index emits envelope ---"
_assert_emits "3) ctx_index emits additionalContext envelope" \
    '{"tool_name":"mcp__context-mode__ctx_index","tool_input":{"intent":"note","text":"hello"},"cwd":"/tmp"}'

echo "--- Case 4: ctx_fetch_and_index emits envelope ---"
_assert_emits "4) ctx_fetch_and_index emits additionalContext envelope" \
    '{"tool_name":"mcp__context-mode__ctx_fetch_and_index","tool_input":{"url":"https://example.com","intent":"doc"},"cwd":"/tmp"}'

echo "--- Case 5: ctx_stats silent (not in matcher scope) ---"
_assert_silent "5) ctx_stats emits nothing" \
    '{"tool_name":"mcp__context-mode__ctx_stats","cwd":"/tmp"}'

echo "--- Case 6: ctx_batch_execute silent (not in matcher scope) ---"
_assert_silent "6) ctx_batch_execute emits nothing" \
    '{"tool_name":"mcp__context-mode__ctx_batch_execute","tool_input":{"steps":[{"intent":"x","code":"ls"}]},"cwd":"/tmp"}'

echo "--- Case 7: second ctx_execute within 120s -> cooldown silent ---"
# First call primes the sentinel
_reset_cooldown
printf '%s' '{"tool_name":"mcp__context-mode__ctx_execute","tool_input":{"intent":"prime"},"cwd":"/tmp"}' | bash "$HOOK" >/dev/null 2>&1
# Second call without resetting cooldown must be silent
_assert_silent "7) cooldown suppresses second call within 120s" \
    '{"tool_name":"mcp__context-mode__ctx_execute","tool_input":{"intent":"second"},"cwd":"/tmp"}' 0

echo "--- Case 8: JSON escaping of quotes and newlines in intent ---"
_reset_cooldown
TRICKY_JSON='{"tool_name":"mcp__context-mode__ctx_execute","tool_input":{"intent":"she said \"hi\"\n\\back"},"cwd":"/tmp"}'
TRICKY_OUT=$(printf '%s' "$TRICKY_JSON" | bash "$HOOK" 2>/dev/null)
if [ -n "$TRICKY_OUT" ] && printf '%s' "$TRICKY_OUT" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
ac = d["hookSpecificOutput"]["additionalContext"]
assert "state in ONE sentence" in ac
' 2>/dev/null; then
    echo "PASS: 8) envelope with tricky intent parses cleanly as JSON"
    PASS=$((PASS+1))
else
    echo "FAIL: 8) tricky intent broke JSON envelope"
    echo "  stdout: $TRICKY_OUT"
    FAIL=$((FAIL+1))
fi

echo "--- Case 9: malformed JSON on stdin -> exit 0 silent ---"
_assert_silent "9) malformed JSON fails open silently" 'not-json{'

echo "--- Case 10: # ctx-exempt bypass marker suppresses emission ---"
_assert_silent "10) ctx-exempt marker suppresses emission" \
    '{"tool_name":"mcp__context-mode__ctx_execute","tool_input":{"intent":"ignore # ctx-exempt here"},"cwd":"/tmp"}'

echo ""
echo "============================================"
echo "Results: $PASS passed, $FAIL failed"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
