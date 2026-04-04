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
# track-hook-blocks.sh is called by both hooks
if [ -f "$PROJECT_ROOT/hooks/project/track-hook-blocks.sh" ]; then
  cp "$PROJECT_ROOT/hooks/project/track-hook-blocks.sh" "$FAKE_PROJ/.claude/hooks/track-hook-blocks.sh"
fi

cleanup_sentinels() {
  rm -f "/tmp/ctx-enforcer-${FAKE_PROJ_HASH}" "/tmp/context-mode-ready-${FAKE_PROJ_HASH}"
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

  # Should ALLOW: targeted read with offset+limit
  _assert_hook "$agent: Read offset+limit allowed" "$FAKE_CMM_NUDGE" 0 \
    "{\"tool_input\":{\"file_path\":\"$FAKE_PROJ/big_module.py\",\"offset\":10,\"limit\":20}}"
done

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

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
