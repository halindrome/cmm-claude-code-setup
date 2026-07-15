#!/bin/bash
# test-global-allowlist.sh — verifies the scope-aware tool allowlist:
#   - --global writes the CMM (+ context-mode) allowlist to GLOBAL settings.json
#   - policy "complete minus destructive": delete_project / ctx_purge / ctx_upgrade
#     excluded; ctx_doctor / ctx_insight included; both registration forms present
#   - --skip-context-mode omits the context-mode tools
#   - --all writes global and SKIPS the project allowlist (global covers it)
#   - --project with no global writes the project allowlist
#   - detection is merged: a global allowlist satisfies the project preflight
#
# Run: bash tests/test-global-allowlist.sh
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$REPO_ROOT/setup.sh"
PASS=0; FAIL=0
_pass(){ echo "PASS: $1"; PASS=$((PASS+1)); }
_fail(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }
_chk(){ if eval "$2"; then _pass "$1"; else _fail "$1"; fi; }

_cmm(){ python3 -c "import json;a=json.load(open('$1')).get('permissions',{}).get('allow',[]);print(sum(1 for t in a if t.startswith('mcp__codebase-memory-mcp__')))" 2>/dev/null || echo -1; }
_ctx(){ python3 -c "import json;a=json.load(open('$1')).get('permissions',{}).get('allow',[]);print(sum(1 for t in a if 'context-mode' in t))" 2>/dev/null || echo -1; }
_has(){ python3 -c "import json,sys;a=json.load(open('$1')).get('permissions',{}).get('allow',[]);sys.exit(0 if '$2' in a else 1)" 2>/dev/null; }

# --- Test 1: --global writes global allowlist with correct policy ---
echo "--- Test 1: --global writes global allowlist (policy: complete minus destructive) ---"
T=$(mktemp -d); CFG="$T/cfg"; mkdir -p "$CFG"
CLAUDE_CONFIG_DIR="$CFG" bash "$SETUP" --global --yes --skip-mcp-check --skip-statusline >/dev/null 2>&1 || true
GF="$CFG/settings.json"
_chk "global settings.json created"          "[ -f '$GF' ]"
_chk "13 CMM tools written"                  "[ \"\$(_cmm '$GF')\" -eq 13 ]"
_chk "18 context-mode entries written"       "[ \"\$(_ctx '$GF')\" -eq 18 ]"
_chk "delete_project excluded"               "! _has '$GF' mcp__codebase-memory-mcp__delete_project"
_chk "ctx_purge excluded (plugin form)"      "! _has '$GF' mcp__plugin_context-mode_context-mode__ctx_purge"
_chk "ctx_upgrade excluded (legacy form)"    "! _has '$GF' mcp__context-mode__ctx_upgrade"
_chk "ctx_doctor included (plugin form)"     "_has '$GF' mcp__plugin_context-mode_context-mode__ctx_doctor"
_chk "ctx_insight included (legacy form)"    "_has '$GF' mcp__context-mode__ctx_insight"
_chk "global settings.json valid JSON"       "python3 -m json.tool '$GF' >/dev/null 2>&1"
rm -rf "$T"

# --- Test 2: --skip-context-mode omits ctx tools ---
echo "--- Test 2: --global --skip-context-mode omits context-mode tools ---"
T=$(mktemp -d); CFG="$T/cfg"; mkdir -p "$CFG"
CLAUDE_CONFIG_DIR="$CFG" bash "$SETUP" --global --yes --skip-mcp-check --skip-statusline --skip-context-mode >/dev/null 2>&1 || true
GF="$CFG/settings.json"
_chk "13 CMM tools present"                  "[ \"\$(_cmm '$GF')\" -eq 13 ]"
_chk "0 context-mode entries"                "[ \"\$(_ctx '$GF')\" -eq 0 ]"
rm -rf "$T"

# --- Test 3: --all writes global, SKIPS project (covered globally) ---
echo "--- Test 3: --all writes global and skips project allowlist ---"
T=$(mktemp -d); CFG="$T/cfg"; PROJ="$T/proj"; mkdir -p "$CFG" "$PROJ"
( cd "$PROJ" && git init -q && git config user.email t@t.co && git config user.name t && git commit --allow-empty -qm i ) >/dev/null 2>&1
( cd "$PROJ" && CLAUDE_CONFIG_DIR="$CFG" bash "$SETUP" --all --yes --skip-mcp-check --skip-statusline --no-migrate >/tmp/_gal_all 2>&1 ) || true
_chk "global allowlist written (13 CMM)"     "[ \"\$(_cmm "$CFG/settings.json")\" -eq 13 ]"
_chk "project allowlist skipped"             "[ ! -f '$PROJ/.claude/settings.json' ] || [ \"\$(_cmm "$PROJ/.claude/settings.json")\" -eq 0 ]"
_chk "output notes global coverage"          "grep -qi 'skipping project allowlist' /tmp/_gal_all"
rm -rf "$T"; rm -f /tmp/_gal_all

# --- Test 4: --project with no global writes project allowlist ---
echo "--- Test 4: --project (no global) writes project allowlist ---"
T=$(mktemp -d); CFG="$T/cfg"; PROJ="$T/proj"; mkdir -p "$CFG" "$PROJ"
( cd "$PROJ" && git init -q && git config user.email t@t.co && git config user.name t && git commit --allow-empty -qm i ) >/dev/null 2>&1
( cd "$PROJ" && CLAUDE_CONFIG_DIR="$CFG" bash "$SETUP" --project --yes --skip-mcp-check --skip-statusline --no-migrate >/dev/null 2>&1 ) || true
PF="$PROJ/.claude/settings.json"
_chk "project settings created"              "[ -f '$PF' ]"
_chk "13 CMM tools in project"               "[ \"\$(_cmm '$PF')\" -eq 13 ]"
_chk "18 context-mode entries in project"    "[ \"\$(_ctx '$PF')\" -eq 18 ]"
rm -rf "$T"

# --- Test 5: merged detection — global allowlist satisfies project preflight ---
echo "--- Test 5: global allowlist satisfies project preflight (no false 'not allowlisted') ---"
T=$(mktemp -d); CFG="$T/cfg"; PROJ="$T/proj"; mkdir -p "$CFG" "$PROJ"
CLAUDE_CONFIG_DIR="$CFG" bash "$SETUP" --global --yes --skip-mcp-check --skip-statusline >/dev/null 2>&1 || true
( cd "$PROJ" && git init -q && git config user.email t@t.co && git config user.name t && git commit --allow-empty -qm i ) >/dev/null 2>&1
( cd "$PROJ" && CLAUDE_CONFIG_DIR="$CFG" bash "$SETUP" --project --dry-run --skip-statusline --no-migrate >/tmp/_gal_pf 2>&1 ) || true
_chk "preflight recognizes global allowlist" "grep -qiE 'CMM tools allowlisted|already' /tmp/_gal_pf && ! grep -qi 'CMM tools not allowlisted' /tmp/_gal_pf"
rm -rf "$T"; rm -f /tmp/_gal_pf

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
