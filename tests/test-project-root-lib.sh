#!/bin/bash
# test-project-root-lib.sh — Tests for hooks/lib/project-root.sh shared library
# Verifies cache creation, cache hit, cache re-creation, variable exports, and non-git fallback
# Usage: bash tests/test-project-root-lib.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
LIB_SCRIPT="$REPO_ROOT/hooks/lib/project-root.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- Global fixture setup ---
TMPDIR_ROOT=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR_ROOT"; }
trap cleanup EXIT

# ===================================================================
echo "=== Test 1: Source from git repo exports all variables ==="
# ===================================================================

TMPDIR_T1="$TMPDIR_ROOT/t1"
REPO_T1="$TMPDIR_T1/repo"
mkdir -p "$REPO_T1"
git -C "$REPO_T1" init -q
# Use plain pwd (not pwd -P) for cache key — matches the library's $(pwd) behavior
REPO_T1_PWD="$(cd "$REPO_T1" && pwd)"
REPO_T1_REAL="$(cd "$REPO_T1" && pwd -P)"
HASH_T1=$(echo -n "$REPO_T1_PWD" | md5 -q 2>/dev/null || echo -n "$REPO_T1_PWD" | md5sum 2>/dev/null | cut -d' ' -f1)

# Clean any pre-existing cache for this temp dir
rm -f "/tmp/cmm-project-root-$HASH_T1"

RESULT=$(cd "$REPO_T1" && bash -c "
  source '$LIB_SCRIPT'
  echo \"ROOT=\$PROJECT_ROOT\"
  echo \"HASH=\$PROJECT_HASH\"
  echo \"CMM=\$CMM_SENTINEL\"
  echo \"CTX=\$CTX_SENTINEL\"
  echo \"LOADED=\$_PROJECT_ROOT_LOADED\"
" 2>/dev/null)

ROOT_VAL=$(echo "$RESULT" | grep '^ROOT=' | cut -d= -f2-)
HASH_VAL=$(echo "$RESULT" | grep '^HASH=' | cut -d= -f2-)
CMM_VAL=$(echo "$RESULT"  | grep '^CMM='  | cut -d= -f2-)
CTX_VAL=$(echo "$RESULT"  | grep '^CTX='  | cut -d= -f2-)
LOADED_VAL=$(echo "$RESULT" | grep '^LOADED=' | cut -d= -f2-)

if [ -n "$ROOT_VAL" ]; then pass "PROJECT_ROOT is set ($ROOT_VAL)"; else fail "PROJECT_ROOT is empty"; fi
if [ -n "$HASH_VAL" ]; then pass "PROJECT_HASH is set"; else fail "PROJECT_HASH is empty"; fi
if [ "$CMM_VAL" = "/tmp/cmm-session-ready-${HASH_VAL}" ]; then
  pass "CMM_SENTINEL has correct format"
else
  fail "CMM_SENTINEL expected /tmp/cmm-session-ready-${HASH_VAL}, got $CMM_VAL"
fi
if [ "$CTX_VAL" = "/tmp/cmm-ctx-ready-${HASH_VAL}" ]; then
  pass "CTX_SENTINEL has correct format"
else
  fail "CTX_SENTINEL expected /tmp/cmm-ctx-ready-${HASH_VAL}, got $CTX_VAL"
fi
if [ "$LOADED_VAL" = "1" ]; then pass "_PROJECT_ROOT_LOADED is 1"; else fail "_PROJECT_ROOT_LOADED expected 1, got $LOADED_VAL"; fi

# ===================================================================
echo ""
echo "=== Test 2: Cache file is created after first source ==="
# ===================================================================

CACHE_T2="/tmp/cmm-project-root-$HASH_T1"
if [ -f "$CACHE_T2" ]; then
  pass "Cache file exists at $CACHE_T2"
  CACHED_ROOT=$(sed -n '1p' "$CACHE_T2")
  CACHED_HASH=$(sed -n '2p' "$CACHE_T2")
  if [ "$CACHED_ROOT" = "$ROOT_VAL" ]; then
    pass "Cache line 1 matches PROJECT_ROOT"
  else
    fail "Cache line 1 expected $ROOT_VAL, got $CACHED_ROOT"
  fi
  if [ "$CACHED_HASH" = "$HASH_VAL" ]; then
    pass "Cache line 2 matches PROJECT_HASH"
  else
    fail "Cache line 2 expected $HASH_VAL, got $CACHED_HASH"
  fi
else
  fail "Cache file missing at $CACHE_T2"
fi

# ===================================================================
echo ""
echo "=== Test 3: Second source uses cache (idempotent guard) ==="
# ===================================================================

# Source twice in the same shell — the idempotent guard should prevent re-computation
RESULT_T3=$(cd "$REPO_T1" && bash -c "
  source '$LIB_SCRIPT'
  FIRST_LOADED=\$_PROJECT_ROOT_LOADED
  # Source again — guard should fire
  source '$LIB_SCRIPT'
  echo \"FIRST=\$FIRST_LOADED\"
  echo \"ROOT=\$PROJECT_ROOT\"
" 2>/dev/null)

FIRST_T3=$(echo "$RESULT_T3" | grep '^FIRST=' | cut -d= -f2-)
ROOT_T3=$(echo "$RESULT_T3" | grep '^ROOT=' | cut -d= -f2-)

if [ "$FIRST_T3" = "1" ]; then
  pass "Idempotent guard: _PROJECT_ROOT_LOADED set after first source"
else
  fail "Idempotent guard: _PROJECT_ROOT_LOADED expected 1, got $FIRST_T3"
fi
if [ "$ROOT_T3" = "$ROOT_VAL" ]; then
  pass "Second source still has correct PROJECT_ROOT"
else
  fail "Second source PROJECT_ROOT expected $ROOT_VAL, got $ROOT_T3"
fi

# ===================================================================
echo ""
echo "=== Test 4: Cache removal forces re-creation ==="
# ===================================================================

rm -f "$CACHE_T2"
if [ -f "$CACHE_T2" ]; then
  fail "Cache file should be deleted before re-source"
else
  pass "Cache file deleted successfully"
fi

# Source in a fresh shell (no _PROJECT_ROOT_LOADED carry-over)
cd "$REPO_T1" && bash -c "source '$LIB_SCRIPT'" 2>/dev/null

if [ -f "$CACHE_T2" ]; then
  pass "Cache file re-created after removal"
else
  fail "Cache file not re-created after removal"
fi

# ===================================================================
echo ""
echo "=== Test 5: Non-git directory falls back to BASH_SOURCE resolution ==="
# ===================================================================

TMPDIR_T5="$TMPDIR_ROOT/t5"
NONGIT_T5="$TMPDIR_T5/nongit"
mkdir -p "$NONGIT_T5"

# Compute cache key for the non-git directory
# Use plain pwd for cache key — matches library behavior
NONGIT_T5_PWD="$(cd "$NONGIT_T5" && pwd)"
HASH_T5=$(echo -n "$NONGIT_T5_PWD" | md5 -q 2>/dev/null || echo -n "$NONGIT_T5_PWD" | md5sum 2>/dev/null | cut -d' ' -f1)
rm -f "/tmp/cmm-project-root-$HASH_T5"

RESULT_T5=$(cd "$NONGIT_T5" && bash -c "
  source '$LIB_SCRIPT'
  echo \"ROOT=\$PROJECT_ROOT\"
  echo \"HASH=\$PROJECT_HASH\"
" 2>/dev/null)

ROOT_T5=$(echo "$RESULT_T5" | grep '^ROOT=' | cut -d= -f2-)
HASH_T5_VAL=$(echo "$RESULT_T5" | grep '^HASH=' | cut -d= -f2-)

if [ -n "$ROOT_T5" ]; then
  pass "Non-git fallback: PROJECT_ROOT is set ($ROOT_T5)"
else
  fail "Non-git fallback: PROJECT_ROOT is empty"
fi
if [ -n "$HASH_T5_VAL" ]; then
  pass "Non-git fallback: PROJECT_HASH is set"
else
  fail "Non-git fallback: PROJECT_HASH is empty"
fi

# Clean up test cache files
rm -f "/tmp/cmm-project-root-$HASH_T1" "/tmp/cmm-project-root-$HASH_T5"

# ===================================================================
echo ""
echo "=== Test 6: Corrupt cache file triggers re-computation ==="
# ===================================================================

TMPDIR_T6="$TMPDIR_ROOT/t6"
REPO_T6="$TMPDIR_T6/repo"
mkdir -p "$REPO_T6"
git -C "$REPO_T6" init -q
REPO_T6_REAL="$(cd "$REPO_T6" && pwd -P)"
# Use plain pwd for cache key — matches the library's $(pwd) behavior (may differ from pwd -P on macOS)
REPO_T6_PWD="$(cd "$REPO_T6" && pwd)"
HASH_T6=$(echo -n "$REPO_T6_PWD" | md5 -q 2>/dev/null || echo -n "$REPO_T6_PWD" | md5sum 2>/dev/null | cut -d' ' -f1)

# Write a corrupt cache (invalid directory path)
echo "/nonexistent/path/that/does/not/exist" > "/tmp/cmm-project-root-$HASH_T6"
echo "badhash" >> "/tmp/cmm-project-root-$HASH_T6"

RESULT_T6=$(cd "$REPO_T6" && bash -c "
  source '$LIB_SCRIPT'
  echo \"ROOT=\$PROJECT_ROOT\"
" 2>/dev/null)

ROOT_T6=$(echo "$RESULT_T6" | grep '^ROOT=' | cut -d= -f2-)

if [ "$ROOT_T6" = "$REPO_T6_REAL" ]; then
  pass "Corrupt cache: re-computed correct PROJECT_ROOT"
else
  fail "Corrupt cache: expected $REPO_T6_REAL, got $ROOT_T6"
fi

# Verify cache was overwritten with correct values
FIXED_ROOT=$(sed -n '1p' "/tmp/cmm-project-root-$HASH_T6" 2>/dev/null)
if [ "$FIXED_ROOT" = "$REPO_T6_REAL" ]; then
  pass "Corrupt cache: cache file overwritten with correct root"
else
  fail "Corrupt cache: cache not fixed, line 1 = $FIXED_ROOT"
fi

# Clean up
rm -f "/tmp/cmm-project-root-$HASH_T6"

# ===================================================================
echo ""
echo "=== Summary ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
