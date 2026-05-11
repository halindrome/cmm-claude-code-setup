#!/bin/bash
# test-agent-hook-enforcement.sh — Verify agent override hooks actually block/allow correctly
# Usage: bash tests/test-agent-hook-enforcement.sh
# Exit: 0 = all pass, 1 = any failure
#
# Unlike test-agent-hook-overrides.sh (which checks hook WIRING in YAML), this test
# INVOKES each hook with realistic payloads to verify enforcement behavior per agent role.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
AGENTS_DIR="$PROJECT_ROOT/agents"
CMM_NUDGE="$PROJECT_ROOT/hooks/global/cmm-nudge.sh"
CTX_ENFORCER="$PROJECT_ROOT/hooks/project/ctx-execute-enforcer.sh"
WEBFETCH_NUDGE="$PROJECT_ROOT/hooks/global/webfetch-nudge.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# ─── Fixture Setup ────────────────────────────────────────────────────────
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Create a fake project with CMM + Context Mode configured
FAKE_PROJ="$TMPDIR_ROOT/proj"
mkdir -p "$FAKE_PROJ/.claude/hooks"
git -C "$FAKE_PROJ" init -q 2>/dev/null
echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"},"context-mode":{"command":"npx"}}}' > "$FAKE_PROJ/.mcp.json"

# Large code file (>50 lines) — cmm-nudge should block Read on this
for i in $(seq 1 80); do echo "def func_$i(): pass"; done > "$FAKE_PROJ/big_module.py"

# Small code file (<50 lines) — cmm-nudge should allow
echo 'print("hello")' > "$FAKE_PROJ/tiny.py"

# Config file — should never be blocked by cmm-nudge
echo '{"key": "value"}' > "$FAKE_PROJ/config.json"

# Fake CLAUDE_CONFIG_DIR to prevent global settings interference
FAKE_CONFIG="$TMPDIR_ROOT/fake-claude-config"
mkdir -p "$FAKE_CONFIG"
echo '{}' > "$FAKE_CONFIG/settings.json"

# Context Mode sentinels for ctx-execute-enforcer
# Resolve canonical path the same way the hook does (pwd -P inside git repo)
# On macOS /var/folders -> /private/var/folders, so raw mktemp path != canonical
CANONICAL_PROJ=$(cd "$FAKE_PROJ" && git rev-parse --show-toplevel 2>/dev/null || pwd -P)
FAKE_PROJ_HASH=$(echo "$CANONICAL_PROJ" | md5 -q 2>/dev/null || echo "$CANONICAL_PROJ" | md5sum | awk '{print $1}')
echo "1" > "/tmp/ctx-enforcer-${FAKE_PROJ_HASH}"
touch "/tmp/context-mode-ready-${FAKE_PROJ_HASH}"

# Copy hooks into fake project so ctx-execute-enforcer's path integrity check passes
cp "$CMM_NUDGE" "$FAKE_PROJ/.claude/hooks/cmm-nudge.sh" 2>/dev/null || true
cp "$CTX_ENFORCER" "$FAKE_PROJ/.claude/hooks/ctx-execute-enforcer.sh" 2>/dev/null || true
cp "$WEBFETCH_NUDGE" "$FAKE_PROJ/.claude/hooks/webfetch-nudge.sh" 2>/dev/null || true
# track-hook-blocks.sh is called by both hooks
if [ -f "$PROJECT_ROOT/hooks/project/track-hook-blocks.sh" ]; then
  cp "$PROJECT_ROOT/hooks/project/track-hook-blocks.sh" "$FAKE_PROJ/.claude/hooks/track-hook-blocks.sh"
fi

# Second fake project WITHOUT context-mode in .mcp.json — for webfetch-nudge pass-through test
FAKE_PROJ_NO_CTX="$TMPDIR_ROOT/proj-no-ctx"
mkdir -p "$FAKE_PROJ_NO_CTX/.claude/hooks"
git -C "$FAKE_PROJ_NO_CTX" init -q 2>/dev/null
echo '{"mcpServers":{"codebase-memory-mcp":{"command":"npx"}}}' > "$FAKE_PROJ_NO_CTX/.mcp.json"
cp "$WEBFETCH_NUDGE" "$FAKE_PROJ_NO_CTX/.claude/hooks/webfetch-nudge.sh" 2>/dev/null || true
if [ -f "$PROJECT_ROOT/hooks/project/track-hook-blocks.sh" ]; then
  cp "$PROJECT_ROOT/hooks/project/track-hook-blocks.sh" "$FAKE_PROJ_NO_CTX/.claude/hooks/track-hook-blocks.sh"
fi
CANONICAL_PROJ_NO_CTX=$(cd "$FAKE_PROJ_NO_CTX" && git rev-parse --show-toplevel 2>/dev/null || pwd -P)
FAKE_PROJ_NO_CTX_HASH=$(echo "$CANONICAL_PROJ_NO_CTX" | md5 -q 2>/dev/null || echo "$CANONICAL_PROJ_NO_CTX" | md5sum | awk '{print $1}')

cleanup_sentinels() {
  rm -f "/tmp/ctx-enforcer-${FAKE_PROJ_HASH}" "/tmp/context-mode-ready-${FAKE_PROJ_HASH}"
  rm -f "/tmp/ctx-webfetch-avail-${FAKE_PROJ_HASH}" "/tmp/ctx-webfetch-avail-${FAKE_PROJ_NO_CTX_HASH}"
  rm -f "/tmp/cmm-recent-${FAKE_PROJ_HASH}" "/tmp/ctx-nudge-${FAKE_PROJ_HASH}"
}
# Append sentinel cleanup to existing trap
trap 'rm -rf "$TMPDIR_ROOT"; cleanup_sentinels' EXIT

# ─── Helper: invoke a hook and check exit code ───────────────────────────
_assert_hook() {
  local label="$1" hook_path="$2" expected="$3" json="$4"
  local actual=0
  # Run hook from inside the fake project so git rev-parse finds it
  echo "$json" | env CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash -c "cd '$FAKE_PROJ' && bash '$hook_path'" >/dev/null 2>&1 || actual=$?
  if [ "$actual" -eq "$expected" ]; then
    pass "$label"
  else
    fail "$label (expected exit $expected, got $actual)"
  fi
}

# ─── Agent Registry ──────────────────────────────────────────────────────
# Format: agent_name|has_cmm_nudge|has_ctx_enforcer
AGENT_HOOKS=(
  "vbw-dev|yes|yes"
  "vbw-debugger|yes|yes"
  "vbw-qa|yes|yes"
  "vbw-scout|yes|no"
  "vbw-architect|yes|no"
  "vbw-lead|yes|yes"
  "vbw-docs|yes|yes"
)

# Use the installed hooks in the fake project (mirrors real agent frontmatter paths)
FAKE_CMM_NUDGE="$FAKE_PROJ/.claude/hooks/cmm-nudge.sh"
FAKE_CTX_ENFORCER="$FAKE_PROJ/.claude/hooks/ctx-execute-enforcer.sh"

# ─── Test: cmm-nudge.sh blocks Read on large code files ──────────────────
echo "=== cmm-nudge.sh: Read enforcement per agent ==="
for entry in "${AGENT_HOOKS[@]}"; do
  IFS='|' read -r agent has_nudge has_ctx <<< "$entry"
  [ ! -f "$AGENTS_DIR/$agent.md" ] && continue
  [ "$has_nudge" != "yes" ] && continue

  # Should BLOCK: large code file
  _assert_hook "$agent: Read large .py BLOCKED" "$FAKE_CMM_NUDGE" 2 \
    "{\"tool_input\":{\"file_path\":\"$FAKE_PROJ/big_module.py\"}}"

  # Should ALLOW: small code file
  _assert_hook "$agent: Read small .py allowed" "$FAKE_CMM_NUDGE" 0 \
    "{\"tool_input\":{\"file_path\":\"$FAKE_PROJ/tiny.py\"}}"

  # Should ALLOW: config file (non-code)
  _assert_hook "$agent: Read .json config allowed" "$FAKE_CMM_NUDGE" 0 \
    "{\"tool_input\":{\"file_path\":\"$FAKE_PROJ/config.json\"}}"

  # Should ALLOW: targeted read with offset+limit — Phase 47 Plan 01 also
  # requires a fresh /tmp/cmm-recent-<PROJECT_HASH> sentinel (CMM call within
  # the last 60s). Touch it to simulate a preceding CMM call.
  touch "/tmp/cmm-recent-${FAKE_PROJ_HASH}"
  _assert_hook "$agent: Read offset+limit allowed" "$FAKE_CMM_NUDGE" 0 \
    "{\"tool_input\":{\"file_path\":\"$FAKE_PROJ/big_module.py\",\"offset\":10,\"limit\":20}}"
done

# Clean up the cmm-recent sentinel so later tests start from a known state.
rm -f "/tmp/cmm-recent-${FAKE_PROJ_HASH}" 2>/dev/null || true

# ─── Test: ctx-execute-enforcer.sh blocks large-output Bash commands ──────
echo ""
echo "=== ctx-execute-enforcer.sh: Bash enforcement per agent ==="
for entry in "${AGENT_HOOKS[@]}"; do
  IFS='|' read -r agent has_nudge has_ctx <<< "$entry"
  [ ! -f "$AGENTS_DIR/$agent.md" ] && continue
  [ "$has_ctx" != "yes" ] && continue

  # Should BLOCK: test runner
  _assert_hook "$agent: Bash 'npm test' BLOCKED" "$FAKE_CTX_ENFORCER" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'

  # Should BLOCK: package install
  _assert_hook "$agent: Bash 'pip install' BLOCKED" "$FAKE_CTX_ENFORCER" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"pip install requests"}}'

  # Should ALLOW: git commit (exempt)
  _assert_hook "$agent: Bash 'git commit' allowed" "$FAKE_CTX_ENFORCER" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix: test\""}}'

  # Should ALLOW: mkdir (exempt)
  _assert_hook "$agent: Bash 'mkdir' allowed" "$FAKE_CTX_ENFORCER" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"mkdir -p /tmp/test"}}'

  # Should ALLOW: ctx-exempt bypass
  _assert_hook "$agent: Bash 'npm test # ctx-exempt' bypassed" "$FAKE_CTX_ENFORCER" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"npm test # ctx-exempt"}}'
done

# ─── Test: Agents WITHOUT ctx-execute-enforcer are not wired ─────────────
echo ""
echo "=== Negative: agents without Bash hooks ==="
for entry in "${AGENT_HOOKS[@]}"; do
  IFS='|' read -r agent has_nudge has_ctx <<< "$entry"
  [ ! -f "$AGENTS_DIR/$agent.md" ] && continue
  [ "$has_ctx" != "no" ] && continue

  # Confirm the hook is NOT referenced in agent frontmatter
  if grep -q 'ctx-execute-enforcer' "$AGENTS_DIR/$agent.md"; then
    fail "$agent: has ctx-execute-enforcer (should not — no Bash access)"
  else
    pass "$agent: correctly lacks ctx-execute-enforcer"
  fi
done

# ─── Test: cmm-nudge blocks even when invoked from agent hook path ────────
echo ""
echo "=== Hook path: agent frontmatter commands use .claude/hooks/ ==="
for entry in "${AGENT_HOOKS[@]}"; do
  IFS='|' read -r agent has_nudge has_ctx <<< "$entry"
  [ ! -f "$AGENTS_DIR/$agent.md" ] && continue
  [ "$has_nudge" != "yes" ] && continue

  # Extract the actual cmm-nudge command from frontmatter
  nudge_cmd=$(grep -A1 'cmm-nudge' "$AGENTS_DIR/$agent.md" | grep 'command:' | head -1 | sed 's/.*command: *"\(.*\)"/\1/')
  if [ -n "$nudge_cmd" ] && echo "$nudge_cmd" | grep -q 'bash .claude/hooks/cmm-nudge.sh'; then
    pass "$agent: cmm-nudge command is 'bash .claude/hooks/cmm-nudge.sh'"
  else
    fail "$agent: cmm-nudge command unexpected: '$nudge_cmd'"
  fi
done

# ─── Test: webfetch-nudge.sh WebFetch enforcement ────────────────────────
echo ""
echo "=== webfetch-nudge.sh: WebFetch enforcement ==="

FAKE_WEBFETCH_NUDGE="$FAKE_PROJ/.claude/hooks/webfetch-nudge.sh"
FAKE_WEBFETCH_NUDGE_NO_CTX="$FAKE_PROJ_NO_CTX/.claude/hooks/webfetch-nudge.sh"

# Helper: assert webfetch-nudge exit code, running inside a specific project dir.
# Clears the per-project cache file so each call re-detects context-mode state.
_assert_webfetch() {
  local label="$1" proj_dir="$2" proj_hash="$3" expected="$4" json="$5"
  local actual=0
  rm -f "/tmp/ctx-webfetch-avail-${proj_hash}" 2>/dev/null || true
  echo "$json" | env CLAUDE_CONFIG_DIR="$FAKE_CONFIG" HOME="$TMPDIR_ROOT" \
    bash -c "cd '$proj_dir' && bash '$proj_dir/.claude/hooks/webfetch-nudge.sh'" \
    >/dev/null 2>&1 || actual=$?
  if [ "$actual" -eq "$expected" ]; then
    pass "$label"
  else
    fail "$label (expected exit $expected, got $actual)"
  fi
}

# Only scout/lead/dev register webfetch-nudge — iterate and confirm enforcement uniformly
for entry in "${AGENT_HOOKS[@]}"; do
  IFS='|' read -r agent has_nudge has_ctx <<< "$entry"
  [ ! -f "$AGENTS_DIR/$agent.md" ] && continue
  case "$agent" in
    vbw-scout|vbw-lead|vbw-dev) ;;
    *) continue ;;
  esac

  # BLOCK: doc URL when context-mode is in .mcp.json
  _assert_webfetch "$agent: WebFetch doc URL BLOCKED (ctx-mode available)" \
    "$FAKE_PROJ" "$FAKE_PROJ_HASH" 2 \
    "{\"tool_name\":\"WebFetch\",\"tool_input\":{\"url\":\"https://docs.example.com/api\"},\"cwd\":\"$FAKE_PROJ\"}"

  # BLOCK: arbitrary URL when context-mode is available (confirms unconditional nudge design)
  _assert_webfetch "$agent: WebFetch arbitrary URL BLOCKED (ctx-mode available)" \
    "$FAKE_PROJ" "$FAKE_PROJ_HASH" 2 \
    "{\"tool_name\":\"WebFetch\",\"tool_input\":{\"url\":\"https://example.org/foo?bar=baz\"},\"cwd\":\"$FAKE_PROJ\"}"

  # PASS: any URL when context-mode absent from .mcp.json (and no global settings fallback)
  _assert_webfetch "$agent: WebFetch allowed (ctx-mode absent)" \
    "$FAKE_PROJ_NO_CTX" "$FAKE_PROJ_NO_CTX_HASH" 0 \
    "{\"tool_name\":\"WebFetch\",\"tool_input\":{\"url\":\"https://docs.example.com/api\"},\"cwd\":\"$FAKE_PROJ_NO_CTX\"}"

  # PASS: empty payload (fail-open)
  _assert_webfetch "$agent: WebFetch fail-open on empty payload" \
    "$FAKE_PROJ" "$FAKE_PROJ_HASH" 0 \
    ""

  # PASS: malformed JSON (fail-open)
  _assert_webfetch "$agent: WebFetch fail-open on malformed JSON" \
    "$FAKE_PROJ" "$FAKE_PROJ_HASH" 0 \
    "not-json-at-all"
done

# ─── Test: webfetch-nudge.sh detection cascade coverage ──────────────────
# Covers the two detection sources the per-agent loop does not exercise:
#   (a) CLAUDE_CONFIG_DIR/settings.json mentions context-mode (global-only)
#   (b) .claude/context-mode.db exists (activation marker)
echo ""
echo "=== webfetch-nudge.sh: detection cascade coverage ==="

# Helper that runs webfetch-nudge against FAKE_PROJ_NO_CTX with a custom
# CLAUDE_CONFIG_DIR so we can test the global-settings fallback path.
_assert_webfetch_with_global() {
  local label="$1" expected="$2" config_dir="$3" json="$4"
  local actual=0
  rm -f "/tmp/ctx-webfetch-avail-${FAKE_PROJ_NO_CTX_HASH}" 2>/dev/null || true
  echo "$json" | env CLAUDE_CONFIG_DIR="$config_dir" HOME="$TMPDIR_ROOT" \
    bash -c "cd '$FAKE_PROJ_NO_CTX' && bash '$FAKE_PROJ_NO_CTX/.claude/hooks/webfetch-nudge.sh'" \
    >/dev/null 2>&1 || actual=$?
  if [ "$actual" -eq "$expected" ]; then
    pass "$label"
  else
    fail "$label (expected exit $expected, got $actual)"
  fi
}

# (a) Global-settings fallback: .mcp.json has no context-mode, but
# CLAUDE_CONFIG_DIR/settings.json does. The hook must BLOCK (exit 2).
FAKE_CONFIG_WITH_CTX="$TMPDIR_ROOT/fake-claude-config-with-ctx"
mkdir -p "$FAKE_CONFIG_WITH_CTX"
echo '{"mcpServers":{"context-mode":{"command":"npx","args":["-y","context-mode"]}}}' \
  > "$FAKE_CONFIG_WITH_CTX/settings.json"

_assert_webfetch_with_global \
  "webfetch-nudge: BLOCKED via CLAUDE_CONFIG_DIR settings.json fallback" \
  2 "$FAKE_CONFIG_WITH_CTX" \
  "{\"tool_name\":\"WebFetch\",\"tool_input\":{\"url\":\"https://docs.example.com/api\"},\"cwd\":\"$FAKE_PROJ_NO_CTX\"}"

# Confirm the original empty CLAUDE_CONFIG_DIR still PASSES (isolation sanity check)
_assert_webfetch_with_global \
  "webfetch-nudge: PASS with empty CLAUDE_CONFIG_DIR (no cascade sources)" \
  0 "$FAKE_CONFIG" \
  "{\"tool_name\":\"WebFetch\",\"tool_input\":{\"url\":\"https://docs.example.com/api\"},\"cwd\":\"$FAKE_PROJ_NO_CTX\"}"

# (b) .claude/context-mode.db activation: neither .mcp.json nor global settings
# mention context-mode, but the repo has a context-mode.db file. The hook must
# BLOCK (exit 2).
touch "$FAKE_PROJ_NO_CTX/.claude/context-mode.db"
_assert_webfetch_with_global \
  "webfetch-nudge: BLOCKED via .claude/context-mode.db activation marker" \
  2 "$FAKE_CONFIG" \
  "{\"tool_name\":\"WebFetch\",\"tool_input\":{\"url\":\"https://docs.example.com/api\"},\"cwd\":\"$FAKE_PROJ_NO_CTX\"}"
rm -f "$FAKE_PROJ_NO_CTX/.claude/context-mode.db"

# Restore pass-through state so any later tests see a clean FAKE_PROJ_NO_CTX.
rm -f "/tmp/ctx-webfetch-avail-${FAKE_PROJ_NO_CTX_HASH}" 2>/dev/null || true

# ─── Test: cmm-orient-nudge.sh wiring + retired ctx hooks absent (Phase 47) ─
# Confirm every VBW agent references cmm-orient-nudge.sh and none references the
# retired ctx-search-nudge.sh or ctx-annotate-nudge.sh. ctx-annotate-nudge was
# removed because its reminder duplicated rules/ctx-rules.md guidance loaded
# every turn, and the duplication caused the model to misread the nudge as a
# turn-terminator (silent stops mid-investigation).
echo ""
echo "=== Phase 47 hooks: agent frontmatter wiring ==="
for entry in "${AGENT_HOOKS[@]}"; do
  IFS='|' read -r agent has_nudge has_ctx <<< "$entry"
  [ ! -f "$AGENTS_DIR/$agent.md" ] && continue

  if grep -q 'cmm-orient-nudge.sh' "$AGENTS_DIR/$agent.md"; then
    pass "$agent: registers cmm-orient-nudge.sh"
  else
    fail "$agent: missing cmm-orient-nudge.sh"
  fi

  if grep -q 'ctx-search-nudge' "$AGENTS_DIR/$agent.md"; then
    fail "$agent: still references retired ctx-search-nudge"
  else
    pass "$agent: no ctx-search-nudge references"
  fi

  if grep -q 'ctx-annotate-nudge' "$AGENTS_DIR/$agent.md"; then
    fail "$agent: still references retired ctx-annotate-nudge"
  else
    pass "$agent: no ctx-annotate-nudge references"
  fi
done

# --- Phase 52 additions ---
# Assert agent body content shipped in Phase 52 Plan 01 is present.
# Pure greps over agents/*.md — no hook invocation required.
echo ""
echo "=== Phase 52: agent body content assertions ==="

# (a) vbw-qa.md: write-verification.sh NON-NEGOTIABLE gate present (>=1)
_qa_count=$(grep -c 'write-verification.sh' "$AGENTS_DIR/vbw-qa.md" || true)
if [ "${_qa_count:-0}" -ge 1 ]; then
  pass "vbw-qa: write-verification.sh keyword present (count=$_qa_count, need >=1)"
else
  fail "vbw-qa: write-verification.sh keyword missing (count=$_qa_count, need >=1)"
fi

# (b) vbw-dev.md: pre_existing_issues mentioned in DEVN-05 rule + Stage 3 (>=2)
_dev_pei_count=$(grep -c 'pre_existing_issues' "$AGENTS_DIR/vbw-dev.md" || true)
if [ "${_dev_pei_count:-0}" -ge 2 ]; then
  pass "vbw-dev: pre_existing_issues keyword present (count=$_dev_pei_count, need >=2)"
else
  fail "vbw-dev: pre_existing_issues keyword underrepresented (count=$_dev_pei_count, need >=2)"
fi

# (c) <skill_no_activation> handling in each of the 6 target agents (>=1 per file)
for _agent in vbw-dev vbw-scout vbw-lead vbw-qa vbw-debugger vbw-docs; do
  if [ ! -f "$AGENTS_DIR/$_agent.md" ]; then
    fail "$_agent: agent file missing (cannot check skill_no_activation)"
    continue
  fi
  _sna_count=$(grep -c 'skill_no_activation' "$AGENTS_DIR/$_agent.md" || true)
  if [ "${_sna_count:-0}" -ge 1 ]; then
    pass "$_agent: skill_no_activation keyword present (count=$_sna_count, need >=1)"
  else
    fail "$_agent: skill_no_activation keyword missing (count=$_sna_count, need >=1)"
  fi
done

# (d) vbw-dev.md: '## Context Mode Web Fetch' preservation (count == 1)
_dev_cmwf_count=$(grep -c '^## Context Mode Web Fetch' "$AGENTS_DIR/vbw-dev.md" || true)
if [ "${_dev_cmwf_count:-0}" -eq 1 ]; then
  pass "vbw-dev: '## Context Mode Web Fetch' heading preserved (count=$_dev_cmwf_count)"
else
  fail "vbw-dev: '## Context Mode Web Fetch' heading count=$_dev_cmwf_count (expected exactly 1)"
fi

# (e) vbw-debugger.md: v1.37.0 PR #627 already_fixed semantic block present in BOTH
# Investigation Protocol and Teammate Mode (PR #627 upstream is two separate insertions
# in two different sections — anchor both independently so a partial mirror is detected).
_dbg_af_inv_count=$(grep -c 'already_fixed.*fresh current evidence' "$AGENTS_DIR/vbw-debugger.md" || true)
if [ "${_dbg_af_inv_count:-0}" -ge 1 ]; then
  pass "vbw-debugger: v1.37.0 Investigation Protocol already_fixed prose present (count=$_dbg_af_inv_count, need >=1)"
else
  fail "vbw-debugger: v1.37.0 Investigation Protocol already_fixed prose missing (count=$_dbg_af_inv_count, need >=1)"
fi

_dbg_af_tm_count=$(grep -c 'Historical .accepted-process-exception. or backlog/UAT-deviation metadata alone is not fresh evidence for .already_fixed.' "$AGENTS_DIR/vbw-debugger.md" || true)
if [ "${_dbg_af_tm_count:-0}" -ge 1 ]; then
  pass "vbw-debugger: v1.37.0 Teammate Mode accepted-process-exception line present (count=$_dbg_af_tm_count, need >=1)"
else
  fail "vbw-debugger: v1.37.0 Teammate Mode accepted-process-exception line missing (count=$_dbg_af_tm_count, need >=1)"
fi

# --- Phase 56 additions ---
# Assert rules/cmm-rules.md upstream-behavior contract keywords introduced by Plan 56-01
# remain present. If a future edit drops the search_graph 200-row cap line, the multi-word
# regex auto-conversion note for search_code, or the list_projects /tmp visibility note,
# this test will fail and surface the drift before agents start handing out stale guidance.
echo ""
echo "=== Phase 56: cmm-rules.md upstream-behavior contract keywords ==="

CMM_RULES="$PROJECT_ROOT/rules/cmm-rules.md"

# (a) search_graph default 200-row cap note (Plan 56-01, upstream commit 9425b99)
_sg_cap_count=$(grep -cE 'search_graph.*200|200.*rows.*search_graph|200 rows' "$CMM_RULES" || true)
if [ "${_sg_cap_count:-0}" -ge 1 ]; then
  pass "cmm-rules: search_graph 200-row cap keyword present (count=$_sg_cap_count, need >=1)"
else
  fail "cmm-rules: search_graph 200-row cap keyword missing (count=$_sg_cap_count, need >=1)"
fi

# (b) Paging guidance: 'offset' and/or 'query_graph' as the paging/full-scan escape hatch
_paging_count=$(grep -cE 'offset|query_graph' "$CMM_RULES" || true)
if [ "${_paging_count:-0}" -ge 2 ]; then
  pass "cmm-rules: paging guidance (offset / query_graph) present (count=$_paging_count, need >=2)"
else
  fail "cmm-rules: paging guidance (offset / query_graph) underrepresented (count=$_paging_count, need >=2)"
fi

# (c) search_code multi-word -> regex auto-conversion note (Plan 56-01, upstream commit cc7ef34)
_sc_regex_count=$(grep -cE 'search_code.*regex|regex.*search_code|multi-word.*regex|auto-converts.*regex' "$CMM_RULES" || true)
if [ "${_sc_regex_count:-0}" -ge 1 ]; then
  pass "cmm-rules: search_code multi-word regex note present (count=$_sc_regex_count, need >=1)"
else
  fail "cmm-rules: search_code multi-word regex note missing (count=$_sc_regex_count, need >=1)"
fi

# (d) list_projects /tmp visibility note (Plan 56-01, upstream commit eb0627e)
_lp_tmp_count=$(grep -cE 'list_projects.*/tmp|/tmp.*list_projects' "$CMM_RULES" || true)
if [ "${_lp_tmp_count:-0}" -ge 1 ]; then
  pass "cmm-rules: list_projects /tmp visibility note present (count=$_lp_tmp_count, need >=1)"
else
  fail "cmm-rules: list_projects /tmp visibility note missing (count=$_lp_tmp_count, need >=1)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
