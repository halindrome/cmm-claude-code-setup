#!/bin/bash
# test-vbw2-override-skip.sh — no VBW 1 agent overrides for a VBW 2-only install (R6)
# VBW 2 spawns plugin agents (vbw:dev, ...), never .claude/agents/vbw-*.md, so a
# VBW 2-only install gets no VBW 1 deltas, no generator registration and no
# overrides, and the generator itself is a quiet no-op there. VBW 1 installs are
# unaffected. Fixture plugin trees only (HOME, CLAUDE_CONFIG_DIR, PATH scrubbed).
# Usage: bash tests/test-vbw2-override-skip.sh
# Exit: 0 = all pass, 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd -P)"
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
_md5() { if command -v md5 >/dev/null 2>&1; then md5 -q; else md5sum | awk '{print $1}'; fi; }

T="$(mktemp -d)"
T="$(cd "$T" && pwd -P)"
_cleanup() {
    local d
    for d in "$T"/*/proj "$T"/*/hookrepo; do rm -f "/tmp/cmm-project-root-$(echo -n "$d" | _md5)"; done
    rm -rf "$T"
}
trap _cleanup EXIT

CLEAN_PATH=""
IFS=':' read -ra _P <<<"$PATH"
for d in "${_P[@]}"; do
    [ -n "$d" ] && [ ! -x "$d/vbw" ] && CLEAN_PATH="${CLEAN_PATH:+$CLEAN_PATH:}$d"
done

# _env <name> <1|2>: HOME with one VBW plugin tree registered as the active install
_env() {
    local h="$T/$1/home" v d a
    if [ "$2" = 2 ]; then v=2.1.18; else v=1.37.1; fi
    d="$h/.config/claude-code/plugins/cache/vbw-marketplace/vbw/$v"
    mkdir -p "$d/agents" "$T/$1/proj"
    echo "$v" >"$d/VERSION"
    for a in architect lead dev qa scout debugger docs; do
        if [ "$2" = 2 ]; then
            printf -- '---\nname: %s\ntools: Read, Grep, Glob, Bash\n---\nVBW 2 %s\n' "$a" "$a" >"$d/agents/$a.md"
        else
            printf -- '---\nname: vbw-%s\ndescription: d\ntools: Read, Grep, Glob, Bash\n---\nVBW 1 %s body\n' "$a" "$a" >"$d/agents/vbw-$a.md"
        fi
    done
    if [ "$2" = 2 ]; then
        mkdir -p "$d/bin"
        printf '#!/bin/bash\n' >"$d/bin/vbw"
        chmod +x "$d/bin/vbw"
    fi
    H="$h" D="$d" V="$v" python3 -c 'import json,os
json.dump({"version":2,"plugins":{"vbw@vbw-marketplace":[{"installPath":os.environ["D"],"version":os.environ["V"],"scope":"user"}]}},
          open(os.path.join(os.environ["H"],".config/claude-code/plugins/installed_plugins.json"),"w"))'
    git -C "$T/$1/proj" init -q
}
_setup() {
    (cd "$T/$1/proj" && echo n | HOME="$T/$1/home" CLAUDE_CONFIG_DIR="$T/$1/home/.config/claude-code" PATH="$CLEAN_PATH" \
        bash "$SETUP" --project --yes --skip-mcp-check --skip-statusline --no-migrate) >"$T/$1/setup.out" 2>&1 || true
}
_count() { find "$1" -maxdepth 1 -name 'vbw-*.md' 2>/dev/null | wc -l | tr -d ' '; }
# _gen <name>: run the generator from the repo layout (deltas from agents/)
_gen() {
    local r="$T/$1/hookrepo"
    mkdir -p "$r/hooks/project" "$r/hooks/lib" "$r/agents"
    git -C "$r" init -q
    cp "$REPO/hooks/project/agent-override-generate.sh" "$r/hooks/project/"
    cp "$REPO/hooks/lib/"*.sh "$r/hooks/lib/"
    cp "$REPO/agents/"vbw-*.md "$r/agents/"
    GEN_RC=0
    (cd "$r" && HOME="$T/$1/home" CLAUDE_CONFIG_DIR="$T/$1/home/.config/claude-code" PATH="$CLEAN_PATH" \
        bash "$r/hooks/project/agent-override-generate.sh" </dev/null >"$T/$1/gen.out" 2>"$T/$1/gen.err") || GEN_RC=$?
    GEN_DIR="$r/.claude/agents"
}

echo "--- VBW 2-only install: no VBW 1 overrides ---"
_env v2 2
_setup v2
P="$T/v2/proj/.claude"
[ "$(_count "$P/agents")" = 0 ] && _pass "setup: no .claude/agents/vbw-*.md" || _fail "setup generated .claude/agents/vbw-*.md for VBW 2"
[ "$(_count "$P/agents-delta")" = 0 ] && _pass "setup: no VBW 1 deltas in .claude/agents-delta" || _fail "setup installed VBW 1 deltas for VBW 2"
if [ -f "$P/settings.json" ] && ! grep -q 'agent-override-generate.sh' "$P/settings.json"; then
    _pass "setup: generator not registered"
else
    _fail "setup registered agent-override-generate.sh for VBW 2 (or wrote no settings.json)"
fi
_gen v2
if [ "$GEN_RC" = 0 ] && [ "$(_count "$GEN_DIR")" = 0 ] && ! grep -q 'WARN' "$T/v2/gen.err"; then
    _pass "generator under VBW 2: exit 0, no overrides, no warnings"
else
    _fail "generator under VBW 2: rc=$GEN_RC, overrides=$(_count "$GEN_DIR"), stderr=$(head -c 300 "$T/v2/gen.err")"
fi

echo "--- VBW 1 install: unchanged ---"
_env v1 1
_setup v1
[ "$(_count "$T/v1/proj/.claude/agents-delta")" = 7 ] && _pass "setup: VBW 1 deltas installed" || _fail "setup: VBW 1 deltas missing ($(_count "$T/v1/proj/.claude/agents-delta"))"
_gen v1
if [ "$GEN_RC" = 0 ] && [ "$(_count "$GEN_DIR")" = 7 ] && grep -q 'VBW 1 dev body' "$GEN_DIR/vbw-dev.md"; then
    _pass "generator under VBW 1: 7 overrides from the VBW 1 bodies"
else
    _fail "generator under VBW 1 changed: rc=$GEN_RC, overrides=$(_count "$GEN_DIR")"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
