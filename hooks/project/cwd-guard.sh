#!/bin/bash
# cwd-guard.sh — PreToolUse:Bash hook (CWD-drift prevention gate)
# BLOCKING: exits 2 when a command would persistently `cd` the shell away from the project root.
#
# Why this exists (monorepo / submodule safety):
#   The Bash tool keeps ONE persistent shell whose cwd survives between calls.
#   A standalone/persistent `cd <subdir>` parks the shell in a subdirectory for
#   every later call. In a monorepo with git submodules that is corrosive: once
#   the shell sits inside a submodule, `git rev-parse --show-toplevel` resolves
#   to the SUBMODULE root, so every CMM/Context-Mode hook computes a DIFFERENT
#   PROJECT_HASH, the `/tmp/cmm-session-ready-<hash>` and
#   `/tmp/context-mode-ready-<hash>` sentinels no longer match, and the session
#   gate + enforcer wrongly report "not indexed / not initialized". Hooks cannot
#   read the persistent shell's drifted cwd (the hook payload's cwd is the
#   session root), so drift cannot be DETECTED after the fact — only PREVENTED.
#
#   This hook blocks any command whose top-level (non-subshell) effect is to
#   change the shell's directory to anything other than the project root.
#   Allowed instead:
#     - absolute paths:            cat /abs/path/file
#     - per-repo git:              git -C apps/rest-api status
#     - subshells (cd is local):   ( cd apps/rest-api && make test )
#     - re-anchoring to root:      cd /abs/project/root   |   cd "$CLAUDE_PROJECT_DIR"
#
#   Operator bypass: include the literal `# cwd-exempt` anywhere in the command.
#
# Install: cp hooks/project/cwd-guard.sh .claude/hooks/ && chmod +x .claude/hooks/cwd-guard.sh
# Register in .claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/cwd-guard.sh"}] }] }
# Matcher: PreToolUse:Bash

# --- Project root detection (shared library with /tmp cache) ---
# Use the same git-aware superproject detection the other hooks use, so the
# "root" this guard anchors to is byte-identical to the root the sentinel hash
# is computed from. Falls back to inline detection for pre-lib installs.
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" 2>/dev/null && pwd -P)"
if [ -f "$_LIB_DIR/project-root.sh" ]; then
  source "$_LIB_DIR/project-root.sh"
else
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$PROJECT_ROOT" ]; then
      _WALK="$PROJECT_ROOT"
      while true; do
          _PARENT="$(git -C "$_WALK" rev-parse --show-superproject-working-tree 2>/dev/null)"
          [ -z "$_PARENT" ] && break
          _WALK="$_PARENT"
      done
      PROJECT_ROOT="$_WALK"
  fi
  if [ -z "$PROJECT_ROOT" ]; then
      PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd -P)"
  fi
fi
[ -z "$PROJECT_ROOT" ] && exit 0   # fail-open: cannot resolve root

INPUT=$(cat)

# Fail open if python3 is unavailable — never wedge every Bash call.
command -v python3 >/dev/null 2>&1 || exit 0

DECISION=$(CWD_GUARD_ROOT="$PROJECT_ROOT" python3 - "$INPUT" <<'PY' 2>/dev/null
import sys, json, os, re, shlex

root = os.environ.get("CWD_GUARD_ROOT", "")
try:
    data = json.loads(sys.argv[1])
except Exception:
    print("ALLOW"); sys.exit(0)

ti = data.get("tool_input", {}) or {}
cmd = ti.get("command", "") or data.get("command", "")
if not cmd:
    print("ALLOW"); sys.exit(0)

# Operator bypass.
if "# cwd-exempt" in cmd:
    print("ALLOW"); sys.exit(0)

# Remove subshell / command-substitution groups: a `cd` inside `( ... )` or
# `$( ... )` runs in a child shell and does NOT persist. Strip innermost
# parens repeatedly until stable so nested groups are handled too.
stripped = cmd
prev = None
while prev != stripped:
    prev = stripped
    stripped = re.sub(r"\([^()]*\)", " ", stripped)

# Split into top-level segments on ; && || | and newlines.
segments = re.split(r";|&&|\|\||\||\n", stripped)

ALLOWED_TARGET_TOKENS = {
    "$CLAUDE_PROJECT_DIR", '"$CLAUDE_PROJECT_DIR"', "${CLAUDE_PROJECT_DIR}",
    '"${CLAUDE_PROJECT_DIR}"', ".", "./",
}

def target_is_root(tok):
    if tok in ALLOWED_TARGET_TOKENS:
        return True
    t = tok.strip().strip('"').strip("'")
    if not t:
        return False
    if t.startswith("/"):
        try:
            return os.path.realpath(t) == os.path.realpath(root)
        except Exception:
            return False
    return False

# Directory-changing builtins whose top-level use persists in the shell.
# `cd`/`pushd` take a target (allowed only when it is the root); `popd` moves to
# an unknown prior stack dir, so any top-level `popd` is treated as drift.
DRIFT_WITH_TARGET = {"cd", "pushd"}
ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

def cd_target(rest):
    # Skip leading option flags (e.g. `cd -P`, `cd -L`, `cd --`) to find the path.
    for r in rest:
        if r.startswith("-"):
            continue
        return r
    return ""

for seg in segments:
    s = seg.strip()
    if not s:
        continue
    # A segment backgrounded with a trailing '&' runs in a child shell; its cwd
    # change does NOT persist in the parent. (Top-level '&&' was already split out
    # above, so a remaining trailing '&' is backgrounding.)
    if s.endswith("&"):
        s = s[:-1].strip()
        if not s:
            continue
        # Re-check: a backgrounded cd does not drift the persistent shell.
        try:
            bg_toks = shlex.split(s, comments=False, posix=True)
        except Exception:
            continue
        idx = 0
        while idx < len(bg_toks) and ENV_ASSIGN.match(bg_toks[idx]):
            idx += 1
        if idx < len(bg_toks) and bg_toks[idx] in ("cd", "pushd", "popd"):
            continue  # backgrounded dir change — non-persistent, allow
        continue
    try:
        toks = shlex.split(s, comments=False, posix=True)
    except Exception:
        # Unparseable: conservative regex fallback (also covers pushd/popd).
        m = re.match(r"^\s*(cd|pushd|popd)(\s+(\S+))?\s*$", s)
        if m:
            verb = m.group(1); tgt = m.group(3) or ""
            if verb == "popd" or not tgt or not target_is_root(tgt):
                print("BLOCK\t" + s); sys.exit(0)
        continue
    if not toks:
        continue
    # Skip leading NAME=VALUE env-assignment prefixes (e.g. `FOO=1 cd sub`).
    idx = 0
    while idx < len(toks) and ENV_ASSIGN.match(toks[idx]):
        idx += 1
    if idx >= len(toks):
        continue
    verb = toks[idx]
    if verb == "popd":
        print("BLOCK\t" + s); sys.exit(0)
    if verb in DRIFT_WITH_TARGET:
        tgt = cd_target(toks[idx + 1:])
        if not tgt or not target_is_root(tgt):
            print("BLOCK\t" + s); sys.exit(0)

print("ALLOW")
PY
)

case "$DECISION" in
  BLOCK*)
    BAD_SEG="${DECISION#BLOCK	}"
    cat >&2 <<EOF
BLOCKED: persistent 'cd' detected — it would park the shell's directory and drift every later call.

  offending: ${BAD_SEG}

The Bash tool's working directory persists between calls, and a drifted cwd makes
the CMM / Context Mode sentinels stop matching (they are keyed on the project
root), so the session gate wrongly reports "not indexed". Keep commands
cwd-independent instead:
  - absolute paths:        cat ${PROJECT_ROOT}/some/file
  - per-repo git:          git -C apps/rest-api status
  - local cd in subshell:  ( cd apps/rest-api && make test )
  - re-anchor to root:     cd "${PROJECT_ROOT}"

Operator bypass (rare, intentional drift): append '# cwd-exempt' to the command.
EOF
    exit 2
    ;;
esac

exit 0
