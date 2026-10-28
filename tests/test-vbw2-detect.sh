#!/bin/bash
# test-vbw2-detect.sh — VBW 2 detection, separate from VBW 1 (R3)
# hooks/lib/vbw-source.sh must classify a 2.x plugin tree as VBW 2 (source type
# "vbw2", version from the plugin's VERSION file) and pick the version Claude
# Code loads; setup.sh must report VBW 2 with its version, VBW 1 as before,
# both, or absent. Fixture plugin trees only: HOME, CLAUDE_CONFIG_DIR and PATH
# are scrubbed so the developer's real VBW install is never seen.
# Usage: bash tests/test-vbw2-detect.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd -P)"
LIB="$REPO/hooks/lib/vbw-source.sh"
SETUP="$REPO/setup.sh"

PASS=0
FAIL=0
_pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}
_fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}
_eq() { if [ "$2" = "$3" ]; then _pass "$1"; else _fail "$1 (expected '$3', got '$2')"; fi; }

T="$(mktemp -d)"
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT

# PATH without any directory that holds a `vbw` executable: a VBW 2 CLI on the
# developer's PATH must not leak into the "VBW 1 only" or "neither" cases.
CLEAN_PATH=""
IFS=':' read -ra _P <<<"$PATH"
for d in "${_P[@]}"; do
    [ -n "$d" ] && [ ! -x "$d/vbw" ] && CLEAN_PATH="${CLEAN_PATH:+$CLEAN_PATH:}$d"
done

# _home <name> -> a fresh scratch HOME; its config dir is $HOME/.config/claude-code
_home() {
    local h="$T/$1/home"
    mkdir -p "$h/.config/claude-code/plugins/cache/vbw-marketplace/vbw"
    echo "$h"
}
_cache() { echo "$1/.config/claude-code/plugins/cache/vbw-marketplace/vbw"; }

# _vbw2 <home> <version>: a VBW 2 plugin tree (VERSION, bin/vbw, 7 agents)
_vbw2() {
    local d
    d="$(_cache "$1")/$2"
    mkdir -p "$d/agents" "$d/bin" "$d/hooks"
    printf '%s\n' "$2" >"$d/VERSION"
    printf '#!/bin/bash\necho "vbw %s"\n' "$2" >"$d/bin/vbw"
    chmod +x "$d/bin/vbw"
    for a in architect lead dev qa scout debugger docs; do printf -- '---\nname: %s\n---\n' "$a" >"$d/agents/$a.md"; done
}

# _vbw1 <home> <version>: a VBW 1 plugin tree (agents/vbw-*.md)
_vbw1() {
    local d
    d="$(_cache "$1")/$2"
    mkdir -p "$d/agents"
    printf '%s\n' "$2" >"$d/VERSION"
    for a in architect lead dev qa scout debugger docs; do printf -- '---\nname: vbw-%s\n---\nbody\n' "$a" >"$d/agents/vbw-$a.md"; done
}

# _plugins <home> <version>[:<scope>] ... : installed_plugins.json, entries in order
_plugins() {
    local h="$1"
    shift
    H="$h" C="$(_cache "$h")" python3 - "$@" <<'PY'
import json, os, sys
entries = []
for spec in sys.argv[1:]:
    ver, _, scope = spec.partition(":")
    e = {"installPath": os.path.join(os.environ["C"], ver), "version": ver, "scope": scope or "user"}
    if scope == "local":
        e["projectPath"] = "/elsewhere/project"
    entries.append(e)
path = os.path.join(os.environ["H"], ".config/claude-code/plugins/installed_plugins.json")
json.dump({"version": 2, "plugins": {"vbw@vbw-marketplace": entries}}, open(path, "w"), indent=1)
PY
}

# _resolve <home> -> "TYPE|VERSION" from resolve_vbw_source
_resolve() {
    HOME="$1" CLAUDE_CONFIG_DIR="$1/.config/claude-code" PATH="$CLEAN_PATH" bash -c '
        source "$0" >/dev/null 2>&1
        resolve_vbw_source >/dev/null 2>&1 || true
        printf "%s|%s" "${VBW_SOURCE_TYPE:-}" "${VBW_VERSION:-}"' "$LIB"
}

# _resolve2 <home> -> "RC|VBW2_VERSION" from resolve_vbw2
_resolve2() {
    HOME="$1" CLAUDE_CONFIG_DIR="$1/.config/claude-code" PATH="$CLEAN_PATH" bash -c '
        source "$0" >/dev/null 2>&1
        rc=0; resolve_vbw2 >/dev/null 2>&1 || rc=$?
        printf "%s|%s" "$rc" "${VBW2_VERSION:-}"' "$LIB"
}

# _setup <home> -> path of setup.sh output for a project install into a fresh repo
_setup() {
    local h="$1" proj
    proj="$(dirname "$h")/proj"
    mkdir -p "$proj"
    git -C "$proj" init -q
    (cd "$proj" && echo n | HOME="$h" CLAUDE_CONFIG_DIR="$h/.config/claude-code" PATH="$CLEAN_PATH" \
        bash "$SETUP" --project --yes --skip-mcp-check --skip-statusline --no-migrate) >"$proj.out" 2>&1 || true
    echo "$proj.out"
}

VBW2_LINE='VBW 2([^.0-9]|$)|VBW 2\.[0-9]'
VBW1_LINE='VBW installed \((marketplace|local-symlink)\)'

echo "--- lib: VBW 2 is its own source type, version from VERSION ---"
H="$(_home only2)"
_vbw2 "$H" 2.1.18
_plugins "$H" 2.1.18
_eq "VBW 2 install -> resolve_vbw_source vbw2|2.1.18" "$(_resolve "$H")" "vbw2|2.1.18"
_eq "VBW 2 install -> resolve_vbw2 0|2.1.18" "$(_resolve2 "$H")" "0|2.1.18"

H="$(_home cacheonly2)"
_vbw2 "$H" 2.1.18
_eq "VBW 2 in plugin cache, no installed_plugins.json -> vbw2|2.1.18" "$(_resolve "$H")" "vbw2|2.1.18"

echo "--- lib: several VBW 2 versions -> the one Claude Code loads ---"
H="$(_home multi)"
_vbw2 "$H" 2.0.30
_vbw2 "$H" 2.1.9
_vbw2 "$H" 2.1.18
_eq "no registry: highest by semver (2.1.18 > 2.1.9) via resolve_vbw_source" "$(_resolve "$H")" "vbw2|2.1.18"
_eq "no registry: highest by semver via resolve_vbw2" "$(_resolve2 "$H")" "0|2.1.18"
_plugins "$H" 2.1.9
_eq "registry active entry wins over a newer cache dir (resolve_vbw_source)" "$(_resolve "$H")" "vbw2|2.1.9"
_eq "registry active entry wins over a newer cache dir (resolve_vbw2)" "$(_resolve2 "$H")" "0|2.1.9"

echo "--- lib: VBW 1 unchanged, both, neither ---"
H="$(_home only1)"
_vbw1 "$H" 1.37.1
_plugins "$H" 1.37.1
_eq "VBW 1 install -> marketplace|1.37.1 (unchanged)" "$(_resolve "$H")" "marketplace|1.37.1"
_eq "VBW 1 install -> resolve_vbw2 finds nothing" "$(_resolve2 "$H" | cut -d'|' -f1)" "1"

H="$(_home both)"
_vbw1 "$H" 1.37.1
_vbw2 "$H" 2.1.18
_plugins "$H" 1.37.1:user 2.1.18:local
_eq "both: active VBW 1 entry still resolves marketplace|1.37.1" "$(_resolve "$H")" "marketplace|1.37.1"
_eq "both: resolve_vbw2 reports 2.1.18" "$(_resolve2 "$H")" "0|2.1.18"

H="$(_home neither)"
_eq "neither -> absent" "$(_resolve "$H" | cut -d'|' -f1)" "absent"
_eq "neither -> resolve_vbw2 rc 1" "$(_resolve2 "$H" | cut -d'|' -f1)" "1"

echo "--- setup.sh reports what it detected ---"
OUT="$(_setup "$T/only2/home")"
if grep -Eq "$VBW2_LINE" "$OUT" && grep -E "$VBW2_LINE" "$OUT" | grep -q '2\.1\.18'; then
    _pass "VBW 2 only: setup names VBW 2 and 2.1.18"
else
    _fail "VBW 2 only: no line naming VBW 2 and 2.1.18"
fi
if grep -Eq "$VBW1_LINE" "$OUT"; then _fail "VBW 2 only: misreported as VBW 1"; else _pass "VBW 2 only: not reported as VBW 1"; fi

OUT="$(_setup "$T/only1/home")"
if grep -Eq "$VBW1_LINE" "$OUT"; then _pass "VBW 1 only: VBW 1 detection line as before"; else _fail "VBW 1 only: VBW 1 detection line missing"; fi
if grep -Eq "$VBW2_LINE" "$OUT"; then _fail "VBW 1 only: VBW 2 wrongly reported"; else _pass "VBW 1 only: no VBW 2 line"; fi

OUT="$(_setup "$T/both/home")"
if grep -Eq "$VBW1_LINE" "$OUT" && grep -E "$VBW2_LINE" "$OUT" | grep -q '2\.1\.18'; then
    _pass "both: VBW 1 and VBW 2 (2.1.18) reported"
else
    _fail "both: expected a VBW 1 line and a VBW 2 2.1.18 line"
fi

H="$(_home multisetup)"
_vbw2 "$H" 2.0.30
_vbw2 "$H" 2.1.9
_vbw2 "$H" 2.1.18
OUT="$(_setup "$H")"
if grep -E "$VBW2_LINE" "$OUT" | grep -q '2\.1\.18' && ! grep -E "$VBW2_LINE" "$OUT" | grep -q '2\.1\.9'; then
    _pass "several VBW 2 versions: setup reports 2.1.18 only"
else
    _fail "several VBW 2 versions: setup must report 2.1.18 (and not 2.1.9)"
fi

OUT="$(_setup "$T/neither/home")"
if grep -q 'VBW not installed (absent)' "$OUT" && ! grep -Eq "$VBW2_LINE|$VBW1_LINE" "$OUT"; then
    _pass "neither: reported absent"
else
    _fail "neither: expected 'VBW not installed (absent)' and no VBW 1/2 line"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
