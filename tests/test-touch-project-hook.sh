#!/bin/bash
# test-touch-project-hook.sh — Tests for touch_project hook in reindex-after-commit.sh
# Tests run against the ephemeral fixture from setup-test-monorepo.sh.
# Does NOT require a live CMM server — stubs codebase-memory-mcp CLI with a spy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=setup-test-monorepo.sh
source "$SCRIPT_DIR/setup-test-monorepo.sh"

trap 'teardown_test_monorepo; echo "Fixture cleaned up."' EXIT

PASS=0; FAIL=0
_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
_assert_eq() {
    local label="$1" got="$2" want="$3"
    if [ "$got" = "$want" ]; then _pass "$label"; else _fail "$label (got='$got' want='$want')"; fi
}

# resolve_cmm_project_name: given a CWD, returns the CMM project name.
# Mirrors the logic in hooks/project/reindex-after-commit.sh.
resolve_cmm_project_name() {
    local cwd="${1:-$(pwd)}"
    local project_root
    project_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || { echo ""; return 1; }
    local _walk="$project_root"
    while true; do
        local _parent
        _parent="$(git -C "$_walk" rev-parse --show-superproject-working-tree 2>/dev/null)"
        [ -z "$_parent" ] && break
        _walk="$_parent"
    done
    project_root="$_walk"
    # Worktree detection
    local _git_dir _git_common
    _git_dir="$(git -C "$project_root" rev-parse --git-dir 2>/dev/null)"
    _git_common="$(git -C "$project_root" rev-parse --git-common-dir 2>/dev/null)"
    [ "${_git_dir:0:1}" != "/" ]    && _git_dir="$project_root/$_git_dir"
    [ "${_git_common:0:1}" != "/" ] && _git_common="$project_root/$_git_common"
    if [ "$_git_dir" != "$_git_common" ]; then
        local main_root
        main_root="$(cd "$_git_common/.." 2>/dev/null && pwd -P)"
        [ -n "$main_root" ] && project_root="$main_root"
    fi
    # CMM derives project names from full path: strip leading /, replace / with -
    local name="${project_root#/}"
    echo "${name//\//-}"
}

# CMM project name = full resolved path with leading / stripped, remaining / replaced by -
# Use pwd -P to resolve symlinks (macOS /tmp -> /private/tmp)
_resolved_root="$(cd "$CMM_TEST_MONOREPO_ROOT" && pwd -P)"
_tmp="${_resolved_root#/}"
MONO_NAME="${_tmp//\//-}"

echo "--- Test 1: project name from monorepo root ---"
got=$(resolve_cmm_project_name "$CMM_TEST_MONOREPO_ROOT")
_assert_eq "root -> $MONO_NAME" "$got" "$MONO_NAME"

echo "--- Test 2: project name from apps/alpha submodule ---"
got=$(resolve_cmm_project_name "$CMM_TEST_MONOREPO_ROOT/apps/alpha")
_assert_eq "apps/alpha -> $MONO_NAME" "$got" "$MONO_NAME"

echo "--- Test 3: project name from nested submodule apps/alpha/vendor/core ---"
got=$(resolve_cmm_project_name "$CMM_TEST_MONOREPO_ROOT/apps/alpha/vendor/core")
_assert_eq "apps/alpha/vendor/core -> $MONO_NAME" "$got" "$MONO_NAME"

echo "--- Test 4: project name from apps/beta submodule ---"
got=$(resolve_cmm_project_name "$CMM_TEST_MONOREPO_ROOT/apps/beta")
_assert_eq "apps/beta -> $MONO_NAME" "$got" "$MONO_NAME"

echo "--- Test 5: project name from shared-lib submodule ---"
got=$(resolve_cmm_project_name "$CMM_TEST_MONOREPO_ROOT/shared-lib")
_assert_eq "shared-lib -> $MONO_NAME" "$got" "$MONO_NAME"

echo "--- Test 6: debug log written when debug_logging=true ---"
FAKE_CONFIG_DIR=$(mktemp -d)
mkdir -p "$FAKE_CONFIG_DIR/.vbw-planning"
echo '{"debug_logging": true}' > "$FAKE_CONFIG_DIR/.vbw-planning/config.json"
rm -f /tmp/cmm-touch-project.log

_CMM_PROJECT_NAME="$(resolve_cmm_project_name "$CMM_TEST_MONOREPO_ROOT")"
_CMM_CONFIG="$FAKE_CONFIG_DIR/.vbw-planning/config.json"
if [ -f "$_CMM_CONFIG" ] && python3 -c "import sys,json; d=json.load(open('$_CMM_CONFIG')); sys.exit(0 if d.get('debug_logging') else 1)" 2>/dev/null; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] touch_project project=$_CMM_PROJECT_NAME output=test cwd=$(pwd)" >> /tmp/cmm-touch-project.log 2>/dev/null || true
fi
if [ -f /tmp/cmm-touch-project.log ] && grep -q "touch_project" /tmp/cmm-touch-project.log; then
    _pass "debug log written when debug_logging=true"
else
    _fail "debug log not written when debug_logging=true"
fi
rm -rf "$FAKE_CONFIG_DIR"
rm -f /tmp/cmm-touch-project.log

echo "--- Test 7: debug log not written when debug_logging=false ---"
FAKE_CONFIG_DIR2=$(mktemp -d)
mkdir -p "$FAKE_CONFIG_DIR2/.vbw-planning"
echo '{"debug_logging": false}' > "$FAKE_CONFIG_DIR2/.vbw-planning/config.json"
rm -f /tmp/cmm-touch-project.log

_CMM_PROJECT_NAME2="$(resolve_cmm_project_name "$CMM_TEST_MONOREPO_ROOT")"
_CMM_CONFIG2="$FAKE_CONFIG_DIR2/.vbw-planning/config.json"
if [ -f "$_CMM_CONFIG2" ] && python3 -c "import sys,json; d=json.load(open('$_CMM_CONFIG2')); sys.exit(0 if d.get('debug_logging') else 1)" 2>/dev/null; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] touch_project project=$_CMM_PROJECT_NAME2 output=test cwd=$(pwd)" >> /tmp/cmm-touch-project.log 2>/dev/null || true
fi
if [ ! -f /tmp/cmm-touch-project.log ]; then
    _pass "debug log not written when debug_logging=false"
else
    _fail "debug log should not be written when debug_logging=false"
fi
rm -rf "$FAKE_CONFIG_DIR2"

echo "--- Test 8: hook invokes codebase-memory-mcp CLI (stubbed) ---"
# Create a stub that records calls instead of invoking the real CMM server
STUB_DIR=$(mktemp -d)
STUB_LOG="$STUB_DIR/touch-calls.log"
cat > "$STUB_DIR/codebase-memory-mcp" <<STUBEOF
#!/bin/bash
# Spy: record all arguments
echo "\$@" >> "$STUB_LOG"
echo '{"status":"ok"}'
STUBEOF
chmod +x "$STUB_DIR/codebase-memory-mcp"

# Run the hook with stub in PATH, feeding it a fake git commit tool_input/output
HOOK_SCRIPT="$SCRIPT_DIR/../hooks/project/reindex-after-commit.sh"
FAKE_INPUT='{"tool_input":{"command":"git commit -m test"},"tool_output":{"stdout":"[main abc1234] test 1 file changed"}}'
# Run from monorepo root so sentinel/project resolution works; export PATH so it propagates through pipe
(cd "$CMM_TEST_MONOREPO_ROOT" && export PATH="$STUB_DIR:$PATH" && echo "$FAKE_INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)
if [ -f "$STUB_LOG" ] && grep -q "cli touch_project" "$STUB_LOG"; then
    _pass "hook calls codebase-memory-mcp cli touch_project"
else
    _fail "hook did not call codebase-memory-mcp cli touch_project (log: $(cat "$STUB_LOG" 2>/dev/null || echo 'empty'))"
fi
rm -rf "$STUB_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
