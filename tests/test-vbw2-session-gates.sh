#!/bin/bash
# test-vbw2-session-gates.sh — session-gate and agent-cmm-gate never strand a vbw:* agent (R4)
# A vbw:* agent cannot call MCP tools, ctx_stats or create sentinels by hand.
# session-gate must either allow it or name a cmm-query.sh call that, once run,
# lifts the block (proven here); the Context Mode gate must not hold it.
# agent-cmm-gate must not block an Agent spawn of a vbw:* subagent for lacking
# CMM keywords, and the docs must say workflow-spawned vbw:* agents never pass
# through that gate. Main-thread and non-VBW behavior is unchanged.
# Usage: bash tests/test-vbw2-session-gates.sh
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
_hashes() {
    local r
    for r in "$T/repo" "$T/nowrap"; do echo "$r" | _md5; done
}
_cleanup() {
    local h r
    for h in $(_hashes); do
        rm -f "/tmp/cmm-session-ready-$h" "/tmp/cmm-indexing-$h" "/tmp/cmm-indexer-$h.pid" \
            "/tmp/context-mode-ready-$h" "/tmp/ctx-session-gate-$h"
    done
    for r in "$T/repo" "$T/nowrap"; do rm -f "/tmp/cmm-project-root-$(echo -n "$r" | _md5)"; done
    rm -rf "$T"
}
trap _cleanup EXIT

# _repo <dir> [wrapper]: hooks in installed layout (.claude/hooks + lib)
_repo() {
    local r="$1"
    mkdir -p "$r/.claude/hooks/lib" "$r/.claude/rules"
    git -C "$r" init -q
    cp "$REPO/hooks/project/session-gate.sh" "$REPO/hooks/project/agent-cmm-gate.sh" "$r/.claude/hooks/"
    cp "$REPO/hooks/lib/"*.sh "$r/.claude/hooks/lib/"
    cp "$REPO/rules/cmm-agent-preamble.md" "$r/.claude/rules/" 2>/dev/null || true
    if [ "${2:-}" = wrapper ] && [ -f "$REPO/hooks/project/cmm-query.sh" ]; then
        cp "$REPO/hooks/project/cmm-query.sh" "$r/.claude/hooks/"
    fi
}
R="$T/repo"
_repo "$R" wrapper
_repo "$T/nowrap"
H="$(echo "$R" | _md5)"
HN="$(echo "$T/nowrap" | _md5)"

mkdir -p "$T/bin" "$T/home"
cat >"$T/bin/codebase-memory-mcp" <<'PY'
#!/usr/bin/env python3
import sys
print('{"project":"x","status":"indexed"}')
PY
chmod +x "$T/bin/codebase-memory-mcp"
P_CLI="$T/bin:$PATH"

_hook() { # <repo> <hook> <json>  -> RC, ERR
    RC=0
    printf '%s' "$3" | (cd "$1" && HOME="$T/home" PATH="$P_CLI" CMM_AGENT_GATE_WAIT_SECS=0 bash "$1/.claude/hooks/$2" >"$T/out" 2>"$T/err") || RC=$?
    ERR="$(cat "$T/err")"
}
_edit() { # <repo> [agent_type]
    F="$1/x.txt" AT="${2:-}" python3 -c 'import json,os
d={"tool_name":"Edit","tool_input":{"file_path":os.environ["F"],"old_string":"a","new_string":"b"}}
if os.environ["AT"]: d["agent_type"]=os.environ["AT"]
print(json.dumps(d))'
}
_reset() { rm -f "/tmp/cmm-session-ready-$1" "/tmp/cmm-indexing-$1" "/tmp/cmm-indexer-$1.pid" "/tmp/context-mode-ready-$1" "/tmp/ctx-session-gate-$1"; }

echo "--- session-gate, CMM index not refreshed ---"
_reset "$H"
_hook "$R" session-gate.sh "$(_edit "$R" vbw:dev)"
if [ "$RC" = 0 ]; then
    _pass "vbw:dev Edit allowed while the index is not refreshed"
elif [ "$RC" = 2 ] && ! printf '%s' "$ERR" | grep -q 'mcp__'; then
    LINE="$(printf '%s\n' "$ERR" | grep -Eo "bash ['\"]?[^ ]*cmm-query\.sh['\"]? index_repository.*" | head -1 || true)"
    if [ -n "$LINE" ]; then
        rc=0
        (cd "$R" && HOME="$T/home" PATH="$P_CLI" bash -c "$LINE") >/dev/null 2>&1 || rc=$?
        _hook "$R" session-gate.sh "$(_edit "$R" vbw:dev)"
        if [ "$rc" = 0 ] && [ "$RC" = 0 ]; then
            _pass "vbw:dev block names '$LINE'; running it lifts the block"
        else
            _fail "running '$LINE' (rc=$rc) did not lift the block (gate rc=$RC)"
        fi
    else
        _fail "vbw:dev blocked without a cmm-query.sh index_repository command (err=$ERR)"
    fi
else
    _fail "vbw:dev blocked with MCP-only instructions it cannot follow (rc=$RC, err=$ERR)"
fi
_reset "$HN"
_hook "$T/nowrap" session-gate.sh "$(_edit "$T/nowrap" vbw:dev)"
[ "$RC" = 0 ] && _pass "vbw:dev with no wrapper installed is not held at the gate" ||
    _fail "vbw:dev with no wrapper installed is blocked with no route (rc=$RC)"
_reset "$H"
_hook "$R" session-gate.sh "$(_edit "$R")"
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'mcp__codebase-memory-mcp__index_repository'; then
    _pass "main thread still blocked with the MCP index call"
else
    _fail "main-thread session gate changed (rc=$RC)"
fi
_hook "$R" session-gate.sh "$(_edit "$R" general-purpose)"
[ "$RC" = 2 ] && _pass "non-VBW agent still blocked" || _fail "non-VBW agent no longer gated (rc=$RC)"

echo "--- session-gate, Context Mode installed but not initialized ---"
_reset "$H"
echo ready >"/tmp/cmm-session-ready-$H"
echo 1 >"/tmp/ctx-session-gate-$H"
_hook "$R" session-gate.sh "$(_edit "$R" vbw:dev)"
[ "$RC" = 0 ] && _pass "vbw:dev not held for a Context Mode sentinel it cannot create" ||
    _fail "vbw:dev held for the Context Mode sentinel (rc=$RC)"
_hook "$R" session-gate.sh "$(_edit "$R")"
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'Context Mode is installed but not yet initialized'; then
    _pass "main thread still held for Context Mode"
else
    _fail "main-thread Context Mode gate changed (rc=$RC)"
fi

echo "--- agent-cmm-gate ---"
PROMPT="Implement the plan: edit the hook script and the source file, refactor the function that parses the schema, update the module and its imports, then debug the failing endpoint. Read each file you change and keep the package layout as it is. This prompt is deliberately longer than three hundred characters so the short-prompt exemption does not apply."
_agent() { # <subagent_type>
    S="$1" PR="$PROMPT" python3 -c 'import json,os; print(json.dumps({"tool_name":"Agent","tool_input":{"subagent_type":os.environ["S"],"prompt":os.environ["PR"]}}))'
}
_hook "$R" agent-cmm-gate.sh "$(_agent vbw:dev)"
[ "$RC" = 0 ] && _pass "Agent spawn of vbw:dev not blocked for missing CMM keywords" ||
    _fail "Agent spawn of vbw:dev blocked for missing CMM keywords (rc=$RC)"
_hook "$R" agent-cmm-gate.sh "$(_agent vbw:scout)"
[ "$RC" = 0 ] && _pass "Agent spawn of vbw:scout not blocked" || _fail "Agent spawn of vbw:scout blocked (rc=$RC)"
_hook "$R" agent-cmm-gate.sh "$(_agent general-purpose)"
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'BLOCKED: Agent prompt does not reference codebase-memory-mcp'; then
    _pass "non-VBW Agent spawn still gated"
else
    _fail "non-VBW Agent spawn no longer gated (rc=$RC)"
fi
if grep -Eq 'vbw:\*.*(agent-cmm-gate|Workflow)|(agent-cmm-gate|Workflow).*vbw:\*' "$REPO/rules/cmm-rules.md"; then
    _pass "rules/cmm-rules.md documents that workflow-spawned vbw:* agents bypass agent-cmm-gate"
else
    _fail "rules/cmm-rules.md does not document workflow-spawned vbw:* agents and agent-cmm-gate"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
