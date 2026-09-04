#!/bin/bash
# test-ctx-payload-guard.sh — Tests for hooks/project/ctx-payload-guard.sh.
# The hook blocks output truncation inside Context Mode payloads: piping stdout
# into head/tail, and redirecting stdout to a file. Both discard bytes before
# ctx_* can index them.
#
# The PASS cases here are the load-bearing half. An over-firing gate is worse
# than no gate: measured redirect behaviour shows agents pivot back to raw tools
# when a block names no usable alternative, so every legitimate shell idiom must
# survive. These cases mirror scripts/analyze-antipatterns.py --selftest.
#
# Usage: bash tests/test-ctx-payload-guard.sh
# Exit: 0 = all pass, 1 = any failure
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
HOOK="$ROOT/hooks/project/ctx-payload-guard.sh"

PASS=0; FAIL=0
pass() { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

PLUGIN="mcp__plugin_context-mode_context-mode__ctx_execute"
LEGACY="mcp__context-mode__ctx_execute"
PFILE="mcp__plugin_context-mode_context-mode__ctx_execute_file"
PBATCH="mcp__plugin_context-mode_context-mode__ctx_batch_execute"
LBATCH="mcp__context-mode__ctx_batch_execute"

# _json <tool> <language> <code>  -> stdin payload for the hook
_json() {
  python3 -c '
import json,sys
print(json.dumps({"tool_name": sys.argv[1],
                  "tool_input": {"language": sys.argv[2], "code": sys.argv[3]}}))
' "$1" "$2" "$3"
}

# _batch <tool> <cmd0> [cmd1...]
_batch() {
  local tool="$1"; shift
  python3 -c '
import json,sys
cmds=[{"label":"c%d"%i,"command":c} for i,c in enumerate(sys.argv[2:])]
print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"commands": cmds}}))
' "$tool" "$@"
}

_run() { printf '%s' "$1" | bash "$HOOK" 2>/tmp/ctxpg-err.$$; echo "$?"; }

_blocks() { # _blocks <label> <json>
  local rc; rc=$(_run "$2")
  if [ "$rc" -eq 2 ]; then pass "$1"; else fail "$1 (expected exit 2, got $rc)"; fi
}
_allows() { # _allows <label> <json>
  local rc; rc=$(_run "$2")
  if [ "$rc" -eq 0 ]; then pass "$1"; else fail "$1 (expected exit 0, got $rc)"; fi
}
_stderr_has() { # _stderr_has <label> <json> <substring>
  _run "$2" >/dev/null
  if grep -qF -- "$3" "/tmp/ctxpg-err.$$"; then pass "$1"; else fail "$1 (stderr lacks: $3)"; fi
}
_stderr_lacks() {
  _run "$2" >/dev/null
  if grep -qF -- "$3" "/tmp/ctxpg-err.$$"; then fail "$1 (stderr still has: $3)"; else pass "$1"; fi
}
# The REPLACE WITH block only — the first line of the message names the offending
# token on purpose, so a whole-stderr check can never distinguish "the message
# mentions `| head -5`" from "the suggested call still runs `| head -5`". The
# block spans several lines when the payload does, so scoping to the single line
# containing `ctx_execute(` is not enough either.
_suggest_lacks() { # _suggest_lacks <label> <json> <substring>
  _run "$2" >/dev/null
  local s; s=$(awk '/REPLACE WITH:/{f=1;next} f&&/^$/{exit} f' "/tmp/ctxpg-err.$$")
  if printf '%s' "$s" | grep -qF -- "$3"; then
    fail "$1 (REPLACE WITH still has: $3)"
  else
    pass "$1"
  fi
}
trap 'rm -f /tmp/ctxpg-err.$$' EXIT

echo ""
echo "=== ctx-payload-guard ==="
echo ""
echo "--- hook exists and is executable-ready ---"
if [ -f "$HOOK" ]; then pass "hook present"; else fail "hook missing"; exit 1; fi

echo ""
echo "--- BLOCK: pipe-to-truncate, across all tools and both name forms ---"
for t in "$PLUGIN" "$LEGACY" "$PFILE"; do
  _blocks "blocks '| head -20' on ${t##*__}" "$(_json "$t" shell 'orb list 2>&1 | head -20')"
done
_blocks "blocks '| tail -50'"        "$(_json "$PLUGIN" shell 'cmd | tail -50')"
_blocks "blocks '| head -c 2000'"    "$(_json "$PLUGIN" shell 'cmd | head -c 2000')"
_blocks "blocks top-N derivation"    "$(_json "$PLUGIN" shell 'find . | sort | uniq -c | sort -rn | head -20')"

echo ""
echo "--- BLOCK: stdout redirected to a file (fd 1 only) ---"
_blocks "blocks '> out.log'"         "$(_json "$PLUGIN" shell 'cmd > out.log')"
_blocks "blocks explicit '1> out.log'" "$(_json "$PLUGIN" shell 'cmd 1> out.log')"
_blocks "blocks '>> run.txt'"        "$(_json "$PLUGIN" shell 'cmd >> run.txt')"
_blocks "blocks '> out.log 2>&1'"    "$(_json "$PLUGIN" shell 'cmd > out.log 2>&1')"
_blocks "blocks '&> everything.log'" "$(_json "$PLUGIN" shell 'cmd &> everything.log')"

echo ""
echo "--- BLOCK: batch names the offending entry ---"
_blocks "blocks when any commands[] entry truncates" \
  "$(_batch "$PBATCH" 'git status' 'cmd | tail -50')"
_stderr_has "batch block names commands[1]" \
  "$(_batch "$PBATCH" 'git status' 'cmd | tail -50')" "commands[1]"
_stderr_has "batch block offers queries= not intent=" \
  "$(_batch "$PBATCH" 'git status' 'cmd | tail -50')" "queries="
_blocks "blocks batch on legacy name form" \
  "$(_batch "$LBATCH" 'cmd | head -5')"

echo ""
echo "--- PASS: stream splitting is never an anti-pattern ---"
# Only stdout leaving the pipeline defeats capture. stderr handling is hygiene.
_allows "allows '2> err.log'"        "$(_json "$PLUGIN" shell 'cmd 2> err.log')"
_allows "allows '2>/dev/null'"       "$(_json "$PLUGIN" shell 'cmd 2>/dev/null')"
_allows "allows '2>&1'"              "$(_json "$PLUGIN" shell 'cmd 2>&1')"
_allows "allows '3> trace.log'"      "$(_json "$PLUGIN" shell 'cmd 3> trace.log')"
_allows "allows '>&2'"               "$(_json "$PLUGIN" shell 'echo hi >&2')"
_allows "allows '> /dev/null'"       "$(_json "$PLUGIN" shell 'cmd > /dev/null')"

echo ""
echo "--- PASS: legitimate shell idioms ---"
_allows "allows '| tee' (stdout still flows)" "$(_json "$PLUGIN" shell 'cmd 2>&1 | tee run.log')"
_allows "allows bare 'head file'"    "$(_json "$PLUGIN" shell 'head -50 CHANGELOG.md')"
_allows "allows 'tail -f'"           "$(_json "$PLUGIN" shell 'tail -f app.log')"
_allows "allows redirect whose target is read back" \
  "$(_json "$PLUGIN" shell 'cmd > out.log && grep foo out.log')"
_allows "allows head inside command substitution" \
  "$(_json "$PLUGIN" shell 'V=$(git rev-list --count HEAD | head -1)')"
_allows "allows heredoc file authoring" \
  "$(_json "$PLUGIN" shell "$(printf 'cat > script.sh <<%s\ncmd | head -5\nEOF' "'EOF'")")"
_allows "allows '| head' inside a quoted string" \
  "$(_json "$PLUGIN" shell 'echo "a | head"')"
_allows "allows '>' inside a quoted string" \
  "$(_json "$PLUGIN" shell "grep 'x > y' file")"
_allows "allows '||' (not a truncating pipe)" "$(_json "$PLUGIN" shell 'a || b')"

echo ""
echo "--- a here-STRING must not be mistaken for a here-DOC ---"
# `<<< word` matched the heredoc pattern, took the word as a terminator, and
# blanked every following line until one equalled it -- scrubbing away real
# truncations later in a multi-line payload. Fail-open, so it hid blocks.
_blocks "truncation after a here-string is still caught" \
  "$(_json "$PLUGIN" shell "$(printf 'read -ra a <<< x\ncmd | head -5')")"
_blocks "redirect on a here-string line is still caught" \
  "$(_json "$PLUGIN" shell 'cmd <<< x > out.log')"

echo ""
echo "--- PASS: writing a file with literal content is authoring, not truncation ---"
# Found by dogfooding: the guard blocked a test fixture being written. `echo x >
# f` discards no captured output because nothing was going to print, so there is
# no alternative to offer -- the same category as the heredoc case.
_allows "allows 'echo ... > file'"   "$(_json "$PLUGIN" shell "echo hi > /tmp/out.log")"
_allows "allows 'printf ... > file'" "$(_json "$PLUGIN" shell 'printf "%s" x > /tmp/out.json')"
_allows "allows authoring inside a loop" \
  "$(_json "$PLUGIN" shell 'for i in 1 2 3; do echo x > "/tmp/p$i.cgi"; done')"
# But a real command's output redirected to a file still blocks.
_blocks "still blocks 'grep ... > file'" \
  "$(_json "$PLUGIN" shell 'grep -rn foo src/ > /tmp/hits.log')"

echo ""
echo "--- QUOTED redirect targets (the form agents actually write) ---"
# These were ALL silently allowed until scrub() started filling quoted spans with
# `_` instead of spaces: a blanked span presents no TARGET to REDIR, so the
# redirect matched nothing at all and scored clean. `> "$F"` and `> "/tmp/x.log"`
# are the common forms, so the gap covered most real stdout-to-file payloads.
_blocks "blocks '> \"/tmp/hits.log\"'" \
  "$(_json "$PLUGIN" shell 'grep -rn foo src/ > "/tmp/hits.log"')"
_blocks "blocks '> \"\$F\"'"          "$(_json "$PLUGIN" shell 'cmd > "$F"')"
_blocks "blocks single-quoted target" "$(_json "$PLUGIN" shell "cmd > '/tmp/out.log'")"
# The stream rule and every exclusion must survive quoting.
_allows "allows quoted '2> \"err.log\"'" "$(_json "$PLUGIN" shell 'cmd 2> "err.log"')"
_allows "allows quoted '> \"/dev/null\"'" "$(_json "$PLUGIN" shell 'cmd > "/dev/null"')"
_allows "allows quoted target read back later" \
  "$(_json "$PLUGIN" shell 'cmd > "out.log" && grep x "out.log"')"
_allows "allows quoted authoring target" "$(_json "$PLUGIN" shell 'echo hi > "f.txt"')"
echo ""
echo "--- backslash-escaped quotes do not end a quoted span (QA round 1, F-01) ---"
# Inside "..." a backslash escapes the next char, so \" does NOT close the span.
# Without this the span ended early, the rest was re-parsed as unquoted shell, and
# a '>' inside a JSON body became a real redirect: a valid command was hard-blocked
# AND the suggested replacement had the middle of the body spliced out of it.
_allows "escaped quote inside a JSON body with '>'" \
  "$(_json "$PLUGIN" shell 'curl -sS -d "{\"q\":\"a > b\"}" https://example.test/api')"
_allows "escaped quote around a pipe-looking string" \
  "$(_json "$PLUGIN" shell 'curl -d "{\"cmd\":\"x | head -5\"}" https://example.test/api')"
# Single quotes take no escapes in shell: inside '...' a backslash is literal, so
# the span still ends at the next quote and a real truncation after it is caught.
_blocks "backslash in single quotes does not swallow a later truncation" \
  "$(_json "$PLUGIN" shell "grep 'a\\' src/ | head -5")"

echo ""
echo "--- the suggestion strips EVERY truncation, not just the first (F-05) ---"
# Splicing out only the first match leaves the rest in REPLACE WITH, so an agent
# that pastes it is blocked again on the next one -- the laundering loop this hook
# exists to close, rebuilt inside the hook.
_M2="$(_json "$PLUGIN" shell 'a | head -5
b | tail -3')"
_blocks "blocks a two-truncation payload" "$_M2"
_suggest_lacks "suggestion drops the SECOND pipe truncation too" "$_M2" '| tail -3'
_suggest_lacks "suggestion drops the first pipe truncation"      "$_M2" '| head -5'
_R2="$(_json "$PLUGIN" shell 'cmd1 > out1.log
cmd2 > out2.log')"
_blocks "blocks a two-redirect payload" "$_R2"
_suggest_lacks "suggestion drops the SECOND redirect too" "$_R2" '> out2.log'
_suggest_lacks "suggestion drops the first redirect"      "$_R2" '> out1.log'

echo ""
echo "--- a shell comment is prose, not a pipeline ---"
# Found by dogfooding: the guard blocked its own author's payload because a
# comment contained `-> isolates`, which read as a redirect to a file named
# "isolates". `# see cmd | head -5` would have blocked the same way.
_allows "allows '->' inside a comment" \
  "$(_json "$PLUGIN" shell '# this -> isolates the fix
git status')"
_allows "allows '| head' inside a comment" \
  "$(_json "$PLUGIN" shell '# see: cmd | head -5
git status')"
_allows "allows a shebang line" "$(_json "$PLUGIN" shell '#!/bin/bash
git status')"
# But `$#` is a positional-count expansion, not a comment, and a real
# truncation on another line is still caught.
_blocks "'\$#' does not start a comment" \
  "$(_json "$PLUGIN" shell 'echo $# ; cmd | head -5')"
_blocks "real redirect below a comment still blocks" \
  "$(_json "$PLUGIN" shell 'git log
# note > here
cmd > out.log')"

# The block message must name the file, not the `___` placeholder scrub leaves.
_stderr_has "quoted-target message names the real file" \
  "$(_json "$PLUGIN" shell 'grep -rn foo src/ > "/tmp/hits.log"')" '/tmp/hits.log'

echo ""
echo "--- multi-line payloads render a well-formed message ---"
# A tab-delimited record broke when a newline landed inside the token: `cut -f5`
# read past the end of line 1 and the message lost its tool name.
_ML="$(_json "$PLUGIN" shell "$(printf 'cd /tmp\nls -la \\\n  > /tmp/listing.log')")"
_blocks "blocks a multi-line redirect" "$_ML"
_stderr_has "multi-line block still names the tool" "$_ML" "$PLUGIN"
_stderr_has "multi-line block still offers intent="  "$_ML" 'intent='
_run "$_ML" >/dev/null
if grep -qE '^\s+\(language=' "/tmp/ctxpg-err.$$"; then
  fail "message lost the tool name (empty field before the paren)"
else
  pass "message has no empty tool-name field"
fi

echo ""
echo "--- PASS: non-shell languages are never scanned ---"
# '>' is a comparison operator outside shell.
_allows "allows javascript comparison" "$(_json "$PLUGIN" javascript 'const a = b > c ? 1 : 2')"
_allows "allows python shift"          "$(_json "$PLUGIN" python 'x = y >> 1')"
_allows "allows perl filehandle"       "$(_json "$PLUGIN" perl 'print $fh > 5')"

echo ""
echo "--- PASS: fail-open on anything unexpected ---"
_allows "allows an unrelated tool"     "$(_json "Bash" shell 'cmd | head -5')"
_allows "allows empty tool_input"      '{"tool_name":"'"$PLUGIN"'","tool_input":{}}'
_allows "allows malformed JSON"        'not-json-at-all'
# An absent language means shell -- ctx_execute's default, and 4,571 of the
# measured calls omit the key. Treating absent as non-shell would blind the gate
# on a fifth of all traffic.
_blocks "treats a missing language key as shell" \
  '{"tool_name":"'"$PLUGIN"'","tool_input":{"code":"cmd | head -5"}}'
if printf '' | bash "$HOOK" >/dev/null 2>&1; then
  pass "allows empty stdin"
else
  fail "empty stdin should exit 0"
fi

echo ""
echo "--- escape hatch ---"
_allows "'# ctx-truncate-ok' bypasses" \
  "$(_json "$PLUGIN" shell 'cmd | head -20  # ctx-truncate-ok')"
# The bypass is a NEW marker on purpose. `# ctx-exempt` is ctx-execute-enforcer's
# operator-only key, matched there as a bare substring anywhere in a command;
# honouring it here would hand agents the master key to that hook's 2,510 blocks.
_blocks "'# ctx-exempt' does NOT bypass this guard" \
  "$(_json "$PLUGIN" shell 'ls -la /usr/bin | head -5 # ctx-exempt')"
# The marker must be a real comment, not any occurrence of the string: a payload
# that merely mentions it must not disarm the gate on itself.
_blocks "marker inside a quoted string does not bypass" \
  "$(_json "$PLUGIN" shell "grep -rn '# ctx-truncate-ok' hooks/ | head -5")"
_blocks "exempt in one batch entry does not whitelist another" \
  "$(_batch "$PBATCH" 'a | head -5  # ctx-truncate-ok' 'b | head -5')"

echo ""
echo "--- block message names the concrete replacement ---"
# Measured: gates naming a specific replacement convert at 36-50%; gates naming
# none convert at ~0% and send 90-95% of blocks straight back to raw tools.
J="$(_json "$PLUGIN" shell 'orb list 2>&1 | head -20')"
_stderr_has   "message echoes the stripped command" "$J" 'orb list 2>&1'
# The first line names the offending token on purpose ("BLOCKED -- `| head -20`").
# What must be clean is the REPLACE WITH line: if the suggested call still carries
# the truncation, the agent pastes it back and is blocked again -- which is the
# exact laundering loop ctx-execute-enforcer currently creates.
_run "$J" >/dev/null
if grep -F 'ctx_execute(' "/tmp/ctxpg-err.$$" | grep -qF '| head'; then
  fail "REPLACE WITH line still carries the truncation"
else
  pass "REPLACE WITH line is free of the truncation"
fi
_stderr_has   "message offers intent="              "$J" 'intent='
_stderr_has   "message advertises the bypass"       "$J" 'ctx-truncate-ok'
_stderr_has   "message names the tool form used"    "$J" "$PLUGIN"
JL="$(_json "$LEGACY" shell 'cmd | head -3')"
_stderr_has   "legacy form echoed, not hardcoded plugin form" "$JL" "$LEGACY"
JR="$(_json "$PLUGIN" shell 'cmd > out.log')"
_stderr_has   "redirect message offers tee"         "$JR" 'tee out.log'
_stderr_has   "redirect message says stderr is fine" "$JR" '2>/dev/null'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
