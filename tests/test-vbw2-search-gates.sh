#!/bin/bash
# test-vbw2-search-gates.sh — search gates give vbw:* agents a route they can run (R4)
# vbw:* agents have Bash but no MCP tools. grep-cmm-gate (D1: redirect) blocks
# their code Grep with the exact cmm-query.sh wrapper command, which this test
# then runs; non-code Grep, a missing CMM CLI, an unindexed repo or a missing
# wrapper all fail open. cmm-grep-nudge either allows them or names the wrapper;
# cmm-nudge stays advisory and names the wrapper. Main-thread messages keep the
# mcp__ tool names.
# Usage: bash tests/test-vbw2-search-gates.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd -P)"

PASS=0
FAIL=0
_pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}
_fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}
_md5() { if command -v md5 >/dev/null 2>&1; then md5 -q; else md5sum | awk '{print $1}'; fi; }

T="$(mktemp -d)"
T="$(cd "$T" && pwd -P)"
SID="vbw2gates-$$"
_cleanup() {
    local r
    for r in "$T/repo" "$T/nowrap"; do
        rm -f "/tmp/cmm-session-ready-$(echo "$r" | _md5)" "/tmp/cmm-project-root-$(echo -n "$r" | _md5)"
    done
    rm -f /tmp/cmm-reads-"$SID"-* /tmp/cmm-reads-"$SID"main-* /tmp/cmm-reads-"$SID"nw-*
    rm -rf "$T"
}
trap _cleanup EXIT

# _repo <dir> [wrapper]: git repo, CMM registered in .mcp.json, indexed (sentinel),
# hooks in repo layout, a 60-line code file; with "wrapper", the installed wrapper.
_repo() {
    local r="$1"
    mkdir -p "$r/src" "$r/.vbw" "$r/hooks/project" "$r/hooks/global" "$r/hooks/lib"
    git -C "$r" init -q
    echo '{"mcpServers":{"codebase-memory-mcp":{"command":"codebase-memory-mcp"}}}' >"$r/.mcp.json"
    cp "$REPO/hooks/project/grep-cmm-gate.sh" "$REPO/hooks/project/track-hook-blocks.sh" "$r/hooks/project/"
    cp "$REPO/hooks/global/cmm-grep-nudge.sh" "$REPO/hooks/global/cmm-nudge.sh" "$r/hooks/global/"
    cp "$REPO/hooks/project/track-hook-blocks.sh" "$r/hooks/global/"
    cp "$REPO/hooks/lib/"*.sh "$r/hooks/lib/"
    for i in $(seq 1 30); do printf 'def f%s():\n    return %s\n' "$i" "$i"; done >"$r/src/app.py"
    printf '# spec\n' >"$r/.vbw/spec.md"
    echo ready >"/tmp/cmm-session-ready-$(echo "$r" | _md5)"
    if [ "${2:-}" = wrapper ]; then
        mkdir -p "$r/.claude/hooks/lib"
        [ -f "$REPO/hooks/project/cmm-query.sh" ] && cp "$REPO/hooks/project/cmm-query.sh" "$r/.claude/hooks/"
        cp "$REPO/hooks/lib/"*.sh "$r/.claude/hooks/lib/"
    fi
}
R="$T/repo"
_repo "$R" wrapper
_repo "$T/nowrap"

# Stub CMM CLI (logs argv) and a PATH without any CMM binary.
mkdir -p "$T/bin" "$T/nobin" "$T/home"
cat >"$T/bin/codebase-memory-mcp" <<'PY'
#!/usr/bin/env python3
import json, os, sys
json.dump(sys.argv[1:], open(os.environ["STUB_LOG"], "w"))
print("results: 1\n  stub.f1 Function src/app.py 1-2 0 0")
PY
chmod +x "$T/bin/codebase-memory-mcp"
STUB_LOG="$T/stub.json"
WITH_CLI="$T/bin:$PATH"
NO_CLI="$T/nobin"
IFS=':' read -ra _P <<<"$PATH"
for d in "${_P[@]}"; do
    [ -n "$d" ] && [ ! -x "$d/codebase-memory-mcp" ] && NO_CLI="$NO_CLI:$d"
done

# _hook <hook-path> <cwd> <PATH> <json>  -> sets RC, ERR (stderr), OUT (stdout)
_hook() {
    RC=0
    printf '%s' "$4" | (cd "$2" && HOME="$T/home" PATH="$3" bash "$1" >"$T/out" 2>"$T/err") || RC=$?
    OUT="$(cat "$T/out")"
    ERR="$(cat "$T/err")"
}
_grep_in() { # <tool_input-json> [agent_type] [cwd]
    TI="$1" AT="${2:-}" CWD="${3:-$R}" SID="$SID" python3 -c 'import json,os
d={"tool_name":"Grep","tool_input":json.loads(os.environ["TI"]),"cwd":os.environ["CWD"],"session_id":os.environ["SID"]}
if os.environ["AT"]: d["agent_type"]=os.environ["AT"]
print(json.dumps(d))'
}
_bash_in() { # <command> [agent_type]
    CMD="$1" AT="${2:-}" CWD="$R" python3 -c 'import json,os
d={"tool_name":"Bash","tool_input":{"command":os.environ["CMD"]},"cwd":os.environ["CWD"]}
if os.environ["AT"]: d["agent_type"]=os.environ["AT"]
print(json.dumps(d))'
}
_read_in() { # <file> <session> [agent_type]
    F="$1" S="$2" AT="${3:-}" python3 -c 'import json,os
d={"tool_name":"Read","tool_input":{"file_path":os.environ["F"]},"session_id":os.environ["S"]}
if os.environ["AT"]: d["agent_type"]=os.environ["AT"]
print(json.dumps(d))'
}
# _wrapper_line <text> -> the runnable wrapper command a message names (search tools)
_wrapper_line() {
    printf '%s\n' "$1" | grep -Eo "bash ['\"]?[^ ]*cmm-query\.sh['\"]? (search_graph|search_code) .*" | head -1 || true
}
# _runs <line> <want-tool> <want-term>: the named command runs and reaches CMM with the term
_runs() {
    local rc=0
    rm -f "$STUB_LOG"
    (cd "$R" && PATH="$WITH_CLI" STUB_LOG="$STUB_LOG" bash -c "$1") >/dev/null 2>&1 || rc=$?
    [ "$rc" = 0 ] && python3 - "$STUB_LOG" "$2" "$3" <<'PY' 2>/dev/null
import json, sys
a = json.load(open(sys.argv[1]))
assert sys.argv[2] in a and any(sys.argv[3] in x for x in a)
PY
}

GATE="$R/hooks/project/grep-cmm-gate.sh"
echo "--- grep-cmm-gate: vbw:* code Grep is redirected to a runnable wrapper command ---"
_hook "$GATE" "$R" "$WITH_CLI" "$(_grep_in "{\"pattern\":\"resolve_vbw_source\",\"path\":\"$R/src\"}" vbw:dev)"
LINE="$(_wrapper_line "$ERR")"
if [ "$RC" = 2 ] && [ -n "$LINE" ] && ! printf '%s' "$ERR" | grep -q 'mcp__'; then
    _pass "vbw:dev code Grep blocked with: $LINE"
else
    _fail "vbw:dev code Grep: expected exit 2 naming the wrapper and no mcp__ (rc=$RC, err=$ERR)"
fi
if [ -n "$LINE" ] && _runs "$LINE" search_graph resolve_vbw_source; then
    _pass "the named wrapper command runs and queries CMM for the term"
else
    _fail "the named wrapper command does not run or lost the term"
fi
if printf '%s' "$ERR" | grep -q '\[grep-cmm-gate\] BLOCKED'; then
    _pass "block keeps the [grep-cmm-gate] BLOCKED fingerprint"
else
    _fail "block lost the [grep-cmm-gate] BLOCKED fingerprint (make measure counts it)"
fi
_hook "$GATE" "$R" "$WITH_CLI" "$(_grep_in '{"pattern":"needle literal","type":"py"}' vbw:qa)"
LINE="$(_wrapper_line "$ERR")"
if [ "$RC" = 2 ] && [ -n "$LINE" ] && _runs "$LINE" search_code "needle literal"; then
    _pass "vbw:qa non-identifier code Grep -> runnable search_code wrapper command"
else
    _fail "vbw:qa non-identifier code Grep not redirected to a runnable search_code command (rc=$RC, err=$ERR)"
fi

echo "--- grep-cmm-gate: vbw:* Grep allowed where there is no graph route ---"
for ti in '{"pattern":"x","glob":"*.md"}' '{"pattern":"x","type":"json"}' "{\"pattern\":\"x\",\"path\":\"$R/.vbw\"}"; do
    _hook "$GATE" "$R" "$WITH_CLI" "$(_grep_in "$ti" vbw:dev)"
    [ "$RC" = 0 ] && _pass "non-code Grep allowed: $ti" || _fail "non-code Grep blocked: $ti (rc=$RC)"
done
_hook "$GATE" "$R" "$NO_CLI" "$(_grep_in "{\"pattern\":\"f1\",\"path\":\"$R/src\"}" vbw:dev)"
[ "$RC" = 0 ] && _pass "CMM CLI missing -> fail open for vbw:*" || _fail "CMM CLI missing still blocks vbw:* (rc=$RC)"
_hook "$GATE" "$T/nowrap" "$WITH_CLI" "$(_grep_in "{\"pattern\":\"f1\",\"path\":\"$T/nowrap/src\"}" vbw:dev "$T/nowrap")"
[ "$RC" = 0 ] && _pass "wrapper not installed -> fail open for vbw:*" || _fail "no wrapper installed but vbw:* blocked (rc=$RC)"
rm -f "/tmp/cmm-session-ready-$(echo "$R" | _md5)"
_hook "$GATE" "$R" "$WITH_CLI" "$(_grep_in "{\"pattern\":\"f1\",\"path\":\"$R/src\"}" vbw:dev)"
[ "$RC" = 0 ] && _pass "repo unindexed -> fail open for vbw:*" || _fail "unindexed repo still blocks vbw:* (rc=$RC)"
echo ready >"/tmp/cmm-session-ready-$(echo "$R" | _md5)"

echo "--- grep-cmm-gate: main thread unchanged ---"
_hook "$GATE" "$R" "$WITH_CLI" "$(_grep_in "{\"pattern\":\"resolve_vbw_source\",\"path\":\"$R/src\"}")"
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'mcp__codebase-memory-mcp__search_graph'; then
    _pass "main-thread code Grep still blocked with the MCP call"
else
    _fail "main-thread code Grep changed (rc=$RC)"
fi
_hook "$GATE" "$R" "$NO_CLI" "$(_grep_in "{\"pattern\":\"resolve_vbw_source\",\"path\":\"$R/src\"}")"
[ "$RC" = 2 ] && _pass "main thread does not fail open on a missing CLI (it has the MCP server)" ||
    _fail "main thread now fails open on a missing CLI (rc=$RC)"

NUDGE="$R/hooks/global/cmm-grep-nudge.sh"
echo "--- cmm-grep-nudge: vbw:* either allowed or given the wrapper ---"
_either() { # <label>
    if [ "$RC" = 0 ]; then
        _pass "$1: allowed"
    elif [ "$RC" = 2 ] && [ -n "$(_wrapper_line "$ERR")" ] && ! printf '%s' "$ERR" | grep -q 'mcp__'; then
        local line tool
        line="$(_wrapper_line "$ERR")"
        tool="$(printf '%s' "$line" | grep -Eo 'search_(graph|code)' | head -1)"
        if _runs "$line" "$tool" ""; then
            _pass "$1: blocked with a runnable wrapper command"
        else
            _fail "$1: names a wrapper command that does not run"
        fi
    else
        _fail "$1: blocked with no route a vbw:* agent can run (rc=$RC, err=$ERR)"
    fi
}
_hook "$NUDGE" "$R" "$WITH_CLI" "$(_grep_in '{"pattern":"helper","glob":"*.py"}' vbw:dev)"
_either "vbw:dev Grep glob *.py"
_hook "$NUDGE" "$R" "$WITH_CLI" "$(_bash_in 'grep -rn helper src/' vbw:dev)"
_either "vbw:dev Bash 'grep -rn helper src/'"
_hook "$NUDGE" "$R" "$NO_CLI" "$(_grep_in '{"pattern":"helper","glob":"*.py"}' vbw:dev)"
[ "$RC" = 0 ] && _pass "cmm-grep-nudge: CMM CLI missing -> fail open for vbw:*" || _fail "cmm-grep-nudge blocks vbw:* with no CLI (rc=$RC)"
_hook "$NUDGE" "$T/nowrap" "$WITH_CLI" "$(_grep_in '{"pattern":"helper","glob":"*.py"}' vbw:dev "$T/nowrap")"
[ "$RC" = 0 ] && _pass "cmm-grep-nudge: no wrapper installed -> fail open for vbw:*" || _fail "cmm-grep-nudge blocks vbw:* with no wrapper (rc=$RC)"
_hook "$NUDGE" "$R" "$WITH_CLI" "$(_grep_in '{"pattern":"helper","glob":"*.py"}')"
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'mcp__codebase-memory-mcp__search_graph'; then
    _pass "cmm-grep-nudge main thread unchanged"
else
    _fail "cmm-grep-nudge main thread changed (rc=$RC)"
fi

READ="$R/hooks/global/cmm-nudge.sh"
echo "--- cmm-nudge: advisory for vbw:*, names the wrapper ---"
_reads() { # <repo> <session> [agent_type] -> output of the 4th read (first past the budget)
    local i
    for i in 1 2 3 4; do _hook "$READ" "$1" "$WITH_CLI" "$(_read_in "$1/src/app.py" "$2" "${3:-}")"; done
}
_reads "$R" "$SID" vbw:dev
if [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q 'cmm-query\.sh' && ! printf '%s' "$OUT" | grep -q 'mcp__'; then
    _pass "vbw:dev 4th read: exit 0, nudge names the wrapper, no mcp__"
else
    _fail "vbw:dev 4th read nudge (rc=$RC, out=$OUT)"
fi
_reads "$T/nowrap" "${SID}nw" vbw:dev
if [ "$RC" = 0 ] && ! printf '%s' "$OUT" | grep -q 'mcp__'; then
    _pass "vbw:dev without a wrapper: exit 0, no MCP tool names"
else
    _fail "vbw:dev without a wrapper is told to use MCP tools (rc=$RC, out=$OUT)"
fi
_reads "$R" "${SID}main"
if [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q 'mcp__codebase-memory-mcp__get_code_snippet'; then
    _pass "main-thread nudge unchanged"
else
    _fail "main-thread nudge changed (rc=$RC, out=$OUT)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
