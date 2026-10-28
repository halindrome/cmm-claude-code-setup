#!/bin/bash
# test-cmm-query-install.sh — install, uninstall and enforcer route for the CMM wrapper (R5)
# setup.sh --project installs .claude/hooks/cmm-query.sh only when VBW 2 is
# detected, --uninstall removes it, and the wrapper's own command line (the one
# it prints when a project is not indexed) passes ctx-execute-enforcer and
# ctx-payload-guard for the main thread and vbw:* agents. Fixture plugin trees
# only; HOME, CLAUDE_CONFIG_DIR and PATH are scrubbed of the real VBW install.
# Usage: bash tests/test-cmm-query-install.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SETUP="$REPO/setup.sh"

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
_cleanup() {
    local p
    for p in "$T/v2/proj" "$T/none/proj"; do
        rm -f "/tmp/ctx-enforcer-$(echo "$p" | _md5)" "/tmp/context-mode-ready-$(echo "$p" | _md5)"
        rm -f "/tmp/cmm-project-root-$(echo -n "$p" | _md5)"
    done
    rm -rf "$T"
}
trap _cleanup EXIT

CLEAN_PATH=""
IFS=':' read -ra _P <<<"$PATH"
for d in "${_P[@]}"; do
    [ -n "$d" ] && [ ! -x "$d/vbw" ] && CLEAN_PATH="${CLEAN_PATH:+$CLEAN_PATH:}$d"
done

# _env <name> [vbw2] -> fresh HOME (+ VBW 2.1.18 fixture tree) and a git project
_env() {
    local h="$T/$1/home" d
    mkdir -p "$h/.config/claude-code/plugins" "$T/$1/proj"
    git -C "$T/$1/proj" init -q
    if [ "${2:-}" = vbw2 ]; then
        d="$h/.config/claude-code/plugins/cache/vbw-marketplace/vbw/2.1.18"
        mkdir -p "$d/agents" "$d/bin"
        echo 2.1.18 >"$d/VERSION"
        printf '#!/bin/bash\necho vbw\n' >"$d/bin/vbw"
        chmod +x "$d/bin/vbw"
        for a in architect lead dev qa scout debugger docs; do : >"$d/agents/$a.md"; done
    fi
}
_setup() { # <name> [extra args...]
    local n="$1"
    shift
    (cd "$T/$n/proj" && echo n | HOME="$T/$n/home" CLAUDE_CONFIG_DIR="$T/$n/home/.config/claude-code" PATH="$CLEAN_PATH" \
        bash "$SETUP" --project --yes --skip-mcp-check --skip-statusline --no-migrate "$@") >"$T/$n/setup.out" 2>&1 || true
}

echo "--- installed only when VBW 2 is detected ---"
_env v2 vbw2
_setup v2
W="$T/v2/proj/.claude/hooks/cmm-query.sh"
if [ -f "$W" ]; then _pass "VBW 2 detected -> .claude/hooks/cmm-query.sh installed"; else _fail "VBW 2 detected but cmm-query.sh not installed"; fi
if [ -f "$T/v2/proj/.claude/hooks/lib/project-root.sh" ] && [ -f "$T/v2/proj/.claude/hooks/lib/cmm-registered.sh" ]; then
    _pass "wrapper's libs installed beside it"
else
    _fail "project-root.sh / cmm-registered.sh missing from .claude/hooks/lib"
fi
_env none
_setup none
if [ ! -e "$T/none/proj/.claude/hooks/cmm-query.sh" ]; then _pass "no VBW 2 -> wrapper not installed"; else _fail "wrapper installed without VBW 2"; fi

echo "--- the wrapper's own command line passes the enforcer and payload guard ---"
LINE=""
if [ -f "$W" ]; then
    mkdir -p "$T/stub"
    printf '#!/bin/bash\necho %s\nexit 1\n' "'{\"error\":\"project not found or not indexed\"}'" >"$T/stub/codebase-memory-mcp"
    chmod +x "$T/stub/codebase-memory-mcp"
    OUT="$(cd "$T/v2/proj" && PATH="$T/stub:$CLEAN_PATH" bash "$W" search_graph '{"name_pattern":"x"}' 2>&1 || true)"
    LINE="$(printf '%s\n' "$OUT" | grep -Eo 'bash [^ ]*cmm-query\.sh index_repository' | head -1 || true)"
fi
if [ -n "$LINE" ]; then
    _pass "wrapper names its index command: $LINE"
    QLINE="${LINE% index_repository} search_graph '{\"name_pattern\":\"resolve_vbw_source\"}'"
    P="$T/v2/proj"
    HASH="$(echo "$P" | _md5)"
    echo 1 >"/tmp/ctx-enforcer-$HASH"
    echo live >"/tmp/context-mode-ready-$HASH"
    ENF="$P/.claude/hooks/ctx-execute-enforcer.sh"
    _enf() { # <command> [agent_type]
        local rc=0
        CMD="$1" AT="${2:-}" python3 -c 'import json,os
d={"tool_name":"Bash","tool_input":{"command":os.environ["CMD"]}}
if os.environ["AT"]: d["agent_type"]=os.environ["AT"]
print(json.dumps(d))' | (cd "$P" && HOME="$T/v2/home" bash "$ENF") >/dev/null 2>&1 || rc=$?
        echo "$rc"
    }
    [ "$(_enf 'pytest')" = 2 ] && _pass "enforcer is armed in the fixture (main-thread pytest blocked)" ||
        _fail "enforcer not armed in the fixture; the cases below would prove nothing"
    for c in "$LINE" "$QLINE"; do
        [ "$(_enf "$c")" = 0 ] && _pass "enforcer allows (main thread): $c" || _fail "enforcer blocks (main thread): $c"
        [ "$(_enf "$c" vbw:dev)" = 0 ] && _pass "enforcer allows (vbw:dev): $c" || _fail "enforcer blocks (vbw:dev): $c"
    done
    [ "$(_enf "$QLINE | head -5")" = 2 ] && _pass "compound wrapper call still blocked for the main thread" ||
        _fail "compound wrapper call exempted for the main thread"
    [ "$(_enf "$QLINE > out.txt")" = 2 ] && _pass "redirected wrapper call still blocked for the main thread" ||
        _fail "redirected wrapper call exempted for the main thread"
    PG="$P/.claude/hooks/ctx-payload-guard.sh"
    rc=0
    CMD="$QLINE" python3 -c 'import json,os; print(json.dumps({"tool_name":"mcp__plugin_context-mode_context-mode__ctx_execute","tool_input":{"language":"shell","code":os.environ["CMD"],"intent":"x"}}))' |
        (cd "$P" && HOME="$T/v2/home" bash "$PG") >/dev/null 2>&1 || rc=$?
    [ "$rc" = 0 ] && _pass "ctx-payload-guard allows the wrapper call inside ctx_execute" || _fail "ctx-payload-guard blocks the wrapper call (rc=$rc)"
else
    _fail "installed wrapper did not print its index_repository command line"
fi

echo "--- uninstall removes it ---"
WAS_INSTALLED=false
[ -f "$W" ] && WAS_INSTALLED=true
_setup v2 --uninstall
if [ "$WAS_INSTALLED" = true ] && [ ! -e "$W" ]; then
    _pass "--uninstall removed .claude/hooks/cmm-query.sh"
else
    _fail "--uninstall: wrapper was not installed first, or is still present"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
