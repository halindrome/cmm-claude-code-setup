#!/bin/bash
# test-phase-59-cmm-install-scope.sh — CMM global-scope detection regression coverage.
#
# Phase 59 fixed a bug where setup.sh --project unconditionally wrote
# codebase-memory-mcp into the project .mcp.json even when CMM was already
# registered globally in ${CLAUDE_CONFIG_DIR:-~/.config/claude-code}/settings.json.
#
# The fix introduces detect_cmm_install_scope() which probes global settings.json
# and project .mcp.json and sets INSTALL_CMM_LOCAL (true/false) and CMM_INSTALL_SCOPE
# (local/global/both). The python MCP merge block in install_project() is then gated
# on INSTALL_CMM_LOCAL via sys.argv[3].
#
# What this test asserts (5 cases):
#
#   Case 1 — Global CMM present, --project install (primary regression fix):
#            Scratch CLAUDE_CONFIG_DIR with codebase-memory-mcp in mcpServers causes
#            setup.sh --project to skip local .mcp.json registration. Assert
#            .mcp.json does not contain codebase-memory-mcp after install and stdout
#            contains "[skip] codebase-memory-mcp already registered globally".
#
#   Case 2 — No global CMM, --project install (preserve existing behavior):
#            Scratch settings.json with no CMM entry causes setup.sh --project to write
#            codebase-memory-mcp into .mcp.json. Assert .mcp.json contains
#            codebase-memory-mcp and stdout contains "[ok] Registered codebase-memory-mcp".
#
#   Case 3 — --force-local-cmm with global CMM present:
#            Same global fixture as Case 1 but with --force-local-cmm. Assert CMM IS
#            written to .mcp.json (flag overrides skip) and stdout contains
#            "--force-local-cmm".
#
#   Case 4 — Dry-run with global CMM present:
#            Same global fixture as Case 1 with --dry-run. Assert stdout contains
#            "Would skip CMM" and does NOT contain "Would merge CMM". Assert no
#            .mcp.json is created.
#
#   Case 5 — Extract-and-source unit test for detect_cmm_install_scope():
#            Extract detect_cmm_install_scope() from setup.sh via awk and source it
#            in a scratch shell with synthetic fixtures. Assert INSTALL_CMM_LOCAL=false
#            and CMM_INSTALL_SCOPE=global for the global-present branch; assert
#            INSTALL_CMM_LOCAL=true and CMM_INSTALL_SCOPE=local for the absent branch.
#
# Usage: bash tests/test-phase-59-cmm-install-scope.sh
# Exit: 0 = all pass, 1 = any failure
#
# Notes:
# - Each case uses its own scratch directory under a single $SCRATCH temp dir.
# - Cleanup on EXIT trap removes all scratch state.
# - Real ~/.config/claude-code and real project .mcp.json are never touched.
# - A dummy codebase-memory-mcp stub is put on PATH to satisfy detect_cmm_binary()
#   without triggering the interactive abort prompt.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SETUP="$REPO_ROOT/setup.sh"

PASS=0
FAIL=0
FAILED_CASES=()

_pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}

_fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$1")
}

# Single scratch dir shared across all cases; cleaned up on EXIT.
SCRATCH=$(mktemp -d -t cmm-phase59-install-scope-XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

# Create a fake codebase-memory-mcp stub binary so detect_cmm_binary() succeeds
# without prompting. All integration cases (1, 2, 3, 4) run with this on PATH.
STUB_BIN="$SCRATCH/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/codebase-memory-mcp" <<'STUB'
#!/bin/bash
echo "stub codebase-memory-mcp"
STUB
chmod +x "$STUB_BIN/codebase-memory-mcp"
export PATH="$STUB_BIN:$PATH"

# Helper: create a scratch CLAUDE_CONFIG_DIR with a settings.json that has
# codebase-memory-mcp in mcpServers.
_make_global_cmm_fixture() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/settings.json" <<'JSON'
{
  "mcpServers": {
    "codebase-memory-mcp": {
      "command": "codebase-memory-mcp",
      "args": [],
      "type": "stdio"
    }
  }
}
JSON
}

# Helper: create a scratch CLAUDE_CONFIG_DIR with settings.json that has NO CMM.
_make_empty_global_fixture() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/settings.json" <<'JSON'
{
  "mcpServers": {}
}
JSON
}

# Helper: create a minimal scratch git project.
_make_project() {
    local dir="$1"
    mkdir -p "$dir"
    (cd "$dir" && git init -q && git commit --allow-empty -q -m init)
}

# --- Case 1: Global CMM present — skip local registration ---------------------
CASE="case 1 - global CMM present: skip local .mcp.json registration"

C1_DIR="$SCRATCH/case1"
C1_CONF="$SCRATCH/case1-conf"
_make_project "$C1_DIR"
_make_global_cmm_fixture "$C1_CONF"

(
    cd "$C1_DIR"
    CLAUDE_CONFIG_DIR="$C1_CONF" bash "$SETUP" --project --yes --skip-context-mode 2>&1
) > "$SCRATCH/c1.out" 2>&1 || true

# Assert: stdout contains the global-skip message
if grep -q "already registered globally" "$SCRATCH/c1.out"; then
    _pass "$CASE - stdout contains '[skip] already registered globally'"
else
    _fail "$CASE - stdout missing '[skip] already registered globally' (got: $(tail -20 "$SCRATCH/c1.out"))"
fi

# Assert: .mcp.json does not contain codebase-memory-mcp
if [ ! -f "$C1_DIR/.mcp.json" ] || ! grep -q "codebase-memory-mcp" "$C1_DIR/.mcp.json" 2>/dev/null; then
    _pass "$CASE - .mcp.json does not contain codebase-memory-mcp after global-skip"
else
    _fail "$CASE - .mcp.json still contains codebase-memory-mcp despite global registration"
fi

# --- Case 2: No global CMM — preserve existing behavior (local write) ---------
CASE="case 2 - no global CMM: write codebase-memory-mcp to .mcp.json"

C2_DIR="$SCRATCH/case2"
C2_CONF="$SCRATCH/case2-conf"
_make_project "$C2_DIR"
_make_empty_global_fixture "$C2_CONF"

(
    cd "$C2_DIR"
    CLAUDE_CONFIG_DIR="$C2_CONF" bash "$SETUP" --project --yes --skip-context-mode 2>&1
) > "$SCRATCH/c2.out" 2>&1 || true

# Assert: stdout contains the registered-ok message
if grep -q "Registered codebase-memory-mcp" "$SCRATCH/c2.out"; then
    _pass "$CASE - stdout contains '[ok] Registered codebase-memory-mcp'"
else
    _fail "$CASE - stdout missing '[ok] Registered codebase-memory-mcp' (got: $(tail -20 "$SCRATCH/c2.out"))"
fi

# Assert: .mcp.json contains codebase-memory-mcp
if [ -f "$C2_DIR/.mcp.json" ] && grep -q "codebase-memory-mcp" "$C2_DIR/.mcp.json" 2>/dev/null; then
    _pass "$CASE - .mcp.json contains codebase-memory-mcp after no-global install"
else
    _fail "$CASE - .mcp.json missing codebase-memory-mcp when global is absent"
fi

# --- Case 3: --force-local-cmm with global CMM present ----------------------
CASE="case 3 - --force-local-cmm overrides global skip"

C3_DIR="$SCRATCH/case3"
C3_CONF="$SCRATCH/case3-conf"
_make_project "$C3_DIR"
_make_global_cmm_fixture "$C3_CONF"

(
    cd "$C3_DIR"
    CLAUDE_CONFIG_DIR="$C3_CONF" bash "$SETUP" --project --yes --skip-context-mode --force-local-cmm 2>&1
) > "$SCRATCH/c3.out" 2>&1 || true

# Assert: stdout contains the --force-local-cmm info message
if grep -q "force-local-cmm" "$SCRATCH/c3.out"; then
    _pass "$CASE - stdout contains '--force-local-cmm' info message"
else
    _fail "$CASE - stdout missing '--force-local-cmm' message (got: $(tail -20 "$SCRATCH/c3.out"))"
fi

# Assert: CMM IS written to .mcp.json (flag overrides skip)
if [ -f "$C3_DIR/.mcp.json" ] && grep -q "codebase-memory-mcp" "$C3_DIR/.mcp.json" 2>/dev/null; then
    _pass "$CASE - .mcp.json contains codebase-memory-mcp when --force-local-cmm used"
else
    _fail "$CASE - .mcp.json missing codebase-memory-mcp despite --force-local-cmm"
fi

# --- Case 4: Dry-run with global CMM present ---------------------------------
CASE="case 4 - dry-run with global CMM: 'Would skip CMM' not 'Would merge CMM'"

C4_DIR="$SCRATCH/case4"
C4_CONF="$SCRATCH/case4-conf"
_make_project "$C4_DIR"
_make_global_cmm_fixture "$C4_CONF"

(
    cd "$C4_DIR"
    CLAUDE_CONFIG_DIR="$C4_CONF" bash "$SETUP" --project --dry-run --skip-context-mode 2>&1
) > "$SCRATCH/c4.out" 2>&1 || true

# Assert: stdout contains "Would skip CMM"
if grep -q "Would skip CMM" "$SCRATCH/c4.out"; then
    _pass "$CASE - stdout contains 'Would skip CMM'"
else
    _fail "$CASE - stdout missing 'Would skip CMM' (got: $(tail -20 "$SCRATCH/c4.out"))"
fi

# Assert: stdout does NOT contain "Would merge CMM"
if ! grep -q "Would merge CMM" "$SCRATCH/c4.out"; then
    _pass "$CASE - stdout does not contain 'Would merge CMM'"
else
    _fail "$CASE - stdout erroneously contains 'Would merge CMM'"
fi

# Assert: no .mcp.json created in dry-run
if [ ! -f "$C4_DIR/.mcp.json" ]; then
    _pass "$CASE - no .mcp.json created during dry-run"
else
    _fail "$CASE - .mcp.json was created during --dry-run (should not write files)"
fi

# --- Case 5: Extract-and-source unit test for detect_cmm_install_scope() ----
CASE="case 5 - extract detect_cmm_install_scope() and assert GLOBAL branch"

C5_DIR="$SCRATCH/case5"
mkdir -p "$C5_DIR"

# Extract detect_cmm_install_scope() from setup.sh via awk.
# Pattern: from the line starting the function to the first standalone `}`.
awk '/^detect_cmm_install_scope\(\)/,/^}$/' "$SETUP" > "$SCRATCH/detect-scope.sh"

if [ ! -s "$SCRATCH/detect-scope.sh" ]; then
    _fail "$CASE - could not extract detect_cmm_install_scope from $SETUP"
else
    # Sub-case A: global settings.json HAS codebase-memory-mcp → GLOBAL branch.
    FIXTURE_GLOBAL="$SCRATCH/c5-global-conf"
    _make_global_cmm_fixture "$FIXTURE_GLOBAL"

    C5_PROJ_A="$C5_DIR/proj-a"
    mkdir -p "$C5_PROJ_A"

    (
        cd "$C5_PROJ_A"
        # Provide stub helpers and variables the function expects.
        FORCE_LOCAL_CMM=false
        SKIP_MCP_CHECK=false
        CMM_INSTALL_SCOPE="local"
        INSTALL_CMM_LOCAL=true
        detect_config_dir() { echo "$FIXTURE_GLOBAL"; }
        # shellcheck disable=SC1091
        . "$SCRATCH/detect-scope.sh"
        detect_cmm_install_scope >/dev/null 2>&1
        echo "INSTALL_CMM_LOCAL=$INSTALL_CMM_LOCAL"
        echo "CMM_INSTALL_SCOPE=$CMM_INSTALL_SCOPE"
    ) > "$SCRATCH/c5a.out" 2>&1

    if grep -qx "INSTALL_CMM_LOCAL=false" "$SCRATCH/c5a.out"; then
        _pass "$CASE (global-present): INSTALL_CMM_LOCAL=false"
    else
        _fail "$CASE (global-present): INSTALL_CMM_LOCAL not false (got: $(cat "$SCRATCH/c5a.out"))"
    fi

    if grep -qx "CMM_INSTALL_SCOPE=global" "$SCRATCH/c5a.out"; then
        _pass "$CASE (global-present): CMM_INSTALL_SCOPE=global"
    else
        _fail "$CASE (global-present): CMM_INSTALL_SCOPE not 'global' (got: $(cat "$SCRATCH/c5a.out"))"
    fi

    # Sub-case B: global settings.json has NO codebase-memory-mcp → NONE branch.
    FIXTURE_EMPTY="$SCRATCH/c5-empty-conf"
    _make_empty_global_fixture "$FIXTURE_EMPTY"

    C5_PROJ_B="$C5_DIR/proj-b"
    mkdir -p "$C5_PROJ_B"

    (
        cd "$C5_PROJ_B"
        FORCE_LOCAL_CMM=false
        SKIP_MCP_CHECK=false
        CMM_INSTALL_SCOPE="local"
        INSTALL_CMM_LOCAL=true
        detect_config_dir() { echo "$FIXTURE_EMPTY"; }
        # shellcheck disable=SC1091
        . "$SCRATCH/detect-scope.sh"
        detect_cmm_install_scope >/dev/null 2>&1
        echo "INSTALL_CMM_LOCAL=$INSTALL_CMM_LOCAL"
        echo "CMM_INSTALL_SCOPE=$CMM_INSTALL_SCOPE"
    ) > "$SCRATCH/c5b.out" 2>&1

    if grep -qx "INSTALL_CMM_LOCAL=true" "$SCRATCH/c5b.out"; then
        _pass "$CASE (global-absent): INSTALL_CMM_LOCAL=true"
    else
        _fail "$CASE (global-absent): INSTALL_CMM_LOCAL not true (got: $(cat "$SCRATCH/c5b.out"))"
    fi

    if grep -qx "CMM_INSTALL_SCOPE=local" "$SCRATCH/c5b.out"; then
        _pass "$CASE (global-absent): CMM_INSTALL_SCOPE=local"
    else
        _fail "$CASE (global-absent): CMM_INSTALL_SCOPE not 'local' (got: $(cat "$SCRATCH/c5b.out"))"
    fi
fi

# --- Summary ------------------------------------------------------------------
echo ""
echo "============================================================"
echo "Summary: $PASS pass / $FAIL fail"
if [ "$FAIL" -gt 0 ]; then
    for f in "${FAILED_CASES[@]}"; do
        echo "  FAIL: $f"
    done
    echo "============================================================"
    exit 1
fi
echo "PASS: phase 59 CMM install-scope regression coverage"
echo "============================================================"
exit 0
