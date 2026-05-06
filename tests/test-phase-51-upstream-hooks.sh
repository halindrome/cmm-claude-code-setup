#!/bin/bash
# test-phase-51-upstream-hooks.sh — Regression coverage for phase-51 upstream
# context-mode hook registration in setup.sh.
#
# Covers:
#   Case 1 — Registration: fresh `setup.sh --project` writes the five upstream
#            hook entries (PostToolUse, PreToolUse, PreCompact, SessionStart,
#            UserPromptSubmit) as `bash <abs-path>/.claude/hooks/context-mode-hook-dispatch.sh <event>`.
#            The dispatcher is a small shell helper that exec's the global
#            `context-mode` binary when present and falls back to
#            `npx -y context-mode@latest` otherwise — eliminating the
#            ENOTEMPTY race that bare `npx -y @latest` suffers under
#            concurrent hook fires on rapid tool-call sessions.
#   Case 2 — Idempotency: running setup.sh twice produces identical settings.json
#            and each upstream command appears exactly once.
#   Case 3 — --skip-context-mode: no upstream entries written; regular project
#            hooks (session-gate.sh etc.) are still registered.
#   Case 4 — Matcher ordering: our PreToolUse hooks (session-gate,
#            ctx-execute-enforcer, cmm-nudge, cmm-grep-nudge) appear at lower
#            array indices than the new upstream context-mode PreToolUse entry.
#   Case 5 — Deprecated-wrapper cleanup: pre-existing context-mode-event-logger.sh
#            and context-mode-pre-compact.sh wrappers are removed from disk AND
#            their settings.json entries are pruned, while the five upstream hooks
#            ARE registered (clean upgrade).
#
# Usage: bash tests/test-phase-51-upstream-hooks.sh
# Exit: 0 = all pass, 1 = any failure
#
# Notes:
# - Each case uses its own `mktemp -d` scratch dir; the real repo and
#   ~/.claude are not touched.
# - The test only verifies that setup.sh writes the correct command STRINGS;
#   it does not invoke `context-mode` itself, so the context-mode binary does
#   not need to be installed.
# - --skip-context-mode is only honored when detect_context_mode runs (i.e.,
#   when --skip-mcp-check is NOT passed). Case 3 relies on the MCP pre-flight
#   path being active.

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

# Helper: run setup.sh --project in a fresh scratch dir, pipe "n" to any
# interactive allowlist/statusline prompt, return the scratch dir path on stdout.
_scratch_install() {
    local extra_flags="${1:-}"
    local scratch
    scratch=$(mktemp -d -t cmm-phase51-XXXXXX)
    (
        cd "$scratch" && git init -q && git commit --allow-empty -q -m init
    )
    # shellcheck disable=SC2086
    ( cd "$scratch" && echo n | bash "$SETUP" --project --yes --skip-mcp-check $extra_flags ) >"$scratch/setup.out" 2>&1 || {
        echo "SETUP_FAILED" >&2
        tail -20 "$scratch/setup.out" >&2
    }
    echo "$scratch"
}

# --- Case 1: Registration (fresh install) ------------------------------------
CASE="case 1 - registration"
SCRATCH1=$(_scratch_install "")
trap 'rm -rf "$SCRATCH1"' EXIT

SETTINGS1="$SCRATCH1/.claude/settings.json"
if [ ! -f "$SETTINGS1" ]; then
    _fail "$CASE - settings.json not created"
else
    for event in PostToolUse PreToolUse PreCompact SessionStart UserPromptSubmit; do
        lower=$(echo "$event" | tr '[:upper:]' '[:lower:]')
        cmd_count=$(jq "[.. | objects | .command? // empty | select(contains(\"context-mode-hook-dispatch.sh $lower\"))] | length" "$SETTINGS1")
        if [ "$cmd_count" = "1" ]; then
            _pass "$CASE - $event registered with dispatcher command"
        else
            _fail "$CASE - $event dispatcher command count is $cmd_count (expected 1)"
        fi
    done

    # PostToolUse matcher: broad tool list including mcp__
    ptu_matcher=$(jq -r '.hooks.PostToolUse[] | select(.hooks[0].command | contains("context-mode-hook-dispatch.sh posttooluse")) | .matcher' "$SETTINGS1")
    expected_ptu="Bash|Read|Write|Edit|NotebookEdit|Glob|Grep|WebFetch|WebSearch|TodoWrite|TaskCreate|TaskUpdate|EnterPlanMode|ExitPlanMode|Skill|Agent|AskUserQuestion|EnterWorktree|mcp__"
    if [ "$ptu_matcher" = "$expected_ptu" ]; then
        _pass "$CASE - PostToolUse matcher is exact broad matcher string"
    else
        _fail "$CASE - PostToolUse matcher mismatch (got '$ptu_matcher')"
    fi

    # PreToolUse matcher: must contain mcp__context-mode__ctx_execute AND must NOT
    # contain the plugin form mcp__plugin_context-mode_context-mode__.
    pre_matcher=$(jq -r '.hooks.PreToolUse[] | select(.hooks[0].command | contains("context-mode-hook-dispatch.sh pretooluse")) | .matcher' "$SETTINGS1")
    if [[ "$pre_matcher" == *"mcp__context-mode__ctx_execute"* ]]; then
        _pass "$CASE - PreToolUse matcher uses MCP-server form (mcp__context-mode__)"
    else
        _fail "$CASE - PreToolUse matcher missing MCP-server form (got '$pre_matcher')"
    fi
    if [[ "$pre_matcher" == *"mcp__plugin_context-mode_context-mode__"* ]]; then
        _fail "$CASE - PreToolUse matcher uses plugin form instead of MCP-server form"
    else
        _pass "$CASE - PreToolUse matcher correctly avoids plugin form"
    fi
fi

# --- Case 2: Idempotency (double-install) ------------------------------------
CASE="case 2 - idempotency"
# Snapshot settings.json after run 1 (SCRATCH1 state).
cp "$SETTINGS1" "$SCRATCH1/settings.run1.json"

# Second run on the same scratch dir.
( cd "$SCRATCH1" && echo n | bash "$SETUP" --project --yes --skip-mcp-check ) >"$SCRATCH1/setup2.out" 2>&1 || true
cp "$SETTINGS1" "$SCRATCH1/settings.run2.json"

if diff <(jq -S . "$SCRATCH1/settings.run1.json") <(jq -S . "$SCRATCH1/settings.run2.json") >/dev/null 2>&1; then
    _pass "$CASE - settings.json byte-identical across two runs"
else
    _fail "$CASE - settings.json diverged between run 1 and run 2"
fi

upstream_count=$(jq '[.. | objects | .command? // empty | select(contains("context-mode-hook-dispatch.sh"))] | length' "$SETTINGS1")
if [ "$upstream_count" = "5" ]; then
    _pass "$CASE - exactly 5 upstream entries after double-install"
else
    _fail "$CASE - expected 5 upstream entries, got $upstream_count"
fi

# --- Case 3: --skip-context-mode honored -------------------------------------
CASE="case 3 - skip-context-mode"
SCRATCH3=$(mktemp -d -t cmm-phase51-skipctx-XXXXXX)
trap 'rm -rf "$SCRATCH1" "$SCRATCH3"' EXIT

(
    cd "$SCRATCH3"
    git init -q
    git commit --allow-empty -q -m init
    echo n | bash "$SETUP" --project --yes --skip-context-mode
) >"$SCRATCH3/setup.out" 2>&1 || true

SETTINGS3="$SCRATCH3/.claude/settings.json"
if [ ! -f "$SETTINGS3" ]; then
    _fail "$CASE - settings.json not created"
else
    skip_upstream=$(jq '[.. | objects | .command? // empty | select(contains("context-mode-hook-dispatch.sh"))] | length' "$SETTINGS3")
    if [ "$skip_upstream" = "0" ]; then
        _pass "$CASE - no upstream entries written with --skip-context-mode"
    else
        _fail "$CASE - expected 0 upstream entries, got $skip_upstream"
    fi

    # Regular project hooks must still be registered.
    sg_count=$(jq '[.. | objects | .command? // empty | select(contains("session-gate.sh"))] | length' "$SETTINGS3")
    if [ "$sg_count" -ge 1 ]; then
        _pass "$CASE - session-gate.sh still registered under --skip-context-mode"
    else
        _fail "$CASE - session-gate.sh missing (regression — --skip-context-mode should not drop non-context-mode hooks)"
    fi
fi

# --- Case 4: Matcher ordering (our hooks before upstream) --------------------
CASE="case 4 - matcher ordering"
# Reuse SCRATCH1 (successfully ran setup twice).
python3 - "$SETTINGS1" <<'PY' >"$SCRATCH1/order.out" 2>&1
import json, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

errors = []
def cmd(entry):
    hooks = entry.get("hooks", [])
    return hooks[0].get("command", "") if hooks else ""

pre = data.get("hooks", {}).get("PreToolUse", [])

# Find the upstream entry's index
upstream_idx = next(
    (i for i, e in enumerate(pre) if "context-mode-hook-dispatch.sh pretooluse" in cmd(e)),
    None,
)
if upstream_idx is None:
    errors.append("context-mode upstream PreToolUse entry not found")
else:
    # Our hooks: session-gate.sh, ctx-execute-enforcer.sh, cmm-nudge.sh, cmm-grep-nudge.sh
    for needle in ("session-gate.sh", "ctx-execute-enforcer.sh", "cmm-nudge.sh", "cmm-grep-nudge.sh"):
        idx = next((i for i, e in enumerate(pre) if needle in cmd(e)), None)
        if idx is None:
            errors.append(f"{needle} not found in PreToolUse")
        elif idx >= upstream_idx:
            errors.append(f"{needle} at index {idx} must be BEFORE upstream at {upstream_idx}")

# First entry in PreToolUse should not be the upstream context-mode entry.
if pre and "context-mode-hook-dispatch.sh pretooluse" in cmd(pre[0]):
    errors.append("first PreToolUse entry is context-mode upstream (should be one of ours)")

if errors:
    for e in errors:
        print("ERR:", e)
    sys.exit(1)
else:
    print("OK")
PY
if [ "$?" = "0" ] && grep -q '^OK$' "$SCRATCH1/order.out"; then
    _pass "$CASE - our PreToolUse hooks appear before upstream context-mode entry"
else
    _fail "$CASE - matcher ordering failed ($(cat "$SCRATCH1/order.out"))"
fi

# --- Case 5: Deprecated-wrapper cleanup on upgrade ---------------------------
CASE="case 5 - deprecated wrapper cleanup"
SCRATCH5=$(mktemp -d -t cmm-phase51-legacy-XXXXXX)
trap 'rm -rf "$SCRATCH1" "$SCRATCH3" "$SCRATCH5"' EXIT

(
    cd "$SCRATCH5"
    git init -q
    git commit --allow-empty -q -m init

    # Pre-populate the old wrapper files AND fake settings.json entries
    # referencing them — mimics a pre-phase-51 install upgrading.
    mkdir -p .claude/hooks
    printf '#!/bin/bash\nexit 0\n' > .claude/hooks/context-mode-event-logger.sh
    printf '#!/bin/bash\nexit 0\n' > .claude/hooks/context-mode-pre-compact.sh
    cat > .claude/settings.json <<'J'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [{"type": "command", "command": "bash .claude/hooks/context-mode-event-logger.sh"}]
      }
    ],
    "PreCompact": [
      {
        "hooks": [{"type": "command", "command": "bash .claude/hooks/context-mode-pre-compact.sh"}]
      }
    ]
  }
}
J

    echo n | bash "$SETUP" --project --yes --skip-mcp-check
) >"$SCRATCH5/setup.out" 2>&1 || true

SETTINGS5="$SCRATCH5/.claude/settings.json"

# Files must be gone
if [ ! -f "$SCRATCH5/.claude/hooks/context-mode-event-logger.sh" ]; then
    _pass "$CASE - context-mode-event-logger.sh removed from .claude/hooks/"
else
    _fail "$CASE - context-mode-event-logger.sh still present on disk"
fi

if [ ! -f "$SCRATCH5/.claude/hooks/context-mode-pre-compact.sh" ]; then
    _pass "$CASE - context-mode-pre-compact.sh removed from .claude/hooks/"
else
    _fail "$CASE - context-mode-pre-compact.sh still present on disk"
fi

# Settings.json entries must be gone
evt_log_entries=$(jq '[.. | objects | .command? // empty | select(contains("context-mode-event-logger"))] | length' "$SETTINGS5")
if [ "$evt_log_entries" = "0" ]; then
    _pass "$CASE - context-mode-event-logger.sh entries pruned from settings.json"
else
    _fail "$CASE - found $evt_log_entries context-mode-event-logger entries in settings.json"
fi

pc_entries=$(jq '[.. | objects | .command? // empty | select(contains("context-mode-pre-compact"))] | length' "$SETTINGS5")
if [ "$pc_entries" = "0" ]; then
    _pass "$CASE - context-mode-pre-compact.sh entries pruned from settings.json"
else
    _fail "$CASE - found $pc_entries context-mode-pre-compact entries in settings.json"
fi

# Upstream hooks should be registered now (clean upgrade)
upgrade_upstream=$(jq '[.. | objects | .command? // empty | select(contains("context-mode-hook-dispatch.sh"))] | length' "$SETTINGS5")
if [ "$upgrade_upstream" = "5" ]; then
    _pass "$CASE - five upstream hooks registered after clean upgrade"
else
    _fail "$CASE - expected 5 upstream hooks after upgrade, got $upgrade_upstream"
fi

# --- Summary -----------------------------------------------------------------
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
echo "PASS: phase 51 upstream hooks registration"
echo "============================================================"
exit 0
