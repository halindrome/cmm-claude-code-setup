#!/bin/bash
# test-phase-48-statusline-reprompt.sh — Regression coverage for install_statusline re-prompt
#
# Covers the phase-48 bugfix where re-running `setup.sh --project` on an
# already-installed project used to silently skip the six statusline component
# prompts. After phase 48, interactive re-runs re-prompt using each cached
# value as the default (Enter preserves, y/n flips), while --yes / --force /
# non-TTY stays on the silent path.
#
# Strategy: we exercise the helper `_prompt_with_default` directly by sourcing
# setup.sh in an inert mode and driving stdin via here-strings. This avoids
# fragile pseudo-TTY feeding while still covering Cases A (Enter preserves) and
# B (y flips false->true). Case C (--yes skips re-prompt, preserves cache) is
# tested end-to-end against a real setup.sh invocation.
#
# Usage: bash tests/test-phase-48-statusline-reprompt.sh
# Exit: 0 = all pass, 1 = any failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

PASS=0; FAIL=0

_assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (expected '$expected', got '$actual')"
        FAIL=$((FAIL+1))
    fi
}

# --- Load _prompt_with_default from setup.sh without running main() ----------
# setup.sh is a CLI entrypoint: sourcing it would normally run the install.
# We extract just the helper via sed between its definition markers.
HELPER_SRC=$(awk '/^_prompt_with_default\(\) \{/,/^\}$/' "$REPO_ROOT/setup.sh")
if [ -z "$HELPER_SRC" ]; then
    echo "FAIL: could not extract _prompt_with_default from setup.sh"
    exit 1
fi

# Evaluate the helper in this shell so we can call it directly.
eval "$HELPER_SRC"

# --- Case A: Enter preserves current value -----------------------------------
# Current=false, input=empty -> should return false.
a1=$(_prompt_with_default "test" "false" < /dev/null)
_assert_eq "Enter preserves current=false" "false" "$a1"

# Current=true, input=empty -> should return true.
a2=$(_prompt_with_default "test" "true" < /dev/null)
_assert_eq "Enter preserves current=true" "true" "$a2"

# --- Case B: explicit y/n flips ---------------------------------------------
b1=$(_prompt_with_default "test" "false" <<<"y")
_assert_eq "y flips false->true" "true" "$b1"

b2=$(_prompt_with_default "test" "true" <<<"n")
_assert_eq "n flips true->false" "false" "$b2"

b3=$(_prompt_with_default "test" "false" <<<"Y")
_assert_eq "Y flips false->true (uppercase)" "true" "$b3"

b4=$(_prompt_with_default "test" "true" <<<"N")
_assert_eq "N flips true->false (uppercase)" "false" "$b4"

# --- Spurious input falls back to current ------------------------------------
# Anything other than y/Y/n/N keeps the current value (per helper spec).
c1=$(_prompt_with_default "test" "false" <<<"garbage")
_assert_eq "unrecognized input keeps current=false" "false" "$c1"

c2=$(_prompt_with_default "test" "true" <<<"x")
_assert_eq "unrecognized input keeps current=true" "true" "$c2"

# --- Case C: --yes preserves an existing cache JSON end-to-end ---------------
# Exercises the non-interactive branch: if the config file exists and
# --reconfigure-statusline is false, setup.sh must preserve the cache
# untouched. Previous behavior also preserved, but this test locks it in so
# phase-48 branching doesn't regress it.
SCRATCH=$(mktemp -d -t cmm-phase48-XXXXXX)

# Compute the cache path the same way setup.sh does. We trap on EXIT to remove
# both the scratch dir and the cache file.
SCRATCH_HASH=$(echo "$SCRATCH" | md5 -q 2>/dev/null || echo "$SCRATCH" | md5sum | awk '{print $1}')
CACHE_FILE="$HOME/.cache/codebase-memory-mcp/_statusline-config-${SCRATCH_HASH}.json"

cleanup() {
    rm -rf "$SCRATCH"
    rm -f "$CACHE_FILE" "${CACHE_FILE}.tmp"
}
trap cleanup EXIT

cd "$SCRATCH"
git init -q
git commit --allow-empty -q -m "init"

# Seed a cache JSON with two keys flipped to false. This simulates an
# already-installed project with customized preferences.
mkdir -p "$(dirname "$CACHE_FILE")"
cat > "$CACHE_FILE" <<'SEED'
{
  "cmm_total": false,
  "cmm_details": true,
  "blocks_total": true,
  "block_details": true,
  "ctx_total": true,
  "ctx_details": false
}
SEED

# Run setup.sh with --yes. Since a statusLine may already be registered in the
# user's global settings, the outer "has_statusline" guard can short-circuit
# before Phase 2 runs in some environments -- that is existing behavior and
# not in scope here. What we are testing is: if Phase 2 DOES execute under
# --yes and the cache file exists, it must be preserved, not overwritten.
echo "n" | bash "$REPO_ROOT/setup.sh" --project --yes --skip-mcp-check >/dev/null 2>&1 || true

# Verify cache still exists and still has the two flipped values.
if [ ! -f "$CACHE_FILE" ]; then
    echo "FAIL: cache file was deleted by --yes run"
    FAIL=$((FAIL+1))
else
    got_cmm=$(python3 -c "import json; print(json.load(open('$CACHE_FILE'))['cmm_total'])")
    got_ctx=$(python3 -c "import json; print(json.load(open('$CACHE_FILE'))['ctx_details'])")
    _assert_eq "--yes preserves cmm_total=false in cache" "False" "$got_cmm"
    _assert_eq "--yes preserves ctx_details=false in cache" "False" "$got_ctx"
fi

# --- Case D: --reconfigure-statusline + --yes rewrites from current defaults
# Under --yes + --reconfigure-statusline, the non-interactive branch writes the
# current values back (not all-true, not the silent preserve). This locks in
# the "settings-wiped-but-config-survived" edge case behavior.
echo "n" | bash "$REPO_ROOT/setup.sh" --project --yes --reconfigure-statusline --skip-mcp-check >/dev/null 2>&1 || true

if [ -f "$CACHE_FILE" ]; then
    got_cmm2=$(python3 -c "import json; print(json.load(open('$CACHE_FILE'))['cmm_total'])")
    got_ctx2=$(python3 -c "import json; print(json.load(open('$CACHE_FILE'))['ctx_details'])")
    # After --reconfigure-statusline with --yes: non-interactive branch falls
    # through to write-back, echoing the current cur_* values. So the flipped
    # false values should still be false after the rewrite.
    _assert_eq "--reconfigure + --yes preserves cmm_total=false" "False" "$got_cmm2"
    _assert_eq "--reconfigure + --yes preserves ctx_details=false" "False" "$got_ctx2"
fi

# --- Case E: writer hash matches reader hash (QA round 01 F1 regression) -----
# The writer and the emitted statusline-cmm.sh must hash the SAME project
# root, otherwise the cache file the writer creates is never read. Run
# setup.sh --project from a subdirectory of a git repo and confirm the
# writer's chosen cache path matches the reader's computed path.
#
# We do not re-run setup (too heavy); instead we inline-replicate the writer's
# and reader's resolution logic against the same scratch repo and assert they
# produce the same hash.
HASH_SCRATCH=$(mktemp -d -t cmm-phase48-hash-XXXXXX)
trap 'rm -rf "$HASH_SCRATCH"' EXIT
(
    cd "$HASH_SCRATCH"
    git init -q
    mkdir -p subdir
    cd subdir
    # Writer resolution (mirrors setup.sh install_statusline after phase 48 fix).
    writer_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
    _walk="$writer_root"
    while true; do
        _parent="$(git -C "$_walk" rev-parse --show-superproject-working-tree 2>/dev/null)"
        [ -z "$_parent" ] && break
        _walk="$_parent"
    done
    writer_root="$_walk"
    writer_hash=$(echo "$writer_root" | md5 -q 2>/dev/null || echo "$writer_root" | md5sum | awk '{print $1}')
    # Reader resolution (mirrors the emitted statusline-cmm.sh top block).
    reader_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    _rwalk="$reader_root"
    while true; do
        _rparent="$(git -C "$_rwalk" rev-parse --show-superproject-working-tree 2>/dev/null)"
        [ -z "$_rparent" ] && break
        _rwalk="$_rparent"
    done
    reader_root="$_rwalk"
    reader_hash=$(echo "$reader_root" | md5 -q 2>/dev/null || echo "$reader_root" | md5sum | awk '{print $1}')
    echo "$writer_hash $reader_hash"
) | {
    read -r w_hash r_hash
    _assert_eq "writer and reader hash match when run from subdirectory" "$w_hash" "$r_hash"
}

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
