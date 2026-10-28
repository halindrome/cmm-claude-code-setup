#!/bin/bash
# test-vbw2-subagent-guidance.sh — SubagentStart guidance for VBW 2 agents (R6, R11)
# subagent-cmm-startup.sh must give each of the 7 vbw:* agent types CMM-first
# code-search guidance they can run with Bash: exact cmm-query.sh command lines,
# this repo's project, no mcp__/ctx_execute/Skill( calls, when Grep/Read still
# fit, and no command that would fail when the CLI is missing or the repo is
# not indexed. The scout gets mapping guidance (R11). Non-VBW agents unchanged.
# Usage: bash tests/test-vbw2-subagent-guidance.sh [agents|mapping]
#   agents  = R6 cases, mapping = R11 cases; no argument runs both.
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ONLY="${1:-}"
case "$ONLY" in "" | agents | mapping) ;; *)
    echo "unknown case group: $ONLY (agents|mapping)" >&2
    exit 2
    ;;
esac

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
R="$T/repo"
_cleanup() {
    rm -f "/tmp/cmm-session-ready-$(echo "$R" | _md5)" "/tmp/cmm-project-root-$(echo -n "$R" | _md5)"
    rm -rf "$T"
}
trap _cleanup EXIT

# Installed layout: hook, libs and the wrapper under .claude/hooks.
mkdir -p "$R/.claude/hooks/lib" "$T/home" "$T/bin" "$T/nobin"
git -C "$R" init -q
cp "$REPO/hooks/project/subagent-cmm-startup.sh" "$R/.claude/hooks/"
cp "$REPO/hooks/lib/"*.sh "$R/.claude/hooks/lib/"
[ -f "$REPO/hooks/project/cmm-query.sh" ] && cp "$REPO/hooks/project/cmm-query.sh" "$R/.claude/hooks/"
PROJ="$(PROJECT_ROOT="$R" bash -c 'source "$0"; cmm_project_name' "$REPO/hooks/lib/cmm-registered.sh")"

# Stub CMM CLI: answers like an indexed project unless STUB_MODE=notindexed.
cat >"$T/bin/codebase-memory-mcp" <<'PY'
#!/usr/bin/env python3
import os, sys
if os.environ.get("STUB_MODE") == "notindexed":
    print('{"error":"project not found or not indexed"}')
    sys.exit(1)
print('{"project":"p","status":"indexed","nodes":10}')
PY
chmod +x "$T/bin/codebase-memory-mcp"
NO_CLI="$T/nobin"
IFS=':' read -ra _P <<<"$PATH"
for d in "${_P[@]}"; do
    [ -n "$d" ] && [ ! -x "$d/codebase-memory-mcp" ] && NO_CLI="$NO_CLI:$d"
done

# Indexed state: session sentinel + CMM db file + stub answering "indexed".
_indexed() {
    echo ready >"/tmp/cmm-session-ready-$(echo "$R" | _md5)"
    mkdir -p "$T/home/.cache/codebase-memory-mcp"
    : >"$T/home/.cache/codebase-memory-mcp/$PROJ.db"
    STUB_MODE=ok
}
_unindexed() {
    rm -f "/tmp/cmm-session-ready-$(echo "$R" | _md5)" "$T/home/.cache/codebase-memory-mcp/$PROJ.db"
    STUB_MODE=notindexed
}
# _ctx <agent_type> [PATH] -> the additionalContext the hook emits
_ctx() {
    AT="$1" CWD="$R" python3 -c 'import json,os; print(json.dumps({"hook_event_name":"SubagentStart","agent_type":os.environ["AT"],"agent_id":"a1","session_id":"s1","cwd":os.environ["CWD"]}))' |
        (cd "$R" && HOME="$T/home" PATH="${2:-$T/bin:$PATH}" STUB_MODE="$STUB_MODE" bash "$R/.claude/hooks/subagent-cmm-startup.sh" 2>/dev/null) |
        python3 -c 'import json,sys
try: print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception: print("")'
}
QUERY_RE='cmm-query\.sh['"'"'"]? (search_graph|trace_path|get_code_snippet|search_code)'

if [ -z "$ONLY" ] || [ "$ONLY" = agents ]; then
    echo "--- R6: every vbw:* agent gets runnable wrapper guidance ---"
    _indexed
    for a in architect lead dev qa scout debugger docs; do
        C="$(_ctx "vbw:$a")"
        miss=""
        for tool in search_graph trace_path get_code_snippet search_code; do
            printf '%s\n' "$C" | grep -Eq "bash ['\"]?$R/\.claude/hooks/cmm-query\.sh['\"]? $tool" || miss="$miss $tool"
        done
        [ -z "$miss" ] && _pass "vbw:$a: wrapper command lines for all four query tools" ||
            _fail "vbw:$a: missing wrapper command lines for:$miss"
        printf '%s' "$C" | grep -qF "$PROJ" && _pass "vbw:$a: names project $PROJ" || _fail "vbw:$a: project $PROJ not named"
        if printf '%s' "$C" | grep -Eq 'mcp__|ctx_execute|ctx_batch_execute|Skill\('; then
            _fail "vbw:$a: names a tool it does not have (mcp__/ctx_*/Skill)"
        else
            _pass "vbw:$a: no mcp__, ctx_* or Skill( calls"
        fi
        if printf '%s' "$C" | grep -q 'Grep' && printf '%s' "$C" | grep -Eqi 'config|non-code'; then
            _pass "vbw:$a: says when Grep/Read still fit (non-code, configs)"
        else
            _fail "vbw:$a: does not say when Grep/Read still fit"
        fi
    done

    echo "--- R6: never a command that would fail ---"
    C="$(_ctx vbw:dev "$NO_CLI")"
    if ! printf '%s' "$C" | grep -Eq "$QUERY_RE" && ! printf '%s' "$C" | grep -q 'mcp__'; then
        _pass "CMM CLI missing: no wrapper query lines, no MCP calls"
    else
        _fail "CMM CLI missing: guidance still instructs commands that will fail"
    fi
    _unindexed
    C="$(_ctx vbw:dev)"
    if printf '%s' "$C" | grep -Eq "$QUERY_RE" && ! printf '%s' "$C" | grep -q 'cmm-query\.sh['"'"'"]\? index_repository'; then
        _fail "unindexed repo: query commands given without the index_repository wrapper command"
    elif printf '%s' "$C" | grep -q 'mcp__'; then
        _fail "unindexed repo: guidance names MCP calls"
    else
        _pass "unindexed repo: says how to index (or omits CMM advice), no failing command"
    fi
    _indexed

    echo "--- R6: non-VBW agents keep their guidance ---"
    C="$(_ctx general-purpose)"
    if printf '%s' "$C" | grep -q 'use it for all code navigation' && printf '%s' "$C" | grep -q "Skill('cmm-rules')"; then
        _pass "general-purpose guidance unchanged"
    else
        _fail "general-purpose guidance changed"
    fi
fi

if [ -z "$ONLY" ] || [ "$ONLY" = mapping ]; then
    echo "--- R11: scouts take structure from the graph and point the map at it ---"
    _indexed
    C="$(_ctx vbw:scout)"
    if printf '%s' "$C" | grep -Eq "cmm-query\.sh['\"]? get_architecture" && printf '%s' "$C" | grep -Eq "cmm-query\.sh['\"]? search_graph"; then
        _pass "vbw:scout: get_architecture and search_graph wrapper commands"
    else
        _fail "vbw:scout: no get_architecture/search_graph wrapper commands"
    fi
    if printf '%s' "$C" | grep -Eqi 'before (read|opening|reading)'; then
        _pass "vbw:scout: structure from the graph before reading files"
    else
        _fail "vbw:scout: not told to take structure from the graph before reading files"
    fi
    if printf '%s' "$C" | grep -Eq 'map' && printf '%s' "$C" | grep -Eq 'Structure|Stack and commands' &&
        printf '%s' "$C" | grep -Eqi 'project'; then
        _pass "vbw:scout: told to put the CMM project and wrapper command in a map section"
    else
        _fail "vbw:scout: no instruction to name the CMM project and wrapper in the map (Structure / Stack and commands)"
    fi
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
