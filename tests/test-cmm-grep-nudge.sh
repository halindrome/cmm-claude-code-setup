#!/bin/bash
# test-cmm-grep-nudge.sh — Tests for cmm-grep-nudge.sh hard-blocking Grep gate
# Usage: bash tests/test-cmm-grep-nudge.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/global/cmm-grep-nudge.sh"

PASS=0; FAIL=0
# _assert_exit LABEL EXPECTED_EXIT JSON [ENV_PREFIX]
_assert_exit() {
    local label="$1" expected="$2" json="$3" env_prefix="${4:-}"
    local actual=0
    if [ -n "$env_prefix" ]; then
        echo "$json" | env $env_prefix bash "$HOOK" >/dev/null 2>&1 || actual=$?
    else
        echo "$json" | bash "$HOOK" >/dev/null 2>&1 || actual=$?
    fi
    if [ "$actual" -eq "$expected" ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (expected exit $expected, got $actual)"
        FAIL=$((FAIL+1))
    fi
}

# --- Fixture Setup ---
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Primary test project: CMM installed, git repo
PROJ="$TMPDIR_ROOT/proj"
mkdir -p "$PROJ/src"
git -C "$PROJ" init -q
echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"}}}' > "$PROJ/.mcp.json"

# Create a code file for path-based tests
echo 'print("hello")' > "$PROJ/src/main.py"

# Planning path fixture
mkdir -p "$PROJ/.vbw-planning/phases"
echo 'plan content' > "$PROJ/.vbw-planning/phases/plan.py"

# .claude path fixture
mkdir -p "$PROJ/.claude/hooks"
echo 'hook content' > "$PROJ/.claude/hooks/some-hook.sh"

# Second project: CMM NOT in .mcp.json
PROJ_NO_CMM="$TMPDIR_ROOT/proj-no-cmm"
mkdir -p "$PROJ_NO_CMM"
git -C "$PROJ_NO_CMM" init -q
echo '{"mcpServers":{"some-other-mcp":{"command":"npx"}}}' > "$PROJ_NO_CMM/.mcp.json"

# Fake CLAUDE_CONFIG_DIR without CMM — suppresses global fallback
FAKE_CONFIG="$TMPDIR_ROOT/fake-claude-config"
mkdir -p "$FAKE_CONFIG"
echo '{"hooks":{}}' > "$FAKE_CONFIG/settings.json"

# --- Tests ---

echo "--- Test 1: Grep with glob=*.py blocked (exit 2) ---"
_assert_exit "Test 1: glob=*.py blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"def handler\",\"glob\":\"*.py\",\"path\":\"$PROJ\"}}"

echo "--- Test 2: Grep with glob=*.ts blocked (exit 2) ---"
_assert_exit "Test 2: glob=*.ts blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"export\",\"glob\":\"*.ts\",\"path\":\"$PROJ\"}}"

echo "--- Test 3: Grep with type=sh blocked (exit 2) ---"
_assert_exit "Test 3: type=sh blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"function\",\"type\":\"sh\",\"path\":\"$PROJ\"}}"

echo "--- Test 4: Grep with glob=*.json allowed (exit 0) ---"
_assert_exit "Test 4: glob=*.json allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"version\",\"glob\":\"*.json\",\"path\":\"$PROJ\"}}"

echo "--- Test 5: Grep with glob=*.md allowed (exit 0) ---"
_assert_exit "Test 5: glob=*.md allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"TODO\",\"glob\":\"*.md\",\"path\":\"$PROJ\"}}"

echo "--- Test 6: Grep with glob=*.yaml allowed (exit 0) ---"
_assert_exit "Test 6: glob=*.yaml allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"port\",\"glob\":\"*.yaml\",\"path\":\"$PROJ\"}}"

echo "--- Test 7: Grep targeting .vbw-planning/ allowed (exit 0) ---"
_assert_exit "Test 7: .vbw-planning path allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"plan\",\"glob\":\"*.py\",\"path\":\"$PROJ/.vbw-planning/phases\"}}"

echo "--- Test 8: Grep targeting .claude/ allowed (exit 0) ---"
_assert_exit "Test 8: .claude path allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"hook\",\"glob\":\"*.sh\",\"path\":\"$PROJ/.claude/hooks\"}}"

echo "--- Test 9: Grep with no glob/type/path allowed (exit 0) ---"
_assert_exit "Test 9: bare pattern allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"something\"}}"

echo "--- Test 10: Grep without CMM allowed (exit 0) ---"
_assert_exit "Test 10: no CMM glob=*.py allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"def handler\",\"glob\":\"*.py\",\"path\":\"$PROJ_NO_CMM\"}}" \
    "CLAUDE_CONFIG_DIR=$FAKE_CONFIG"

echo "--- Test 11: Grep on code file path blocked (exit 2) ---"
_assert_exit "Test 11: code file path blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"TODO\",\"path\":\"$PROJ/src/main.py\"}}"

echo "--- Test 12: Grep with glob=*.tsx blocked (exit 2) ---"
_assert_exit "Test 12: glob=*.tsx blocked" 2 \
    "{\"tool_input\":{\"pattern\":\"import\",\"glob\":\"*.tsx\",\"path\":\"$PROJ\"}}"

# --- Bash navigation block tests (c1-c5) ---
# The Bash block requires the CMM sentinel to be present (indexed state).
# Compute the sentinel path using the normalized (realpath) form — the hook
# resolves symlinks via `cd ... && pwd -P` before hashing (macOS /var/folders fix).
PROJ_REAL=$(cd "$PROJ" && pwd -P)
PROJ_HASH=$(echo "$PROJ_REAL" | md5 -q 2>/dev/null || echo "$PROJ_REAL" | md5sum | awk '{print $1}')
BASH_SENTINEL="/tmp/cmm-session-ready-${PROJ_HASH}"
# Create sentinel (mark as ready)
echo "ready" > "$BASH_SENTINEL"
trap 'rm -rf "$TMPDIR_ROOT" "$BASH_SENTINEL"' EXIT

echo "--- Test c1: Bash grep against src/ + CMM ready -> exit 2 (BLOCKED) ---"
_assert_exit "c1: Bash grep src/ blocked" 2 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep -r 'parse' src/\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c2: Bash grep with # cmm-exempt -> exit 0 (bypass) ---"
_assert_exit "c2: Bash grep src/ cmm-exempt allowed" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep -r 'parse' src/ # cmm-exempt\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c3: Bash find against hooks/ -> exit 2 (BLOCKED) ---"
_assert_exit "c3: Bash find hooks/ blocked" 2 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"find hooks/ -name '*.sh'\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c4: Bash echo (non-navigation) -> exit 0 ---"
_assert_exit "c4: Bash echo allowed" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hello\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c5: Bash grep against src/ with CMM absent -> exit 0 (fail-open) ---"
# Remove sentinel so CMM appears not indexed
rm -f "$BASH_SENTINEL"
_assert_exit "c5: Bash grep src/ CMM absent allowed" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep -r 'parse' src/\"},\"cwd\":\"$PROJ_NO_CMM\"}" \
    "CLAUDE_CONFIG_DIR=$FAKE_CONFIG"
# Restore sentinel for any subsequent tests
echo "ready" > "$BASH_SENTINEL"

# --- Write / heredoc false-positive tests (c6-c9) ---
# Regression: a write (output redirection > / >> or a heredoc <<) is NOT code
# navigation. The gate must inspect only the command HEAD (before the first
# redirection), so write targets and heredoc bodies cannot trip it — even when
# the body contains a source-path token. Previously `cat > x.gd <<EOF ... EOF`
# false-positived because `cat` matched the verb and a path token in the body
# matched the source-path regex.

echo "--- Test c6: Bash heredoc write with src path in body -> exit 0 (ALLOW) ---"
_assert_exit "c6: heredoc write allowed" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat > /tmp/dump_desk.gd <<'EOF'\nextends Node\nscripts/foo\nEOF\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c7: Bash grep src/ with output redirected -> exit 2 (BLOCKED) ---"
_assert_exit "c7: redirected grep src/ still blocked" 2 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep -rn foo src/ > /tmp/out\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c8: Bash cat of a source file -> exit 2 (BLOCKED) ---"
_assert_exit "c8: cat src file still blocked" 2 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat src/main.py\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c9: Bash bare heredoc (no redirect) with lib path in body -> exit 0 (ALLOW) ---"
_assert_exit "c9: bare heredoc allowed" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat <<'EOF'\nlib/ helpers\nEOF\"},\"cwd\":\"$PROJ_REAL\"}"

# --- QA round 1 (F-01): bare '<' is input-redirect / process-substitution, NOT a
# heredoc — the path after it is real navigation and must still BLOCK. Only '>' and
# heredoc '<<' bodies are stripped from the command head.
echo "--- Test c10: Bash process substitution reading src -> exit 2 (BLOCKED) ---"
_assert_exit "c10: process substitution src/ blocked" 2 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"diff <(cat src/a.py) /tmp/b\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c11: Bash input redirect from src -> exit 2 (BLOCKED) ---"
_assert_exit "c11: input redirect src/ blocked" 2 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep foo < src/main.py\"},\"cwd\":\"$PROJ_REAL\"}"

# --- Nav verb must match in COMMAND position, not as a substring of an argument ---
echo "--- Test c12: git add of a file whose name contains 'grep' -> exit 0 (ALLOW) ---"
_assert_exit "c12: verb substring in filename not blocked" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git add hooks/global/cmm-grep-nudge.sh tests/test-cmm-grep-nudge.sh\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c13: real 'wc' verb against src/ still -> exit 2 (BLOCKED) ---"
_assert_exit "c13: real wc verb still blocked" 2 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"wc -l src/main.py\"},\"cwd\":\"$PROJ_REAL\"}"

# --- A verb in PIPE-SINK position is not navigation ---
# Measured 2026-09-03: `git log --oneline | cat` and `git diff --stat | cat` were
# blocked as "code search". CMM has no replacement for them, and a block with no
# usable alternative sends 90-95% of attempts straight back to raw tools.
echo "--- Test c14: 'git log --oneline | cat' under a source path -> exit 0 (ALLOW) ---"
_assert_exit "c14: git log piped to cat not blocked" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $PROJ_REAL/src && git log --oneline | cat\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c15: 'git diff --stat | cat' -> exit 0 (ALLOW) ---"
_assert_exit "c15: git diff piped to cat not blocked" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $PROJ_REAL/src && git diff --stat | cat\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c16: pipeline HEAD naming a source path still -> exit 2 (BLOCKED) ---"
# The fix must not disarm the gate: `cat` here reads a file, it is not a sink.
_assert_exit "c16: cat of src/ piped onward still blocked" 2 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat src/main.py | wc -l\"},\"cwd\":\"$PROJ_REAL\"}"

echo "--- Test c17: quoted pipe in a grep pattern still -> exit 2 (BLOCKED) ---"
_assert_exit "c17: quoted alternation does not disarm the gate" 2 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep -n 'foo|cat' src/main.py\"},\"cwd\":\"$PROJ_REAL\"}"

# --- Block messages must name a concrete call, not a placeholder ---
# Measured: gates naming a specific replacement convert 36-50% of blocks; a "..."
# template converts 13-25%; naming no alternative at all converts ~0%.
_msg_of() { echo "$1" | bash "$HOOK" 2>&1 >/dev/null || true; }

echo "--- Test c18: Grep block echoes the real search term ---"
_M=$(_msg_of "{\"tool_input\":{\"pattern\":\"handleRequest\",\"glob\":\"*.ts\",\"path\":\"$PROJ\"}}")
if printf '%s' "$_M" | grep -qF 'search_graph(name_pattern="handleRequest")'; then
    echo "PASS: c18: block names the concrete search_graph call"; PASS=$((PASS+1))
else
    echo "FAIL: c18: block still prints a placeholder"; FAIL=$((FAIL+1))
fi

echo "--- Test c19: regex-shaped term leads with search_code ---"
_M=$(_msg_of "{\"tool_input\":{\"pattern\":\"foo.*bar\",\"glob\":\"*.py\",\"path\":\"$PROJ\"}}")
if printf '%s' "$_M" | grep -m1 -q 'search_code'; then
    echo "PASS: c19: regex term leads with search_code"; PASS=$((PASS+1))
else
    echo "FAIL: c19: regex term did not lead with search_code"; FAIL=$((FAIL+1))
fi

# --- Perl reassurance at the moment of blocking ---
# Observed failure: an agent blocked on a *.pm grep concludes CMM cannot search
# Perl and falls back to Read. Perl IS a Hybrid LSP language here.
echo "--- Test c20: Perl target gets the 'fully indexed' line ---"
_M=$(_msg_of "{\"tool_input\":{\"pattern\":\"ApTest::SQLiteFile\",\"glob\":\"*.pm\",\"path\":\"$PROJ\"}}")
if printf '%s' "$_M" | grep -qF 'Perl is fully indexed'; then
    echo "PASS: c20: Perl block states Perl is indexed"; PASS=$((PASS+1))
else
    echo "FAIL: c20: Perl block omits the Perl reassurance"; FAIL=$((FAIL+1))
fi

echo "--- Test c21: non-Perl target does NOT get the Perl line ---"
_M=$(_msg_of "{\"tool_input\":{\"pattern\":\"handleRequest\",\"glob\":\"*.ts\",\"path\":\"$PROJ\"}}")
if printf '%s' "$_M" | grep -qF 'Perl is fully indexed'; then
    echo "FAIL: c21: Perl line leaked onto a TypeScript block"; FAIL=$((FAIL+1))
else
    echo "PASS: c21: Perl line correctly absent"; PASS=$((PASS+1))
fi

# --- extra_extensions cache must follow the config, not outlive it ---
# .cgi is known to neither the built-in list nor CMM; both learn it only from
# extra_extensions in .codebase-memory.json. Keying the cache on REPO_ROOT alone
# made the first read permanent, so adding an extension had no effect until the
# /tmp file was deleted by hand.
echo "--- Test c22: .cgi not blocked before it is declared ---"
_assert_exit "c22: undeclared .cgi allowed" 0 \
    "{\"tool_input\":{\"pattern\":\"handler\",\"glob\":\"*.cgi\",\"path\":\"$PROJ\"}}"

echo "--- Test c23: .cgi blocked once declared in extra_extensions ---"
echo '{"extra_extensions":{".cgi":"perl"}}' > "$PROJ/.codebase-memory.json"
# No cache clearing here on purpose: if the key ignored the config mtime, the
# stale entry from c22 would still be in effect and this assertion would fail.
_assert_exit "c23: declared .cgi blocked without clearing the cache" 2 \
    "{\"tool_input\":{\"pattern\":\"handler\",\"glob\":\"*.cgi\",\"path\":\"$PROJ\"}}"
rm -f "$PROJ/.codebase-memory.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
