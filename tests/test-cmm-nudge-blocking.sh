#!/bin/bash
# test-cmm-nudge-blocking.sh — Tests for cmm-nudge.sh hard-blocking Read gate
# Usage: bash tests/test-cmm-nudge-blocking.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/global/cmm-nudge.sh"

PASS=0; FAIL=0
# _assert_exit LABEL EXPECTED_EXIT JSON [ENV_PREFIX]
# ENV_PREFIX is optional; if set, it is prepended to the bash invocation
# (e.g. "CLAUDE_CONFIG_DIR=/tmp/fake" to override global settings lookup)
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
mkdir -p "$PROJ"
git -C "$PROJ" init -q
echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"}}}' > "$PROJ/.mcp.json"

# Large code file (>50 lines) — will be blocked
for i in $(seq 1 60); do echo "line $i"; done > "$PROJ/big.py"

# Large .ts file (>50 lines) — will be blocked
for i in $(seq 1 60); do echo "// line $i"; done > "$PROJ/big.ts"

# Small code file (<50 lines) — will be allowed
echo 'print("hello")' > "$PROJ/small.py"

# Config file — should never be blocked
echo '{}' > "$PROJ/config.json"

# Markdown file — should never be blocked
echo '# Some doc' > "$PROJ/some-doc.md"

# CLAUDE.md — basename exempt
echo '# CLAUDE.md' > "$PROJ/CLAUDE.md"

# Planning path fixture
mkdir -p "$PROJ/.vbw-planning/phases/01"
for i in $(seq 1 60); do echo "plan line $i"; done > "$PROJ/.vbw-planning/phases/01/big-plan.py"

# .claude path fixture
mkdir -p "$PROJ/.claude/hooks"
for i in $(seq 1 60); do echo "hook line $i"; done > "$PROJ/.claude/hooks/some-hook.sh"

# Second project: CMM NOT in .mcp.json
PROJ_NO_CMM="$TMPDIR_ROOT/proj-no-cmm"
mkdir -p "$PROJ_NO_CMM"
git -C "$PROJ_NO_CMM" init -q
echo '{"mcpServers":{"some-other-mcp":{"command":"npx"}}}' > "$PROJ_NO_CMM/.mcp.json"
for i in $(seq 1 60); do echo "line $i"; done > "$PROJ_NO_CMM/big.py"

# Third project: No .mcp.json at all
PROJ_NO_MCP="$TMPDIR_ROOT/proj-no-mcp"
mkdir -p "$PROJ_NO_MCP"
git -C "$PROJ_NO_MCP" init -q
for i in $(seq 1 60); do echo "line $i"; done > "$PROJ_NO_MCP/big.py"

# Fake CLAUDE_CONFIG_DIR without CMM — used by tests 9+10 to suppress global fallback
FAKE_CONFIG="$TMPDIR_ROOT/fake-claude-config"
mkdir -p "$FAKE_CONFIG"
echo '{"hooks":{}}' > "$FAKE_CONFIG/settings.json"

# --- Tests ---

echo "--- Test 1: Large .py file blocked (exit 2) ---"
_assert_exit "Test 1: large .py blocked" 2 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\"}}"

echo "--- Test 2: Large .ts file blocked (exit 2) ---"
_assert_exit "Test 2: large .ts blocked" 2 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.ts\"}}"

echo "--- Test 3: Small .py file allowed (exit 0) ---"
_assert_exit "Test 3: small .py allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/small.py\"}}"

echo "--- Test 4: Config file (.json) allowed (exit 0) ---"
_assert_exit "Test 4: config .json allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/config.json\"}}"

echo "--- Test 5: Markdown file (.md) allowed (exit 0) ---"
_assert_exit "Test 5: markdown .md allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/some-doc.md\"}}"

echo "--- Test 6: CLAUDE.md basename exempt (exit 0) ---"
_assert_exit "Test 6: CLAUDE.md exempt" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/CLAUDE.md\"}}"

echo "--- Test 7: Planning path exempt (exit 0) ---"
_assert_exit "Test 7: .vbw-planning path exempt" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/.vbw-planning/phases/01/big-plan.py\"}}"

echo "--- Test 8: .claude/ path exempt (exit 0) ---"
_assert_exit "Test 8: .claude path exempt" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/.claude/hooks/some-hook.sh\"}}"

echo "--- Test 9: CMM not in .mcp.json -> allowed (exit 0) ---"
_assert_exit "Test 9: no CMM in .mcp.json allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ_NO_CMM/big.py\"}}" \
    "CLAUDE_CONFIG_DIR=$FAKE_CONFIG"

echo "--- Test 10: No .mcp.json at all -> allowed (exit 0) ---"
_assert_exit "Test 10: no .mcp.json allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ_NO_MCP/big.py\"}}" \
    "CLAUDE_CONFIG_DIR=$FAKE_CONFIG"

echo "--- Test 11: Top-level file_path fallback (exit 2) ---"
_assert_exit "Test 11: top-level file_path blocked" 2 \
    "{\"file_path\":\"$PROJ/big.py\"}"

# --- Phase 47 Finding B: targeted-Read exemption requires fresh cmm-recent sentinel ---
# Compute the project hash using the same algorithm as cmm-nudge.sh (git-toplevel path
# via md5 -q || md5sum). Must resolve realpath because git rev-parse returns the
# canonical path which may differ from the symlinked TMPDIR path on macOS.
_hash_of() {
    echo "$1" | md5 -q 2>/dev/null || echo "$1" | md5sum 2>/dev/null | awk '{print $1}'
}
PROJ_REAL=$(git -C "$PROJ" rev-parse --show-toplevel)
PROJ_HASH=$(_hash_of "$PROJ_REAL")
PROJ_SENTINEL="/tmp/cmm-recent-${PROJ_HASH}"

# Portable helper: set mtime to ~90s in the past (stale for the 60s TTL)
_touch_stale() {
    local target="$1"
    touch "$target"
    # macOS: touch -t CCYYMMDDhhmm accepts an absolute timestamp; use date -v.
    # Linux: touch -d "NN seconds ago" works directly.
    touch -t "$(date -v-2M +%Y%m%d%H%M 2>/dev/null)" "$target" 2>/dev/null \
        || touch -d "2 minutes ago" "$target" 2>/dev/null
}

echo "--- Test 12: Targeted Read with offset+limit + fresh sentinel -> allowed (exit 0) ---"
touch "$PROJ_SENTINEL"
_assert_exit "Test 12: offset+limit allowed (fresh sentinel)" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":100,\"limit\":20}}"

echo "--- Test 13: Non-existent file -> allowed (exit 0) ---"
_assert_exit "Test 13: non-existent file allowed" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/does-not-exist.py\"}}"

echo "--- Test 14: Large offset+limit (>100 lines) -> blocked (exit 2) ---"
_assert_exit "Test 14: large limit still blocked" 2 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":0,\"limit\":500}}"

echo "--- Test 15: Offset only (no limit) -> blocked (exit 2) ---"
_assert_exit "Test 15: offset-only still blocked" 2 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":10}}"

echo "--- Test 16: Limit only (no offset) -> blocked (exit 2) ---"
_assert_exit "Test 16: limit-only still blocked" 2 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"limit\":20}}"

# --- Phase 47 Finding B: cmm-recent sentinel gating on targeted-Read ---

echo "--- Test 17: offset+limit with fresh sentinel -> allowed (exit 0) ---"
touch "$PROJ_SENTINEL"
_assert_exit "Test 17: offset+limit fresh sentinel" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":10,\"limit\":50}}"

echo "--- Test 18: offset+limit with NO sentinel -> blocked (exit 2) ---"
rm -f "$PROJ_SENTINEL"
_assert_exit "Test 18: offset+limit no sentinel blocks" 2 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":10,\"limit\":50}}"

echo "--- Test 19: offset+limit with STALE sentinel -> blocked (exit 2) ---"
_touch_stale "$PROJ_SENTINEL"
_assert_exit "Test 19: offset+limit stale sentinel blocks" 2 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py\",\"offset\":10,\"limit\":50}}"

echo "--- Test 20: '# cmm-exempt' marker bypasses sentinel check (exit 0) ---"
rm -f "$PROJ_SENTINEL"
_assert_exit "Test 20: cmm-exempt marker bypasses sentinel" 0 \
    "{\"tool_input\":{\"file_path\":\"$PROJ/big.py # cmm-exempt\",\"offset\":10,\"limit\":50}}"

# --- Submodule sentinel-hash agreement (regression for cmm-nudge/track-cmm-calls drift) ---
# Bug: when FILE_PATH lived inside a git submodule, cmm-nudge.sh hashed the SUBMODULE
# root via `git rev-parse --show-toplevel`, but track-cmm-calls.sh (via lib/project-root.sh)
# walked the superproject chain and hashed the OUTERMOST root. The two hooks named
# different /tmp/cmm-recent-* sentinels, so the offset+limit<=100 exemption never fired
# inside submodules. Fix: cmm-nudge.sh now also walks the superproject chain. This test
# pins that contract by touching ONLY the superproject-hash sentinel and asserting that
# a Read inside the submodule passes the freshness gate.
echo "--- Test 21: submodule Read uses superproject hash (exit 0) ---"
SUPER="$TMPDIR_ROOT/super"
SUB_DIR="$SUPER/sub"
mkdir -p "$SUPER"
git -C "$SUPER" init -q
echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"}}}' > "$SUPER/.mcp.json"
# Build a real submodule (file:// URL ensures git accepts it without a remote).
SUB_SRC="$TMPDIR_ROOT/sub-src"
mkdir -p "$SUB_SRC"
git -C "$SUB_SRC" init -q
for i in $(seq 1 60); do echo "sub line $i"; done > "$SUB_SRC/sub-big.py"
git -C "$SUB_SRC" add . >/dev/null 2>&1
git -C "$SUB_SRC" -c user.email=t@t -c user.name=t commit -qm init
git -C "$SUPER" -c protocol.file.allow=always submodule add -q "$SUB_SRC" sub 2>/dev/null
git -C "$SUPER" -c user.email=t@t -c user.name=t commit -qm super-init 2>/dev/null
SUPER_REAL=$(git -C "$SUPER" rev-parse --show-toplevel)
SUPER_HASH=$(_hash_of "$SUPER_REAL")
SUPER_SENTINEL="/tmp/cmm-recent-${SUPER_HASH}"
SUB_REAL=$(git -C "$SUB_DIR" rev-parse --show-toplevel)
SUB_HASH=$(_hash_of "$SUB_REAL")
SUB_SENTINEL="/tmp/cmm-recent-${SUB_HASH}"
# Touch ONLY the superproject sentinel; explicitly remove the submodule one.
touch "$SUPER_SENTINEL"
rm -f "$SUB_SENTINEL"
_assert_exit "Test 21: submodule Read honors superproject sentinel" 0 \
    "{\"tool_input\":{\"file_path\":\"$SUB_DIR/sub-big.py\",\"offset\":1,\"limit\":50}}"
# Cleanup the test sentinels we wrote.
rm -f "$SUPER_SENTINEL" "$SUB_SENTINEL"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
