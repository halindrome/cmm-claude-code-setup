#!/bin/bash
# test-version-stamp.sh — Regression coverage for the .cmm-stack-version install stamp
#
# Closes QA-round-1 finding F-01 (no test asserted the version marker is written).
# Asserts that setup.sh's write_version_stamp helper:
#   T1 writes <target>/.cmm-stack-version with the bare VERSION string on line 1
#   T2 honors DRY_RUN: prints "Would write", creates no file
#   T3 is fail-safe — with no VERSION file and no git repo it emits unknown/nogit
#      and returns 0 (never aborts the install under set -euo pipefail)
#   T4 install_global invokes the stamp with the global config dir
#   T5 install_project invokes the stamp with the project .claude dir
#
# The helper is extracted from setup.sh and sourced standalone, so the installer's
# main() never runs. T4/T5 are static guards against a future refactor dropping
# either call site.
#
# Usage: bash tests/test-version-stamp.sh
# Exit:  0 = all pass, 1 = any failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP="$REPO_ROOT/setup.sh"

PASS=0
FAIL=0
_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Extract just the write_version_stamp function body (column-0 closing brace ends
# it; the inner `{ ... } > file` block is indented and does not match /^}/).
FUNC_FILE="$(mktemp)"
trap 'rm -f "$FUNC_FILE"' EXIT
awk '/^write_version_stamp\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$SETUP" > "$FUNC_FILE"
if ! grep -q 'write_version_stamp()' "$FUNC_FILE"; then
  echo "  FAIL: could not extract write_version_stamp from setup.sh"
  exit 1
fi

# --- T1: normal write — line 1 is the bare version ---
T1_OUT="$(mktemp -d)"
(
  DRY_RUN=false
  SCRIPT_DIR="$REPO_ROOT"
  source "$FUNC_FILE"
  write_version_stamp "$T1_OUT" >/dev/null 2>&1
)
EXPECT="$(cat "$REPO_ROOT/VERSION")"
if [ -f "$T1_OUT/.cmm-stack-version" ] && [ "$(head -1 "$T1_OUT/.cmm-stack-version")" = "$EXPECT" ]; then
  _pass "T1 marker written, line 1 is the bare version ($EXPECT)"
else
  _fail "T1 marker missing or line 1 != '$EXPECT' (got '$(head -1 "$T1_OUT/.cmm-stack-version" 2>/dev/null)')"
fi
rm -rf "$T1_OUT"

# --- T2: DRY_RUN writes nothing ---
T2_OUT="$(mktemp -d)"
T2_LOG="$(
  DRY_RUN=true
  SCRIPT_DIR="$REPO_ROOT"
  source "$FUNC_FILE"
  write_version_stamp "$T2_OUT" 2>&1
)"
if [ ! -f "$T2_OUT/.cmm-stack-version" ] && printf '%s' "$T2_LOG" | grep -q "Would write"; then
  _pass "T2 DRY_RUN prints 'Would write' and creates no marker"
else
  _fail "T2 DRY_RUN wrote a marker or omitted the notice"
fi
rm -rf "$T2_OUT"

# --- T3: fail-safe fallback (no VERSION, not a git repo) ---
T3_FAKE="$(mktemp -d)" # empty: no VERSION, no .git
T3_OUT="$(mktemp -d)"
T3_RC=0
(
  set -euo pipefail # mirror the installer's strict mode
  DRY_RUN=false
  SCRIPT_DIR="$T3_FAKE"
  source "$FUNC_FILE"
  write_version_stamp "$T3_OUT" >/dev/null 2>&1
) || T3_RC=$?
if [ "$T3_RC" -eq 0 ] &&
  [ "$(head -1 "$T3_OUT/.cmm-stack-version" 2>/dev/null)" = "unknown" ] &&
  grep -q '^commit=nogit$' "$T3_OUT/.cmm-stack-version" 2>/dev/null; then
  _pass "T3 fallback emits unknown/nogit and returns 0 under set -euo pipefail"
else
  _fail "T3 fallback failed (rc=$T3_RC, line1='$(head -1 "$T3_OUT/.cmm-stack-version" 2>/dev/null)')"
fi
rm -rf "$T3_FAKE" "$T3_OUT"

# --- T4/T5: both install scopes invoke the stamp ---
if grep -qE 'write_version_stamp "\$\{config_dir\}"' "$SETUP"; then
  _pass "T4 install_global invokes write_version_stamp with the config dir"
else
  _fail "T4 install_global does not call write_version_stamp"
fi
if grep -qE 'write_version_stamp "\.claude"' "$SETUP"; then
  _pass "T5 install_project invokes write_version_stamp with .claude"
else
  _fail "T5 install_project does not call write_version_stamp"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
