#!/bin/bash
# test-context-mode-hook-dispatch.sh — behaviour of hooks/project/context-mode-hook-dispatch.sh
#
# Runs the dispatcher against a stub `context-mode` binary on PATH that records each call
# and echoes its stdin, so the test needs no real context-mode install.
#
# Covers the Agent re-injection guard: upstream context-mode (routing.mjs, v1.0.169) appends
# its <context_window_protection> block to every Agent prompt unconditionally. A prompt that
# already carries the block (the model re-sent a hook-rewritten prompt) gained a second copy,
# and auto mode could not classify the doubled launch. The dispatcher now passes such a
# prompt through untouched.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/project/context-mode-hook-dispatch.sh"
PASS=0; FAIL=0
_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d /tmp/cmhd-test-XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/context-mode" <<'EOF'
#!/bin/bash
# stub: record argv, echo stdin back
echo "$*" >> "$CMHD_CALLS"
cat
EOF
chmod +x "$TMP/bin/context-mode"
export CMHD_CALLS="$TMP/calls"

# run <event> <json>: sets OUT, RC, CALLED (number of stub invocations for this run)
run() {
    : > "$CMHD_CALLS"
    OUT=$(printf '%s' "$2" | PATH="$TMP/bin:/usr/bin:/bin" bash "$HOOK" "$1" 2>/dev/null); RC=$?
    CALLED=$(wc -l < "$CMHD_CALLS" | tr -d ' ')
}

BLOCK='<context_window_protection> route through ctx_execute </context_window_protection>'
AGENT_PLAIN='{"tool_name":"Agent","tool_input":{"description":"x","prompt":"do the thing"}}'
AGENT_MARKED="{\"tool_name\": \"Agent\", \"tool_input\": {\"description\": \"x\", \"prompt\": \"do the thing\\n$BLOCK\"}}"
TASK_MARKED="{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"y $BLOCK\"}}"
BASH_MARKED="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo '$BLOCK'\"}}"

# 1. Agent prompt that already carries the block -> passed through, upstream NOT called
run pretooluse "$AGENT_MARKED"
if [ "$RC" -eq 0 ] && [ "$CALLED" -eq 0 ] && [ -z "$OUT" ]; then
    _pass "Agent prompt already carrying the block is not re-injected"
else
    _fail "Agent prompt already carrying the block (rc=$RC called=$CALLED out=$OUT)"
fi

# 2. Same for the legacy Task tool name
run pretooluse "$TASK_MARKED"
if [ "$RC" -eq 0 ] && [ "$CALLED" -eq 0 ]; then
    _pass "Task prompt already carrying the block is not re-injected"
else
    _fail "Task prompt already carrying the block (rc=$RC called=$CALLED)"
fi

# 3. Agent prompt WITHOUT the block -> upstream called once, payload intact
run pretooluse "$AGENT_PLAIN"
if [ "$CALLED" -eq 1 ] && grep -q 'hook claude-code pretooluse' "$CMHD_CALLS" && [ "$OUT" = "$AGENT_PLAIN" ]; then
    _pass "Agent prompt without the block still reaches context-mode, stdin intact"
else
    _fail "Agent prompt without the block (called=$CALLED out=$OUT)"
fi

# 4. Non-Agent tool mentioning the block -> still dispatched (guard is Agent-only)
run pretooluse "$BASH_MARKED"
if [ "$CALLED" -eq 1 ] && [ "$OUT" = "$BASH_MARKED" ]; then
    _pass "non-Agent pretooluse is dispatched even when it mentions the block"
else
    _fail "non-Agent pretooluse (called=$CALLED out=$OUT)"
fi

# 5. Other events are untouched, even for an Agent payload carrying the block
run posttooluse "$AGENT_MARKED"
if [ "$CALLED" -eq 1 ] && grep -q 'hook claude-code posttooluse' "$CMHD_CALLS" && [ "$OUT" = "$AGENT_MARKED" ]; then
    _pass "posttooluse dispatches unchanged"
else
    _fail "posttooluse (called=$CALLED out=$OUT)"
fi

# 6. Missing event arg -> fail open
run "" "$AGENT_PLAIN"
if [ "$RC" -eq 0 ] && [ "$CALLED" -eq 0 ]; then
    _pass "missing event arg fails open"
else
    _fail "missing event arg (rc=$RC called=$CALLED)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
