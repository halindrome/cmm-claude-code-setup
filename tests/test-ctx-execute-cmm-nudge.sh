#!/bin/bash
# test-ctx-execute-cmm-nudge.sh — Tests for ctx-execute-cmm-nudge.sh (source-code search laundering gate on mcp__context-mode__ctx_execute)
# Usage: bash tests/test-ctx-execute-cmm-nudge.sh
# Exit: 0 = all pass, 1 = any failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/project/ctx-execute-cmm-nudge.sh"

PASS=0; FAIL=0

_assert_exit() {
    local label="$1" expected="$2" json="$3"
    local actual=0
    echo "$json" | bash "$HOOK" >/dev/null 2>&1 || actual=$?
    if [ "$actual" -eq "$expected" ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (expected exit $expected, got $actual)"
        FAIL=$((FAIL+1))
    fi
}

_assert_stderr_contains() {
    local label="$1" json="$2" needle="$3"
    local out
    out=$(echo "$json" | bash "$HOOK" 2>&1)
    if echo "$out" | grep -qF "$needle"; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (stderr missing '$needle')"
        echo "  stderr: $out"
        FAIL=$((FAIL+1))
    fi
}

if [ ! -f "$HOOK" ]; then
    echo "FATAL: $HOOK not found"
    exit 1
fi

# --- Indexed-repo fixture setup ---
# Create a tempdir, seed .mcp.json with codebase-memory-mcp, and drop the
# /tmp/cmm-session-ready-<hash> sentinel so the hook treats it as an indexed repo.
# Important: macOS mktemp returns /var/... but the hook will resolve to /private/var/...
# via `pwd -P`. We normalize with `pwd -P` before computing the hash.
FIX_RAW="$(mktemp -d)"
FIX="$(cd "$FIX_RAW" && pwd -P)"
mkdir -p "$FIX/src"
mkdir -p "$FIX/node_modules/lib"
cat > "$FIX/.mcp.json" <<EOF
{"mcpServers":{"codebase-memory-mcp":{"command":"x"}}}
EOF
git -C "$FIX" init -q >/dev/null 2>&1 || true

# Non-indexed sibling fixture (no .mcp.json, no sentinel)
NONIDX_RAW="$(mktemp -d)"
NONIDX="$(cd "$NONIDX_RAW" && pwd -P)"
mkdir -p "$NONIDX/src"
git -C "$NONIDX" init -q >/dev/null 2>&1 || true

if command -v md5 >/dev/null 2>&1; then
    PROJECT_HASH="$(echo "$FIX" | md5 -q)"
else
    PROJECT_HASH="$(echo "$FIX" | md5sum | awk '{print $1}')"
fi
CMM_SENTINEL="/tmp/cmm-session-ready-${PROJECT_HASH}"
touch "$CMM_SENTINEL"

cleanup() {
    rm -rf "$FIX_RAW" "$NONIDX_RAW" "$CMM_SENTINEL" 2>/dev/null || true
}
trap cleanup EXIT

echo "--- Fail-open basics (expect exit 0) ---"
_assert_exit "empty stdin"                  0 ''
_assert_exit "empty JSON"                   0 '{}'
_assert_exit "malformed JSON"               0 'not-json'
_assert_exit "wrong tool_name (Bash)"       0 '{"tool_name":"Bash","tool_input":{"command":"grep foo src/"}}'
_assert_exit "wrong tool_name (Grep)"       0 '{"tool_name":"Grep","tool_input":{"pattern":"foo"}}'
_assert_exit "empty code field"             0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"\"},\"cwd\":\"$FIX\"}"

echo ""
echo "--- Blocked code-search cases (indexed repo, expect exit 2) ---"
_assert_exit "grep bare identifier"         2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -rn 'MyFunc' src/\"},\"cwd\":\"$FIX\"}"
_assert_exit "grep double-quoted identifier" 2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -rn \\\"MyFunc\\\" src/\"},\"cwd\":\"$FIX\"}"
_assert_exit "grep unquoted identifier"     2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -rn MyFunc src/\"},\"cwd\":\"$FIX\"}"
_assert_exit "rg regex alternation"         2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"rg 'password|PASSWORD' src/\"},\"cwd\":\"$FIX\"}"
_assert_exit "ack foo src/"                 2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"ack foo src/\"},\"cwd\":\"$FIX\"}"
_assert_exit "ag foo src/"                  2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"ag foo src/\"},\"cwd\":\"$FIX\"}"
_assert_exit "ugrep foo src/"               2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"ugrep foo src/\"},\"cwd\":\"$FIX\"}"
_assert_exit "find src -name *.go"          2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"find src -name '*.go'\"},\"cwd\":\"$FIX\"}"

echo ""
echo "--- Allowed non-code-search commands (expect exit 0) ---"
_assert_exit "git log --oneline"            0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"git log --oneline\"},\"cwd\":\"$FIX\"}"
_assert_exit "git log --grep=foo (first token is git)" 0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"git log --grep=foo\"},\"cwd\":\"$FIX\"}"
_assert_exit "npm test"                     0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"npm test\"},\"cwd\":\"$FIX\"}"
_assert_exit "pytest tests/"                0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"pytest tests/\"},\"cwd\":\"$FIX\"}"
_assert_exit "curl https"                   0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"curl https://example.com\"},\"cwd\":\"$FIX\"}"
_assert_exit "jq .foo file.json"            0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"jq .foo file.json\"},\"cwd\":\"$FIX\"}"
_assert_exit "cargo test"                   0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"cargo test\"},\"cwd\":\"$FIX\"}"
_assert_exit "go test ./..."                0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"go test ./...\"},\"cwd\":\"$FIX\"}"
_assert_exit "find src -name *.log (non-code ext)" 0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"find src -name '*.log'\"},\"cwd\":\"$FIX\"}"

echo ""
# Compound commands are how agents actually write sandbox searches. They used to
# fail open wholesale; observed 2026-10-14, a subagent ran 26 of them in a row.
echo "--- Compound commands: every segment is classified (expect exit 2) ---"
_assert_exit "multi-statement with semicolon" 2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"echo x; grep y src/\"},\"cwd\":\"$FIX\"}"
_assert_exit "&& chained"                   2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"cd src && grep foo .\"},\"cwd\":\"$FIX\"}"
_assert_exit "|| chained"                   2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep foo src/ || true\"},\"cwd\":\"$FIX\"}"
_assert_exit "for-loop"                     2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"for f in src/*; do grep foo \\\"\$f\\\"; done\"},\"cwd\":\"$FIX\"}"
_assert_exit "newline-separated statements" 2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"ls src\\ngrep -rn foo src/\"},\"cwd\":\"$FIX\"}"
_assert_exit "grep at pipeline head"        2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -rn foo src/ 2>&1 | grep -v spec\"},\"cwd\":\"$FIX\"}"
_assert_stderr_contains "quoted pipe is pattern, not separator" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep 'a|b' src/; echo done\"},\"cwd\":\"$FIX\"}" \
    'search_code(pattern="a|b"'
_assert_exit "incident payload (cd; for; do grep | grep)" 2 "{\"tool_name\":\"mcp__plugin_context-mode_context-mode__ctx_execute\",\"tool_input\":{\"code\":\"cd $FIX; ls; for a in src lib; do echo \\\"== \$a\\\"; grep -rnE \\\"\\\\\\\\.userID|userID\\\\\\\\]\\\" \$a --include=*.ts 2>/dev/null | grep -viE \\\"spec\\\\\\\\.ts\\\"; done\"},\"cwd\":\"$FIX\"}"
_assert_exit "non-code file target passes"  0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"cd $FIX; grep -n 'Phase' CHANGELOG.md; echo done\"},\"cwd\":\"$FIX\"}"
_assert_exit "cd into another repo releases" 0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"cd $NONIDX && grep -rn foo .\"},\"cwd\":\"$FIX\"}"
# --include restricted to non-code files: a config search. Allowlist only, so an
# extension the parser does not know (.cgi, via extra_extensions) still blocks.
_assert_exit "--include non-code only passes" 0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -rn externalEvents --include='*.conf' --include=*.yaml .\"},\"cwd\":\"$FIX\"}"
_assert_exit "--include unknown ext blocks"   2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -rn checkSession --include='*.cgi' .\"},\"cwd\":\"$FIX\"}"
_assert_exit "--include mixed blocks"         2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -rn foo --include='*.conf' --include '*.pm' .\"},\"cwd\":\"$FIX\"}"
_assert_exit "rg -g '!*.md' exclusion blocks" 2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"rg foo -g '!*.md' src/\"},\"cwd\":\"$FIX\"}"
_assert_exit "rg -g '*.json' passes"          0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"rg foo -g '*.json' src/\"},\"cwd\":\"$FIX\"}"
# QA round 1. F-01: a released first search must not release the rest.
_ce() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"mcp__context-mode__ctx_execute","tool_input":{"code":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$FIX"; }
_assert_exit "F-01 non-code grep then source grep blocks" 2 "$(_ce 'grep -n hi CHANGELOG.md; grep -rn Foo src/')"
_assert_exit "F-01 outside-repo grep then source grep"    2 "$(_ce 'grep foo /tmp/nonexistent-qa.log; grep -rn Foo src/')"
_assert_exit "F-01 batch: non-code then source"           2 "$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"mcp__plugin_context-mode_context-mode__ctx_batch_execute","tool_input":{"commands":[{"label":"a","command":"grep -n x CHANGELOG.md"},{"label":"b","command":"grep -rn Foo src/"}]},"cwd":sys.argv[1]}))' "$FIX")"
_assert_exit "F-01 only non-code greps still pass"        0 "$(_ce 'grep -n hi CHANGELOG.md; grep -c x /tmp/nonexistent-qa.log')"
# F-05: a detached output redirect's file is not the grep target.
_assert_exit "F-05 2> /dev/null keeps src/ target"        2 "$(_ce 'grep -rn Foo src/ 2> /dev/null')"
_assert_exit "F-05 > out.log; cat out.log blocks"         2 "$(_ce 'grep -rn Foo src/ > out.log; cat out.log')"
# F-06: wrapper words, a glued (, and heredocs ahead of a search.
_assert_exit "F-06 if grep ...; then"                     2 "$(_ce 'if grep -rn Foo src/; then echo y; fi')"
_assert_exit "F-06 time grep"                             2 "$(_ce 'time grep -rn Foo src/')"
_assert_exit "F-06 env grep"                              2 "$(_ce 'env grep -rn Foo src/')"
_assert_exit "F-06 command grep"                          2 "$(_ce 'command grep -rn Foo src/')"
_assert_exit "F-06 (grep ...)"                            2 "$(_ce '(grep -rn Foo src/)')"
_assert_exit "F-06 heredoc write then source grep"        2 "$(_ce "$(printf "cat > /tmp/qa-f <<'EOF'\nhello\nEOF\ngrep -rn Foo src/")")"
_assert_exit "F-06 arithmetic shift then source grep"     2 "$(_ce 'x=$((1<<2)); grep -rn Foo src/')"
_assert_exit "F-06 grep inside a heredoc body passes"     0 "$(_ce "$(printf "cat <<'EOF'\ngrep -rn Foo src/\nEOF")")"
# QA round 2.
_assert_exit "R2-01 python payload is not shell"          0 "$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"mcp__context-mode__ctx_execute","tool_input":{"language":"python","code":"import re\nrg = re.compile(\"x\")\nprint(open(\"src/a.py\").read())"},"cwd":sys.argv[1]}))' "$FIX")"
_assert_exit "R2-03 here-string grep passes"              0 "$(_ce 'out=$(npm test); grep -c FAIL <<< "$out"')"
_assert_exit "R2-04 grep of a mktemp var passes"          0 "$(_ce 'T=$(mktemp); npm test > $T 2>&1; grep -c FAIL $T')"
_assert_exit "R2-04 grep of an assigned log path passes"  0 "$(_ce 'LOG=/tmp/run.log; grep -c FAIL $LOG')"
_assert_exit "R2-04 loop over .md files passes"           0 "$(_ce 'for f in docs/*.md; do grep -n TODO "$f"; done')"
_assert_exit "R2-04 loop over source dirs blocks"         2 "$(_ce 'for d in src lib; do grep -rn Foo $d; done')"
_assert_exit "R2-04 mid-word loop var blocks"             2 "$(_ce 'for a in x y; do grep -rn Foo src/$a; done')"
_assert_exit "R2-04 loop over \$(find) blocks"             2 "$(_ce 'for f in $(find src -name "*.ts"); do grep -n Foo $f; done')"
_assert_exit "R2-08 unresolvable cd: src/ grep blocks"    2 "$(_ce 'R=$(git rev-parse --show-toplevel); cd $R; grep -rn Foo src/')"
# Registered as a RELATIVE path (bash .claude/hooks/...) with the payload cwd in
# a subdirectory: the lib must still load, or the gate fails open.
_rel_rc=0
( cd "$SCRIPT_DIR/.." && python3 -c 'import json,sys; print(json.dumps({"tool_name":"mcp__context-mode__ctx_execute","tool_input":{"code":"grep -rn Foo ."},"cwd":sys.argv[1]}))' "$FIX/src" \
    | bash hooks/project/ctx-execute-cmm-nudge.sh >/dev/null 2>&1 ) || _rel_rc=$?
if [ "$_rel_rc" -eq 2 ]; then echo "PASS: relative hook path, subdir cwd still gates"; PASS=$((PASS+1))
else echo "FAIL: relative hook path, subdir cwd still gates (expected exit 2, got $_rel_rc)"; FAIL=$((FAIL+1)); fi

echo ""
echo "--- Still allowed inside compound commands (expect exit 0) ---"
_assert_exit "grep as a pipe sink"          0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"cat foo | grep bar\"},\"cwd\":\"$FIX\"}"
_assert_exit "git log | grep sink"          0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"git log --oneline | grep foo; echo done\"},\"cwd\":\"$FIX\"}"
_assert_exit "heredoc containing grep"      0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"cat <<EOF\\ngrep foo bar\\nEOF\"},\"cwd\":\"$FIX\"}"
_assert_exit "backtick subshell"            0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"echo \\\`grep foo src/\\\`\"},\"cwd\":\"$FIX\"}"
_assert_exit "\$(...) subshell"             0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"echo \$(grep foo src/)\"},\"cwd\":\"$FIX\"}"

echo ""
echo "--- Retired '# cmm-exempt' marker is ignored (expect exit 2) ---"
_assert_exit "# cmm-exempt no longer bypasses grep" 2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep foo src/ # cmm-exempt\"},\"cwd\":\"$FIX\"}"
_assert_exit "# cmm-exempt no longer bypasses find" 2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"find src -name '*.go' # cmm-exempt\"},\"cwd\":\"$FIX\"}"

echo ""
echo "--- Path exemptions (expect exit 0) ---"
_assert_exit "node_modules path exempt"     0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep foo node_modules/lib/\"},\"cwd\":\"$FIX\"}"
_assert_exit "dist path exempt"             0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep foo dist/\"},\"cwd\":\"$FIX\"}"
_assert_exit "build path exempt"            0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep foo build/\"},\"cwd\":\"$FIX\"}"
_assert_exit "vendor path exempt"           0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep foo vendor/\"},\"cwd\":\"$FIX\"}"
_assert_exit "target path exempt"           0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep foo target/\"},\"cwd\":\"$FIX\"}"

echo ""
echo "--- Non-indexed repo (expect exit 0) ---"
_assert_exit "non-indexed cwd (no .mcp.json / no sentinel)" 0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep foo src/\"},\"cwd\":\"$NONIDX\"}"

# Temporarily remove sentinel and verify indexed fixture falls open too
rm -f "$CMM_SENTINEL"
_assert_exit "indexed repo, sentinel missing (fail open)" 0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep foo src/\"},\"cwd\":\"$FIX\"}"
touch "$CMM_SENTINEL"

echo ""
echo "--- REPLACE WITH ordering (stderr content checks) ---"
_assert_stderr_contains "bare identifier -> search_graph first" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -rn 'MyFunc' src/\"},\"cwd\":\"$FIX\"}" \
    'REPLACE WITH: mcp__codebase-memory-mcp__search_graph(name_pattern="MyFunc", project="'
_assert_stderr_contains "bare identifier -> search_code second" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -rn 'MyFunc' src/\"},\"cwd\":\"$FIX\"}" \
    'OR:           mcp__codebase-memory-mcp__search_code(pattern="MyFunc", project="'
_assert_stderr_contains "regex alternation -> search_code first" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep 'password|PASSWORD' src/\"},\"cwd\":\"$FIX\"}" \
    'REPLACE WITH: mcp__codebase-memory-mcp__search_code(pattern="password|PASSWORD", project="'
_assert_stderr_contains "regex alternation -> search_graph second" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep 'password|PASSWORD' src/\"},\"cwd\":\"$FIX\"}" \
    'OR:           mcp__codebase-memory-mcp__search_graph(name_pattern="password|PASSWORD", project="'
_assert_stderr_contains "find -name *.go -> search_code first (no bare id)" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"find src -name '*.go'\"},\"cwd\":\"$FIX\"}" \
    'REPLACE WITH: mcp__codebase-memory-mcp__search_code(pattern='
_assert_stderr_contains "block message prefix" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -rn 'MyFunc' src/\"},\"cwd\":\"$FIX\"}" \
    '[ctx-execute-cmm-nudge] BLOCKED'

echo ""
echo "--- QA round 1 regressions (M1, M2, M3, m1) ---"
# M1: -r / -o are boolean in grep, must not consume the next token.
_assert_exit "grep -r <pat> <target> blocks (not swallow)" 2 \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -r MyFunc src/\"},\"cwd\":\"$FIX\"}"
_assert_stderr_contains "grep -r keeps pattern, not target" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -r MyFunc src/\"},\"cwd\":\"$FIX\"}" \
    'name_pattern="MyFunc"'
_assert_exit "grep -r <pat> (no target) still blocks" 2 \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -r foo\"},\"cwd\":\"$FIX\"}"
_assert_exit "grep -o <pat> <target> blocks" 2 \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -o foo src/\"},\"cwd\":\"$FIX\"}"
_assert_stderr_contains "grep -o keeps pattern, not target" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -o foo src/\"},\"cwd\":\"$FIX\"}" \
    'pattern="foo"'
# rg -r IS value-taking (--replace), so next token is consumed.
_assert_exit "rg -r <repl> <pat> <target> blocks on pat" 2 \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"rg -r REPLACED MyFunc src/\"},\"cwd\":\"$FIX\"}"
_assert_stderr_contains "rg -r uses pattern after consumed replacement" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"rg -r REPLACED MyFunc src/\"},\"cwd\":\"$FIX\"}" \
    'name_pattern="MyFunc"'

# M2: egrep / fgrep / ripgrep (full binary name) must block.
_assert_exit "egrep foo src/ blocks"       2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"egrep foo src/\"},\"cwd\":\"$FIX\"}"
_assert_exit "fgrep foo src/ blocks"       2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"fgrep foo src/\"},\"cwd\":\"$FIX\"}"
_assert_exit "ripgrep foo src/ blocks"     2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"ripgrep foo src/\"},\"cwd\":\"$FIX\"}"

# M3: git grep <pat> <target> must block.
_assert_exit "git grep MyFunc src/ blocks" 2 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"git grep MyFunc src/\"},\"cwd\":\"$FIX\"}"
_assert_stderr_contains "git grep uses pattern after unwrap" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"git grep MyFunc src/\"},\"cwd\":\"$FIX\"}" \
    'name_pattern="MyFunc"'
_assert_exit "git log stays allowed"        0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"git log --oneline\"},\"cwd\":\"$FIX\"}"

# m1: absolute target that doesn't exist must not attribute to cwd's indexed repo.
_assert_exit "grep foo /tmp/nonexistent-xyz/ fails open" 0 \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep foo /tmp/nonexistent-cmm-qa-xyz/\"},\"cwd\":\"$FIX\"}"

# QA round 2 N1: git-level options before grep must still unwrap.
_assert_exit "git -c foo=bar grep blocks" 2 \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"git -c foo.bar=baz grep MyFunc src/\"},\"cwd\":\"$FIX\"}"
_assert_stderr_contains "git -c ... grep uses pattern" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"git -c foo.bar=baz grep MyFunc src/\"},\"cwd\":\"$FIX\"}" \
    'name_pattern="MyFunc"'
_assert_exit "git -C path grep blocks" 2 \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"git -C /tmp grep MyFunc src/\"},\"cwd\":\"$FIX\"}"
_assert_exit "git --no-pager grep blocks" 2 \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"git --no-pager grep MyFunc src/\"},\"cwd\":\"$FIX\"}"
_assert_exit "git --git-dir=... grep blocks" 2 \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"git --git-dir=/tmp/.git grep MyFunc src/\"},\"cwd\":\"$FIX\"}"
# git with leading opts whose subcommand is not grep stays allowed.
_assert_exit "git -c foo=bar log still allowed" 0 \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"git -c foo.bar=baz log --oneline\"},\"cwd\":\"$FIX\"}"

# --- Registration-gap regression (2026-09-04) ---
# ctx-execute-cmm-nudge was registered for ctx_execute ONLY, so a blocked Bash
# grep re-issued as ctx_batch_execute(grep ...) bypassed the gate entirely --
# reported by a live session as "the two hooks compose into a hole rather than a
# fence". Three layers must agree: the setup.sh matcher, the python _ACCEPTED
# set, and the shell TOOL_NAME case. These pin all three.
echo ""
echo "--- Registration gap: all three ctx tools must gate a source search ---"

_assert_exit "ctx_execute gates a source grep" 2 \
    "{\"tool_name\":\"mcp__plugin_context-mode_context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -rn MyFunc src/\"},\"cwd\":\"$FIX\"}"

_assert_exit "ctx_execute_file gates a source grep" 2 \
    "{\"tool_name\":\"mcp__plugin_context-mode_context-mode__ctx_execute_file\",\"tool_input\":{\"path\":\"src/a.ts\",\"code\":\"grep -rn MyFunc src/\"},\"cwd\":\"$FIX\"}"

_assert_exit "ctx_batch_execute gates a source grep (THE hole)" 2 \
    "{\"tool_name\":\"mcp__plugin_context-mode_context-mode__ctx_batch_execute\",\"tool_input\":{\"commands\":[{\"label\":\"f\",\"command\":\"grep -rn MyFunc src/\"}],\"queries\":[\"q\"]},\"cwd\":\"$FIX\"}"

_assert_exit "legacy-form ctx_batch_execute gates too" 2 \
    "{\"tool_name\":\"mcp__context-mode__ctx_batch_execute\",\"tool_input\":{\"commands\":[{\"label\":\"f\",\"command\":\"grep -rn MyFunc src/\"}],\"queries\":[\"q\"]},\"cwd\":\"$FIX\"}"

# One grep hidden among innocuous commands must still be caught -- otherwise the
# bypass is just "put git status first".
_assert_exit "grep buried mid-batch still caught" 2 \
    "{\"tool_name\":\"mcp__plugin_context-mode_context-mode__ctx_batch_execute\",\"tool_input\":{\"commands\":[{\"label\":\"a\",\"command\":\"git status\"},{\"label\":\"b\",\"command\":\"grep -rn MyFunc src/\"},{\"label\":\"c\",\"command\":\"date\"}],\"queries\":[\"q\"]},\"cwd\":\"$FIX\"}"

_assert_exit "batch with no code search passes" 0 \
    "{\"tool_name\":\"mcp__plugin_context-mode_context-mode__ctx_batch_execute\",\"tool_input\":{\"commands\":[{\"label\":\"a\",\"command\":\"git status\"},{\"label\":\"b\",\"command\":\"date\"}],\"queries\":[\"q\"]},\"cwd\":\"$FIX\"}"

_assert_exit "retired cmm-exempt ignored inside a batch" 2 \
    "{\"tool_name\":\"mcp__plugin_context-mode_context-mode__ctx_batch_execute\",\"tool_input\":{\"commands\":[{\"label\":\"a\",\"command\":\"grep -rn MyFunc src/  # cmm-exempt\"}],\"queries\":[\"q\"]},\"cwd\":\"$FIX\"}"

_assert_exit "non-code dir in a batch still passes" 0 \
    "{\"tool_name\":\"mcp__plugin_context-mode_context-mode__ctx_batch_execute\",\"tool_input\":{\"commands\":[{\"label\":\"a\",\"command\":\"grep -rn MyFunc node_modules/lib/\"}],\"queries\":[\"q\"]},\"cwd\":\"$FIX\"}"

_assert_exit "non-indexed repo still fails open on batch" 0 \
    "{\"tool_name\":\"mcp__plugin_context-mode_context-mode__ctx_batch_execute\",\"tool_input\":{\"commands\":[{\"label\":\"a\",\"command\":\"grep -rn MyFunc src/\"}],\"queries\":[\"q\"]},\"cwd\":\"$NONIDX\"}"

# --- Source reads: advisory via cmm-nudge.sh's shared per-file budget ---
# sed -n / head / cat on source never blocks (Read doesn't either); past the
# Read budget it gets the same nudge Read would.
echo ""
echo "--- Source reads: advisory, shared budget with Read ---"
for i in $(seq 1 60); do echo "line $i"; done > "$FIX/src/big.ts"
_SID="ctxread-test-$$"
_rd() { echo "{\"tool_name\":\"mcp__plugin_context-mode_context-mode__ctx_execute\",\"tool_input\":{\"code\":\"$1\"},\"session_id\":\"$_SID\",\"cwd\":\"$FIX\"}"; }
_assert_exit "sed -n read is allowed" 0 "$(_rd "cd $FIX/src; sed -n '10,20p;40,45p' big.ts")"
_assert_exit "head read is allowed"   0 "$(_rd "head -n 30 src/big.ts")"
_out=$(_rd "cat src/big.ts" | bash "$HOOK" 2>/dev/null)
if [ -z "$_out" ]; then echo "PASS: third read under budget is silent"; PASS=$((PASS+1)); else echo "FAIL: third read nudged: $_out"; FAIL=$((FAIL+1)); fi
_out=$(_rd "sed -n 1,5p src/big.ts" | bash "$HOOK" 2>/dev/null)
if echo "$_out" | grep -q "read 'big.ts' 4 times"; then echo "PASS: fourth read gets the Read nudge"; PASS=$((PASS+1)); else echo "FAIL: fourth read not nudged: $_out"; FAIL=$((FAIL+1)); fi
_out=$(_rd "sed -i 's/a/b/' src/big.ts" | bash "$HOOK" 2>/dev/null)
if [ -z "$_out" ]; then echo "PASS: sed -i is not a read"; PASS=$((PASS+1)); else echo "FAIL: sed -i counted as read"; FAIL=$((FAIL+1)); fi
_assert_exit "read + grep in one payload still blocks" 2 "$(_rd "sed -n 1,5p src/big.ts; grep -rn foo src/")"
rm -f /tmp/cmm-reads-${_SID}-* 2>/dev/null

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
