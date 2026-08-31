#!/bin/bash
# test-phase-63-rule-refresh.sh — Regression coverage for phase-63 rule refresh
#
# Asserts that:
#   (a) rules/ctx-rules.md ctx_search row documents project: with three value forms
#       (omit, "global", <absolute-path>)
#   (b) rules/ctx-rules.md mentions sort: "timeline" and contentType
#   (c) rules/cmm-rules.md behavior-notes label contains v0.8.1 (not v0.7.0)
#   (d) rules/cmm-rules.md documents qualified_name (trace_path fallback)
#   (e) rules/cmm-rules.md mentions LSP (call graph accuracy)
#   (f) diff rules/ctx-rules.md .claude/rules/ctx-rules.md exits 0 (propagation check)
#   (g) diff rules/cmm-rules.md .claude/rules/cmm-rules.md exits 0 (propagation check)
#
# Usage: bash tests/test-phase-63-rule-refresh.sh
# Exit:  0 = all pass, 1 = any failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

PASS=0
FAIL=0

_pass() {
  echo "  [PASS] $1"
  PASS=$((PASS + 1))
}

_fail() {
  echo "  [FAIL] $1"
  FAIL=$((FAIL + 1))
}

_grep_assert() {
  local desc="$1"
  local pattern="$2"
  local file="$3"
  if grep -q "$pattern" "$file"; then
    _pass "$desc"
  else
    _fail "$desc"
  fi
}

_grep_absent() {
  local desc="$1"
  local pattern="$2"
  local file="$3"
  if grep -q "$pattern" "$file"; then
    _fail "$desc"
  else
    _pass "$desc"
  fi
}

_diff_assert() {
  local desc="$1"
  local file_a="$2"
  local file_b="$3"
  if diff -q "$file_a" "$file_b" >/dev/null 2>&1; then
    _pass "$desc"
  else
    _fail "$desc"
  fi
}

echo ""
echo "=== Phase 63: ctx-rules and cmm-rules refresh ==="
echo ""

echo "--- (a) ctx-rules: ctx_search row documents project: parameter ---"
_grep_assert "ctx-rules documents project: parameter" \
  'project:' "rules/ctx-rules.md"
_grep_assert "ctx-rules documents \"global\" value form" \
  '"global"' "rules/ctx-rules.md"
_grep_assert "ctx-rules documents <absolute-path> value form" \
  'absolute-path' "rules/ctx-rules.md"

echo ""
echo "--- (b) ctx-rules: sort: timeline and contentType documented ---"
_grep_assert "ctx-rules mentions sort: \"timeline\"" \
  'sort.*timeline\|timeline.*sort' "rules/ctx-rules.md"
_grep_assert "ctx-rules mentions contentType" \
  'contentType' "rules/ctx-rules.md"

echo ""
echo "--- (c) cmm-rules: behavior-notes label is v0.10.8, not v0.8.1 ---"
_grep_assert "cmm-rules label contains v0.10.8" \
  'v0\.10\.8' "rules/cmm-rules.md"
_grep_absent "cmm-rules label does not contain stale v0.8.1" \
  'v0\.8\.1' "rules/cmm-rules.md"

echo ""
echo "--- (d) cmm-rules: trace_path qualified_name fallback documented ---"
_grep_assert "cmm-rules documents qualified_name fallback" \
  'qualified_name' "rules/cmm-rules.md"

echo ""
echo "--- (e) cmm-rules: LSP call-graph accuracy note present + correct language set ---"
_grep_assert "cmm-rules mentions LSP" \
  'LSP' "rules/cmm-rules.md"
# Hybrid LSP set must match upstream v0.10.8 (README "Hybrid LSP ... and Perl";
# internal/cbm/lsp/perl_lsp.c). CUDA, Rust and Perl are all resolved languages.
_grep_assert "cmm-rules LSP set includes CUDA (resolved upstream)" \
  'C/C++/CUDA' "rules/cmm-rules.md"
_grep_assert "cmm-rules lists Rust among LSP-resolved languages" \
  'Kotlin, Rust' "rules/cmm-rules.md"
_grep_assert "cmm-rules lists Perl among LSP-resolved languages" \
  'Rust, and \*\*Perl\*\*' "rules/cmm-rules.md"
_grep_assert "cmm-rules calls Perl a first-class Hybrid LSP language" \
  'Perl is a first-class Hybrid LSP language' "rules/cmm-rules.md"
_grep_assert "cmm-rules forbids inferring non-support from an absent language" \
  'Never infer that a language is unsupported' "rules/cmm-rules.md"
_grep_assert "cmm-rules warns qn_pattern noise is not absence" \
  'name_pattern' "rules/cmm-rules.md"
_grep_assert "cmm-rules notes unresolved languages fall back to heuristics" \
  'fall back to grep on a pessimistic assumption' "rules/cmm-rules.md"

echo ""
echo "--- (f) installed .claude/rules/ctx-rules.md matches source ---"
_diff_assert "diff rules/ctx-rules.md .claude/rules/ctx-rules.md exits 0" \
  "rules/ctx-rules.md" ".claude/rules/ctx-rules.md"

echo ""
echo "--- (g) installed .claude/rules/cmm-rules.md matches source ---"
_diff_assert "diff rules/cmm-rules.md .claude/rules/cmm-rules.md exits 0" \
  "rules/cmm-rules.md" ".claude/rules/cmm-rules.md"

echo ""
echo "--- pre-existing notes still retained in cmm-rules ---"
_grep_assert "cmm-rules retains 200-row cap note" \
  '200' "rules/cmm-rules.md"
_grep_assert "cmm-rules retains search_code regex note" \
  'foo\.\*bar\|regex\|multi-word' "rules/cmm-rules.md"
_grep_assert "cmm-rules retains list_projects /tmp note" \
  '/tmp/' "rules/cmm-rules.md"

echo ""
echo "--- CHECKSUMS.sha256 verifies all entries ---"
if shasum -a 256 --check CHECKSUMS.sha256 >/dev/null 2>&1; then
  _pass "shasum -a 256 --check CHECKSUMS.sha256 exits 0"
else
  _fail "CHECKSUMS.sha256 verification failed"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
