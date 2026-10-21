#!/bin/bash
# test-ctx-shell-compat.sh — Tests for hooks/project/ctx-shell-compat.sh.
#
# The hook warns when a Context Mode shell payload uses bash-only syntax.
# context-mode resolves ONE "shell" runtime ($SHELL when allowlisted, else bash),
# so on a default macOS install every language="shell" payload runs zsh, and
# language="bash" cannot select bash because there is no such runtime key.
#
# It is ADVISORY: it must NEVER exit non-zero. A false block here would stop
# legitimate work -- a bash-only construct inside a heredoc bound for a remote
# bash is perfectly valid.
#
# Usage: bash tests/test-ctx-shell-compat.sh
# Exit: 0 = all pass, 1 = any failure
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
HOOK="$ROOT/hooks/project/ctx-shell-compat.sh"

PASS=0; FAIL=0
pass() { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

PLUGIN="mcp__plugin_context-mode_context-mode__ctx_execute"
LEGACY="mcp__context-mode__ctx_execute"
PBATCH="mcp__plugin_context-mode_context-mode__ctx_batch_execute"

_json() {
  python3 -c '
import json,sys
print(json.dumps({"tool_name": sys.argv[1],
                  "tool_input": {"language": sys.argv[2], "code": sys.argv[3]}}))
' "$1" "$2" "$3"
}
_batch() {
  python3 -c '
import json,sys
cmds=[{"label":"c%d"%i,"command":c} for i,c in enumerate(sys.argv[2:])]
print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"commands": cmds}}))
' "$1" "$@"
}
_out() { printf '%s' "$1" | bash "$HOOK" 2>/dev/null; }
_rc()  { printf '%s' "$1" | bash "$HOOK" >/dev/null 2>&1; echo "$?"; }

_warns() { # _warns <label> <json> <substring>
  local o; o=$(_out "$2")
  if printf '%s' "$o" | grep -qF -- "$3"; then pass "$1"; else fail "$1 (no warning for: $3)"; fi
}
_silent() { # _silent <label> <json>
  local o; o=$(_out "$2")
  if [ -z "$o" ]; then pass "$1"; else fail "$1 (unexpected output: $o)"; fi
}

echo ""
echo "=== ctx-shell-compat ==="
echo ""
echo "--- hook present ---"
if [ -f "$HOOK" ]; then pass "hook present"; else fail "hook missing"; exit 1; fi

echo ""
echo "--- NEVER blocks (advisory only) ---"
# The single most important property. Every case below must exit 0.
for probe in 'v=x; echo ${!v}' 'mapfile -t a < f' 'declare -n ref=x' \
             'echo ${s^^}' 'read -a arr <<< "x y"' 'for f in $files; do :; done' \
             'echo ok' ''; do
  rc=$(_rc "$(_json "$PLUGIN" shell "$probe")")
  if [ "$rc" -eq 0 ]; then
    pass "exit 0 for: ${probe:-(empty)}"
  else
    fail "exit $rc for: ${probe:-(empty)} — this hook must never block"
  fi
done
if printf '' | bash "$HOOK" >/dev/null 2>&1; then pass "exit 0 on empty stdin"; else fail "empty stdin"; fi
if printf 'not-json' | bash "$HOOK" >/dev/null 2>&1; then pass "exit 0 on malformed JSON"; else fail "malformed JSON"; fi

echo ""
echo "--- warns on bash-only constructs, naming the zsh replacement ---"
_warns "warns on \${!var}"        "$(_json "$PLUGIN" shell 'v=x; echo ${!v}')" '${(P)var}'
_warns "warns on mapfile"         "$(_json "$PLUGIN" shell 'mapfile -t a < f')" '(@f)'
_warns "warns on declare -n"      "$(_json "$PLUGIN" shell 'declare -n ref=x')" 'nameref'
_warns "warns on \${var^^}"       "$(_json "$PLUGIN" shell 'echo ${s^^}')" '${var:u}'
_warns "warns on read -a"         "$(_json "$PLUGIN" shell 'read -a arr <<< "x y"')" 'read -A'

echo ""
echo "--- the silent failure gets the loudest explanation ---"
# zsh does not word-split an unquoted $var, so this iterates once over the whole
# string and reports nothing. There is no error to notice, which is why the
# advisory has to say so explicitly.
_W="$(_json "$PLUGIN" shell 'for f in $files; do echo $f; done')"
_warns "warns on unquoted word-split loop" "$_W" 'iterates ONCE'
_warns "word-split warning says it is silent" "$_W" 'SILENTLY'

echo ""
echo "--- states the actual runtime ---"
_warns "names \$SHELL/zsh"            "$(_json "$PLUGIN" shell 'echo ${!v}')" 'zsh'
_warns "says language=bash won't help" "$(_json "$PLUGIN" shell 'echo ${!v}')" 'not a distinct runtime'
_warns "marks itself advisory"         "$(_json "$PLUGIN" shell 'echo ${!v}')" 'Advisory only'

echo ""
echo "--- emits a valid PreToolUse envelope ---"
_E=$(_out "$(_json "$PLUGIN" shell 'echo ${!v}')")
if printf '%s' "$_E" | python3 -c '
import json,sys
d=json.load(sys.stdin)
o=d["hookSpecificOutput"]
assert o["hookEventName"]=="PreToolUse", o
assert isinstance(o["additionalContext"], str) and o["additionalContext"]
' 2>/dev/null; then
  pass "valid hookSpecificOutput JSON"
else
  fail "output is not a valid PreToolUse envelope"
fi

echo ""
echo "--- coverage across tools and name forms ---"
_warns "legacy name form covered" "$(_json "$LEGACY" shell 'echo ${!v}')" '${(P)var}'
_warns "batch commands[] scanned" "$(_batch "$PBATCH" 'git status' 'echo ${!v}')" '${(P)var}'

echo ""
echo "--- silent where it should be ---"
_silent "clean shell payload"     "$(_json "$PLUGIN" shell 'grep -rn foo src/')"
_silent "unrelated tool"          "$(_json "Bash" shell 'echo ${!v}')"
# '${!v}' is not bash-only syntax in another language; do not warn on it there.
_silent "python payload skipped"     "$(_json "$PLUGIN" python 'x = {"a": 1}')"
_silent "javascript payload skipped" "$(_json "$PLUGIN" javascript 'const a = b > c')"
_silent "perl payload skipped"       "$(_json "$PLUGIN" perl 'my %h = (a => 1);')"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
