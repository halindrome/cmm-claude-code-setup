#!/bin/bash
# test-uninstall.sh — verifies `setup.sh --uninstall` removes the stack precisely
# while preserving user-owned files, strips only our settings.json entries, backs
# up removed files, and leaves .mcp.json intact unless --purge-mcp is passed.
#
# Run: bash tests/test-uninstall.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$SCRIPT_DIR/setup.sh"
PASS=0
FAIL=0
_pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
_chk()  { if eval "$2"; then _pass "$1"; else _fail "$1"; fi; }

_seed_project() {
  # Populate a fake prior install into $1/.claude (+ .mcp.json at $1).
  local root="$1"
  mkdir -p "$root/.claude/hooks/lib" "$root/.claude/rules" \
           "$root/.claude/skills/cmm-rules" "$root/.claude/skills/my-skill" \
           "$root/.claude/agents" "$root/.claude/agents-delta" \
           "$root/.claude/tools" "$root/.claude/.cmm-setup"
  local h
  for h in session-gate.sh cmm-session-start.sh reindex-after-commit.sh statusline-cmm.sh; do
    echo '#!/bin/bash' > "$root/.claude/hooks/$h"
  done
  echo '#!/bin/bash' > "$root/.claude/hooks/lib/vbw-source.sh"
  echo '#!/bin/bash' > "$root/.claude/hooks/lib/project-root.sh"
  echo '#!/bin/bash' > "$root/.claude/hooks/my-custom-hook.sh"   # user hook — must survive
  echo ctx  > "$root/.claude/rules/ctx-rules.md"
  echo skill > "$root/.claude/skills/cmm-rules/SKILL.md"
  echo user  > "$root/.claude/skills/my-skill/SKILL.md"          # must survive
  local ag
  for ag in architect dev qa; do
    echo gen   > "$root/.claude/agents/vbw-$ag.md"
    echo delta > "$root/.claude/agents-delta/vbw-$ag.md"
  done
  echo user > "$root/.claude/agents/my-agent.md"                 # must survive
  echo metrics > "$root/.claude/tools/analyze-gate-blocks.py"
  cat > "$root/.claude/settings.json" <<'JSON'
{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash .claude/hooks/cmm-session-start.sh"}]}],"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"bash .claude/hooks/session-gate.sh"},{"type":"command","command":"bash .claude/hooks/my-custom-hook.sh"}]}]},"permissions":{"allow":["mcp__codebase-memory-mcp__search_graph","mcp__context-mode__ctx_execute","Bash(ls:*)"]},"statusLine":{"type":"command","command":"bash .claude/hooks/statusline-cmm.sh"}}
JSON
  echo '{"mcpServers":{"codebase-memory-mcp":{"command":"cmm"},"context-mode":{"command":"npx"},"other":{"command":"x"}}}' > "$root/.mcp.json"
}

# --- Test 1: real uninstall (project, keep mcp) ---
echo "--- Test 1: uninstall --project --yes (mcp kept) ---"
T1=$(mktemp -d); ( cd "$T1" && _seed_project "$T1" && bash "$SETUP" --uninstall --project --yes >/dev/null 2>&1 )
_chk "stack hook removed"                '[ ! -f "$T1/.claude/hooks/session-gate.sh" ]'
_chk "stack lib removed"                 '[ ! -f "$T1/.claude/hooks/lib/vbw-source.sh" ]'
_chk "user hook preserved"               '[ -f "$T1/.claude/hooks/my-custom-hook.sh" ]'
_chk "vbw generated override removed"     '[ ! -f "$T1/.claude/agents/vbw-dev.md" ]'
_chk "vbw delta removed"                 '[ ! -f "$T1/.claude/agents-delta/vbw-dev.md" ]'
_chk "user agent preserved"              '[ -f "$T1/.claude/agents/my-agent.md" ]'
_chk "our skill removed"                 '[ ! -f "$T1/.claude/skills/cmm-rules/SKILL.md" ]'
_chk "user skill preserved"              '[ -f "$T1/.claude/skills/my-skill/SKILL.md" ]'
_chk "metrics tool removed"              '[ ! -f "$T1/.claude/tools/analyze-gate-blocks.py" ]'
_chk "backup dir created"                'ls -d "$T1"/.claude/.cmm-setup-uninstall-* >/dev/null 2>&1'
_chk "our hook entry stripped"           '! grep -q session-gate.sh "$T1/.claude/settings.json"'
_chk "user hook entry preserved"         'grep -q my-custom-hook.sh "$T1/.claude/settings.json"'
_chk "cmm allowlist entry removed"       '! grep -q codebase-memory-mcp "$T1/.claude/settings.json"'
_chk "non-stack allow preserved"         'grep -q "Bash(ls" "$T1/.claude/settings.json"'
_chk "statusLine removed"                '! grep -q statusLine "$T1/.claude/settings.json"'
_chk "settings.json valid JSON"          'python3 -m json.tool "$T1/.claude/settings.json" >/dev/null 2>&1'
_chk ".mcp.json untouched (no purge)"    'grep -q codebase-memory-mcp "$T1/.mcp.json"'
rm -rf "$T1"

# --- Test 2: --purge-mcp removes MCP entries, preserves others ---
echo "--- Test 2: uninstall --project --purge-mcp ---"
T2=$(mktemp -d); ( cd "$T2" && _seed_project "$T2" && bash "$SETUP" --uninstall --project --purge-mcp --yes >/dev/null 2>&1 )
_chk "cmm removed from .mcp.json"        '! grep -q codebase-memory-mcp "$T2/.mcp.json"'
_chk "context-mode removed"              '! grep -q context-mode "$T2/.mcp.json"'
_chk "unrelated server preserved"        'grep -q other "$T2/.mcp.json"'
_chk ".mcp.json valid JSON"              'python3 -m json.tool "$T2/.mcp.json" >/dev/null 2>&1'
rm -rf "$T2"

# --- Test 3: missing scope errors out ---
echo "--- Test 3: --uninstall without scope ---"
bash "$SETUP" --uninstall >/tmp/_uninstall_noscope 2>&1; EC=$?
_chk "exits non-zero"                    '[ "$EC" -ne 0 ]'
_chk "prints scope-required message"     'grep -q "requires a scope" /tmp/_uninstall_noscope'
rm -f /tmp/_uninstall_noscope

# --- Test 4: dry-run mutates nothing ---
echo "--- Test 4: --uninstall --dry-run ---"
T4=$(mktemp -d); _seed_project "$T4"
BEFORE=$(cd "$T4" && find .claude -type f | sort | xargs md5 2>/dev/null | md5)
( cd "$T4" && bash "$SETUP" --uninstall --project --dry-run --yes >/tmp/_uninstall_dry 2>&1 )
AFTER=$(cd "$T4" && find .claude -type f | sort | xargs md5 2>/dev/null | md5)
_chk "filesystem unchanged"              '[ "$BEFORE" = "$AFTER" ]'
_chk "prints Would remove"               'grep -qi "would remove" /tmp/_uninstall_dry'
rm -rf "$T4"; rm -f /tmp/_uninstall_dry

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
