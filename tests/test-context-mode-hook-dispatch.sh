#!/bin/bash
# test-context-mode-hook-dispatch.sh — behaviour of hooks/project/context-mode-hook-dispatch.sh
#
# Runs the dispatcher against a stub `context-mode` binary on PATH that records each call
# and the EXACT bytes it received on stdin, so the test needs no real context-mode install.
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
mkdir -p "$TMP/bin" "$TMP/bare"
cat > "$TMP/bin/context-mode" <<'EOF'
#!/bin/bash
# stub: record argv, capture stdin byte-for-byte
echo "$*" >> "$CMHD_CALLS"
cat > "$CMHD_STDIN"
EOF
chmod +x "$TMP/bin/context-mode"
# A PATH with neither context-mode nor npx, but the coreutils the dispatcher needs.
# `id` is a stub: the dispatcher keys its notice stamp on `id -u`, so a fake uid gives the
# test its own stamp file and never touches the developer's real
# /tmp/cmhd-no-runtime-notice-<uid> (which would mute a genuine notice for 5 minutes).
for t in cat date touch; do ln -s "$(command -v "$t")" "$TMP/bare/$t"; done
FAKE_UID="cmhdtest$$"
printf '#!/bin/sh\necho %s\n' "$FAKE_UID" > "$TMP/bare/id"; chmod +x "$TMP/bare/id"
STAMP="/tmp/cmhd-no-runtime-notice-$FAKE_UID"
trap 'rm -rf "$TMP"; rm -f "$STAMP"' EXIT
export CMHD_CALLS="$TMP/calls" CMHD_STDIN="$TMP/stdin"

# run <event> <json> [path]: sets RC, CALLED, ERR; the stub's stdin lands in $CMHD_STDIN
run() {
    : > "$CMHD_CALLS"; rm -f "$CMHD_STDIN"
    ERR=$(printf '%s' "$2" | PATH="${3:-$TMP/bin:/usr/bin:/bin}" "$BASH" "$HOOK" "$1" 2>&1 >/dev/null); RC=$?
    CALLED=$(wc -l < "$CMHD_CALLS" | tr -d ' ')
}
# received_is <expected-bytes>: exact byte comparison of what the stub got
received_is() { [ -f "$CMHD_STDIN" ] && cmp -s "$CMHD_STDIN" <(printf '%s' "$1"); }

BLOCK='<context_window_protection> route through ctx_execute </context_window_protection>'
AGENT_PLAIN='{"tool_name":"Agent","tool_input":{"description":"x","prompt":"do the thing"}}'
AGENT_MARKED="{\"tool_name\": \"Agent\", \"tool_input\": {\"description\": \"x\", \"prompt\": \"do the thing\\n$BLOCK\"}}"
AGENT_MENTION='{"tool_name":"Agent","tool_input":{"prompt":"explain what the <context_window_protection> tag does"}}'
TASK_MARKED="{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"y $BLOCK\"}}"
BASH_MARKED="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo '$BLOCK'\"}}"
NL=$'\n'

# 1. Agent prompt that already carries the block -> passed through, upstream NOT called
run pretooluse "$AGENT_MARKED"
if [ "$RC" -eq 0 ] && [ "$CALLED" -eq 0 ] && [ ! -f "$CMHD_STDIN" ]; then
    _pass "Agent prompt already carrying the block is not re-injected"
else
    _fail "Agent prompt already carrying the block (rc=$RC called=$CALLED)"
fi

# 2. Same for the legacy Task tool name
run pretooluse "$TASK_MARKED"
if [ "$RC" -eq 0 ] && [ "$CALLED" -eq 0 ]; then
    _pass "Task prompt already carrying the block is not re-injected"
else
    _fail "Task prompt already carrying the block (rc=$RC called=$CALLED)"
fi

# 2b. Pretty-printed, multi-line payload (line breaks between keys and around the colon,
#     block content spanning real newlines) -> still recognised
AGENT_PRETTY=$'{\n  "tool_name"\n    :\n  "Agent",\n  "tool_input": {\n    "prompt": "do it <context_window_protection>\n  a\n  b\n</context_window_protection>"\n  }\n}'
run pretooluse "$AGENT_PRETTY"
if [ "$RC" -eq 0 ] && [ "$CALLED" -eq 0 ]; then
    _pass "multi-line pretty-printed Agent payload carrying the block is recognised"
else
    _fail "multi-line pretty-printed Agent payload (rc=$RC called=$CALLED)"
fi

# 2c. A prompt that QUOTES "tool_name": "Agent" inside a non-Agent call is not mistaken
#     for an Agent call: inside a JSON string the quotes are escaped (\")
BASH_QUOTING='{"tool_name":"Bash","tool_input":{"command":"echo \"tool_name\": \"Agent\" <context_window_protection>x</context_window_protection>"}}'
run pretooluse "$BASH_QUOTING"
if [ "$CALLED" -eq 1 ]; then
    _pass "escaped \"tool_name\": \"Agent\" inside a string does not trigger the guard"
else
    _fail "escaped tool_name inside a string triggered the guard (called=$CALLED)"
fi

# 2c. Auto mode: ANY hook rewrite of an Agent input makes auto mode refuse the launch,
#     so the dispatcher must not call upstream (which always rewrites) for Agent/Task.
AGENT_AUTO='{"tool_name":"Agent","permission_mode":"auto","tool_input":{"prompt":"do the thing"}}'
run pretooluse "$AGENT_AUTO"
if [ "$RC" -eq 0 ] && [ "$CALLED" -eq 0 ]; then
    _pass "Agent in auto mode is not rewritten"
else
    _fail "Agent in auto mode (rc=$RC called=$CALLED)"
fi
BASH_AUTO='{"tool_name":"Bash","permission_mode":"auto","tool_input":{"command":"ls"}}'
run pretooluse "$BASH_AUTO"
if [ "$CALLED" -eq 1 ]; then
    _pass "Bash in auto mode still reaches context-mode"
else
    _fail "Bash in auto mode (called=$CALLED)"
fi
AGENT_DEFAULT='{"tool_name":"Agent","permission_mode":"default","tool_input":{"prompt":"do the thing"}}'
run pretooluse "$AGENT_DEFAULT"
if [ "$CALLED" -eq 1 ]; then
    _pass "Agent in default mode still reaches context-mode"
else
    _fail "Agent in default mode (called=$CALLED)"
fi

# 3. Agent prompt WITHOUT the block -> upstream called once; pretooluse re-feeds the
#    payload with exactly one trailing newline (the only byte it may add)
run pretooluse "$AGENT_PLAIN"
if [ "$CALLED" -eq 1 ] && grep -q 'hook claude-code pretooluse' "$CMHD_CALLS" && received_is "$AGENT_PLAIN$NL"; then
    _pass "Agent prompt without the block reaches context-mode, payload + one newline"
else
    _fail "Agent prompt without the block (called=$CALLED got=$(cat "$CMHD_STDIN" 2>/dev/null))"
fi

# 4. A prompt that merely MENTIONS the tag (no closing tag) is still routed
run pretooluse "$AGENT_MENTION"
if [ "$CALLED" -eq 1 ] && received_is "$AGENT_MENTION$NL"; then
    _pass "Agent prompt that only mentions the tag is still routed"
else
    _fail "Agent prompt that only mentions the tag (called=$CALLED)"
fi

# 5. Non-Agent tool mentioning the block -> still dispatched (guard is Agent-only)
run pretooluse "$BASH_MARKED"
if [ "$CALLED" -eq 1 ] && received_is "$BASH_MARKED$NL"; then
    _pass "non-Agent pretooluse is dispatched even when it carries the block"
else
    _fail "non-Agent pretooluse (called=$CALLED)"
fi

# 6/7. Other events exec straight through: stdin byte-for-byte, even for an Agent payload
for ev in posttooluse sessionstart; do
    run "$ev" "$AGENT_MARKED"
    if [ "$CALLED" -eq 1 ] && grep -q "hook claude-code $ev" "$CMHD_CALLS" && received_is "$AGENT_MARKED"; then
        _pass "$ev dispatches with stdin byte-for-byte"
    else
        _fail "$ev (called=$CALLED got=$(cat "$CMHD_STDIN" 2>/dev/null))"
    fi
done

# 8. Missing event arg -> fail open
run "" "$AGENT_PLAIN"
if [ "$RC" -eq 0 ] && [ "$CALLED" -eq 0 ]; then
    _pass "missing event arg fails open"
else
    _fail "missing event arg (rc=$RC called=$CALLED)"
fi

# 9. No context-mode and no npx on PATH -> fail open (exit 0), for pretooluse and others.
#    The first call prints the notice and writes the (test-private) stamp; the second,
#    inside the 5-minute window, stays silent.
rm -f "$STAMP"
run pretooluse "$AGENT_PLAIN" "$TMP/bare"
if [ "$RC" -eq 0 ] && [ "$CALLED" -eq 0 ] && [[ "$ERR" == *"neither 'context-mode' nor 'npx' found"* ]] && [ -f "$STAMP" ]; then
    _pass "no runtime on PATH fails open with the notice (pretooluse)"
else
    _fail "no runtime on PATH (pretooluse): rc=$RC called=$CALLED err=$ERR stamp=$([ -f "$STAMP" ] && echo yes || echo no)"
fi
run posttooluse "$AGENT_PLAIN" "$TMP/bare"
if [ "$RC" -eq 0 ] && [ "$CALLED" -eq 0 ] && [ -z "$ERR" ]; then
    _pass "no runtime on PATH fails open, notice rate-limited (posttooluse)"
else
    _fail "no runtime on PATH (posttooluse): rc=$RC called=$CALLED err=$ERR"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
