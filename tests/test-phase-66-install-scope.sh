#!/bin/bash
# test-phase-66-install-scope.sh — PROJECT-SCOPE-ONLY regression guard for
# agent-override-generate.sh in setup.sh.
#
# Asserts by scoping greps to install_project vs install_global function bodies:
#   1. install_project body DOES reference/register agent-override-generate.sh
#   2. install_global body does NOT reference agent-override-generate.sh
#   3. install_global body does NOT write .claude/agents/ (no mkdir/copy there)
#   4. The only agents/*.md copy/install loop is in install_project
#   5. Whole-file sanity: agent-override-generate.sh in setup.sh
#   6. install_project installs delta files into .claude/agents-delta/
#   7. install_global does NOT install agents-delta files
#   8. setup.sh --project in scratch project: .claude/agents-delta/ has all 7 delta files
#      AND .claude/hooks/lib/{project-root.sh,vbw-source.sh} exist
#   9. Hook exits 0 (clean no-op) when no VBW source is resolvable
#  10. Hook exits 0 (clean no-op) when delta files are absent
#  11. Hook reads delta from .claude/agents-delta/ (installed path) when both locations present
#
# Rationale: deterministic guarantee that agent generation is project-mode-only.
# A project that never ran `setup.sh --project` gets no agent generation, and
# global install never touches VBW agents.
#
# Usage: bash tests/test-phase-66-install-scope.sh
# Exit: 0 = all pass, 1 = any failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
cd "$REPO_ROOT"

SETUP="$REPO_ROOT/setup.sh"
PASS=0; FAIL=0

_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

# -----------------------------------------------------------------------
# Extract line ranges for install_project and install_global function bodies.
# Strategy: find the line where each function is declared (^function_name()),
# then find the next top-level function or EOF as the end boundary.
# -----------------------------------------------------------------------
total_lines=$(wc -l <"$SETUP" | tr -d ' ')

# Find install_project start — strip any trailing whitespace/CR
ip_start=$(grep -n '^install_project()' "$SETUP" | head -1 | cut -d: -f1 | tr -d '[:space:]')
# Find install_global start
ig_start=$(grep -n '^install_global()' "$SETUP" | head -1 | cut -d: -f1 | tr -d '[:space:]')

if [ -z "${ip_start:-}" ] || [ -z "${ig_start:-}" ]; then
    echo "FAIL: Could not locate install_project() or install_global() in setup.sh"
    exit 1
fi

# install_project body: from its declaration to one line before install_global
# (whichever comes first). Handle either ordering.
if [ "$ip_start" -lt "$ig_start" ]; then
    ip_end=$((ig_start - 1))
    ig_end=$total_lines
else
    ig_end=$((ip_start - 1))
    ip_end=$total_lines
fi

# Extract bodies using awk
_body_of() {
    local start="$1" end="$2"
    awk "NR>=$start && NR<=$end" "$SETUP"
}

# NOTE: match against these bodies with `grep -q PAT <<<"$body"`, never
# `echo "$body" | grep -q PAT`. Under `set -o pipefail` (set above), grep -q
# exits on its first match and closes the pipe while echo is still writing;
# echo takes SIGPIPE and the pipeline reports 141, so a SUCCESSFUL match is
# read as a failure. It is invisible while the body fits in the 64KB pipe
# buffer and starts flapping the moment setup.sh grows past it — which is
# exactly how it was found (install_project body reached 68,097 bytes).

ip_body=$(_body_of "$ip_start" "$ip_end")
ig_body=$(_body_of "$ig_start" "$ig_end")

echo ""
echo "=== Phase 66: install-scope assertions (setup.sh) ==="
echo "install_project: lines $ip_start to $ip_end"
echo "install_global:  lines $ig_start to $ig_end"
echo ""

# -----------------------------------------------------------------------
# 1. install_project body DOES register agent-override-generate.sh
# -----------------------------------------------------------------------
echo "--- 1: install_project registers agent-override-generate.sh ---"
if grep -q 'agent-override-generate' <<<"$ip_body"; then
    _pass "install_project: references agent-override-generate.sh"
else
    _fail "install_project: references agent-override-generate.sh" \
        "not found in install_project body"
fi

# Also verify it's in the SessionStart context (hook registration)
if grep -qE 'agent-override-generate|SessionStart' <<<"$ip_body"; then
    _pass "install_project: SessionStart or agent-override-generate registration present"
else
    _fail "install_project: SessionStart or agent-override-generate registration present" \
        "neither SessionStart nor agent-override-generate found in install_project"
fi

# -----------------------------------------------------------------------
# 2. install_global body does NOT reference agent-override-generate.sh
# -----------------------------------------------------------------------
echo "--- 2: install_global does NOT reference agent-override-generate.sh ---"
if grep -q 'agent-override-generate' <<<"$ig_body"; then
    _fail "install_global: no agent-override-generate reference" \
        "unexpected agent-override-generate found in install_global"
else
    _pass "install_global: no agent-override-generate reference"
fi

# -----------------------------------------------------------------------
# 3. install_global body does NOT write to .claude/agents/
#    (no .claude/agents mkdir or copy in that function)
# -----------------------------------------------------------------------
echo "--- 3: install_global does NOT write .claude/agents/ ---"
if grep -qE '\.claude/agents' <<<"$ig_body"; then
    _fail "install_global: no .claude/agents write" \
        "unexpected .claude/agents reference found in install_global"
else
    _pass "install_global: no .claude/agents reference"
fi

if grep -qE 'agents/\*\.md|agents/vbw' <<<"$ig_body"; then
    _fail "install_global: no agents/*.md copy loop" \
        "unexpected agents/*.md or agents/vbw reference in install_global"
else
    _pass "install_global: no agents/*.md copy loop"
fi

# -----------------------------------------------------------------------
# 4. The only agents/*.md install/copy loop lives in install_project
# -----------------------------------------------------------------------
echo "--- 4: agents/ copy/install loop only in install_project ---"

# Check install_project has the agent install section
if grep -qE '\.claude/agents|agent-override-generate|agents/.*\.md' <<<"$ip_body"; then
    _pass "install_project: has agent install section"
else
    _fail "install_project: has agent install section" \
        "no .claude/agents or agent-override-generate in install_project body"
fi

# Confirm global scope has zero agent copy operations
if grep -qE '\.claude/agents|agents/\*\.md' <<<"$ig_body"; then
    _fail "install_global: zero .claude/agents or agents/*.md operations" \
        "unexpected match found in install_global body"
else
    _pass "install_global: zero .claude/agents or agents/*.md operations"
fi

# -----------------------------------------------------------------------
# 5. Whole-file sanity: agent-override-generate.sh referenced in setup.sh at all
# -----------------------------------------------------------------------
echo "--- 5: sanity — agent-override-generate.sh appears in setup.sh ---"
total_refs=$(grep -c 'agent-override-generate' "$SETUP" 2>/dev/null || echo 0)
if [ "$total_refs" -ge 1 ]; then
    _pass "setup.sh: agent-override-generate.sh referenced at least once (count=$total_refs)"
else
    _fail "setup.sh: agent-override-generate.sh referenced at least once" \
        "zero references — hook may not be registered"
fi

# -----------------------------------------------------------------------
# 6. install_project installs delta files into .claude/agents-delta/
# -----------------------------------------------------------------------
echo "--- 6: install_project installs .claude/agents-delta/ ---"
if grep -q 'agents-delta' <<<"$ip_body"; then
    _pass "install_project: references agents-delta install"
else
    _fail "install_project: references agents-delta install" \
        "agents-delta not found in install_project body"
fi

# -----------------------------------------------------------------------
# 7. install_global does NOT install agents-delta
# -----------------------------------------------------------------------
echo "--- 7: install_global does NOT reference agents-delta ---"
if grep -q 'agents-delta' <<<"$ig_body"; then
    _fail "install_global: no agents-delta reference" \
        "unexpected agents-delta found in install_global body"
else
    _pass "install_global: no agents-delta reference"
fi

# -----------------------------------------------------------------------
# 8. setup.sh --project WITH VBW installed (marketplace): agents-delta + lib files
# -----------------------------------------------------------------------
# VBW delta injection is gated on VBW being installed as a plugin. Set up a fake
# marketplace VBW via CLAUDE_CONFIG_DIR so the gate resolves "available"
# deterministically (independent of the test machine's ambient VBW state).
echo "--- 8: setup.sh --project installs .claude/agents-delta/ + lib files (VBW present) ---"
TMPROOT8=$(mktemp -d /tmp/test-phase-66-scope-XXXXXX)
trap 'rm -rf "$TMPROOT8"' EXIT
SCRATCH8="$TMPROOT8/proj"
FAKE_CFG8="$TMPROOT8/cfg"
MKT8="vbw-marketplace"; VBWVER8="1.99.0"
FAKE_VBW8="$FAKE_CFG8/plugins/cache/$MKT8/vbw/$VBWVER8"
mkdir -p "$SCRATCH8" "$FAKE_VBW8/agents" "$FAKE_CFG8/plugins"
(cd "$SCRATCH8" && git init -q && git commit --allow-empty -q -m "init") >/dev/null 2>&1
cat >"$FAKE_CFG8/plugins/installed_plugins.json" <<JSON
{"version":2,"plugins":{"vbw@vbw-marketplace":[{"installPath":"$FAKE_VBW8","version":"$VBWVER8","scope":"user"}]},"enabledPlugins":{"vbw@vbw-marketplace":true}}
JSON
(
  cd "$SCRATCH8"
  CLAUDE_CONFIG_DIR="$FAKE_CFG8" bash "$REPO_ROOT/setup.sh" --project --yes --skip-statusline --skip-mcp-check --no-migrate 2>&1
) >/dev/null 2>&1 || true

_delta_ok=1
for _ag in architect debugger dev docs lead qa scout; do
    if [ ! -f "$SCRATCH8/.claude/agents-delta/vbw-${_ag}.md" ]; then
        _delta_ok=0
        break
    fi
done
if [ "$_delta_ok" -eq 1 ]; then
    _pass "setup.sh --project (VBW present): all 7 .claude/agents-delta/vbw-*.md installed"
else
    _fail "setup.sh --project (VBW present): all 7 .claude/agents-delta/vbw-*.md installed" \
        "one or more delta files missing in $SCRATCH8/.claude/agents-delta/"
fi

if [ -f "$SCRATCH8/.claude/hooks/lib/project-root.sh" ] && [ -f "$SCRATCH8/.claude/hooks/lib/vbw-source.sh" ]; then
    _pass "setup.sh --project: .claude/hooks/lib/{project-root.sh,vbw-source.sh} installed"
else
    _fail "setup.sh --project: .claude/hooks/lib/{project-root.sh,vbw-source.sh} installed" \
        "lib files missing in $SCRATCH8/.claude/hooks/lib/"
fi

# 8b. setup.sh --project WITHOUT VBW: no agents-delta injection; stale moved aside
# -----------------------------------------------------------------------
echo "--- 8b: setup.sh --project with VBW absent skips delta injection + moves stale aside ---"
TMPROOT8B=$(mktemp -d /tmp/test-phase-66-scope-XXXXXX)
SCRATCH8B="$TMPROOT8B/proj"
FAKE_CFG8B="$TMPROOT8B/cfg"
mkdir -p "$SCRATCH8B" "$FAKE_CFG8B/plugins"
echo '{"version":2,"plugins":{},"enabledPlugins":{}}' > "$FAKE_CFG8B/plugins/installed_plugins.json"
(cd "$SCRATCH8B" && git init -q && git commit --allow-empty -q -m "init") >/dev/null 2>&1
# Seed a stale generated override from a hypothetical prior VBW-enabled install
mkdir -p "$SCRATCH8B/.claude/agents"
echo "stale" > "$SCRATCH8B/.claude/agents/vbw-dev.md"
(
  cd "$SCRATCH8B"
  # CLAUDE_CONFIG_DIR → no plugins; HOME override neutralizes any ~/Sources dev-checkout
  CLAUDE_CONFIG_DIR="$FAKE_CFG8B" HOME="$TMPROOT8B" bash "$REPO_ROOT/setup.sh" --project --yes --skip-statusline --skip-mcp-check --no-migrate 2>&1
) >/dev/null 2>&1 || true
if [ ! -e "$SCRATCH8B/.claude/agents-delta/vbw-dev.md" ]; then
    _pass "VBW absent: no vbw deltas injected into .claude/agents-delta/"
else
    _fail "VBW absent: no vbw deltas injected into .claude/agents-delta/" \
        "unexpected vbw delta present in $SCRATCH8B/.claude/agents-delta/"
fi
if [ ! -e "$SCRATCH8B/.claude/agents/vbw-dev.md" ] && \
   [ -e "$SCRATCH8B/.claude/.cmm-setup/vbw-agents.bak/agents/vbw-dev.md" ]; then
    _pass "VBW absent: stale override moved aside to .cmm-setup/vbw-agents.bak/"
else
    _fail "VBW absent: stale override moved aside to .cmm-setup/vbw-agents.bak/" \
        "stale vbw-dev.md not moved as expected in $SCRATCH8B"
fi
# Zero-VBW footprint: the two VBW-only files are NOT installed, and the generator
# is NOT registered in settings.json.
if [ ! -e "$SCRATCH8B/.claude/hooks/lib/vbw-source.sh" ]; then
    _pass "VBW absent: vbw-source.sh not installed (zero footprint)"
else
    _fail "VBW absent: vbw-source.sh not installed (zero footprint)" "vbw-source.sh present in $SCRATCH8B"
fi
if [ ! -e "$SCRATCH8B/.claude/hooks/agent-override-generate.sh" ]; then
    _pass "VBW absent: agent-override-generate.sh not installed (zero footprint)"
else
    _fail "VBW absent: agent-override-generate.sh not installed (zero footprint)" "generate hook present in $SCRATCH8B"
fi
if [ -f "$SCRATCH8B/.claude/settings.json" ] && grep -q 'agent-override-generate' "$SCRATCH8B/.claude/settings.json"; then
    _fail "VBW absent: no agent-override-generate SessionStart registration" "registration present in settings.json"
else
    _pass "VBW absent: no agent-override-generate SessionStart registration"
fi
# Non-VBW libs/hooks are still installed (proves we gate ONLY the VBW files).
if [ -e "$SCRATCH8B/.claude/hooks/lib/project-root.sh" ]; then
    _pass "VBW absent: non-VBW lib project-root.sh still installed"
else
    _fail "VBW absent: non-VBW lib project-root.sh still installed" "project-root.sh missing"
fi
rm -rf "$TMPROOT8B"

# -----------------------------------------------------------------------
# 9. Hook exits 0 when no VBW source resolvable (no plugins installed)
# -----------------------------------------------------------------------
echo "--- 9: hook exits 0 (clean no-op) when VBW absent ---"
TMPROOT9=$(mktemp -d /tmp/test-phase-66-scope-XXXXXX)
SCRATCH9="$TMPROOT9/proj"
mkdir -p "$SCRATCH9/.claude/hooks/lib"
mkdir -p "$SCRATCH9/.claude/agents-delta"
mkdir -p "$SCRATCH9/.claude/agents"
(cd "$SCRATCH9" && git init -q && git commit --allow-empty -q -m "init") >/dev/null 2>&1
cp "$REPO_ROOT/hooks/lib/project-root.sh" "$SCRATCH9/.claude/hooks/lib/"
cp "$REPO_ROOT/hooks/lib/vbw-source.sh"   "$SCRATCH9/.claude/hooks/lib/"
# Copy delta files so delta-absent isn't the reason for skip
for _ag in architect debugger dev docs lead qa scout; do
    cp "$REPO_ROOT/agents/vbw-${_ag}.md" "$SCRATCH9/.claude/agents-delta/"
done
cp "$REPO_ROOT/hooks/project/agent-override-generate.sh" "$SCRATCH9/.claude/hooks/"
chmod +x "$SCRATCH9/.claude/hooks/agent-override-generate.sh"
# Point CLAUDE_CONFIG_DIR to a dir with no plugins
FAKE_CFG9="$TMPROOT9/cfg"
mkdir -p "$FAKE_CFG9/plugins"
echo '{"version":2,"plugins":{},"enabledPlugins":{}}' > "$FAKE_CFG9/plugins/installed_plugins.json"
_exit_code=0
(cd "$SCRATCH9" && CLAUDE_CONFIG_DIR="$FAKE_CFG9" bash ".claude/hooks/agent-override-generate.sh") >/dev/null 2>&1 || _exit_code=$?
rm -rf "$TMPROOT9"
if [ "$_exit_code" -eq 0 ]; then
    _pass "hook exits 0 when VBW absent (no VBW in plugins)"
else
    _fail "hook exits 0 when VBW absent (no VBW in plugins)" \
        "hook exited $_exit_code — expected 0"
fi

# -----------------------------------------------------------------------
# 10. Hook exits 0 when delta files are absent (no agents-delta, no repo agents/)
# -----------------------------------------------------------------------
echo "--- 10: hook exits 0 (clean no-op) when delta files absent ---"
TMPROOT10=$(mktemp -d /tmp/test-phase-66-scope-XXXXXX)
SCRATCH10="$TMPROOT10/proj"
FAKE_VBW10="$TMPROOT10/vbw/1.0.0"
FAKE_CFG10="$TMPROOT10/cfg"
mkdir -p "$SCRATCH10/.claude/hooks/lib"
mkdir -p "$SCRATCH10/.claude/agents"
mkdir -p "$FAKE_VBW10/agents"
mkdir -p "$FAKE_CFG10/plugins"
(cd "$SCRATCH10" && git init -q && git commit --allow-empty -q -m "init") >/dev/null 2>&1
# Create a minimal VBW agent file so VBW resolves
echo '---
name: vbw-architect
description: test
---
body' > "$FAKE_VBW10/agents/vbw-architect.md"
cat >"$FAKE_CFG10/plugins/installed_plugins.json" <<JSON
{"version":2,"plugins":{"vbw@vbw-marketplace":[{"installPath":"$FAKE_VBW10","version":"1.0.0","scope":"user"}]},"enabledPlugins":{"vbw@vbw-marketplace":true}}
JSON
cp "$REPO_ROOT/hooks/lib/project-root.sh" "$SCRATCH10/.claude/hooks/lib/"
cp "$REPO_ROOT/hooks/lib/vbw-source.sh"   "$SCRATCH10/.claude/hooks/lib/"
cp "$REPO_ROOT/hooks/project/agent-override-generate.sh" "$SCRATCH10/.claude/hooks/"
chmod +x "$SCRATCH10/.claude/hooks/agent-override-generate.sh"
# No .claude/agents-delta/ and hook runs from .claude/hooks/ which has no ../../agents/
_exit_code=0
(cd "$SCRATCH10" && CLAUDE_CONFIG_DIR="$FAKE_CFG10" bash ".claude/hooks/agent-override-generate.sh") >/dev/null 2>&1 || _exit_code=$?
rm -rf "$TMPROOT10"
if [ "$_exit_code" -eq 0 ]; then
    _pass "hook exits 0 when delta files absent"
else
    _fail "hook exits 0 when delta files absent" \
        "hook exited $_exit_code — expected 0"
fi

# -----------------------------------------------------------------------
# 11. Hook reads delta from .claude/agents-delta/ (installed path) when present
# -----------------------------------------------------------------------
echo "--- 11: hook reads delta from .claude/agents-delta/ (installed path) ---"
TMPROOT11=$(mktemp -d /tmp/test-phase-66-scope-XXXXXX)
SCRATCH11="$TMPROOT11/proj"
FAKE_VBW11="$TMPROOT11/vbw/2.0.0"
FAKE_CFG11="$TMPROOT11/cfg"
mkdir -p "$SCRATCH11/.claude/hooks/lib"
mkdir -p "$SCRATCH11/.claude/agents"
mkdir -p "$SCRATCH11/.claude/agents-delta"
mkdir -p "$FAKE_VBW11/agents"
mkdir -p "$FAKE_CFG11/plugins"
(cd "$SCRATCH11" && git init -q && git commit --allow-empty -q -m "init") >/dev/null 2>&1
# Create minimal VBW base files for all 7 agents
for _ag in architect debugger dev docs lead qa scout; do
    cat > "$FAKE_VBW11/agents/vbw-${_ag}.md" <<VBWEOF
---
name: vbw-${_ag}
description: test base
model: claude-opus-4-5
---
base body
VBWEOF
done
cat >"$FAKE_CFG11/plugins/installed_plugins.json" <<JSON
{"version":2,"plugins":{"vbw@vbw-marketplace":[{"installPath":"$FAKE_VBW11","version":"2.0.0","scope":"user"}]},"enabledPlugins":{"vbw@vbw-marketplace":true}}
JSON
# Install delta files from repo into .claude/agents-delta/
for _ag in architect debugger dev docs lead qa scout; do
    cp "$REPO_ROOT/agents/vbw-${_ag}.md" "$SCRATCH11/.claude/agents-delta/"
done
cp "$REPO_ROOT/hooks/lib/project-root.sh" "$SCRATCH11/.claude/hooks/lib/"
cp "$REPO_ROOT/hooks/lib/vbw-source.sh"   "$SCRATCH11/.claude/hooks/lib/"
cp "$REPO_ROOT/hooks/project/agent-override-generate.sh" "$SCRATCH11/.claude/hooks/"
chmod +x "$SCRATCH11/.claude/hooks/agent-override-generate.sh"
# Run from inside the scratch project so project-root.sh detects it as PROJECT_ROOT
# (project-root.sh resolves from pwd via git rev-parse)
_exit_code=0
(cd "$SCRATCH11" && CLAUDE_CONFIG_DIR="$FAKE_CFG11" bash ".claude/hooks/agent-override-generate.sh") >/dev/null 2>&1 || _exit_code=$?
# Verify: at least one .claude/agents/vbw-*.md was generated using the installed delta
_generated_count=0
for _ag in architect debugger dev docs lead qa scout; do
    [ -f "$SCRATCH11/.claude/agents/vbw-${_ag}.md" ] && _generated_count=$((_generated_count+1))
done
rm -rf "$TMPROOT11"
if [ "$_exit_code" -eq 0 ] && [ "$_generated_count" -gt 0 ]; then
    _pass "hook reads from .claude/agents-delta/ and generates overrides (exit=0, generated=$_generated_count agents)"
else
    _fail "hook reads from .claude/agents-delta/ and generates overrides" \
        "exit=$_exit_code generated=$_generated_count (expected exit=0, ≥1 agent)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
