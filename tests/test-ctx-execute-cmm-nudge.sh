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
echo "--- Conservative parser: ambiguous commands fail open (expect exit 0) ---"
_assert_exit "multi-statement with semicolon" 0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"echo x; grep y src/\"},\"cwd\":\"$FIX\"}"
_assert_exit "piped cat | grep"             0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"cat foo | grep bar\"},\"cwd\":\"$FIX\"}"
_assert_exit "&& chained"                   0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"cd src && grep foo .\"},\"cwd\":\"$FIX\"}"
_assert_exit "|| chained"                   0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep foo src/ || true\"},\"cwd\":\"$FIX\"}"
_assert_exit "heredoc containing grep"      0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"cat <<EOF\\ngrep foo bar\\nEOF\"},\"cwd\":\"$FIX\"}"
_assert_exit "for-loop"                     0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"for f in src/*; do grep foo \\\"\\$f\\\"; done\"},\"cwd\":\"$FIX\"}"
_assert_exit "backtick subshell"            0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"echo \\\`grep foo src/\\\`\"},\"cwd\":\"$FIX\"}"
_assert_exit "\$(...) subshell"             0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"echo \$(grep foo src/)\"},\"cwd\":\"$FIX\"}"

echo ""
echo "--- Exempt marker (expect exit 0) ---"
_assert_exit "# cmm-exempt bypasses grep"   0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep foo src/ # cmm-exempt\"},\"cwd\":\"$FIX\"}"
_assert_exit "# cmm-exempt bypasses find"   0 "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"find src -name '*.go' # cmm-exempt\"},\"cwd\":\"$FIX\"}"

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
    'REPLACE WITH: mcp__codebase-memory-mcp__search_graph(name_pattern="MyFunc")'
_assert_stderr_contains "bare identifier -> search_code second" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep -rn 'MyFunc' src/\"},\"cwd\":\"$FIX\"}" \
    'OR:           mcp__codebase-memory-mcp__search_code(query="MyFunc")'
_assert_stderr_contains "regex alternation -> search_code first" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep 'password|PASSWORD' src/\"},\"cwd\":\"$FIX\"}" \
    'REPLACE WITH: mcp__codebase-memory-mcp__search_code(query="password|PASSWORD")'
_assert_stderr_contains "regex alternation -> search_graph second" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"grep 'password|PASSWORD' src/\"},\"cwd\":\"$FIX\"}" \
    'OR:           mcp__codebase-memory-mcp__search_graph(name_pattern="password|PASSWORD")'
_assert_stderr_contains "find -name *.go -> search_code first (no bare id)" \
    "{\"tool_name\":\"mcp__context-mode__ctx_execute\",\"tool_input\":{\"code\":\"find src -name '*.go'\"},\"cwd\":\"$FIX\"}" \
    'REPLACE WITH: mcp__codebase-memory-mcp__search_code(query='
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
    'query="foo"'
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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
