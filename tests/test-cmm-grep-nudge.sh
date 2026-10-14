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

echo "--- Test c2: '# cmm-exempt' is no longer a bypass -> exit 2 (BLOCKED) ---"
_assert_exit "c2: Bash grep src/ with retired marker still blocked" 2 \
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
if printf '%s' "$_M" | grep -qF 'search_graph(name_pattern="handleRequest", project="'; then
    echo "PASS: c18: block names the concrete search_graph call"; PASS=$((PASS+1))
else
    echo "FAIL: c18: block still prints a placeholder"; FAIL=$((FAIL+1))
fi

echo "--- Test c14b/c15b: pipe-sink payloads that actually REACH the sink logic ---"
# c14/c15 send 'cd $PROJ_REAL/src && git log --oneline | cat'. The gate first
# requires a path fragment matching (src/|app/|lib/|hooks/|…); '…/src && git'
# contains 'src ' not 'src/', so those payloads never reach the pipe-sink code at
# all — both assertions passed against a hook with the fix fully removed. These
# forms carry a real 'src/' and so discriminate: fixed => exit 0, unfixed => 2.
_assert_exit "c14b: 'git log --oneline src/ | cat' not blocked" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git log --oneline src/ | cat\"},\"cwd\":\"$PROJ_REAL\"}"
_assert_exit "c15b: 'git diff --stat src/ | cat' not blocked" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git diff --stat src/ | cat\"},\"cwd\":\"$PROJ_REAL\"}"
_assert_exit "c15c: 'ls src/ | cat' not blocked" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls src/ | cat\"},\"cwd\":\"$PROJ_REAL\"}"
# …and the sink fix must not disarm a REAL navigation command that happens to
# end in a sink. This is the pair that keeps the fix honest in both directions.
_assert_exit "c15d: 'grep -rn foo src/ | cat' still blocked" 2 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep -rn foo src/ | cat\"},\"cwd\":\"$PROJ_REAL\"}"

# --- Verb and path must belong to the SAME command, and that path must be code ---
# Shapes from the 2026-10-14 maintainx replay that blocked a non-code read.
_bash_cmd() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$PROJ_REAL"; }
_assert_exit "c40: verb and src/ path in different commands allowed" 0 \
    "$(_bash_cmd 'M=apps/mobile; cat $M/tsconfig.spec.json')"
_assert_exit "c41: log grep in a compound that mentions apps/ allowed" 0 \
    "$(_bash_cmd 'grep -c FAIL /tmp/qa/verify.log; ls apps/ | wc -l')"
_assert_exit "c42: cat of a non-code file under src/ allowed" 0 \
    "$(_bash_cmd 'cat src/config/settings.json')"
_assert_exit "c43: grep restricted to non-code --include globs allowed" 0 \
    "$(_bash_cmd "grep -rn externalEvents --include='*.conf' --include='*.yaml' apps/")"
_assert_exit "c44: a code --include glob still blocked" 2 \
    "$(_bash_cmd "grep -rn externalEvents --include='*.conf' --include='*.pm' apps/")"
_assert_exit "c44b: an rg -g exclusion is not a non-code restriction" 2 \
    "$(_bash_cmd "rg foo -g '!*.md' src/")"
_assert_exit "c45: code file alongside a non-code one still blocked" 2 \
    "$(_bash_cmd 'grep -n foo src/a.json src/main.py')"
_assert_exit "c46: source grep later in a compound still blocked" 2 \
    "$(_bash_cmd 'cd /tmp; echo start; grep -rn handler src/')"
_assert_exit "c47: quoted separator does not split the command" 2 \
    "$(_bash_cmd "grep -n 'a;b' src/main.py")"
# QA round 1 F-02: the source dir can arrive via cd or a variable.
_assert_exit "c48: cd src/ && grep . still blocked" 2 "$(_bash_cmd 'cd src/ && grep -rn Foo .')"
_assert_exit "c49: cd src && grep (no slash) blocked" 2 "$(_bash_cmd 'cd src && grep -rn Foo .')"
_assert_exit "c50: cd apps/web && grep src blocked" 2 "$(_bash_cmd 'cd apps/web && grep -rn Foo src')"
_assert_exit "c51: D=src/; grep \$D blocked" 2 "$(_bash_cmd 'D=src/; grep -rn Foo $D')"
_assert_exit "c52: cd src/ && cat a.json allowed" 0 "$(_bash_cmd 'cd src/ && cat settings.json')"
_assert_exit "c53: cd /tmp && grep . allowed" 0 "$(_bash_cmd 'cd /tmp && grep -rn Foo . ; ls src/')"
# F-08: an earlier redirect must not hide a later command.
_assert_exit "c54: echo > file; grep src/ blocked" 2 "$(_bash_cmd 'echo hi > /tmp/x; grep -rn Foo src/')"
_assert_exit "c55: ls 2>/dev/null; grep src/ blocked" 2 "$(_bash_cmd 'ls 2>/dev/null; grep -rn Foo src/')"
_assert_exit "c56: grep 2>&1 | head on src/ blocked" 2 "$(_bash_cmd 'grep -rn Foo src/ 2>&1 | head -5')"
# QA round 2.
_assert_exit "c57: R2-02 quoted > keeps quotes balanced" 0 "$(_bash_cmd 'grep -n "a > b" CHANGELOG.md; ls apps/')"
_assert_exit "c58: R2-07 here-string does not hide a later grep" 2 "$(_bash_cmd 'cat <<< "$x"; grep -rn Foo src/')"
_assert_exit "c59: R2-07 \$((1<<2)) does not hide a later grep" 2 "$(_bash_cmd 'x=$((1<<2)); grep -rn Foo src/')"
_assert_exit "c60: R2-07 grep after a heredoc body blocked" 2 "$(_bash_cmd "cat > /tmp/n <<'EOF'
note
EOF
grep -rn Foo src/")"
_assert_exit "c61: R2-07 heredoc commit message allowed" 0 "$(_bash_cmd "git -C /repo/apps/mobile commit -m \"\$(cat <<'EOF'
fix: src/ thing
EOF
)\"")"
_assert_exit "c62: \"\$(cat apps/x.ts)\" still blocked" 2 "$(_bash_cmd 'echo "$(cat apps/x.ts)"')"
_assert_exit "c63: R2-06 cd src && tail absolute log allowed" 0 "$(_bash_cmd 'cd src && tail -f /tmp/server.out')"
_assert_exit "c64: R2-06 cd apps/web && cat Makefile allowed" 0 "$(_bash_cmd 'cd apps/web && cat Makefile')"
_assert_exit "c65: cd src && cat main.py still blocked" 2 "$(_bash_cmd 'cd src && cat main.py')"

echo "--- Test c18b: an --include glob never becomes the search term (QA r1 F-03) ---"
# `.*` in the extractor was greedy, so it bound the LAST quoted string: a trailing
# --include='*.pl' produced search_graph(name_pattern="*.pl"), a call that returns
# nothing. Worse than the old "..." placeholder because it looks correct -- and it
# misfires hardest on the Perl case WS2 exists to fix.
for _CMD in "grep -rn 'reqStatus' src/ --include='*.pl'" \
            "grep -rn --include='*.pm' 'reqStatus' src/" \
            "grep -rn 'reqStatus' -t perl src/" ; do
  _M=$(_msg_of "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$_CMD\"},\"cwd\":\"$PROJ_REAL\"}")
  if printf '%s' "$_M" | grep -qF 'reqStatus'; then
    echo "PASS: c18b: term recovered from: $_CMD"; PASS=$((PASS+1))
  else
    echo "FAIL: c18b: wrong term from: $_CMD"; FAIL=$((FAIL+1))
  fi
  if printf '%s' "$_M" | grep -qE '(name_pattern|query)="\*\.(pl|pm)"'; then
    echo "FAIL: c18b: glob leaked in as the search term: $_CMD"; FAIL=$((FAIL+1))
  else
    echo "PASS: c18b: no glob in the suggested call: $_CMD"; PASS=$((PASS+1))
  fi
done

echo "--- Test c20: extension-cache mtime probe tries GNU stat first (QA r1 F-04) ---"
# On GNU coreutils `stat -f` is --file-system and EXITS 0 for any existing file,
# so `stat -f %m || stat -c %Y` never reaches the fallback and the cache key is a
# per-platform constant -- restoring the "first read is permanent" bug on all of
# Linux. This hook installs to ~/.claude and runs for every repo, so order matters.
_STATLINE=$(grep -n '_CFG_MTIME=' "$HOOK" | head -1)
if printf '%s' "$_STATLINE" | grep -qE 'stat -c %Y.*stat -f %m'; then
    echo "PASS: c20: GNU stat -c is attempted before BSD stat -f"; PASS=$((PASS+1))
else
    echo "FAIL: c20: BSD stat -f runs first; on GNU it succeeds and pins the key"; FAIL=$((FAIL+1))
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

# --- c24: the search term comes from the SEGMENT that owns the search verb ---
# Compound commands are routinely narrated with echo labels. _extract_term took
# the FIRST quoted string in the whole command, so an echo label ahead of the
# grep supplied the term: the block fired correctly and then suggested
#   search_code(pattern="=== spec: changeTarget/_fetch coverage ===")
# which runs and returns nothing. Same class as the --include='*.pl' fix (c18b):
# a plausible-but-wrong term converts worse than a bare "..." placeholder.
# Observed live 2026-09-04 in liverpool-cleanup.
echo ""
echo "--- Test c24: echo labels must not hijack the extracted term ---"

_c24_term_is() {
    local label="$1" cmd="$2" want="$3"
    local msg
    msg=$(_msg_of "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"},\"cwd\":\"$PROJ_REAL\"}")
    if printf '%s' "$msg" | grep -qF "\"$want\""; then
        echo "PASS: c24: $label"; PASS=$((PASS+1))
    else
        echo "FAIL: c24: $label (term not '$want')"
        echo "    msg: $msg"
        FAIL=$((FAIL+1))
    fi
}

_c24_term_is "bare grep keeps its own term" \
    "grep -n 'changeTarget' src/main.py" "changeTarget"
_c24_term_is "echo label BEFORE the grep does not win" \
    "echo '=== coverage ==='; grep -n 'changeTarget' src/main.py" "changeTarget"
_c24_term_is "echo labels on both sides" \
    "echo '=== a ==='; grep -n 'changeTarget' src/main.py; echo '=== b ==='" "changeTarget"
_c24_term_is "grep keeps its pipe sink in the same segment" \
    "grep -n 'changeTarget' src/main.py | head -40" "changeTarget"
# A leading `git -C <dir> <non-grep>` owns no search term; selecting it would
# yield the placeholder and lose the real term further along.
_c24_term_is "leading git -C branch does not claim the segment" \
    "git -C src branch --show-current && echo '=== hdr ==='; grep -n 'changeTarget' src/main.py" "changeTarget"
# Uses `git grep … src/` rather than `git -C src grep … .`: the outer gate
# requires a source-path fragment to classify the command as navigation at all,
# and `.` is not one. That predates this fix and is a separate behaviour.
_c24_term_is "git grep IS a search verb" \
    "echo '=== hdr ==='; git grep -n 'changeTarget' src/" "changeTarget"

# And a compound with no code search at all must still pass through untouched.
_assert_exit "c24: git branch + status compound not blocked" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git -C src branch --show-current && git -C src status --porcelain\"},\"cwd\":\"$PROJ_REAL\"}"

# --- c25: a nav verb left DANGLING by the `<<` cut owns no path ---
# BNAV_HEAD is cut at the first `<<`, so
#   git -C /repo/apps/mobile commit --no-edit -m "$(cat <<'EOF' … EOF)"
# became `… -m "$(cat `. The bare `cat` (preceded by `(`, in the separator class)
# satisfied the VERB test while `apps/` from the `git -C` PATH satisfied the path
# test -- the two taken from different commands. Observed live 2026-09-04 in
# liverpool-cleanup, blocking a commit whose message body came from a here-doc:
# exactly the shape ctx-execute-enforcer.sh was fixed for in 4d26952, blocked
# here instead, so that fix bought the agent nothing.
echo ""
echo "--- Test c25: dangling nav verb after the here-doc cut ---"

# Built via a quoted here-doc, then JSON-encoded in python: the payload contains
# both `"` and `$(`, and hand-escaping those through a bash double-quoted string
# into JSON is how the earlier fixtures in this file grew unreadable.
_c25_json() {
    _C25_CMD="$1" _C25_CWD="$PROJ_REAL" python3 -c 'import json, os
print(json.dumps({"tool_name": "Bash",
                  "tool_input": {"command": os.environ["_C25_CMD"]},
                  "cwd": os.environ["_C25_CWD"]}))'
}

read -r -d '' _C25_COMMIT <<'C25EOF' || true
git -C __PROJ__/apps/mobile commit --no-edit -m "$(cat <<'EOF'
fix(comms): correct _fetch change target

Body line that mentions src/main.py on purpose.
EOF
)"
C25EOF
_C25_COMMIT="${_C25_COMMIT//__PROJ__/$PROJ_REAL}"

_assert_exit "c25: here-doc commit message not blocked as navigation" 0 \
    "$(_c25_json "$_C25_COMMIT")"

# The fix must not disarm the gate. Each of these keeps its argument, so the verb
# and the path belong to the SAME command and the block must stand.
_assert_exit "c25: cat inside \$() WITH a path still blocked" 2 \
    "$(_c25_json 'echo "$(cat apps/mobile/src/foo.ts)"')"
_assert_exit "c25: bare input redirect still blocked (F-01)" 2 \
    "$(_c25_json 'cat < src/main.py')"
_assert_exit "c25: plain cat of a source path still blocked" 2 \
    "$(_c25_json 'cat src/main.py')"
_assert_exit "c25: grep with its own term still blocked" 2 \
    "$(_c25_json 'grep -n changeTarget apps/mobile/src/comms.service.spec.ts')"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
