#!/bin/bash
# test-agent-hook-overrides.sh — Verify agent override files have correct CMM hook registrations
# Usage: bash tests/test-agent-hook-overrides.sh
# Exit: 0 = all pass, 1 = any failure
#
# Designed for extensibility: add new agents to the AGENTS array and their
# expected hooks to _must_have_hooks / _must_not_have_hooks. Phase 37 agents
# (architect, lead, docs) can be added by uncommenting the relevant lines.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
AGENTS_DIR="$SCRIPT_DIR/../agents"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# ─── Agent Registry ──────────────────────────────────────────────────────
# Each agent listed here gets the full test suite. To add Phase 37 agents,
# uncomment the lines below and add their hook expectations to _must_have/_must_not_have.
AGENTS=(
  vbw-dev
  vbw-scout
  vbw-qa
  vbw-debugger
  # Phase 37:
  vbw-architect
  vbw-lead
  vbw-docs
)

# ─── Hook Expectations ───────────────────────────────────────────────────
# Returns space-separated list of hooks an agent MUST have.
# Logic: cmm-nudge (all with Read), ctx-execute-enforcer (agents with Bash,
# except scout), reindex-after-commit (agents that commit), track-cmm-calls
# (all), cmm-query-stale-advisory (all).
_must_have_hooks() {
  local agent="$1"
  local hooks="cmm-nudge.sh track-cmm-calls.sh cmm-query-stale-advisory.sh"
  case "$agent" in
    vbw-dev)       hooks="$hooks ctx-execute-enforcer.sh reindex-after-commit.sh" ;;
    vbw-debugger)  hooks="$hooks ctx-execute-enforcer.sh reindex-after-commit.sh" ;;
    vbw-qa)        hooks="$hooks ctx-execute-enforcer.sh" ;;
    vbw-lead)      hooks="$hooks ctx-execute-enforcer.sh" ;;
    vbw-docs)      hooks="$hooks ctx-execute-enforcer.sh" ;;
    vbw-scout)     ;; # No Bash — no ctx-execute-enforcer or reindex
    vbw-architect) ;; # No Bash — no ctx-execute-enforcer or reindex
  esac
  echo "$hooks"
}

# Returns space-separated list of hooks an agent MUST NOT have.
_must_not_have_hooks() {
  local agent="$1"
  # Parent-only hooks — never in any agent override
  local hooks="session-gate.sh subagent-cmm-startup.sh cmm-session-start.sh agent-cmm-gate.sh"
  case "$agent" in
    vbw-scout)     hooks="$hooks ctx-execute-enforcer.sh reindex-after-commit.sh" ;;
    vbw-architect) hooks="$hooks ctx-execute-enforcer.sh reindex-after-commit.sh" ;;
    vbw-qa)        hooks="$hooks reindex-after-commit.sh" ;;
    vbw-lead)      hooks="$hooks reindex-after-commit.sh" ;;
    vbw-docs)      hooks="$hooks reindex-after-commit.sh" ;;
  esac
  echo "$hooks"
}

# ─── Test: Existence ─────────────────────────────────────────────────────
echo "=== Existence ==="
for agent in "${AGENTS[@]}"; do
  if [ -f "$AGENTS_DIR/$agent.md" ]; then
    pass "$agent.md exists"
  else
    fail "$agent.md missing"
  fi
done

# Verify project-specific dev.md in .claude/agents/ is not clobbered
INSTALLED_DIR="$SCRIPT_DIR/../.claude/agents"
if [ -f "$INSTALLED_DIR/dev.md" ]; then
  if grep -q '^name: dev$' "$INSTALLED_DIR/dev.md"; then
    pass "dev.md exists with name: dev (not overwritten)"
  else
    fail "dev.md exists but name: field is wrong"
  fi
else
  pass "dev.md not in agents/ source (expected - it is a project-specific installed agent)"
fi

# ─── Test: Frontmatter Structure ─────────────────────────────────────────
echo ""
echo "=== Frontmatter Structure ==="
for agent in "${AGENTS[@]}"; do
  file="$AGENTS_DIR/$agent.md"
  [ ! -f "$file" ] && continue

  # Starts with ---
  if head -1 "$file" | grep -q '^---$'; then
    pass "$agent.md starts with ---"
  else
    fail "$agent.md does not start with ---"
  fi

  # Has closing --- (second occurrence)
  fm_end=$(awk 'NR>1 && /^---$/{print NR; exit}' "$file")
  if [ -n "$fm_end" ]; then
    pass "$agent.md has closing --- at line $fm_end"
  else
    fail "$agent.md missing closing --- delimiter"
  fi

  # Required frontmatter fields
  for field in name description model hooks; do
    if awk "NR>1 && NR<${fm_end:-999}" "$file" | grep -q "^${field}:"; then
      pass "$agent.md has $field: in frontmatter"
    else
      fail "$agent.md missing $field: in frontmatter"
    fi
  done
done

# ─── Test: Name Field Matches Filename ────────────────────────────────────
echo ""
echo "=== Name Field ==="
for agent in "${AGENTS[@]}"; do
  file="$AGENTS_DIR/$agent.md"
  [ ! -f "$file" ] && continue
  name=$(grep -m1 '^name:' "$file" | sed 's/^name: *//')
  if [ "$name" = "$agent" ]; then
    pass "$agent.md name: $name"
  else
    fail "$agent.md name: '$name' != expected '$agent'"
  fi
done

# ─── Test: Hook Presence (positive) ──────────────────────────────────────
echo ""
echo "=== Hook Presence ==="
for agent in "${AGENTS[@]}"; do
  file="$AGENTS_DIR/$agent.md"
  [ ! -f "$file" ] && continue
  for hook in $(_must_have_hooks "$agent"); do
    if grep -q "$hook" "$file"; then
      pass "$agent.md has $hook"
    else
      fail "$agent.md missing $hook"
    fi
  done
done

# ─── Test: Hook Absence (negative) ───────────────────────────────────────
echo ""
echo "=== Hook Absence ==="
for agent in "${AGENTS[@]}"; do
  file="$AGENTS_DIR/$agent.md"
  [ ! -f "$file" ] && continue
  for hook in $(_must_not_have_hooks "$agent"); do
    if grep -q "$hook" "$file"; then
      fail "$agent.md should NOT have $hook"
    else
      pass "$agent.md correctly omits $hook"
    fi
  done
done

# ─── Test: SUBAGENT_COMMIT Marker ────────────────────────────────────────
echo ""
echo "=== SUBAGENT_COMMIT Marker ==="
for agent in "${AGENTS[@]}"; do
  file="$AGENTS_DIR/$agent.md"
  [ ! -f "$file" ] && continue
  has_marker=false
  grep -q 'SUBAGENT_COMMIT=1' "$file" && has_marker=true
  case "$agent" in
    vbw-dev|vbw-debugger)
      if $has_marker; then
        pass "$agent.md has SUBAGENT_COMMIT=1"
      else
        fail "$agent.md missing SUBAGENT_COMMIT=1"
      fi
      ;;
    *)
      if $has_marker; then
        fail "$agent.md should NOT have SUBAGENT_COMMIT=1"
      else
        pass "$agent.md correctly omits SUBAGENT_COMMIT=1"
      fi
      ;;
  esac
done

# ─── Test: Hook Path Conventions ─────────────────────────────────────────
echo ""
echo "=== Hook Path Conventions ==="
for agent in "${AGENTS[@]}"; do
  file="$AGENTS_DIR/$agent.md"
  [ ! -f "$file" ] && continue

  # All hook commands should use project-relative paths: bash .claude/hooks/
  bad_paths=$(grep -E 'command:.*hooks/' "$file" | grep -vE 'bash .claude/hooks/' || true)
  if [ -z "$bad_paths" ]; then
    pass "$agent.md all hook paths are project-relative (.claude/hooks/)"
  else
    fail "$agent.md has non-relative hook paths: $bad_paths"
  fi

  # No global paths (~/.claude/ or $CLAUDE_CONFIG_DIR or $HOME)
  if grep -E 'command:.*(~/\.claude/|\$CLAUDE_CONFIG_DIR|\$HOME)' "$file" >/dev/null 2>&1; then
    fail "$agent.md has global hook path references"
  else
    pass "$agent.md no global hook path references"
  fi
done

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
