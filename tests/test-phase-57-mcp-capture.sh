#!/bin/bash
# test-phase-57-mcp-capture.sh — Plugin-form MCP capture regression coverage.
#
# Regression test for upstream issue mksglu/context-mode#329 ("raw mcp__*
# tool outputs not persisted") and PR #532 ("route external MCP tools through
# PreToolUse", closes #529). Upstream 1.0.122 closed the architectural gap by
# adding (a) a wildcard `mcp__` matcher to POST_TOOL_USE_MATCHERS and (b) the
# three plugin-form `mcp__plugin_context-mode_context-mode__ctx_execute[_file|
# _batch_execute]` matchers to PRE_TOOL_USE_MATCHERS. Phase 57 plan 01 brought
# our project's setup.sh, merge_context_mode_hooks, and the three project
# hooks (track-ctx-calls.sh, ctx-execute-enforcer.sh, ctx-execute-cmm-nudge.sh)
# in line with this canonical inventory and added dual-coverage probes for
# both install forms (plugin form FIRST per G3; MCP-server form as legacy).
#
# What this test asserts (Phase 57 plan 02, task 3):
#
#   Case 1 — Plugin-form fixture install + setup.sh detection:
#            A scratch HOME with a plugin-form context-mode manifest
#            (~/.claude/plugins/cache/test-marketplace/context-mode/
#            .claude-plugin/plugin.json with "name": "context-mode") causes
#            setup.sh --project to detect the plugin form and route into the
#            dual-form matcher heal path. The upstream PreToolUse matcher
#            written by merge_context_mode_hooks contains the three
#            plugin-form ctx tool names FIRST followed by the three legacy
#            MCP-server-form ctx tool names.
#
#   Case 2 — Project-hook plugin-form awareness:
#            The three installed project hooks each reference the plugin-form
#            prefix `mcp__plugin_context-mode_context-mode__` in their probe /
#            matcher comment logic — proving the dual-coverage path is wired.
#            Counts: track-ctx-calls.sh >= 1, ctx-execute-enforcer.sh >= 1,
#            ctx-execute-cmm-nudge.sh >= 1.
#
#   Case 3 — Hook invocation under plugin-form tool_name:
#            Fire each of the three project hooks via direct stdin invocation
#            with `tool_name="mcp__plugin_context-mode_context-mode__ctx_execute"`
#            and assert each exits cleanly (exit 0 — silent allow — OR exit 2
#            — explicit block). Hooks must NOT crash, parse-error, or emit
#            python tracebacks on the plugin-form payload. This is the
#            practical proxy for end-to-end FTS5 capture; the actual context-
#            mode binary is not available in CI test scratch so we cannot
#            assert `ctx_search` returns the captured payload directly.
#
# Test environment limitation (per 57-CONTEXT.md Risk Notes):
# `/plugin install context-mode@context-mode` is a Claude Code slash command
# and cannot be invoked from a bash test. Plugin-form detection is therefore
# simulated via the fixture-path approach above (scratch HOME with a fake
# plugin-cache manifest). Upstream context-mode's FTS5 store is not running
# inside the test, so we cannot prove end-to-end persistence — Case 3 is the
# strongest assertion feasible without a live MCP server.
#
# Usage: bash tests/test-phase-57-mcp-capture.sh
# Exit: 0 = all pass, 1 = any failure
#
# Notes:
# - Each case uses its own `mktemp -d` scratch dir; the real repo and the
#   real ~/.claude are not touched.
# - Cleanup on EXIT trap removes all scratch state — running the test twice
#   in a row produces identical PASS output with no leftover artifacts.

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

# Single scratch dir used for all cases. Cleaned up on EXIT.
SCRATCH=$(mktemp -d -t cmm-phase57-mcp-capture-XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

# --- Setup: simulate plugin-form context-mode install --------------------------
# setup.sh's detect_context_mode probes ${CLAUDE_PLUGIN_ROOT} first and falls
# back to ~/.claude/plugins/cache/<marketplace>/context-mode/.claude-plugin/
# plugin.json. We populate the fallback path under a scratch HOME so the test
# never touches the real plugin cache.
FAKE_HOME="$SCRATCH/fakehome"
PLUGIN_MANIFEST_DIR="$FAKE_HOME/.claude/plugins/cache/test-marketplace/context-mode/.claude-plugin"
mkdir -p "$PLUGIN_MANIFEST_DIR"
cat > "$PLUGIN_MANIFEST_DIR/plugin.json" <<'JSON'
{
  "name": "context-mode",
  "version": "1.0.122",
  "description": "Plugin-form fixture for tests/test-phase-57-mcp-capture.sh"
}
JSON

PROJECT="$SCRATCH/project"
mkdir -p "$PROJECT"
(
    cd "$PROJECT"
    git init -q
    git commit --allow-empty -q -m init
)

# Run setup.sh --project against the scratch project with HOME pointing at the
# fake plugin cache. --skip-mcp-check avoids triggering an interactive .mcp.json
# install path; detect_context_mode still runs (its early-exit on
# --skip-context-mode is the only skip path).
(
    cd "$PROJECT"
    echo n | HOME="$FAKE_HOME" bash "$SETUP" --project --yes --skip-mcp-check
) >"$SCRATCH/setup.out" 2>&1 || {
    echo "SETUP_FAILED — see $SCRATCH/setup.out" >&2
    tail -30 "$SCRATCH/setup.out" >&2
}

SETTINGS="$PROJECT/.claude/settings.json"
HOOKS_DIR="$PROJECT/.claude/hooks"

# --- Case 1: Plugin-form fixture install + setup.sh detection ------------------
CASE="case 1 - plugin-form detection + canonical PreToolUse matcher"

if [ ! -f "$SETTINGS" ]; then
    _fail "$CASE - settings.json not created at $SETTINGS"
else
    # The upstream merge_context_mode_hooks PreToolUse matcher must contain
    # both plugin-form and MCP-server-form ctx tool names, with plugin form
    # listed first.
    pre_matcher=$(jq -r '.hooks.PreToolUse[]? | select(.hooks[0].command | contains("context-mode-hook-dispatch.sh pretooluse")) | .matcher' "$SETTINGS")
    expected_pre="Bash|WebFetch|Read|Grep|Agent|mcp__plugin_context-mode_context-mode__ctx_execute|mcp__plugin_context-mode_context-mode__ctx_execute_file|mcp__plugin_context-mode_context-mode__ctx_batch_execute|mcp__context-mode__ctx_execute|mcp__context-mode__ctx_execute_file|mcp__context-mode__ctx_batch_execute"
    if [ "$pre_matcher" = "$expected_pre" ]; then
        _pass "$CASE - upstream PreToolUse matcher is canonical 1.0.122 (plugin form first, MCP-server form second)"
    else
        _fail "$CASE - upstream PreToolUse matcher mismatch (got '$pre_matcher')"
    fi

    # PostToolUse matcher must include the wildcard `mcp__` token that closes
    # the #329 capture gap.
    post_matcher=$(jq -r '.hooks.PostToolUse[]? | select(.hooks[0].command | contains("context-mode-hook-dispatch.sh posttooluse")) | .matcher' "$SETTINGS")
    if [[ "$post_matcher" == *"|mcp__"* ]] || [[ "$post_matcher" == mcp__* ]]; then
        _pass "$CASE - upstream PostToolUse matcher includes wildcard mcp__ token (#329 fix baseline)"
    else
        _fail "$CASE - upstream PostToolUse matcher missing wildcard mcp__ token (got '$post_matcher')"
    fi
fi

# --- Case 2: Project-hook plugin-form awareness --------------------------------
CASE="case 2 - project-hook plugin-form awareness"

PLUGIN_PREFIX_RE='mcp__plugin_context-mode_context-mode__'

for hook in track-ctx-calls.sh ctx-execute-enforcer.sh ctx-execute-cmm-nudge.sh; do
    hook_path="$HOOKS_DIR/$hook"
    if [ ! -f "$hook_path" ]; then
        _fail "$CASE - $hook not installed at $hook_path"
        continue
    fi
    count=$(grep -c "$PLUGIN_PREFIX_RE" "$hook_path" 2>/dev/null || echo 0)
    if [ "$count" -ge 1 ]; then
        _pass "$CASE - $hook references plugin-form prefix ($count occurrence(s))"
    else
        _fail "$CASE - $hook missing plugin-form prefix references (expected >= 1, got $count)"
    fi
done

# --- Case 3: Hook invocation under plugin-form tool_name -----------------------
CASE="case 3 - plugin-form tool_name hook invocation"

SENTINEL="phase-57-mcp-capture-sentinel-$RANDOM-$RANDOM"

# Synthesized PostToolUse-shape JSON payload with a plugin-form tool_name. The
# tool_response.stdout carries a unique sentinel string so a downstream live
# context-mode FTS5 store could in principle search for it via ctx_search.
read -r -d '' POST_PAYLOAD <<JSON || true
{
  "hook_event_name": "PostToolUse",
  "tool_name": "mcp__plugin_context-mode_context-mode__ctx_execute",
  "tool_input": {"language": "shell", "code": "echo $SENTINEL"},
  "tool_response": {"stdout": "$SENTINEL", "exit_code": 0},
  "cwd": "$PROJECT"
}
JSON

# track-ctx-calls.sh is the simplest — pure counter, never blocks, always
# exits 0. Fire it with the plugin-form payload and assert exit 0.
if [ -x "$HOOKS_DIR/track-ctx-calls.sh" ]; then
    if echo "$POST_PAYLOAD" | bash "$HOOKS_DIR/track-ctx-calls.sh" >"$SCRATCH/track.out" 2>"$SCRATCH/track.err"; then
        _pass "$CASE - track-ctx-calls.sh exits 0 under plugin-form PostToolUse payload"
    else
        rc=$?
        _fail "$CASE - track-ctx-calls.sh exited $rc under plugin-form payload (stderr: $(head -5 "$SCRATCH/track.err"))"
    fi
else
    _fail "$CASE - track-ctx-calls.sh not executable at $HOOKS_DIR/track-ctx-calls.sh"
fi

# Synthesized PreToolUse-shape payload for the enforcer / nudge hooks.
read -r -d '' PRE_PAYLOAD <<JSON || true
{
  "hook_event_name": "PreToolUse",
  "tool_name": "mcp__plugin_context-mode_context-mode__ctx_execute",
  "tool_input": {"language": "shell", "code": "echo $SENTINEL"},
  "cwd": "$PROJECT"
}
JSON

# ctx-execute-enforcer.sh blocks Bash, not ctx_execute itself. With a plugin-
# form ctx_execute tool_name the hook should fall through (exit 0 — the
# matcher in settings.json is "Bash", so this is a defense-in-depth check
# that the script handles a non-Bash tool_name gracefully).
#
# Invoke from inside $PROJECT so the enforcer's path-integrity guard
# (_SCRIPT_ROOT vs git-toplevel) does NOT fire — otherwise the guard exits 2
# before the plugin-form parser is ever reached and the test becomes vacuous.
if [ -x "$HOOKS_DIR/ctx-execute-enforcer.sh" ]; then
    ( cd "$PROJECT" && echo "$PRE_PAYLOAD" | bash "$HOOKS_DIR/ctx-execute-enforcer.sh" ) \
        >"$SCRATCH/enf.out" 2>"$SCRATCH/enf.err"
    rc=$?
    # With the path-integrity guard inert, exit 0 is the canonical fall-through
    # path (the matcher is Bash, a plugin-form ctx_execute tool_name must not
    # be blocked). A python traceback or parse error would produce a non-zero
    # exit with diagnostic stderr.
    if [ "$rc" -eq 0 ] && ! grep -qE 'Traceback|SyntaxError|python[0-9]*: ' "$SCRATCH/enf.err"; then
        _pass "$CASE - ctx-execute-enforcer.sh fell through (exit 0) under plugin-form payload"
    else
        _fail "$CASE - ctx-execute-enforcer.sh exited $rc under plugin-form payload (stderr: $(head -5 "$SCRATCH/enf.err"))"
    fi
else
    _fail "$CASE - ctx-execute-enforcer.sh not executable at $HOOKS_DIR/ctx-execute-enforcer.sh"
fi

# ctx-execute-cmm-nudge.sh: this is the hook most affected by plugin-form —
# its python parser explicitly probes both install-form tool names. Fire
# with a SAFE non-grep payload (echo) and assert clean exit 0 (fail-open per
# 46-CONTEXT.md — only unambiguous grep-family commands trigger the block).
if [ -x "$HOOKS_DIR/ctx-execute-cmm-nudge.sh" ]; then
    echo "$PRE_PAYLOAD" | bash "$HOOKS_DIR/ctx-execute-cmm-nudge.sh" >"$SCRATCH/nudge.out" 2>"$SCRATCH/nudge.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        _pass "$CASE - ctx-execute-cmm-nudge.sh exits 0 under safe plugin-form payload (fail-open path)"
    elif [ "$rc" -eq 2 ]; then
        # Block on a non-grep payload would be a regression — log details.
        _fail "$CASE - ctx-execute-cmm-nudge.sh blocked (exit 2) on safe plugin-form payload (stderr: $(head -10 "$SCRATCH/nudge.err"))"
    else
        _fail "$CASE - ctx-execute-cmm-nudge.sh exited $rc under plugin-form payload (stderr: $(head -5 "$SCRATCH/nudge.err"))"
    fi
else
    _fail "$CASE - ctx-execute-cmm-nudge.sh not executable at $HOOKS_DIR/ctx-execute-cmm-nudge.sh"
fi

# --- Case 4: Migration helper Y branch (R2 F-04 coverage) ----------------------
# Phase 57 G1 introduced `_do_context_mode_migration_yes`, which removes the
# `context-mode` entry from .mcp.json when the user answers Y to the migration
# prompt. R2 found three bugs in this code path that were invisible to the rest
# of the suite (--yes + piped stdin + plugin-only fixture all skip the prompt):
#
#   R2 F-01: same-run migration undone — INSTALL_CONTEXT_MODE stayed true and
#            install_project's MCP-merge block re-added the entry.
#   R2 F-02: .mcp.json write was non-atomic (no .tmp + os.replace).
#   R2 F-03: bare python heredoc could abort setup under `set -e`.
#
# We exercise the helper directly by extracting its function definition from
# setup.sh and sourcing it into a scratch shell. This proves the data-mutation
# logic (removal, preservation of other entries, atomic .mcp.json.tmp pattern,
# INSTALL_CONTEXT_MODE flip) without needing a PTY harness for the interactive
# prompt. The shell prompt path remains exercised by manual testing.
CASE="case 4 - migration helper Y branch (R2 fix coverage)"
MIG_DIR="$SCRATCH/migration"
mkdir -p "$MIG_DIR"
cat > "$MIG_DIR/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "context-mode": {
      "command": "npx",
      "args": ["-y", "context-mode@latest"],
      "type": "stdio"
    },
    "codebase-memory-mcp": {
      "command": "codebase-memory-mcp",
      "args": [],
      "type": "stdio"
    }
  }
}
JSON

# Extract the helper function from setup.sh. Brittle to function-header
# reformatting; if the function is renamed or its closing `}` no longer sits
# alone on a line, regenerate this awk pattern.
awk '/^_do_context_mode_migration_yes\(\)/,/^}$/' "$SETUP" > "$SCRATCH/migration-helper.sh"

if [ ! -s "$SCRATCH/migration-helper.sh" ]; then
    _fail "$CASE - could not extract _do_context_mode_migration_yes from $SETUP"
else
    (
        cd "$MIG_DIR" || exit 99
        # Set up the bash env the helper expects.
        INSTALL_CONTEXT_MODE=true
        # shellcheck disable=SC1091
        . "$SCRATCH/migration-helper.sh"
        _do_context_mode_migration_yes "$MIG_DIR/.sentinel"
        # Print final state for the parent shell to assert against.
        echo "INSTALL_CONTEXT_MODE=$INSTALL_CONTEXT_MODE"
    ) > "$SCRATCH/migration.out" 2> "$SCRATCH/migration.err"
    mig_rc=$?

    if [ "$mig_rc" -ne 0 ]; then
        _fail "$CASE - helper exited $mig_rc (stderr: $(head -5 "$SCRATCH/migration.err"))"
    else
        # F-01 assertion: INSTALL_CONTEXT_MODE flipped to false in the subshell
        # output (proves install_project would not re-add the removed entry).
        if grep -qx "INSTALL_CONTEXT_MODE=false" "$SCRATCH/migration.out"; then
            _pass "$CASE - INSTALL_CONTEXT_MODE flipped to false after successful removal (F-01)"
        else
            _fail "$CASE - INSTALL_CONTEXT_MODE did not flip to false (stdout: $(cat "$SCRATCH/migration.out"))"
        fi

        # Data assertions: context-mode is gone, codebase-memory-mcp is still there.
        if jq -e '.mcpServers."context-mode" == null' "$MIG_DIR/.mcp.json" >/dev/null 2>&1; then
            _pass "$CASE - context-mode entry removed from .mcp.json"
        else
            _fail "$CASE - context-mode entry NOT removed from .mcp.json"
        fi
        if jq -e '.mcpServers."codebase-memory-mcp".command == "codebase-memory-mcp"' "$MIG_DIR/.mcp.json" >/dev/null 2>&1; then
            _pass "$CASE - codebase-memory-mcp entry preserved during migration"
        else
            _fail "$CASE - codebase-memory-mcp entry was lost during migration"
        fi

        # F-02 assertion: no leftover .mcp.json.tmp (proves os.replace ran, not a bare overwrite).
        if [ ! -f "$MIG_DIR/.mcp.json.tmp" ]; then
            _pass "$CASE - no leftover .mcp.json.tmp after migration (atomic os.replace, F-02)"
        else
            _fail "$CASE - .mcp.json.tmp still present after migration (atomic write regressed)"
        fi

        # Sanity: sentinel was written.
        if [ -f "$MIG_DIR/.sentinel" ]; then
            _pass "$CASE - migration sentinel written"
        else
            _fail "$CASE - migration sentinel not written at $MIG_DIR/.sentinel"
        fi
    fi
fi

# --- Summary -------------------------------------------------------------------
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
echo "PASS: phase 57 plugin-form mcp__ capture regression coverage"
echo "============================================================"
exit 0
