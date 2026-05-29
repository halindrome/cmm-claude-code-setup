#!/bin/bash
# test-phase-62-mcp-grants.sh — Regression coverage for phase-62 MCP tool grants
#
# Asserts that:
#   (a) vbw-lead.md and vbw-debugger.md tools: lines include CMM and context-mode
#       MCP tool names (both plugin-form and legacy-form)
#   (b) vbw-docs.md and vbw-architect.md have disallowedTools: (not tools:) in frontmatter
#   (c) setup.sh allowlist writer block emits mcp__plugin_context-mode_context-mode__ctx_execute
#   (d) scoped Task grants (Task(vbw-dev), Task(vbw-debugger)) are preserved
#   (e) stale trace_call_path name is absent from all 4 agents
#
# Usage: bash tests/test-phase-62-mcp-grants.sh
# Exit:  0 = all pass, 1 = any failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

_pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

_assert() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    _pass "$desc"
  else
    _fail "$desc"
  fi
}

_grep_assert() {
  local desc="$1"
  local pattern="$2"
  local file="$3"
  if grep -q "$pattern" "$file"; then
    _pass "$desc"
  else
    _fail "$desc"
  fi
}

_grep_absent() {
  local desc="$1"
  local pattern="$2"
  local file="$3"
  if grep -q "$pattern" "$file"; then
    _fail "$desc"
  else
    _pass "$desc"
  fi
}

cd "$REPO_ROOT"

echo ""
echo "=== Phase 62: MCP tool grants for override agents ==="
echo ""

# --- vbw-lead.md: tools: allowlist with CMM tools ---
echo "--- vbw-lead.md: CMM tools in allowlist ---"
_grep_assert "vbw-lead has mcp__codebase-memory-mcp__get_architecture" \
  "mcp__codebase-memory-mcp__get_architecture" "agents/vbw-lead.md"
_grep_assert "vbw-lead has mcp__codebase-memory-mcp__search_graph" \
  "mcp__codebase-memory-mcp__search_graph" "agents/vbw-lead.md"
_grep_assert "vbw-lead has mcp__codebase-memory-mcp__get_code_snippet" \
  "mcp__codebase-memory-mcp__get_code_snippet" "agents/vbw-lead.md"
_grep_assert "vbw-lead has mcp__codebase-memory-mcp__trace_path" \
  "mcp__codebase-memory-mcp__trace_path" "agents/vbw-lead.md"
_grep_assert "vbw-lead has plugin-form ctx_execute" \
  "mcp__plugin_context-mode_context-mode__ctx_execute" "agents/vbw-lead.md"
_grep_assert "vbw-lead has legacy ctx_execute" \
  "mcp__context-mode__ctx_execute" "agents/vbw-lead.md"
_grep_assert "vbw-lead preserves Task(vbw-dev) grant" \
  "Task(vbw-dev)" "agents/vbw-lead.md"
_grep_absent "vbw-lead has no stale trace_call_path" \
  "trace_call_path" "agents/vbw-lead.md"
_grep_absent "vbw-lead has no delete_project" \
  "delete_project" "agents/vbw-lead.md"

echo ""
echo "--- vbw-debugger.md: CMM tools in allowlist ---"
_grep_assert "vbw-debugger has mcp__codebase-memory-mcp__get_architecture" \
  "mcp__codebase-memory-mcp__get_architecture" "agents/vbw-debugger.md"
_grep_assert "vbw-debugger has mcp__codebase-memory-mcp__search_graph" \
  "mcp__codebase-memory-mcp__search_graph" "agents/vbw-debugger.md"
_grep_assert "vbw-debugger has plugin-form ctx_execute" \
  "mcp__plugin_context-mode_context-mode__ctx_execute" "agents/vbw-debugger.md"
_grep_assert "vbw-debugger has legacy ctx_execute" \
  "mcp__context-mode__ctx_execute" "agents/vbw-debugger.md"
_grep_assert "vbw-debugger preserves Task(vbw-debugger) grant" \
  "Task(vbw-debugger)" "agents/vbw-debugger.md"
_grep_absent "vbw-debugger has no stale trace_call_path" \
  "trace_call_path" "agents/vbw-debugger.md"
_grep_absent "vbw-debugger has no delete_project" \
  "delete_project" "agents/vbw-debugger.md"

echo ""
echo "--- vbw-docs.md: disallowedTools denylist form ---"
# Only check frontmatter region (first 20 lines)
_assert "vbw-docs has disallowedTools: in frontmatter" \
  bash -c "awk '/^---/{f++} f==1{print}' agents/vbw-docs.md | grep -q '^disallowedTools:'"
_assert "vbw-docs has no tools: in frontmatter" \
  bash -c "! awk '/^---/{f++} f==1{print}' agents/vbw-docs.md | grep -q '^tools:'"
_grep_assert "vbw-docs has disallowedTools: Task" \
  "disallowedTools: Task" "agents/vbw-docs.md"

echo ""
echo "--- vbw-architect.md: disallowedTools denylist form ---"
_assert "vbw-architect has disallowedTools: in frontmatter" \
  bash -c "awk '/^---/{f++} f==1{print}' agents/vbw-architect.md | grep -q '^disallowedTools:'"
_assert "vbw-architect has no tools: in frontmatter" \
  bash -c "! awk '/^---/{f++} f==1{print}' agents/vbw-architect.md | grep -q '^tools:'"
_grep_assert "vbw-architect has disallowedTools: Task" \
  "disallowedTools: Task" "agents/vbw-architect.md"

echo ""
echo "--- setup.sh: allowlist writer emits plugin-form ctx_execute ---"
_grep_assert "setup.sh writer block has mcp__plugin_context-mode_context-mode__ctx_execute" \
  "mcp__plugin_context-mode_context-mode__ctx_execute" "setup.sh"
_grep_assert "setup.sh writer block still has legacy mcp__context-mode__ctx_execute" \
  "mcp__context-mode__ctx_execute" "setup.sh"
_assert "setup.sh has no syntax errors" bash -n setup.sh

echo ""
echo "--- CHECKSUMS.sha256 verifies all agent files ---"
if shasum -a 256 -c CHECKSUMS.sha256 >/dev/null 2>&1; then
  _pass "shasum -a 256 -c CHECKSUMS.sha256 exits 0"
else
  _fail "CHECKSUMS.sha256 verification failed"
fi

agent_ok_count=$(shasum -a 256 -c CHECKSUMS.sha256 2>&1 | grep -cE 'agents/vbw-.*:.*OK')
if [ "$agent_ok_count" -ge 7 ]; then
  _pass "At least 7 agents/vbw-*.md entries verify OK in CHECKSUMS.sha256 (got $agent_ok_count)"
else
  _fail "Expected at least 7 agent entries OK, got $agent_ok_count"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
