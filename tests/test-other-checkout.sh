#!/bin/bash
# test-other-checkout.sh — a search aimed at a git checkout OUTSIDE the session root
# (a linked worktree, a sibling clone) must name that checkout's own CMM project,
# and say when it has no index yet, in every grep gate.
#
# Regression: a session in ../cache-freshness editing a linked worktree in
# ../cache-freshness-wt/ queried the session's project, got nothing back, decided
# "the worktree isn't indexed" and grepped for the rest of the task. The gates
# either stayed silent (ctx-execute-cmm-nudge, grep-cmm-gate: "another repo, fail
# open") or named the session's project (cmm-grep-nudge).
# Usage: bash tests/test-other-checkout.sh
# Exit: 0 = all pass, 1 = any failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$SCRIPT_DIR/.."
LIB="$ROOT/hooks/lib/cmm-registered.sh"
NUDGE="$ROOT/hooks/project/ctx-execute-cmm-nudge.sh"
GATE="$ROOT/hooks/project/grep-cmm-gate.sh"
GREPNUDGE="$ROOT/hooks/global/cmm-grep-nudge.sh"

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
has()  { if printf '%s' "$2" | grep -qF -- "$3"; then pass "$1"; else fail "$1 (missing: $3)"; echo "  got: $2"; fi; }
hasnt(){ if printf '%s' "$2" | grep -qF -- "$3"; then fail "$1 (unexpected: $3)"; echo "  got: $2"; else pass "$1"; fi; }

TMP_RAW="$(mktemp -d)"; TMP="$(cd "$TMP_RAW" && pwd -P)"
CACHE="$TMP/cbm-cache"; mkdir -p "$CACHE"
export CBM_CACHE_DIR="$CACHE"
MAIN="$TMP/repo"; WT="$TMP/repo-wt/feature"
SENT=""; WT_SENT=""
cleanup() { rm -rf "$TMP"; [ -n "$SENT" ] && rm -f "$SENT"; [ -n "$WT_SENT" ] && rm -f "$WT_SENT"; }
trap cleanup EXIT

# --- fixture: a registered, indexed session repo + a linked worktree beside it ---
mkdir -p "$MAIN/lib"
printf '{"mcpServers":{"codebase-memory-mcp":{"command":"x"}}}\n' > "$MAIN/.mcp.json"
# >= 50 lines: grep-cmm-gate exempts small files.
for i in $(seq 1 60); do echo "sub f$i { return $i }"; done > "$MAIN/lib/Helper.pm"
git -C "$MAIN" init -q
git -C "$MAIN" -c user.email=t@t -c user.name=t add -A
git -C "$MAIN" -c user.email=t@t -c user.name=t commit -qm init
mkdir -p "$TMP/repo-wt"
git -C "$MAIN" worktree add -q "$WT" -b feature 2>/dev/null
[ -f "$WT/lib/Helper.pm" ] || { echo "FATAL: worktree fixture failed"; exit 1; }
SENT="/tmp/cmm-session-ready-$(echo "$MAIN" | md5 -q 2>/dev/null || echo "$MAIN" | md5sum | awk '{print $1}')"
touch "$SENT"

# shellcheck disable=SC1090
source "$LIB"
WT_NAME="$(PROJECT_ROOT="$WT" cmm_project_name)"
MAIN_NAME="$(PROJECT_ROOT="$MAIN" cmm_project_name)"

echo "--- lib ---"
[ "$(cmm_checkout_root "$WT/lib/Helper.pm")" = "$WT" ] && pass "worktree file -> worktree root" || fail "worktree root: $(cmm_checkout_root "$WT/lib/Helper.pm")"
[ "$(cmm_checkout_root "$MAIN/lib")" = "$MAIN" ] && pass "dir in main -> main root" || fail "main root"
[ -z "$(cmm_checkout_root "$TMP")" ] && pass "non-git path -> nothing" || fail "non-git path resolved"
[ -z "$(cmm_other_checkout "$MAIN/lib/Helper.pm" "$MAIN")" ] && pass "same checkout -> nothing" || fail "same checkout reported as other"
OC="$(cmm_other_checkout "$WT/lib/Helper.pm" "$MAIN")"
[ "$OC" = "${WT_NAME}"$'\t'"${WT}"$'\t'"0" ] && pass "worktree -> name, root, unindexed" || fail "other_checkout: [$OC]"
touch "$CACHE/$WT_NAME.db"
[ "$(cmm_other_checkout "$WT/lib/Helper.pm" "$MAIN" | cut -f3)" = 1 ] && pass "<name>.db in CBM_CACHE_DIR -> indexed" || fail "indexed flag"
rm -f "$CACHE/$WT_NAME.db"

# Submodule inside the session root is NOT another checkout (the root index covers it).
SUB_SRC="$TMP/subsrc"; mkdir -p "$SUB_SRC"; echo x > "$SUB_SRC/a.pm"
git -C "$SUB_SRC" init -q; git -C "$SUB_SRC" -c user.email=t@t -c user.name=t add -A
git -C "$SUB_SRC" -c user.email=t@t -c user.name=t commit -qm s
git -C "$MAIN" -c protocol.file.allow=always submodule -q add "$SUB_SRC" apps/sub 2>/dev/null
if [ -f "$MAIN/apps/sub/a.pm" ]; then
  [ -z "$(cmm_other_checkout "$MAIN/apps/sub/a.pm" "$MAIN")" ] && pass "submodule inside root -> not other" || fail "submodule counted as other checkout"
else
  fail "submodule fixture failed"
fi

echo "--- ctx-execute-cmm-nudge: grep into the worktree ---"
P="{\"tool_name\":\"mcp__plugin_context-mode_context-mode__ctx_execute\",\"tool_input\":{\"language\":\"shell\",\"code\":\"grep -n running $WT/lib/Helper.pm\"},\"cwd\":\"$MAIN\"}"
rc=0; OUT="$(echo "$P" | bash "$NUDGE" 2>/dev/null)" || rc=$?
[ "$rc" -eq 0 ] && pass "nudge allows (exit 0)" || fail "nudge exit $rc"
has  "nudge names the worktree project" "$OUT" "project=\\\"$WT_NAME\\\""
has  "nudge says to index it" "$OUT" "index_repository(repo_path=\\\"$WT\\\")"
touch "$CACHE/$WT_NAME.db"
OUT="$(echo "$P" | bash "$NUDGE" 2>/dev/null)"
hasnt "nudge: indexed worktree -> no index line" "$OUT" "index_repository"
has   "nudge: indexed worktree -> still names project" "$OUT" "$WT_NAME"
rm -f "$CACHE/$WT_NAME.db"
# Unrelated non-git path: still silent.
mkdir -p "$TMP/plain"; for i in $(seq 1 60); do echo "x$i"; done > "$TMP/plain/a.pm"
OUT="$(echo "{\"tool_name\":\"mcp__plugin_context-mode_context-mode__ctx_execute\",\"tool_input\":{\"language\":\"shell\",\"code\":\"grep -n x $TMP/plain/a.pm\"},\"cwd\":\"$MAIN\"}" | bash "$NUDGE" 2>/dev/null)"
[ -z "$OUT" ] && pass "nudge: non-git target -> silent" || fail "nudge spoke for non-git target: $OUT"

echo "--- grep-cmm-gate: Grep into the worktree ---"
P="{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"running\",\"path\":\"$WT/lib/Helper.pm\"},\"cwd\":\"$MAIN\"}"
rc=0; OUT="$(echo "$P" | bash "$GATE" 2>/dev/null)" || rc=$?
[ "$rc" -eq 0 ] && pass "gate allows (no sentinel for the worktree)" || fail "gate exit $rc"
has "gate names the worktree project" "$OUT" "$WT_NAME"
has "gate says to index it" "$OUT" "index_repository(repo_path=\\\"$WT\\\")"
# Same-checkout Grep still blocks, naming the session project.
# Run from $MAIN: the hook takes the session project from its own cwd, as in a real session.
rc=0; ERR="$(cd "$MAIN" && echo "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"running\",\"path\":\"$MAIN/lib/Helper.pm\"},\"cwd\":\"$MAIN\"}" | bash "$GATE" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 2 ] && pass "gate still blocks in the session checkout" || fail "gate same-checkout exit $rc"
has   "gate: same checkout names session project" "$ERR" "project=\"$MAIN_NAME\""
hasnt "gate: same checkout has no other-checkout note" "$ERR" "different checkout"

echo "--- cmm-grep-nudge: Grep and Bash into the worktree ---"
rc=0; ERR="$(cd "$MAIN" && echo "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"running\",\"path\":\"$WT/lib/Helper.pm\"},\"cwd\":\"$MAIN\"}" | bash "$GREPNUDGE" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 2 ] && pass "grep-nudge Grep blocks" || fail "grep-nudge Grep exit $rc"
has   "grep-nudge Grep: worktree project in the call" "$ERR" "project=\"$WT_NAME\""
hasnt "grep-nudge Grep: not the session project" "$ERR" "project=\"$MAIN_NAME\""
has   "grep-nudge Grep: index line" "$ERR" "index_repository(repo_path=\"$WT\")"
rc=0; ERR="$(cd "$MAIN" && echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep -n 'running' $WT/lib/Helper.pm\"},\"cwd\":\"$MAIN\"}" | bash "$GREPNUDGE" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 2 ] && pass "grep-nudge Bash blocks" || fail "grep-nudge Bash exit $rc"
has   "grep-nudge Bash: worktree project in the call" "$ERR" "project=\"$WT_NAME\""
has   "grep-nudge Bash: index line" "$ERR" "index_repository(repo_path=\"$WT\")"
rc=0; ERR="$(cd "$MAIN" && echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep -n 'running' lib/Helper.pm\"},\"cwd\":\"$MAIN\"}" | bash "$GREPNUDGE" 2>&1 >/dev/null)" || rc=$?
has   "grep-nudge Bash in session checkout: session project" "$ERR" "project=\"$MAIN_NAME\""
hasnt "grep-nudge Bash in session checkout: no note" "$ERR" "different checkout"

echo "--- boundaries: nested, ignored, worktree session, submodule worktree ---"
# A worktree nested INSIDE the session root: index-root-gate blocks indexing it, so never suggest it.
git -C "$MAIN" worktree add -q "$MAIN/.worktrees/nest" -b nest 2>/dev/null
if [ -f "$MAIN/.worktrees/nest/lib/Helper.pm" ]; then
  [ -z "$(cmm_other_checkout "$MAIN/.worktrees/nest/lib/Helper.pm" "$MAIN")" ] && pass "nested worktree inside root -> not other" || fail "nested worktree reported as other checkout"
else
  fail "nested worktree fixture failed"
fi
# A target git ignores in its checkout (the /opt/homebrew stdlib case) is not a project to index.
mkdir -p "$WT/ignored"; echo 'ignored/' > "$WT/.gitignore"; echo x > "$WT/ignored/lib.py"
[ -z "$(cmm_other_checkout "$WT/ignored/lib.py" "$MAIN")" ] && pass "git-ignored target -> not other" || fail "ignored target reported as other checkout"
# A session running INSIDE the worktree: its own files are not "a different checkout".
OUT="$(echo "{\"tool_name\":\"mcp__plugin_context-mode_context-mode__ctx_execute\",\"tool_input\":{\"language\":\"shell\",\"code\":\"grep -n running $WT/lib/Helper.pm\"},\"cwd\":\"$WT\"}" | bash "$NUDGE" 2>/dev/null)"
hasnt "nudge: worktree session's own file -> no other-checkout note" "$OUT" "different checkout"
# The incident shape: a worktree of a submodule placed outside its superproject.
if [ -d "$MAIN/apps/sub" ] && git -C "$MAIN/apps/sub" worktree add -q "$TMP/sub-wt" -b subwt 2>/dev/null; then
  SUBWT_NAME="$(PROJECT_ROOT="$TMP/sub-wt" cmm_project_name)"
  [ "$(cmm_other_checkout "$TMP/sub-wt/a.pm" "$MAIN" | cut -f1,2)" = "${SUBWT_NAME}"$'\t'"$TMP/sub-wt" ] && pass "submodule worktree outside superproject -> its own project" || fail "submodule worktree: [$(cmm_other_checkout "$TMP/sub-wt/a.pm" "$MAIN")]"
else
  fail "submodule worktree fixture failed"
fi
# cmm-grep-nudge: `cd <other checkout> && grep ... rel/` names that checkout.
ERR="$(cd "$MAIN" && echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $WT && grep -rn running lib/\"},\"cwd\":\"$MAIN\"}" | bash "$GREPNUDGE" 2>&1 >/dev/null)"
has "grep-nudge cd-then-grep: worktree project" "$ERR" "project=\"$WT_NAME\""
# grep-cmm-gate BLOCK path: the gate keys its sentinel on the target's checkout, so
# arm the worktree. The REPLACE WITH call itself -- not just the note -- must name it.
WT_SENT="/tmp/cmm-session-ready-$(echo "$WT" | md5 -q 2>/dev/null || echo "$WT" | md5sum | awk '{print $1}')"
touch "$WT_SENT"
rc=0; ERR="$(cd "$MAIN" && echo "$P" | bash "$GATE" 2>&1 >/dev/null)" || rc=$?
rm -f "$WT_SENT"
[ "$rc" -eq 2 ] && pass "gate blocks a Grep into another checkout" || fail "gate armed-other exit $rc"
has "gate block: replacement call names worktree project" "$ERR" "name_pattern=\"running\", project=\"$WT_NAME\""
has "gate block: other-checkout note" "$ERR" "different checkout"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
