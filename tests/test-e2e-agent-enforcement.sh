#!/bin/bash
# test-e2e-agent-enforcement.sh — End-to-end test: setup.sh --project install + agent enforcement validation
# Usage: bash tests/test-e2e-agent-enforcement.sh
# Exit: 0 = all pass, 1 = any failure
#
# Creates a fixture repo, runs setup.sh --project, then validates:
#   Section 1: Installed file existence (hooks, agents, rules, settings, mcp.json)
#   Section 2: settings.json hook registration structure (via python3)
#   Section 3: Agent override content (name fields, hook references, SUBAGENT_COMMIT)
# Plan 03 extends this script with hook blocking tests at the marked insertion point.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SETUP_SH="$PROJECT_ROOT/setup.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# ─── Fixture Setup ────────────────────────────────────────────────────────
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Create a minimal git repo fixture for setup.sh --project
FIXTURE="$TMPDIR_ROOT/proj"
mkdir -p "$FIXTURE"
git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.email "test@test.com"
git -C "$FIXTURE" config user.name "Test"
echo "# fixture" > "$FIXTURE/README.md"
git -C "$FIXTURE" add README.md
git -C "$FIXTURE" commit -q -m "init"

# Fake CLAUDE_CONFIG_DIR to prevent global settings interference
FAKE_CONFIG="$TMPDIR_ROOT/fake-claude-config"
mkdir -p "$FAKE_CONFIG"
echo '{}' > "$FAKE_CONFIG/settings.json"

# Run setup.sh --project --skip-mcp-check --skip-statusline --force from inside the fixture
echo "=== Running setup.sh --project ==="
INSTALL_OUTPUT=$(cd "$FIXTURE" && echo "n" | env CLAUDE_CONFIG_DIR="$FAKE_CONFIG" bash "$SETUP_SH" --project --skip-mcp-check --skip-statusline --force 2>&1) || {
  echo "FATAL: setup.sh --project failed (exit $?)"
  echo "$INSTALL_OUTPUT"
  exit 1
}
echo "  setup.sh --project completed successfully"
echo ""

# ─── Section 1: Installed File Existence ─────────────────────────────────
echo "=== Section 1: Installed File Existence ==="

# Hook files expected in .claude/hooks/ (13 from hooks/project/ + cmm-nudge.sh from hooks/global/)
EXPECTED_HOOKS=(
  session-gate.sh
  agent-cmm-gate.sh
  ctx-execute-enforcer.sh
  cmm-sentinel-writer.sh
  cmm-session-start.sh
  subagent-cmm-startup.sh
  reindex-after-commit.sh
  track-cmm-calls.sh
  cmm-query-stale-advisory.sh
  context-mode-event-logger.sh
  context-mode-sentinel-writer.sh
  context-mode-pre-compact.sh
  track-hook-blocks.sh
  cmm-nudge.sh
)

for hook in "${EXPECTED_HOOKS[@]}"; do
  if [ -f "$FIXTURE/.claude/hooks/$hook" ]; then
    pass "hook exists: $hook"
  else
    fail "hook missing: $hook"
  fi
done

# cmm-nudge.sh specifically — validates global hook was copied to project hooks dir
if [ -f "$FIXTURE/.claude/hooks/cmm-nudge.sh" ]; then
  pass "cmm-nudge.sh copied from global hooks"
else
  fail "cmm-nudge.sh not copied from global hooks"
fi

# Agent override files in .claude/agents/
EXPECTED_AGENTS=(
  vbw-dev.md
  vbw-debugger.md
  vbw-qa.md
  vbw-scout.md
  vbw-architect.md
  vbw-lead.md
  vbw-docs.md
)

for agent in "${EXPECTED_AGENTS[@]}"; do
  if [ -f "$FIXTURE/.claude/agents/$agent" ]; then
    pass "agent exists: $agent"
  else
    fail "agent missing: $agent"
  fi
done

# Rules files in .claude/rules/
EXPECTED_RULES=(
  project-settings-example.json
  mcp-example.json
  allowed-tools.txt
  global-claude-md.md
)

for rule in "${EXPECTED_RULES[@]}"; do
  if [ -f "$FIXTURE/.claude/rules/$rule" ]; then
    pass "rule exists: $rule"
  else
    fail "rule missing: $rule"
  fi
done

# .mcp.json exists and contains codebase-memory-mcp
if [ -f "$FIXTURE/.mcp.json" ]; then
  pass ".mcp.json exists"
  if grep -q "codebase-memory-mcp" "$FIXTURE/.mcp.json"; then
    pass ".mcp.json contains codebase-memory-mcp"
  else
    fail ".mcp.json missing codebase-memory-mcp"
  fi
else
  fail ".mcp.json missing"
fi

# .claude/settings.json exists
if [ -f "$FIXTURE/.claude/settings.json" ]; then
  pass "settings.json exists"
else
  fail "settings.json missing"
fi

echo ""

# ─── Section 2: settings.json Hook Registration Validation ───────────────
echo "=== Section 2: settings.json Hook Registration ==="

# Resolve the fixture's canonical path for absolute path checks
FIXTURE_CANONICAL=$(cd "$FIXTURE" && pwd -P)

# Validate settings.json structure using python3
# Write results to temp file to avoid subshell counter loss from pipes
SETTINGS_RESULTS="$TMPDIR_ROOT/settings-results.txt"

python3 -c "
import json, sys
with open('$FIXTURE/.claude/settings.json') as f:
    data = json.load(f)
hooks = data.get('hooks', {})
if 'hooks' not in data:
    print('NO_HOOKS')
    sys.exit(0)
for htype in ['SessionStart', 'PreToolUse', 'PostToolUse', 'SubagentStart']:
    if htype in hooks:
        print(f'HAS:{htype}')
    else:
        print(f'MISSING:{htype}')
" > "$SETTINGS_RESULTS"

while IFS= read -r line; do
  case "$line" in
    NO_HOOKS) fail "settings.json has no hooks key" ;;
    HAS:*)    pass "settings.json has ${line#HAS:} section" ;;
    MISSING:*) fail "settings.json missing ${line#MISSING:} section" ;;
  esac
done < "$SETTINGS_RESULTS"

# Validate specific hook registrations
python3 -c "
import json, sys
with open('$FIXTURE/.claude/settings.json') as f:
    data = json.load(f)
hooks = data.get('hooks', {})

def find_commands(hook_type):
    groups = hooks.get(hook_type, [])
    cmds = []
    for g in groups:
        for h in g.get('hooks', []):
            cmds.append(h.get('command', ''))
    return cmds

# session-gate.sh in PreToolUse
pre_cmds = find_commands('PreToolUse')
if any('session-gate.sh' in c for c in pre_cmds):
    print('FOUND:session-gate.sh in PreToolUse')
else:
    print('NOTFOUND:session-gate.sh in PreToolUse')

# cmm-session-start.sh in SessionStart
ss_cmds = find_commands('SessionStart')
if any('cmm-session-start.sh' in c for c in ss_cmds):
    print('FOUND:cmm-session-start.sh in SessionStart')
else:
    print('NOTFOUND:cmm-session-start.sh in SessionStart')

# subagent-cmm-startup.sh in SubagentStart
sa_cmds = find_commands('SubagentStart')
if any('subagent-cmm-startup.sh' in c for c in sa_cmds):
    print('FOUND:subagent-cmm-startup.sh in SubagentStart')
else:
    print('NOTFOUND:subagent-cmm-startup.sh in SubagentStart')

# All hook commands use absolute paths containing fixture dir
fixture_path = '$FIXTURE_CANONICAL'
all_cmds = []
for htype in hooks:
    all_cmds.extend(find_commands(htype))
non_abs = [c for c in all_cmds if c and fixture_path not in c]
if non_abs:
    print('BADPATH:' + '|'.join(non_abs[:3]))
else:
    print('ABSPATH:all hook commands use absolute paths')
" > "$SETTINGS_RESULTS"

while IFS= read -r line; do
  case "$line" in
    FOUND:*)    pass "${line#FOUND:}" ;;
    NOTFOUND:*) fail "${line#NOTFOUND:}" ;;
    ABSPATH:*)  pass "${line#ABSPATH:}" ;;
    BADPATH:*)  fail "hook commands with non-absolute paths: ${line#BADPATH:}" ;;
  esac
done < "$SETTINGS_RESULTS"

echo ""

# ─── Section 3: Agent Override Content Validation ────────────────────────
echo "=== Section 3: Agent Override Content ==="

# All 7 agents with correct name: field
AGENT_NAMES=(vbw-dev vbw-debugger vbw-qa vbw-scout vbw-architect vbw-lead vbw-docs)

for agent in "${AGENT_NAMES[@]}"; do
  file="$FIXTURE/.claude/agents/${agent}.md"
  [ ! -f "$file" ] && continue

  # Correct name: field
  if grep -q "^name: ${agent}$" "$file"; then
    pass "$agent has correct name: field"
  else
    fail "$agent missing or incorrect name: field"
  fi

  # cmm-nudge.sh reference (all agents should have it)
  if grep -q "cmm-nudge.sh" "$file"; then
    pass "$agent has cmm-nudge.sh reference"
  else
    fail "$agent missing cmm-nudge.sh reference"
  fi
done

# Agents WITH Bash access should have ctx-execute-enforcer.sh
BASH_AGENTS=(vbw-dev vbw-debugger vbw-qa vbw-lead vbw-docs)
for agent in "${BASH_AGENTS[@]}"; do
  file="$FIXTURE/.claude/agents/${agent}.md"
  [ ! -f "$file" ] && continue
  if grep -q "ctx-execute-enforcer.sh" "$file"; then
    pass "$agent has ctx-execute-enforcer.sh (has Bash access)"
  else
    fail "$agent missing ctx-execute-enforcer.sh (should have it — has Bash access)"
  fi
done

# Agents WITHOUT Bash access should NOT have ctx-execute-enforcer.sh
NO_BASH_AGENTS=(vbw-scout vbw-architect)
for agent in "${NO_BASH_AGENTS[@]}"; do
  file="$FIXTURE/.claude/agents/${agent}.md"
  [ ! -f "$file" ] && continue
  if grep -q "ctx-execute-enforcer.sh" "$file"; then
    fail "$agent has ctx-execute-enforcer.sh (should NOT — no Bash access)"
  else
    pass "$agent correctly lacks ctx-execute-enforcer.sh (no Bash access)"
  fi
done

# dev and debugger have SUBAGENT_COMMIT=1
COMMIT_AGENTS=(vbw-dev vbw-debugger)
for agent in "${COMMIT_AGENTS[@]}"; do
  file="$FIXTURE/.claude/agents/${agent}.md"
  [ ! -f "$file" ] && continue
  if grep -q "SUBAGENT_COMMIT" "$file"; then
    pass "$agent has SUBAGENT_COMMIT marker"
  else
    fail "$agent missing SUBAGENT_COMMIT marker"
  fi
done

# qa, scout, architect, lead, docs should NOT have SUBAGENT_COMMIT
NO_COMMIT_AGENTS=(vbw-qa vbw-scout vbw-architect vbw-lead vbw-docs)
for agent in "${NO_COMMIT_AGENTS[@]}"; do
  file="$FIXTURE/.claude/agents/${agent}.md"
  [ ! -f "$file" ] && continue
  if grep -q "SUBAGENT_COMMIT" "$file"; then
    fail "$agent has SUBAGENT_COMMIT (should NOT)"
  else
    pass "$agent correctly lacks SUBAGENT_COMMIT"
  fi
done

# All hook commands in agent frontmatter use project-relative paths (bash .claude/hooks/)
for agent in "${AGENT_NAMES[@]}"; do
  file="$FIXTURE/.claude/agents/${agent}.md"
  [ ! -f "$file" ] && continue
  # Check for absolute paths in hook commands — should not exist
  if grep -E 'command:.*(/Users|/home|/tmp).*\.claude/hooks/' "$file" >/dev/null 2>&1; then
    fail "$agent agent has absolute paths in hook commands"
  else
    pass "$agent agent uses project-relative hook paths"
  fi
done

echo ""

# ─── Hook Blocking Tests (added by Plan 03) ──────────────────────────
# Source the E2E helper library for _e2e_assert_hook, payload generators, sentinel mgmt
source "$SCRIPT_DIR/e2e-hook-helpers.sh"

# Set required variables for the helper library
E2E_FIXTURE_DIR="$FIXTURE"
E2E_FAKE_CONFIG="$FAKE_CONFIG"

# Compute project hash (macOS-safe: resolves symlinks via pwd -P inside git repo)
PROJECT_HASH=$(_e2e_compute_hash "$FIXTURE")

# Create large code file (80+ lines) and small code file for cmm-nudge tests
python3 -c "
for i in range(85):
    print(f'def func_{i}(): pass')
" > "$FIXTURE/big_module.py"

echo 'x = 1' > "$FIXTURE/tiny.py"
echo '{"key": "value"}' > "$FIXTURE/config.json"

# Update trap to also clean up sentinel files
trap 'rm -rf "$TMPDIR_ROOT"; _e2e_cleanup_sentinels "$PROJECT_HASH"' EXIT

# Hook path variables pointing to INSTALLED hooks inside the fixture
SESSION_GATE="$FIXTURE/.claude/hooks/session-gate.sh"
CMM_NUDGE="$FIXTURE/.claude/hooks/cmm-nudge.sh"
CTX_ENFORCER="$FIXTURE/.claude/hooks/ctx-execute-enforcer.sh"

# ─── Section 4: Sentinel + session-gate blocking ───────────────────────
echo "=== Section 4: session-gate sentinel tests ==="

# --- Without CMM sentinel: Edit and Write should be blocked ---
_e2e_cleanup_sentinels "$PROJECT_HASH"

_e2e_assert_hook "$SESSION_GATE" "$(_e2e_tool_payload "Edit" '{"file_path":"/tmp/f","old_string":"a","new_string":"b"}')" 2 \
  "session-gate blocks Edit without CMM sentinel"

_e2e_assert_hook "$SESSION_GATE" "$(_e2e_tool_payload "Write" '{"file_path":"/tmp/f","content":"x"}')" 2 \
  "session-gate blocks Write without CMM sentinel"

# --- With CMM sentinel: Edit and Write should be allowed ---
_e2e_create_sentinels "$PROJECT_HASH"

_e2e_assert_hook "$SESSION_GATE" "$(_e2e_tool_payload "Edit" '{"file_path":"/tmp/f","old_string":"a","new_string":"b"}')" 0 \
  "session-gate allows Edit with CMM sentinel"

_e2e_assert_hook "$SESSION_GATE" "$(_e2e_tool_payload "Write" '{"file_path":"/tmp/f","content":"x"}')" 0 \
  "session-gate allows Write with CMM sentinel"

# --- Bypass tools: should pass even WITHOUT sentinel ---
_e2e_cleanup_sentinels "$PROJECT_HASH"

_e2e_assert_hook "$SESSION_GATE" "$(_e2e_tool_payload "Bash" '{"command":"echo hi"}')" 0 \
  "session-gate allows Bash bypass (no sentinel)"

_e2e_assert_hook "$SESSION_GATE" "$(_e2e_tool_payload "Read" '{"file_path":"/tmp/f"}')" 0 \
  "session-gate allows Read bypass (no sentinel)"

_e2e_assert_hook "$SESSION_GATE" "$(_e2e_tool_payload "Grep" '{"pattern":"foo"}')" 0 \
  "session-gate allows Grep bypass (no sentinel)"

_e2e_assert_hook "$SESSION_GATE" "$(_e2e_tool_payload "Glob" '{"pattern":"*.sh"}')" 0 \
  "session-gate allows Glob bypass (no sentinel)"

_e2e_assert_hook "$SESSION_GATE" "$(_e2e_tool_payload "Agent" '{"prompt":"hello"}')" 0 \
  "session-gate allows Agent bypass (no sentinel)"

_e2e_assert_hook "$SESSION_GATE" "$(_e2e_tool_payload "mcp__codebase-memory-mcp__search_graph" '{"name_pattern":".*"}')" 0 \
  "session-gate allows mcp__codebase-memory-mcp__search_graph bypass (no sentinel)"

echo ""

# ─── Section 5: cmm-nudge Read blocking ────────────────────────────────
echo "=== Section 5: cmm-nudge Read blocking ==="

# Ensure CMM sentinel exists (session-gate allows Read through; cmm-nudge evaluates it)
_e2e_create_sentinels "$PROJECT_HASH"

# Large code file (80+ lines, .py extension): blocked
_e2e_assert_hook "$CMM_NUDGE" "$(_e2e_read_payload "$FIXTURE/big_module.py")" 2 \
  "cmm-nudge blocks Read on large code file (big_module.py)"

# Small code file (<50 lines): allowed
_e2e_assert_hook "$CMM_NUDGE" "$(_e2e_read_payload "$FIXTURE/tiny.py")" 0 \
  "cmm-nudge allows Read on small code file (tiny.py)"

# Non-code extension (.json): allowed
_e2e_assert_hook "$CMM_NUDGE" "$(_e2e_read_payload "$FIXTURE/config.json")" 0 \
  "cmm-nudge allows Read on non-code file (config.json)"

# Targeted read with offset+limit (offset=1, limit=50): allowed
_e2e_assert_hook "$CMM_NUDGE" "$(_e2e_read_payload "$FIXTURE/big_module.py" 1 50)" 0 \
  "cmm-nudge allows targeted Read on large file (offset=1, limit=50)"

# Exempt basename (README.md): allowed
_e2e_assert_hook "$CMM_NUDGE" "$(_e2e_read_payload "$FIXTURE/README.md")" 0 \
  "cmm-nudge allows Read on exempt basename (README.md)"

echo ""

# ─── Section 6: ctx-execute-enforcer Bash blocking ─────────────────────
echo "=== Section 6: ctx-execute-enforcer Bash blocking ==="

# --- With all sentinels present (CMM + Context Mode + ctx-enforcer cache) ---
_e2e_create_sentinels "$PROJECT_HASH"

# Test runner: blocked
_e2e_assert_hook "$CTX_ENFORCER" "$(_e2e_bash_payload "npm test")" 2 \
  "ctx-enforcer blocks npm test (test runner)"

# Package install: blocked
_e2e_assert_hook "$CTX_ENFORCER" "$(_e2e_bash_payload "pip install requests")" 2 \
  "ctx-enforcer blocks pip install (package manager)"

# Git operation: allowed
_e2e_assert_hook "$CTX_ENFORCER" "$(_e2e_bash_payload "git status")" 0 \
  "ctx-enforcer allows git status"

# Filesystem mutation: allowed
_e2e_assert_hook "$CTX_ENFORCER" "$(_e2e_bash_payload "mkdir -p /tmp/foo")" 0 \
  "ctx-enforcer allows mkdir"

# ctx-exempt marker: allowed
_e2e_assert_hook "$CTX_ENFORCER" "$(_e2e_bash_payload "npm test # ctx-exempt")" 0 \
  "ctx-enforcer allows npm test with # ctx-exempt marker"

# --- Without Context Mode sentinel: no blocking (deadlock prevention) ---
_e2e_remove_ctx_sentinel "$PROJECT_HASH"

_e2e_assert_hook "$CTX_ENFORCER" "$(_e2e_bash_payload "npm test")" 0 \
  "ctx-enforcer allows npm test without Context Mode sentinel (deadlock prevention)"

# Restore sentinels for subsequent tests
_e2e_create_sentinels "$PROJECT_HASH"

echo ""

# ─── Section 7: Known Bypass Documentation ─────────────────────────────
echo "=== Section 7: Known Bypass Documentation ==="
echo "  (Tests that document enforcement gaps agents exploit in practice)"

# Ensure sentinels are present
_e2e_create_sentinels "$PROJECT_HASH"

# --- cmm-nudge bypass via targeted Read ---
# Baseline: full Read on big_module.py is blocked
_e2e_assert_hook "$CMM_NUDGE" "$(_e2e_read_payload "$FIXTURE/big_module.py")" 2 \
  "cmm-nudge blocks full Read on big_module.py (baseline)"

# KNOWN BYPASS: targeted Read with offset=0, limit=100 is allowed through
_e2e_assert_hook "$CMM_NUDGE" "$(_e2e_read_payload "$FIXTURE/big_module.py" 0 100)" 0 \
  "KNOWN-BYPASS: cmm-nudge allows targeted Read (offset=0, limit=100) on large code file"

# KNOWN BYPASS: targeted Read with offset=0, limit=50 is allowed through
_e2e_assert_hook "$CMM_NUDGE" "$(_e2e_read_payload "$FIXTURE/big_module.py" 0 50)" 0 \
  "KNOWN-BYPASS: cmm-nudge allows targeted Read (offset=0, limit=50) on large code file"

# KNOWN GAP: Agents bypass cmm-nudge by adding offset/limit to Read calls on large code files
# instead of switching to CMM tools (search_graph, get_code_snippet). See future phase: Harden CMM Nudge Hook

# --- ctx-execute-enforcer bypass via allowlisted commands ---
# KNOWN BYPASS: ls is not in any block list, falls through to default allow
_e2e_assert_hook "$CTX_ENFORCER" "$(_e2e_bash_payload "ls -la /tmp")" 0 \
  "KNOWN-BYPASS: ctx-enforcer allows ls (not in block list)"

# KNOWN BYPASS: git log is explicitly allowlisted
_e2e_assert_hook "$CTX_ENFORCER" "$(_e2e_bash_payload "git log --oneline -5")" 0 \
  "KNOWN-BYPASS: ctx-enforcer allows git log (explicitly allowlisted)"

# Document actual behavior: cat falls through to default allow (not blocked)
_e2e_assert_hook "$CTX_ENFORCER" "$(_e2e_bash_payload "cat /etc/hosts")" 0 \
  "KNOWN-BYPASS: ctx-enforcer allows cat (falls through to default allow)"

# Document actual behavior: echo is explicitly allowlisted in short queries
_e2e_assert_hook "$CTX_ENFORCER" "$(_e2e_bash_payload "echo hello")" 0 \
  "KNOWN-BYPASS: ctx-enforcer allows echo (explicitly allowlisted)"

# KNOWN GAP: Most agent Bash usage (ls, git, mkdir) falls within the allowlist
# Only test runners (npm test, pytest) and package managers (pip install) are actually blocked

echo ""

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
