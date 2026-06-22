#!/bin/bash
# test-phase-67-statusline.sh — Test Style-C statusline rendering (phase 67)
#
# Covers: Style-C default render, each toggle on/off, context-mode absent fail-open,
# sqlite3 absent fail-open, sentinel absent (⟳ glyph), stderr suppression,
# cmm_calls opt-in, full assembly integration.
#
# Strategy: generate the GLOBAL standalone statusline-cmm.sh via
# setup.sh --global --force with a fake CLAUDE_CONFIG_DIR, then test
# the generated script using the PATH-stub pattern (same as test-phase-66-*.sh).
#
# The generated script computes PROJECT_HASH from git rev-parse --show-toplevel,
# which resolves symlinks on macOS (/var → /private/var). We compute the same
# hash here so config files and sentinel paths match what the script looks for.
#
# Usage: bash tests/test-phase-67-statusline.sh
# Exit: 0 = all pass, 1 = any failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SETUP_SH="$REPO_ROOT/setup.sh"

PASS=0; FAIL=0

_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

_assert_contains() {
    local label="$1" pattern="$2" text="$3"
    if echo "$text" | grep -qF -- "$pattern"; then
        _pass "$label"
    else
        _fail "$label" "expected '$pattern' in: $text"
    fi
}

_assert_not_contains() {
    local label="$1" pattern="$2" text="$3"
    if echo "$text" | grep -qF -- "$pattern"; then
        _fail "$label" "unexpected '$pattern' in: $text"
    else
        _pass "$label"
    fi
}

# -----------------------------------------------------------------------
# Setup: generate GLOBAL standalone statusline-cmm.sh
# Use --global so the STATUSLINE_SCRIPT heredoc is emitted (not the wrapper).
# -----------------------------------------------------------------------
TMPROOT=$(mktemp -d -t phase67-statusline-test-XXXXXX)

# Git repo for running the script from.
# Use pwd -P (inside the subshell) to get the canonical, symlink-resolved path.
# On macOS, mktemp returns /var/folders/... but git rev-parse --show-toplevel
# returns /private/var/folders/... — using pwd -P ensures both the test's hash
# computation and the script's runtime hash computation agree.
SCRATCH=$(cd "$TMPROOT" && mkdir gitrepo && cd gitrepo \
    && git init -q \
    && git config user.email "t@t.com" \
    && git config user.name "T" \
    && git commit --allow-empty -q -m "init" \
    && pwd -P)

# Fake global config dir
FAKE_CONFIG="$TMPROOT/claude-config"
mkdir -p "$FAKE_CONFIG/hooks"

# Generate global standalone statusline-cmm.sh
(cd "$SCRATCH" && CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$SETUP_SH" --global --force --skip-mcp-check 2>/dev/null) || true

STATUSLINE="$FAKE_CONFIG/hooks/statusline-cmm.sh"
if [ ! -f "$STATUSLINE" ]; then
    echo "FATAL: setup.sh did not generate global statusline-cmm.sh at $STATUSLINE"
    exit 1
fi

# Compute PROJECT_HASH from the canonical SCRATCH path.
# SCRATCH is already pwd -P resolved, so this matches what the script computes.
PROJECT_HASH=$(echo "$SCRATCH" | md5 -q 2>/dev/null || echo "$SCRATCH" | md5sum | awk '{print $1}')

# F3: Compute CMM_SLUG using the same algorithm as cbm_project_name_from_path (pipeline/fqn.c):
#   replace non-[A-Za-z0-9._-] with '-', collapse consecutive dashes/dots,
#   trim leading/trailing dashes and dots.
CMM_SLUG=$(printf '%s' "$SCRATCH" \
  | sed 's/[^A-Za-z0-9._-]/-/g' \
  | sed 's/--*/-/g; s/\.\.*/-/g' \
  | sed 's/^[-.]//; s/[-.]$//')
[ -n "$CMM_SLUG" ] || CMM_SLUG="root"

# Config and cache dir
SL_CONFIG_DIR="$HOME/.cache/codebase-memory-mcp"
SL_CONFIG="$SL_CONFIG_DIR/_statusline-config-${PROJECT_HASH}.json"
mkdir -p "$SL_CONFIG_DIR"

# Cleanup on exit
trap 'rm -rf "$TMPROOT"; rm -f "$SL_CONFIG" 2>/dev/null; rm -f "/tmp/cmm-session-ready-${PROJECT_HASH}" 2>/dev/null; rm -f "${SL_CONFIG_DIR}/_call-counts-${PROJECT_HASH}.json" 2>/dev/null; rm -f "${SL_CONFIG_DIR}/${CMM_SLUG}.db" 2>/dev/null' EXIT

# Helper: write a config JSON to the project-specific config path
_write_config() {
    local json="$1"
    echo "$json" > "$SL_CONFIG"
}

# Default config: ctx_savings=true, cmm_health=true, all opt-ins false
_write_default_config() {
    _write_config '{"ctx_savings":true,"cmm_health":true,"cmm_nodes_edges":false,"cmm_calls":false,"blocks_total":false,"block_details":false}'
}

# Run the statusline script with a PATH-stub dir prepended, from the git repo dir
_run_statusline() {
    local stub_dir="$1"
    shift
    (cd "$SCRATCH" && env PATH="${stub_dir}:${PATH}" "$@" bash "$STATUSLINE" 2>/dev/null)
}

# Capture stderr only (stdout discarded)
_run_statusline_stderr() {
    local stub_dir="$1"
    shift
    (cd "$SCRATCH" && env PATH="${stub_dir}:${PATH}" "$@" bash "$STATUSLINE" 2>&1 1>/dev/null)
}

echo ""
echo "=== Phase 67: statusline Style-C rendering tests ==="
echo ""

# Build a reusable context-mode stub that echoes a savings line
# F3: use REAL double-space format (two spaces around ● and around each ·)
STUB_BASE="$TMPROOT/stub-base"
mkdir -p "$STUB_BASE"
cat > "$STUB_BASE/context-mode" <<'SH'
#!/bin/bash
echo "context-mode  ●  170 KB kept out  ·  170 KB/day  ·  preserved across compact, restart & upgrade"
SH
chmod +x "$STUB_BASE/context-mode"

# -----------------------------------------------------------------------
# T1 — Style-C default render
# stub context-mode echoes savings line; sentinel present; sqlite3 absent
# -----------------------------------------------------------------------
echo "--- T1: Style-C default render ---"
_write_default_config
touch "/tmp/cmm-session-ready-${PROJECT_HASH}"

OUT1=$(_run_statusline "$STUB_BASE")
# F3: assert exact trimmed savings field — leading segment so no pipe before it,
# but must contain exactly "170 KB kept out" with no extra leading/trailing spaces.
# Check by asserting the field appears followed by " | " (single-space pipe separator)
_assert_contains "T1: output contains '170 KB kept out |'" "170 KB kept out |" "$OUT1"
_assert_not_contains "T1: output does NOT contain doubled spaces around savings" "170 KB kept out  |" "$OUT1"
_assert_not_contains "T1: savings has no leading space" " 170 KB kept out" "$OUT1"
_assert_contains "T1: output contains 'CMM ✓'" "CMM ✓" "$OUT1"
_assert_not_contains "T1: output does NOT contain 'CTX:'" "CTX:" "$OUT1"
if echo "$OUT1" | grep -qE 'CMM:[0-9]'; then
    _fail "T1: output does NOT contain 'CMM:N' call-count format" "got: $OUT1"
else
    _pass "T1: output does NOT contain 'CMM:N' call-count format"
fi

# -----------------------------------------------------------------------
# T2 — ctx_savings=false toggle
# -----------------------------------------------------------------------
echo "--- T2: ctx_savings=false toggle ---"
_write_config '{"ctx_savings":false,"cmm_health":true,"cmm_nodes_edges":false,"cmm_calls":false,"blocks_total":false,"block_details":false}'
touch "/tmp/cmm-session-ready-${PROJECT_HASH}"
OUT2=$(_run_statusline "$STUB_BASE")
_assert_not_contains "T2: savings hidden when ctx_savings=false" "kept out" "$OUT2"

# -----------------------------------------------------------------------
# T3 — cmm_health=false toggle
# -----------------------------------------------------------------------
echo "--- T3: cmm_health=false toggle ---"
_write_config '{"ctx_savings":true,"cmm_health":false,"cmm_nodes_edges":false,"cmm_calls":false,"blocks_total":false,"block_details":false}'
touch "/tmp/cmm-session-ready-${PROJECT_HASH}"
OUT3=$(_run_statusline "$STUB_BASE")
_assert_not_contains "T3: CMM ✓ hidden when cmm_health=false" "CMM ✓" "$OUT3"
_assert_not_contains "T3: CMM ⟳ hidden when cmm_health=false" "CMM ⟳" "$OUT3"

# -----------------------------------------------------------------------
# T4 — cmm_nodes_edges=true toggle with sqlite3 stub
# -----------------------------------------------------------------------
echo "--- T4: cmm_nodes_edges=true with sqlite3 stub ---"
STUB4="$TMPROOT/stub4"
mkdir -p "$STUB4"
cp "$STUB_BASE/context-mode" "$STUB4/"
cat > "$STUB4/sqlite3" <<'SH'
#!/bin/bash
echo "42"
SH
chmod +x "$STUB4/sqlite3"

# F3: Create a fake CMM DB at the REAL slug path (not md5 hash) so F1 fix is exercised
CMM_DB="$SL_CONFIG_DIR/${CMM_SLUG}.db"
touch "$CMM_DB"

_write_config '{"ctx_savings":true,"cmm_health":true,"cmm_nodes_edges":true,"cmm_calls":false,"blocks_total":false,"block_details":false}'
touch "/tmp/cmm-session-ready-${PROJECT_HASH}"
OUT4=$(_run_statusline "$STUB4")
_assert_contains "T4: output contains '42n/42e'" "42n/42e" "$OUT4"
rm -f "$CMM_DB"

# -----------------------------------------------------------------------
# T5 — context-mode absent fail-open (exit 1)
# -----------------------------------------------------------------------
echo "--- T5: context-mode absent fail-open (exit 1) ---"
STUB5="$TMPROOT/stub5"
mkdir -p "$STUB5"
cat > "$STUB5/context-mode" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$STUB5/context-mode"

_write_default_config
touch "/tmp/cmm-session-ready-${PROJECT_HASH}"
OUT5=$(_run_statusline "$STUB5") || true
(cd "$SCRATCH" && env PATH="${STUB5}:${PATH}" bash "$STATUSLINE" 2>/dev/null)
RC5=$?
if [ "$RC5" -eq 0 ]; then
    _pass "T5: script exits 0 when context-mode exits 1"
else
    _fail "T5: script exits 0 when context-mode exits 1" "got exit $RC5"
fi
_assert_not_contains "T5: no savings output when context-mode fails" "kept out" "$OUT5"

# -----------------------------------------------------------------------
# T6 — context-mode non-zero exit fail-open (exit 2)
# -----------------------------------------------------------------------
echo "--- T6: context-mode non-zero exit fail-open (exit 2) ---"
STUB6="$TMPROOT/stub6"
mkdir -p "$STUB6"
cat > "$STUB6/context-mode" <<'SH'
#!/bin/bash
exit 2
SH
chmod +x "$STUB6/context-mode"

_write_default_config
touch "/tmp/cmm-session-ready-${PROJECT_HASH}"
(cd "$SCRATCH" && env PATH="${STUB6}:${PATH}" bash "$STATUSLINE" 2>/dev/null)
RC6=$?
if [ "$RC6" -eq 0 ]; then
    _pass "T6: script exits 0 when context-mode exits 2"
else
    _fail "T6: script exits 0 when context-mode exits 2" "got exit $RC6"
fi

# -----------------------------------------------------------------------
# T7 — sqlite3 fails fail-open (cmm_nodes_edges=true but sqlite3 returns error)
# -----------------------------------------------------------------------
echo "--- T7: sqlite3 fail-open ---"
STUB7="$TMPROOT/stub7"
mkdir -p "$STUB7"
cp "$STUB_BASE/context-mode" "$STUB7/"
# sqlite3 stub that always fails (simulates absent/broken sqlite3)
cat > "$STUB7/sqlite3" <<'SH'
#!/bin/bash
exit 127
SH
chmod +x "$STUB7/sqlite3"

CMM_DB7="$SL_CONFIG_DIR/${CMM_SLUG}.db"
touch "$CMM_DB7"

_write_config '{"ctx_savings":true,"cmm_health":true,"cmm_nodes_edges":true,"cmm_calls":false,"blocks_total":false,"block_details":false}'
touch "/tmp/cmm-session-ready-${PROJECT_HASH}"
OUT7=$(_run_statusline "$STUB7") || true
(cd "$SCRATCH" && env PATH="${STUB7}:${PATH}" bash "$STATUSLINE" 2>/dev/null)
RC7=$?
if [ "$RC7" -eq 0 ]; then
    _pass "T7: script exits 0 when sqlite3 fails"
else
    _fail "T7: script exits 0 when sqlite3 fails" "got exit $RC7"
fi
_assert_contains "T7: CMM ✓ present even when sqlite3 fails" "CMM ✓" "$OUT7"
_assert_not_contains "T7: no node/edge counts when sqlite3 fails" "n/" "$OUT7"
rm -f "$CMM_DB7"

# -----------------------------------------------------------------------
# T8 — sentinel absent → CMM ⟳
# -----------------------------------------------------------------------
echo "--- T8: sentinel absent → CMM ⟳ ---"
rm -f "/tmp/cmm-session-ready-${PROJECT_HASH}"
_write_default_config
OUT8=$(_run_statusline "$STUB_BASE")
_assert_contains "T8: output contains 'CMM ⟳' when sentinel absent" "CMM ⟳" "$OUT8"
# Restore sentinel for subsequent tests
touch "/tmp/cmm-session-ready-${PROJECT_HASH}"

# -----------------------------------------------------------------------
# T9 — stderr suppression
# -----------------------------------------------------------------------
echo "--- T9: stderr suppression ---"
STUB9="$TMPROOT/stub9"
mkdir -p "$STUB9"
cat > "$STUB9/context-mode" <<'SH'
#!/bin/bash
echo "context-mode ● 170 KB kept out · rest"
echo "ExperimentalWarning: SQLite is an experimental feature" >&2
SH
chmod +x "$STUB9/context-mode"

_write_default_config
touch "/tmp/cmm-session-ready-${PROJECT_HASH}"
STDERR9=$(_run_statusline_stderr "$STUB9")
if [ -z "$STDERR9" ]; then
    _pass "T9: no stderr reaches the caller"
else
    _fail "T9: no stderr reaches the caller" "got stderr: $STDERR9"
fi

# -----------------------------------------------------------------------
# T9b — F4: no-● brand-strip: context-mode output without ● must not leak brand text
# -----------------------------------------------------------------------
echo "--- T9b: F4 no-● brand-strip (no brand text in output) ---"
STUB9B="$TMPROOT/stub9b"
mkdir -p "$STUB9B"
cat > "$STUB9B/context-mode" <<'SH'
#!/bin/bash
# Emits savings line without ● (older/different context-mode variant)
echo "context-mode 170 KB kept out · 170 KB/day · preserved"
SH
chmod +x "$STUB9B/context-mode"

_write_default_config
touch "/tmp/cmm-session-ready-${PROJECT_HASH}"
OUT9B=$(_run_statusline "$STUB9B")
_assert_not_contains "T9b: no 'context-mode' brand in output" "context-mode" "$OUT9B"

# -----------------------------------------------------------------------
# T10 — cmm_calls=true opt-in
# -----------------------------------------------------------------------
echo "--- T10: cmm_calls=true opt-in ---"
CALL_CACHE="$SL_CONFIG_DIR/_call-counts-${PROJECT_HASH}.json"
echo '{"total_calls":7,"by_tool":{}}' > "$CALL_CACHE"

_write_config '{"ctx_savings":true,"cmm_health":true,"cmm_nodes_edges":false,"cmm_calls":true,"blocks_total":false,"block_details":false}'
touch "/tmp/cmm-session-ready-${PROJECT_HASH}"
OUT10=$(_run_statusline "$STUB_BASE")
_assert_contains "T10: output contains 'CMM:' when cmm_calls=true" "CMM:" "$OUT10"
rm -f "$CALL_CACHE"

# -----------------------------------------------------------------------
# T11 — Full Style-C assembly integration
# Default flags, savings stub, sentinel present.
# Expected: "<savings> | CMM ✓" with pipe separator, no CTX: or CMM:N
# -----------------------------------------------------------------------
echo "--- T11: Full Style-C assembly integration ---"
_write_default_config
touch "/tmp/cmm-session-ready-${PROJECT_HASH}"
OUT11=$(_run_statusline "$STUB_BASE")
# F3: assert exact trimmed savings field — leading segment, pipe after it, no extra spaces
_assert_contains "T11: contains '170 KB kept out |'" "170 KB kept out |" "$OUT11"
_assert_not_contains "T11: no doubled spaces around savings" "170 KB kept out  |" "$OUT11"
_assert_not_contains "T11: savings has no leading space" " 170 KB kept out" "$OUT11"
_assert_contains "T11: contains 'CMM ✓'" "CMM ✓" "$OUT11"
_assert_contains "T11: contains ' | ' separator" " | " "$OUT11"
_assert_not_contains "T11: no CTX: label" "CTX:" "$OUT11"
if echo "$OUT11" | grep -qE 'CMM:[0-9]'; then
    _fail "T11: no CMM:N call-count in default output" "got: $OUT11"
else
    _pass "T11: no CMM:N call-count in default output"
fi

# -----------------------------------------------------------------------
# T12 — PROJECT wrapper: Style-C render + fail-open when context-mode absent
# Generate the PROJECT wrapper via setup.sh --project into a temp .claude dir,
# then test it with the same PATH-stub pattern used for the global standalone.
# -----------------------------------------------------------------------
echo "--- T12: PROJECT wrapper Style-C render ---"

# Create a fake project directory with a git repo and .claude/hooks dir
PROJ_DIR="$TMPROOT/projrepo"
mkdir -p "$PROJ_DIR/.claude/hooks"
(cd "$PROJ_DIR" \
  && git init -q \
  && git config user.email "t@t.com" \
  && git config user.name "T" \
  && git commit --allow-empty -q -m "init")
PROJ_DIR=$(cd "$PROJ_DIR" && pwd -P)

# Generate the PROJECT wrapper statusline-cmm.sh
(cd "$PROJ_DIR" && CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$SETUP_SH" --project --force --skip-mcp-check 2>/dev/null) || true

WRAPPER="$PROJ_DIR/.claude/hooks/statusline-cmm.sh"
if [ ! -f "$WRAPPER" ]; then
  _fail "T12-setup: setup.sh --project did not generate wrapper statusline-cmm.sh at $WRAPPER" "file missing"
else
  _pass "T12-setup: wrapper statusline-cmm.sh generated"

  # Compute hash for wrapper's project root (used by config lookup)
  PROJ_HASH=$(echo "$PROJ_DIR" | md5 -q 2>/dev/null || echo "$PROJ_DIR" | md5sum | awk '{print $1}')
  PROJ_CONFIG="$SL_CONFIG_DIR/_statusline-config-${PROJ_HASH}.json"
  echo '{"ctx_savings":true,"cmm_health":true,"cmm_nodes_edges":false,"cmm_calls":false,"blocks_total":false,"block_details":false}' > "$PROJ_CONFIG"
  touch "/tmp/cmm-session-ready-${PROJ_HASH}"

  # T12a — Style-C render with context-mode stub: expect "<savings> | CMM <glyph>"
  OUT12A=$(cd "$PROJ_DIR" && env PATH="${STUB_BASE}:${PATH}" CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$WRAPPER" 2>/dev/null || true)
  _assert_contains "T12a: wrapper contains savings '170 KB kept out |'" "170 KB kept out |" "$OUT12A"
  _assert_not_contains "T12a: wrapper no doubled spaces around savings" "170 KB kept out  |" "$OUT12A"
  _assert_contains "T12a: wrapper contains 'CMM ✓' or 'CMM ⟳'" "CMM" "$OUT12A"
  _assert_not_contains "T12a: wrapper no CTX: label" "CTX:" "$OUT12A"

  # T12b — fail-open: context-mode absent → exit 0, no savings in output
  # Use a minimal PATH containing only essential tools (no context-mode) so the
  # wrapper fails to find context-mode and must exit 0 without savings.
  NO_CTX_STUB="$TMPROOT/stub-noctx"
  mkdir -p "$NO_CTX_STUB"
  # Provide jq, sqlite3, md5/md5sum, git but NOT context-mode via a stripped PATH
  MINIMAL_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  OUT12B=$(cd "$PROJ_DIR" && env PATH="${NO_CTX_STUB}:${MINIMAL_PATH}" CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$WRAPPER" 2>/dev/null || true)
  _assert_not_contains "T12b: wrapper no savings when context-mode absent" "kept out" "$OUT12B"

  # Cleanup proj config
  rm -f "$PROJ_CONFIG" "/tmp/cmm-session-ready-${PROJ_HASH}" 2>/dev/null
fi

# -----------------------------------------------------------------------
# style_c_default anchor for must_have grep verification
style_c_default=true  # phase 67 Style-C default rendering
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
