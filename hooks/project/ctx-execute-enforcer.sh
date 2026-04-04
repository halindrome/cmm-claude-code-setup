#!/bin/bash
# ctx-execute-enforcer.sh — PreToolUse:Bash hook (redirects large-output commands to ctx_execute)
# BLOCKING: exits 2 for test runners, package installs, linters, and log viewers; redirects to mcp__context-mode__ctx_execute
# No-op when Context Mode is not installed or not yet initialized.
#
# Install: cp hooks/project/ctx-execute-enforcer.sh .claude/hooks/ && chmod +x .claude/hooks/ctx-execute-enforcer.sh
# Register in .claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/ctx-execute-enforcer.sh"}] }] }
# Matcher: PreToolUse:Bash

# --- Stable Sentinel Path Computation ---
# Walk the git superproject chain to find the outermost project root.
# Handles arbitrarily nested submodules — each iteration climbs one level until there is
# no further superproject. Falls back to BASH_SOURCE traversal for non-git environments.
# Git worktrees are handled separately below (they are not submodules).
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
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
fi

# --- Git Worktree Detection ---
# git worktrees share the main repo but show-superproject-working-tree returns empty
# (worktrees are not submodules). Detect via git-common-dir: in a worktree it points
# to the main .git dir, while git-dir points into .git/worktrees/<name>.
# Use the main project root so sentinel hashes are stable across worktree sessions.
if [ -n "$PROJECT_ROOT" ]; then
    _GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --git-dir 2>/dev/null)"
    _GIT_COMMON="$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null)"
    # Resolve relative paths (git may return relative paths in the main working tree)
    [ "${_GIT_DIR:0:1}" != "/" ]    && _GIT_DIR="$PROJECT_ROOT/$_GIT_DIR"
    [ "${_GIT_COMMON:0:1}" != "/" ] && _GIT_COMMON="$PROJECT_ROOT/$_GIT_COMMON"
    if [ "$_GIT_DIR" != "$_GIT_COMMON" ]; then
        _MAIN_ROOT="$(cd "$_GIT_COMMON/.." 2>/dev/null && pwd -P)"
        [ -n "$_MAIN_ROOT" ] && PROJECT_ROOT="$_MAIN_ROOT"
    fi
fi

# --- Path Integrity Check ---
# Hooks are registered with absolute paths by setup.sh. If the project was moved or
# cloned without re-running setup.sh, BASH_SOURCE points to the old location while
# git resolves the actual current root — catch this mismatch early.
_SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P 2>/dev/null)"
if [ -n "$_SCRIPT_ROOT" ] && [ -n "$PROJECT_ROOT" ] && [ "$_SCRIPT_ROOT" != "$PROJECT_ROOT" ]; then
    echo "cmm-hooks: path mismatch — hooks registered for '$_SCRIPT_ROOT' but git root is '$PROJECT_ROOT'."
    echo "Project was moved or cloned. Re-run: bash setup.sh --project --force"
    exit 2
fi

PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')

# --- Input Parsing ---
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# If parsing failed or command is empty, do not block — fail open to avoid spurious hook errors
[ -z "$COMMAND" ] && exit 0

# --- Context Mode Detection (cached) ---
# Cache result in /tmp/ctx-enforcer-<hash> to avoid repeated python3 JSON parsing on every Bash call
CTX_CACHE="/tmp/ctx-enforcer-${PROJECT_HASH}"
if [ -f "$CTX_CACHE" ]; then
    CONTEXT_MODE_INSTALLED=$(cat "$CTX_CACHE" 2>/dev/null)
    CONTEXT_MODE_INSTALLED="${CONTEXT_MODE_INSTALLED:-0}"
else
    CONTEXT_MODE_INSTALLED=0
    if python3 -c "
import json, os, sys
# 1. Project .mcp.json
try:
    with open('${PROJECT_ROOT}/.mcp.json') as f:
        if 'context-mode' in json.load(f).get('mcpServers', {}):
            sys.exit(0)
except Exception: pass
# 2. Global Claude Code settings
for d in [os.environ.get('CLAUDE_CONFIG_DIR',''), os.path.expanduser('~/.config/claude-code'), os.path.expanduser('~/.claude')]:
    if not d: continue
    try:
        with open(os.path.join(d, 'settings.json')) as f:
            if 'context-mode' in json.load(f).get('mcpServers', {}):
                sys.exit(0)
    except Exception: pass
sys.exit(1)
" 2>/dev/null; then
        CONTEXT_MODE_INSTALLED=1
    fi
    # Also activate if a session DB already exists (context-mode was used here before)
    [ -f "${PROJECT_ROOT}/.claude/context-mode.db" ] && CONTEXT_MODE_INSTALLED=1
    # Write cache
    echo "$CONTEXT_MODE_INSTALLED" > "$CTX_CACHE" 2>/dev/null || true
fi

# No-op if Context Mode is not installed
if [ "$CONTEXT_MODE_INSTALLED" -eq 0 ]; then
    exit 0
fi

# --- Context Mode Sentinel Check (deadlock prevention) ---
# If ctx_execute is not ready yet, allowing Bash through avoids a catch-22 where
# Claude cannot call ctx_execute to initialize Context Mode.
CONTEXT_MODE_SENTINEL="/tmp/context-mode-ready-${PROJECT_HASH}"
if [ ! -f "$CONTEXT_MODE_SENTINEL" ]; then
    exit 0
fi

# --- Bypass Marker ---
# Add "# ctx-exempt" anywhere in the command to skip the gate for legitimate raw Bash use.
if echo "$COMMAND" | grep -q "ctx-exempt"; then
    exit 0
fi

# --- Exempt Patterns (always allow, exit 0) ---

# Git write operations (state-changing, bounded output, required for workflow)
case "$COMMAND" in
  git\ commit*|git\ add*|git\ push*|git\ pull*|git\ fetch*)  exit 0 ;;
  git\ checkout*|git\ switch*|git\ branch*|git\ tag*)         exit 0 ;;
  git\ rebase*|git\ merge*|git\ cherry-pick*|git\ reset*)     exit 0 ;;
  git\ stash*|git\ worktree*|git\ remote*)                    exit 0 ;;
  git\ config*|git\ init*)                                    exit 0 ;;
esac

# Git bounded read operations (output is short and predictable)
case "$COMMAND" in
  git\ status|git\ status\ *)                          exit 0 ;;
  git\ diff\ --stat*|git\ log\ --oneline\ -*)          exit 0 ;;
  git\ show\ --stat*|git\ rev-parse\ *|git\ rev-list\ --count*)  exit 0 ;;
esac

# Filesystem mutations (no stdout flood)
case "$COMMAND" in
  mkdir\ *|rmdir\ *|rm\ *|mv\ *|cp\ *|ln\ *|chmod\ *|chown\ *)  exit 0 ;;
  touch\ *|install\ -m*|mktemp*)                                  exit 0 ;;
esac

# Navigation and short queries (output is bounded)
case "$COMMAND" in
  cd\ *|pwd|which\ *|type\ *|command\ -v\ *)          exit 0 ;;
  echo\ *|printf\ *|date*|uname*|whoami|hostname)     exit 0 ;;
  wc\ *|head\ *|tail\ -[0-9]*|tail\ -n\ [0-9]*)      exit 0 ;;
esac

# Remote commands (output belongs to remote context, not local CTX store)
case "$COMMAND" in
  ssh\ *|scp\ *|rsync\ *|sftp\ *)                              exit 0 ;;
esac

# --- Block Patterns (redirect to ctx_execute) ---
SHOULD_BLOCK=0

case "$COMMAND" in
  # Test runners
  npm\ test*|npm\ run\ test*|npx\ jest*|npx\ vitest*|npx\ mocha*)  SHOULD_BLOCK=1 ;;
  yarn\ test*|yarn\ run\ test*|pnpm\ test*|pnpm\ run\ test*)     SHOULD_BLOCK=1 ;;
  bun\ test*|deno\ test*|node\ --test*)                           SHOULD_BLOCK=1 ;;
  pytest*|python\ -m\ pytest*|py.test*)                          SHOULD_BLOCK=1 ;;
  cargo\ test*|go\ test\ *|mvn\ test*|./gradlew\ test*)          SHOULD_BLOCK=1 ;;
  make\ test*|make\ check*)                                      SHOULD_BLOCK=1 ;;

  # Log/output viewers (unbounded output)
  tail\ -f\ *|journalctl*|kubectl\ logs\ *)                      SHOULD_BLOCK=1 ;;
  docker\ logs\ *)                                               SHOULD_BLOCK=1 ;;

  # Package managers (verbose install output)
  npm\ install*|npm\ ci*|yarn\ install*|pnpm\ install*)          SHOULD_BLOCK=1 ;;
  pip\ install*|pip3\ install*|poetry\ install*|uv\ sync*)       SHOULD_BLOCK=1 ;;
  cargo\ build*|cargo\ check*)                                   SHOULD_BLOCK=1 ;;

  # Linters/formatters (many lines of output)
  eslint\ *|pylint\ *|mypy\ *|flake8\ *|black\ *|isort\ *)       SHOULD_BLOCK=1 ;;
  cargo\ clippy*|golangci-lint\ *|go\ vet\ *)                    SHOULD_BLOCK=1 ;;

  # Build tools (context-mode handles these too, belt-and-suspenders)
  npm\ run\ build*|yarn\ build*|tsc\ *|webpack\ *|vite\ build*)  SHOULD_BLOCK=1 ;;
esac

# --- Block Decision ---
if [ "$SHOULD_BLOCK" -eq 1 ]; then
  # --- Block Counter ---
  bash "$(dirname "${BASH_SOURCE[0]}")/track-hook-blocks.sh" "bash" 2>/dev/null || true

  cat >&2 <<BLOCKED
BLOCKED: This command produces large output. Use ctx_execute to run it in the sandbox.

Replace:
  Bash("$COMMAND")
With:
  mcp__context-mode__ctx_execute(language="shell", code="$COMMAND")

Context Mode captures only the relevant output portion, preventing context bloat.

To bypass this gate (e.g., when you need raw output in context), add "# ctx-exempt" to your command:
  Bash("$COMMAND # ctx-exempt")
BLOCKED
  exit 2
fi

# Default: allow everything not explicitly blocked
exit 0
