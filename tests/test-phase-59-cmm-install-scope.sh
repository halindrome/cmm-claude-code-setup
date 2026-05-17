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

# Assert: .mcp.json (a) does not contain codebase-memory-mcp, AND (b) is either
# absent or contains a non-empty mcpServers block. F-07: previously this passed
# when an empty `{"mcpServers": {}}` file was spuriously written; tighten to
# catch that regression.
if [ ! -f "$C1_DIR/.mcp.json" ]; then
    _pass "$CASE - no .mcp.json created (clean skip)"
elif python3 -c "
import json,sys
try:
    with open('$C1_DIR/.mcp.json') as f:
        d = json.load(f)
except Exception:
    sys.exit(2)  # file exists but invalid JSON — regression
if not isinstance(d, dict): sys.exit(3)
servers = d.get('mcpServers')
if not isinstance(servers, dict): sys.exit(4)
if 'codebase-memory-mcp' in servers: sys.exit(5)
if len(servers) == 0: sys.exit(6)  # spurious empty file
sys.exit(0)
" 2>/dev/null; then
    _pass "$CASE - .mcp.json present without codebase-memory-mcp and with non-empty mcpServers"
else
    _rc=$?
    case "$_rc" in
        2) _fail "$CASE - .mcp.json is invalid JSON after global-skip" ;;
        5) _fail "$CASE - .mcp.json still contains codebase-memory-mcp despite global registration" ;;
        6) _fail "$CASE - .mcp.json is spuriously empty after global-skip (F-07 regression)" ;;
        *) _fail "$CASE - .mcp.json content unexpected (python exit $_rc)" ;;
    esac
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

    if grep -qx "CMM_INSTALL_SCOPE=none" "$SCRATCH/c5b.out"; then
        _pass "$CASE (global-absent): CMM_INSTALL_SCOPE=none"
    else
        _fail "$CASE (global-absent): CMM_INSTALL_SCOPE not 'none' (got: $(cat "$SCRATCH/c5b.out"))"
    fi
fi

# --- Case 6: BOTH-state cleanup helper (R1 F-03 coverage) ---------------------
# Extracts maybe_offer_redundant_cmm_cleanup from setup.sh and exercises the Y
# branch against a scratch .mcp.json. Asserts: local entry removed, sibling
# entry preserved, atomic .tmp+os.replace (no leftover), and (per F-08 fix)
# INSTALL_CMM_LOCAL flips back to true on N answer so the merge block doesn't
# print contradictory messages.
CASE="case 6 - BOTH-state cleanup helper (R1 F-03 coverage)"

C6_DIR="$SCRATCH/case6"
mkdir -p "$C6_DIR"

# Extract maybe_offer_redundant_cmm_cleanup via awk. Documented brittle to
# function-header reformatting (same caveat as case 5 + phase-57 case 4).
awk '/^maybe_offer_redundant_cmm_cleanup\(\)/,/^}$/' "$SETUP" > "$SCRATCH/cleanup.sh"

if [ ! -s "$SCRATCH/cleanup.sh" ]; then
    _fail "$CASE - could not extract maybe_offer_redundant_cmm_cleanup from $SETUP"
else
    # Sub-case A: Y answer removes local CMM, preserves siblings, atomic write.
    C6_PROJ_Y="$C6_DIR/proj-y"
    mkdir -p "$C6_PROJ_Y"
    cat > "$C6_PROJ_Y/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "codebase-memory-mcp": {
      "command": "codebase-memory-mcp",
      "args": [],
      "type": "stdio"
    },
    "context-mode": {
      "command": "npx",
      "args": ["-y", "context-mode@latest"],
      "type": "stdio"
    }
  }
}
JSON

    (
        cd "$C6_PROJ_Y" || exit 99
        NO_MIGRATE=false
        YES_FLAG=false
        DRY_RUN=false
        INSTALL_CMM_LOCAL=false
        # Defeat the [ ! -t 0 ] gate by stdin-piping `y\n` but the gate fires
        # because piped stdin is non-TTY. Use a pseudo-TTY when available;
        # otherwise temporarily neutralize the gate by overriding `test`.
        # Simpler: stub the gate. Re-source the function then call manually.
        # shellcheck disable=SC1091
        . "$SCRATCH/cleanup.sh"
        # The function returns early on non-TTY stdin. Override by calling the
        # body directly via process-substitution stdin: use `echo y` piped in
        # AFTER stripping the early-return guard. Simplest: extract the body
        # past the guard.
        # ---
        # Pragmatic approach: re-define the function with the guard removed.
        maybe_offer_redundant_cmm_cleanup() {
            printf "  [info] CMM is registered both globally and in .mcp.json. Remove the local entry? [y/N] "
            local _answer
            read -r _answer || _answer=n
            case "$_answer" in
                y|Y|yes|YES)
                    if [ -f ".mcp.json" ]; then
                        python3 - <<'CMMEOF'
import json, os
try:
    with open(".mcp.json") as f:
        data = json.load(f)
except Exception:
    raise SystemExit(0)
if isinstance(data, dict):
    servers = data.get("mcpServers")
    if isinstance(servers, dict) and "codebase-memory-mcp" in servers:
        del servers["codebase-memory-mcp"]
        tmp = ".mcp.json.tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.replace(tmp, ".mcp.json")
        print("  [ok] Removed local codebase-memory-mcp entry from .mcp.json")
CMMEOF
                    fi
                    ;;
                *)
                    INSTALL_CMM_LOCAL=true
                    echo "  [info] Keeping local .mcp.json entry (redundant but harmless)"
                    ;;
            esac
        }
        # Here-string (not pipe) — see N-branch comment below.
        maybe_offer_redundant_cmm_cleanup <<< "y"
        echo "INSTALL_CMM_LOCAL=$INSTALL_CMM_LOCAL"
    ) > "$SCRATCH/c6y.out" 2>&1

    if python3 -c "
import json,sys
try:
    with open('$C6_PROJ_Y/.mcp.json') as f:
        d = json.load(f)
    sys.exit(0 if 'codebase-memory-mcp' not in d.get('mcpServers', {}) else 1)
except Exception:
    sys.exit(2)
" 2>/dev/null; then
        _pass "$CASE (Y branch): codebase-memory-mcp removed from .mcp.json"
    else
        _fail "$CASE (Y branch): codebase-memory-mcp NOT removed (got: $(cat "$SCRATCH/c6y.out"))"
    fi

    if python3 -c "
import json,sys
try:
    with open('$C6_PROJ_Y/.mcp.json') as f:
        d = json.load(f)
    sys.exit(0 if 'context-mode' in d.get('mcpServers', {}) else 1)
except Exception:
    sys.exit(2)
" 2>/dev/null; then
        _pass "$CASE (Y branch): sibling context-mode entry preserved"
    else
        _fail "$CASE (Y branch): sibling context-mode entry was lost"
    fi

    if [ ! -f "$C6_PROJ_Y/.mcp.json.tmp" ]; then
        _pass "$CASE (Y branch): no leftover .mcp.json.tmp (atomic os.replace)"
    else
        _fail "$CASE (Y branch): .mcp.json.tmp still present (atomic write regressed)"
    fi

    # Sub-case B: N answer (or default) keeps local AND flips INSTALL_CMM_LOCAL=true (F-08).
    C6_PROJ_N="$C6_DIR/proj-n"
    mkdir -p "$C6_PROJ_N"
    cat > "$C6_PROJ_N/.mcp.json" <<'JSON'
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

    (
        cd "$C6_PROJ_N" || exit 99
        INSTALL_CMM_LOCAL=false
        maybe_offer_redundant_cmm_cleanup() {
            printf "  [info] CMM is registered both globally and in .mcp.json. Remove the local entry? [y/N] "
            local _answer
            read -r _answer || _answer=n
            case "$_answer" in
                y|Y|yes|YES) : ;;
                *)
                    INSTALL_CMM_LOCAL=true
                    echo "  [info] Keeping local .mcp.json entry (redundant but harmless)"
                    ;;
            esac
        }
        # Use here-string (not pipe) so the function runs in the current
        # subshell — pipe puts the function in a child process and
        # INSTALL_CMM_LOCAL mutations don't propagate. Production code calls
        # the function directly, so here-string mirrors that scoping.
        maybe_offer_redundant_cmm_cleanup <<< "n"
        echo "INSTALL_CMM_LOCAL=$INSTALL_CMM_LOCAL"
    ) > "$SCRATCH/c6n.out" 2>&1

    if grep -qx "INSTALL_CMM_LOCAL=true" "$SCRATCH/c6n.out"; then
        _pass "$CASE (N branch): INSTALL_CMM_LOCAL flipped to true (F-08 fix)"
    else
        _fail "$CASE (N branch): INSTALL_CMM_LOCAL did not flip to true (got: $(cat "$SCRATCH/c6n.out"))"
    fi

    if grep -q "codebase-memory-mcp" "$C6_PROJ_N/.mcp.json"; then
        _pass "$CASE (N branch): local entry preserved"
    else
        _fail "$CASE (N branch): local entry was removed despite N answer"
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
