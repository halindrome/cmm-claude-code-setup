#!/bin/bash
# test-cmm-coverage-advisory.sh — Tests setup.sh's report_unindexed_extensions().
#
# CMM and hooks/global/cmm-grep-nudge.sh both learn repo-specific source
# extensions ONLY from `extra_extensions` in a repo-root .codebase-memory.json.
# They agree, so a repo without that file fails open consistently -- but
# silently: the code is there, CMM is blind to it, and nothing says so. This
# advisory is the only thing that surfaces it. .cgi is the motivating case
# (absent from CMM's own source and from the hook's built-in list).
#
# Usage: bash tests/test-cmm-coverage-advisory.sh
# Exit: 0 = all pass, 1 = any failure
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

PASS=0; FAIL=0
pass() { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Extract just the function so the test never runs the installer.
FN="$TMP/fn.sh"
sed -n '/^report_unindexed_extensions() {/,/^}$/p' "$ROOT/setup.sh" > "$FN"
if [ ! -s "$FN" ]; then
  echo "  [FAIL] could not extract report_unindexed_extensions from setup.sh"
  echo "Results: 0 passed, 1 failed"
  exit 1
fi
_report() { bash -c "source '$FN'; report_unindexed_extensions '$1'" 2>&1; }

echo ""
echo "=== CMM coverage advisory ==="
echo ""

# A repo with several .cgi files and no config.
REPO="$TMP/repo"; mkdir -p "$REPO/cgi-bin"
for i in 1 2 3 4; do printf '#!/usr/bin/perl\n' > "$REPO/cgi-bin/page$i.cgi"; done

echo "--- undeclared extension is reported ---"
OUT="$(_report "$REPO")"
printf '%s' "$OUT" | grep -qF '.cgi' \
  && pass "names the undeclared extension" || fail "did not name .cgi"
printf '%s' "$OUT" | grep -qF '4' \
  && pass "reports how many files" || fail "no file count"
printf '%s' "$OUT" | grep -qF 'extra_extensions' \
  && pass "names the setting to add" || fail "does not name extra_extensions"
printf '%s' "$OUT" | grep -qF 'No .codebase-memory.json' \
  && pass "says the config is missing entirely" || fail "missing-config case not distinguished"

echo ""
echo "--- declaring it silences the advisory ---"
printf '%s\n' '{"extra_extensions":{".cgi":"perl"}}' > "$REPO/.codebase-memory.json"
OUT="$(_report "$REPO")"
if [ -z "$OUT" ]; then
  pass "silent once the extension is declared"
else
  fail "still warned after the extension was declared"
fi

echo ""
echo "--- a config that declares something else still reports .cgi ---"
printf '%s\n' '{"extra_extensions":{".tpl":"html"}}' > "$REPO/.codebase-memory.json"
OUT="$(_report "$REPO")"
printf '%s' "$OUT" | grep -qF '.cgi' \
  && pass "reports .cgi when the config omits it" || fail "missed .cgi with a partial config"
printf '%s' "$OUT" | grep -qF 'Add them to' \
  && pass "uses the has-config wording" || fail "wrong wording for the has-config case"
rm -f "$REPO/.codebase-memory.json"

echo ""
echo "--- ordinary repos stay silent ---"
PLAIN="$TMP/plain"; mkdir -p "$PLAIN"
printf 'x\n' > "$PLAIN/a.py"; printf 'x\n' > "$PLAIN/b.ts"; printf 'x\n' > "$PLAIN/c.md"
OUT="$(_report "$PLAIN")"
[ -z "$OUT" ] && pass "no advisory for known extensions" || fail "warned about known extensions"

echo ""
echo "--- noise control ---"
# Below the threshold: one stray file is not worth a warning.
FEW="$TMP/few"; mkdir -p "$FEW"; printf 'x\n' > "$FEW/one.cgi"
OUT="$(_report "$FEW")"
[ -z "$OUT" ] && pass "single stray file does not warn" || fail "warned on a single file"

# Vendored trees must not be scanned.
VEND="$TMP/vend"; mkdir -p "$VEND/node_modules/pkg"
for i in 1 2 3 4 5; do printf 'x\n' > "$VEND/node_modules/pkg/f$i.cgi"; done
OUT="$(_report "$VEND")"
[ -z "$OUT" ] && pass "skips node_modules" || fail "scanned node_modules"

echo ""
echo "--- never fails the install ---"
# Advisory only: a missing directory or an unreadable config must not error.
if _report "$TMP/does-not-exist" >/dev/null 2>&1; then
  pass "missing directory returns cleanly"
else
  fail "errored on a missing directory"
fi
printf 'not json\n' > "$REPO/.codebase-memory.json"
if _report "$REPO" >/dev/null 2>&1; then
  pass "malformed config returns cleanly"
else
  fail "errored on a malformed config"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
