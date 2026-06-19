#!/bin/bash
# test-phase-66-resolver.sh — Tests for hooks/lib/vbw-source.sh resolver
#
# Covers: CLAUDE_CONFIG_DIR override, marketplace path detection,
# local-symlink path, dev-checkout fallback, absent (each as distinct case).
# Uses fixture dirs under tests/fixtures/mock-vbw-plugin/ to avoid
# depending on a live VBW install.
#
# Usage: bash tests/test-phase-66-resolver.sh
# Exit: 0 = all pass, 1 = any failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
LIB="$REPO_ROOT/hooks/lib/vbw-source.sh"

PASS=0; FAIL=0

_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

# _resolve_in_env <label> <expected_type> <expected_agents_dir_suffix> <env_prefix...>
# Runs resolve_vbw_source in a clean subshell with the given env, checks the exported vars.
_assert_resolves() {
    local label="$1" expected_type="$2" expected_suffix="$3"
    shift 3
    # remaining args are VAR=value pairs to export before sourcing
    local result
    result=$(env "$@" bash -c "
        source '$LIB' 2>/dev/null
        if resolve_vbw_source 2>/dev/null; then
            echo \"type=\$VBW_SOURCE_TYPE\"
            echo \"dir=\$VBW_AGENTS_DIR\"
        else
            echo \"type=\$VBW_SOURCE_TYPE\"
            echo \"dir=absent\"
        fi
    " 2>/dev/null)
    local actual_type
    actual_type=$(echo "$result" | grep '^type=' | cut -d= -f2-)
    local actual_dir
    actual_dir=$(echo "$result" | grep '^dir=' | cut -d= -f2-)

    if [ "$actual_type" != "$expected_type" ]; then
        _fail "$label" "VBW_SOURCE_TYPE: expected '$expected_type', got '$actual_type'"
        return
    fi
    if [ -n "$expected_suffix" ] && [ "$expected_suffix" != "SKIP" ]; then
        case "$actual_dir" in
            *"$expected_suffix"*) : ;;
            *) _fail "$label" "VBW_AGENTS_DIR '$actual_dir' does not contain '$expected_suffix'"; return ;;
        esac
    fi
    _pass "$label"
}

_assert_absent() {
    local label="$1"
    shift
    local rc=0
    env "$@" bash -c "
        source '$LIB' 2>/dev/null
        resolve_vbw_source 2>/dev/null
    " 2>/dev/null || rc=$?
    if [ "$rc" -ne 0 ]; then
        _pass "$label"
    else
        _fail "$label" "Expected resolve_vbw_source to return 1 (absent), got 0"
    fi
}

# -----------------------------------------------------------------------
# Fixture root: a temp dir we control as a mock CLAUDE_CONFIG_DIR
# -----------------------------------------------------------------------
TMPDIR_ROOT=$(mktemp -d -t vbw-resolver-test-XXXXXX)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

MKT="vbw-marketplace"
CACHE_BASE="$TMPDIR_ROOT/plugins/cache/$MKT/vbw"
PLUGINS_JSON="$TMPDIR_ROOT/plugins/installed_plugins.json"

echo ""
echo "=== Phase 66: vbw-source.sh resolver tests ==="
echo ""

# -----------------------------------------------------------------------
# T1 — CLAUDE_CONFIG_DIR override: resolver uses the env var, not defaults
# -----------------------------------------------------------------------
echo "--- T1: CLAUDE_CONFIG_DIR override ---"
# Build a minimal marketplace install in our temp dir
VERSION="1.99.0"
MKTPLACE_AGENTS="$CACHE_BASE/$VERSION/agents"
mkdir -p "$MKTPLACE_AGENTS"
touch "$MKTPLACE_AGENTS/vbw-dev.md"

mkdir -p "$TMPDIR_ROOT/plugins"
cat >"$PLUGINS_JSON" <<JSON
{
  "version": 2,
  "plugins": {
    "vbw@vbw-marketplace": [
      {
        "installPath": "$CACHE_BASE/$VERSION",
        "version": "$VERSION",
        "scope": "user"
      }
    ]
  },
  "enabledPlugins": {
    "vbw@vbw-marketplace": true
  }
}
JSON

_assert_resolves "T1: CLAUDE_CONFIG_DIR override resolves marketplace" \
    "marketplace" "/agents" \
    "CLAUDE_CONFIG_DIR=$TMPDIR_ROOT"

# -----------------------------------------------------------------------
# T2 — Marketplace path: versioned install path is used, version exported
# -----------------------------------------------------------------------
echo "--- T2: Marketplace path ---"
_assert_resolves "T2: VBW_SOURCE_TYPE=marketplace" \
    "marketplace" "/$VERSION/agents" \
    "CLAUDE_CONFIG_DIR=$TMPDIR_ROOT"

# Verify version is exported correctly
actual_version=$(env CLAUDE_CONFIG_DIR="$TMPDIR_ROOT" bash -c "
    source '$LIB' 2>/dev/null
    resolve_vbw_source 2>/dev/null
    echo \"\$VBW_VERSION\"
" 2>/dev/null)
if [ "$actual_version" = "$VERSION" ]; then
    _pass "T2: VBW_VERSION=$VERSION exported"
else
    _fail "T2: VBW_VERSION exported" "expected '$VERSION', got '$actual_version'"
fi

# -----------------------------------------------------------------------
# T3 — Local symlink: symlink at .../vbw/local → dev worktree
# -----------------------------------------------------------------------
echo "--- T3: Local symlink ---"
# Create a fake worktree with agents/
FAKE_WORKTREE="$TMPDIR_ROOT/fake-worktree"
mkdir -p "$FAKE_WORKTREE/agents"
touch "$FAKE_WORKTREE/agents/vbw-dev.md"

LOCAL_LINK="$CACHE_BASE/local"
# Remove any prior link, then create symlink
rm -f "$LOCAL_LINK"
ln -s "$FAKE_WORKTREE" "$LOCAL_LINK"

_assert_resolves "T3: VBW_SOURCE_TYPE=local-symlink" \
    "local-symlink" "/fake-worktree/agents" \
    "CLAUDE_CONFIG_DIR=$TMPDIR_ROOT"

# VBW_VERSION should be "local"
actual_lver=$(env CLAUDE_CONFIG_DIR="$TMPDIR_ROOT" bash -c "
    source '$LIB' 2>/dev/null
    resolve_vbw_source 2>/dev/null
    echo \"\$VBW_VERSION\"
" 2>/dev/null)
if [ "$actual_lver" = "local" ]; then
    _pass "T3: VBW_VERSION=local for symlink"
else
    _fail "T3: VBW_VERSION=local for symlink" "got '$actual_lver'"
fi

# Remove symlink so T4/T5 get clean slate
rm -f "$LOCAL_LINK"
rm -rf "$MKTPLACE_AGENTS"
# Remove plugins.json so marketplace path is also gone
rm -f "$PLUGINS_JSON"

# -----------------------------------------------------------------------
# T4 — Dev checkout fallback: ~/Sources/vibe-better-with-claude-code-vbw/agents
# -----------------------------------------------------------------------
echo "--- T4: Dev checkout fallback ---"
FAKE_HOME="$TMPDIR_ROOT/fakehome"
mkdir -p "$FAKE_HOME/Sources/vibe-better-with-claude-code-vbw/agents"
touch "$FAKE_HOME/Sources/vibe-better-with-claude-code-vbw/agents/vbw-dev.md"

# Point to an empty config dir so marketplace/local paths don't resolve
EMPTY_CONFIG="$TMPDIR_ROOT/empty-config"
mkdir -p "$EMPTY_CONFIG"

actual_type=$(env CLAUDE_CONFIG_DIR="$EMPTY_CONFIG" HOME="$FAKE_HOME" bash -c "
    source '$LIB' 2>/dev/null
    resolve_vbw_source 2>/dev/null
    echo \"\$VBW_SOURCE_TYPE\"
" 2>/dev/null)
if [ "$actual_type" = "dev-checkout" ]; then
    _pass "T4: VBW_SOURCE_TYPE=dev-checkout"
else
    _fail "T4: VBW_SOURCE_TYPE=dev-checkout" "got '$actual_type'"
fi

actual_dir=$(env CLAUDE_CONFIG_DIR="$EMPTY_CONFIG" HOME="$FAKE_HOME" bash -c "
    source '$LIB' 2>/dev/null
    resolve_vbw_source 2>/dev/null
    echo \"\$VBW_AGENTS_DIR\"
" 2>/dev/null)
case "$actual_dir" in
    *"vibe-better-with-claude-code-vbw/agents"*)
        _pass "T4: VBW_AGENTS_DIR points into dev checkout" ;;
    *)
        _fail "T4: VBW_AGENTS_DIR points into dev checkout" "got '$actual_dir'" ;;
esac

# -----------------------------------------------------------------------
# T5 — Absent: no entries anywhere; resolve_vbw_source returns 1
# -----------------------------------------------------------------------
echo "--- T5: Absent ---"
ABSENT_HOME="$TMPDIR_ROOT/absenthome"
mkdir -p "$ABSENT_HOME"
ABSENT_CONFIG="$TMPDIR_ROOT/absent-config"
mkdir -p "$ABSENT_CONFIG"

_assert_absent "T5: resolve_vbw_source returns 1 when absent" \
    CLAUDE_CONFIG_DIR="$ABSENT_CONFIG" HOME="$ABSENT_HOME"

absent_type=$(env CLAUDE_CONFIG_DIR="$ABSENT_CONFIG" HOME="$ABSENT_HOME" bash -c "
    source '$LIB' 2>/dev/null
    resolve_vbw_source 2>/dev/null || true
    echo \"\$VBW_SOURCE_TYPE\"
" 2>/dev/null)
if [ "$absent_type" = "absent" ]; then
    _pass "T5: VBW_SOURCE_TYPE=absent when not found"
else
    _fail "T5: VBW_SOURCE_TYPE=absent when not found" "got '$absent_type'"
fi

# -----------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
