#!/bin/bash
# test-cmm-orient-nudge.sh — Tests for cmm-orient-nudge.sh one-shot PostToolUse hook
# Usage: bash tests/test-cmm-orient-nudge.sh
# Exit: 0 = all pass, 1 = any failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/global/cmm-orient-nudge.sh"

PASS=0; FAIL=0

# Use deterministic but unique-per-run session_ids so parallel test runs don't collide.
RUN_ID="test-session-$$-$RANDOM"
SID1="${RUN_ID}-abc"
SID2="${RUN_ID}-def"
SID3="${RUN_ID}-ghi"
SID4="${RUN_ID}-jkl"

# Cleanup sentinels on exit (best-effort; /tmp TTL GCs anything we miss).
cleanup() {
    rm -f /tmp/cmm-orient-nudged-*-"${RUN_ID}"-* 2>/dev/null
}
trap cleanup EXIT

_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

# --- Test 1: first search_graph call emits envelope naming three under-promoted tools ---
echo "--- Test 1: first search_graph call emits envelope ---"
PAYLOAD1="{\"tool_name\":\"mcp__codebase-memory-mcp__search_graph\",\"session_id\":\"$SID1\",\"tool_input\":{\"name_pattern\":\"Foo\"}}"
OUT1=$(echo "$PAYLOAD1" | bash "$HOOK" 2>/dev/null)
EC1=$?
if [ "$EC1" -eq 0 ] && [ -n "$OUT1" ]; then
    # Parse + check all three tool names present
    CHECK=$(echo "$OUT1" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ac = d['hookSpecificOutput']['additionalContext']
    need = ['get_architecture', 'query_graph', 'trace_call_path']
    missing = [t for t in need if t not in ac]
    print('missing:' + ','.join(missing) if missing else 'ok')
except Exception as e:
    print('parse-error:' + str(e))
")
    if [ "$CHECK" = "ok" ]; then
        _pass "Test 1: envelope emitted with three tool names"
    else
        _fail "Test 1: envelope content" "$CHECK"
    fi
else
    _fail "Test 1: first-call emission" "exit=$EC1 out_len=${#OUT1}"
fi

# --- Test 2: second call same session_id exits 0 silent ---
echo "--- Test 2: second call same session exits silent ---"
OUT2=$(echo "$PAYLOAD1" | bash "$HOOK" 2>/dev/null)
EC2=$?
if [ "$EC2" -eq 0 ] && [ -z "$OUT2" ]; then
    _pass "Test 2: second call silent"
else
    _fail "Test 2: second call" "exit=$EC2 out=[$OUT2]"
fi

# --- Test 3: different session_id emits again ---
echo "--- Test 3: different session_id emits again ---"
PAYLOAD2="{\"tool_name\":\"mcp__codebase-memory-mcp__search_graph\",\"session_id\":\"$SID2\",\"tool_input\":{\"name_pattern\":\"Bar\"}}"
OUT3=$(echo "$PAYLOAD2" | bash "$HOOK" 2>/dev/null)
EC3=$?
if [ "$EC3" -eq 0 ] && [ -n "$OUT3" ]; then
    _pass "Test 3: different session emits"
else
    _fail "Test 3: different session" "exit=$EC3 out_len=${#OUT3}"
fi

# --- Test 4: non-search_graph tool_name exits 0 silent ---
echo "--- Test 4: non-search_graph tool_name silent ---"
PAYLOAD4="{\"tool_name\":\"mcp__codebase-memory-mcp__get_architecture\",\"session_id\":\"$SID3\"}"
OUT4=$(echo "$PAYLOAD4" | bash "$HOOK" 2>/dev/null)
EC4=$?
if [ "$EC4" -eq 0 ] && [ -z "$OUT4" ]; then
    _pass "Test 4: non-matching tool silent"
else
    _fail "Test 4: non-matching tool" "exit=$EC4 out=[$OUT4]"
fi

# --- Test 5: session_id missing — functional one-shot (emits once per invocation) ---
echo "--- Test 5: session_id missing emits (one-shot per invocation) ---"
PAYLOAD5="{\"tool_name\":\"mcp__codebase-memory-mcp__search_graph\",\"tool_input\":{\"name_pattern\":\"Baz\"}}"
OUT5=$(echo "$PAYLOAD5" | bash "$HOOK" 2>/dev/null)
EC5=$?
if [ "$EC5" -eq 0 ] && [ -n "$OUT5" ]; then
    _pass "Test 5: missing session_id emits"
else
    _fail "Test 5: missing session_id" "exit=$EC5 out_len=${#OUT5}"
fi

# --- Test 6: '# cmm-exempt' in tool_input silent ---
echo "--- Test 6: cmm-exempt bypass silent ---"
PAYLOAD6="{\"tool_name\":\"mcp__codebase-memory-mcp__search_graph\",\"session_id\":\"$SID4\",\"tool_input\":{\"name_pattern\":\"Foo # cmm-exempt\"}}"
OUT6=$(echo "$PAYLOAD6" | bash "$HOOK" 2>/dev/null)
EC6=$?
if [ "$EC6" -eq 0 ] && [ -z "$OUT6" ]; then
    _pass "Test 6: cmm-exempt silent"
else
    _fail "Test 6: cmm-exempt" "exit=$EC6 out=[$OUT6]"
fi

# --- Test 7: malformed JSON silent ---
echo "--- Test 7: malformed JSON silent ---"
OUT7=$(echo 'not-json-at-all' | bash "$HOOK" 2>/dev/null)
EC7=$?
if [ "$EC7" -eq 0 ] && [ -z "$OUT7" ]; then
    _pass "Test 7: malformed JSON silent"
else
    _fail "Test 7: malformed JSON" "exit=$EC7 out=[$OUT7]"
fi

# --- Test 8: stdout JSON parses and additionalContext contains all three literal tool names ---
echo "--- Test 8: envelope parses via json.loads and names three tools ---"
# Use a brand-new session id so this is a first-call emission.
SID8="${RUN_ID}-mno"
PAYLOAD8="{\"tool_name\":\"mcp__codebase-memory-mcp__search_graph\",\"session_id\":\"$SID8\",\"tool_input\":{\"name_pattern\":\"Qux\"}}"
OUT8=$(echo "$PAYLOAD8" | bash "$HOOK" 2>/dev/null)
EC8=$?
if [ "$EC8" -eq 0 ] && [ -n "$OUT8" ]; then
    VERDICT=$(echo "$OUT8" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    if d.get('hookSpecificOutput', {}).get('hookEventName') != 'PostToolUse':
        print('bad-event-name')
        sys.exit(0)
    ac = d['hookSpecificOutput']['additionalContext']
    for t in ('get_architecture', 'query_graph', 'trace_call_path'):
        if t not in ac:
            print('missing-' + t)
            sys.exit(0)
    print('ok')
except Exception as e:
    print('parse-error:' + str(e))
")
    if [ "$VERDICT" = "ok" ]; then
        _pass "Test 8: envelope parses and names all three tools"
    else
        _fail "Test 8: envelope structure" "$VERDICT"
    fi
else
    _fail "Test 8: envelope emission" "exit=$EC8 out_len=${#OUT8}"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
