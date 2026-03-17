# jmunch-claude-code-setup — Worktree / Monorepo / Submodule Safety Evaluation

**Date:** 2026-03-17
**Analyst:** cmm-claude-code-setup dev agent
**Reference repo:** `../jmunch-claude-code-setup` (Shachar Bard, MIT license)
**Comparison baseline:** cmm-claude-code-setup post-PR #9 (superproject chain walk + worktree detection)

---

## 1. Scope

Hooks examined under `../jmunch-claude-code-setup/hooks/project/`:

| Hook | Type | Role |
|---|---|---|
| `jmunch-session-gate.sh` | PreToolUse: * | Blocks all tools until sentinel is present |
| `jmunch-session-start.sh` | SessionStart | Injects reindex instruction into system prompt |
| `jmunch-sentinel-writer.sh` | PostToolUse: index tools | Writes sentinel lines after each index completes |
| `reindex-after-commit.sh` | PostToolUse: Bash | Marks sentinel stale after `git commit` |
| `agent-jcodemunch-gate.sh` | PostToolUse | Nudge/gate for agent jCodeMunch usage |
| `track-genuine-savings.sh` | PostToolUse | Tracks deferred-tool savings metrics |
| `track-genuine-savings-ctx.sh` | PostToolUse | Tracks context-mode savings metrics |

The first four hooks all use the sentinel hash pattern. The last three do not.

---

## 2. Sentinel Hash Mechanism: jmunch vs CMM

| Aspect | jmunch | cmm-claude-code-setup |
|---|---|---|
| Hash input source | `cwd` from hook JSON stdin | `git rev-parse --show-toplevel` |
| Superproject walk | No | Yes (climbs to outermost) |
| Worktree detection | No | Yes (`--git-common-dir != --git-dir`) |
| Symlink resolution | No | `pwd -P` |
| Path integrity check | No | Yes (BASH_SOURCE vs git root) |
| Fallback | `git rev-parse --show-toplevel` if stdin empty | BASH_SOURCE traversal |

### jmunch pattern (identical across all 4 sentinel hooks)

```bash
INPUT=$(cat)
CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
if [ -z "$CWD" ]; then
  CWD=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
HASH=$(echo "$CWD" | md5 -q 2>/dev/null || echo "$CWD" | md5sum 2>/dev/null | cut -c1-32)
SENTINEL="/tmp/jmunch-ready-${HASH}"
```

The `cwd` field in Claude Code hook JSON is the working directory of the Claude Code process at the moment the hook fires. In a standard session at the project root this equals the git root, so the pattern works correctly. The problem surfaces in the three non-standard topologies below.

---

## 3. Vulnerability Analysis

### 3.1 Git Worktree

**Scenario:** `git worktree add .vbw-worktrees/16-01 -b vbw/16-01`; Claude Code is opened inside the worktree directory.

**jmunch behaviour:**
`cwd` = `/…/project/.vbw-worktrees/16-01` (the worktree path).
`md5(.vbw-worktrees/16-01)` → a unique hash distinct from the one used by a main-root session.
Each worktree produces its own sentinel file. A sentinel written by a main-root session is invisible to a worktree session and vice versa. The worktree session must re-run both index tools even though both sessions share the same `.git` directory and the same jCodeMunch/jDocMunch index.

The `reindex-after-commit.sh` hook has the same flaw: a commit made inside a worktree marks the worktree-specific sentinel stale, leaving the main-root sentinel untouched — the two sessions can diverge silently.

**CMM hooks behaviour:**
The worktree detection block fires: `--git-dir` points to `.git/worktrees/16-01` while `--git-common-dir` points to the main `.git`. Because they differ, `PROJECT_ROOT` is set to `dirname(git-common-dir)` = the main project root. The sentinel hash is therefore identical to the main-root session hash — no re-index is needed.

**Severity: HIGH**
Worktree sessions are functionally always blocked on first use. The forced re-index adds ~30 s per session and can surprise developers who expect worktree isolation to be transparent.

---

### 3.2 Git Submodule

**Scenario:** Claude Code is opened at a submodule path, e.g., `vendor/some-lib/`.

**jmunch behaviour:**
`cwd` = the submodule directory. The fallback `git rev-parse --show-toplevel` resolves to the submodule root (git considers the submodule a stand-alone repo), not the parent project root. Hash is submodule-specific. Index refresh, sentinel, and gate all operate on the submodule's sentinel, entirely separate from the parent project's sentinel.

**CMM hooks behaviour:**
The superproject chain walk calls `git rev-parse --show-superproject-working-tree` iteratively until the outermost ancestor is reached. `PROJECT_ROOT` becomes the top-level project root, not the submodule. The sentinel hash is shared with the parent project session.

**Severity: MEDIUM**
Each submodule gets a separate index and sentinel. Cross-project context is not shared. In monorepo-style setups with many submodules, each must be indexed independently. Users working across parent + submodule in separate Claude Code sessions will see inconsistent views.

---

### 3.3 Monorepo / CWD ≠ Git Root

**Scenario:** Claude Code is launched from a subdirectory of a large monorepo (e.g., `services/api/`).

**jmunch behaviour:**
`cwd` = `…/monorepo/services/api`. `git rev-parse --show-toplevel` returns the monorepo root, which is different from `cwd`. Because stdin CWD is non-empty, the fallback is never reached, so the hash is derived from the subdirectory path. A separate session at the monorepo root uses the git-root hash (via the fallback). These two hashes differ — inconsistent sentinels.

**CMM hooks behaviour:**
`git rev-parse --show-toplevel` is always the starting point, never `cwd`. Regardless of which subdirectory Claude Code was launched from, `PROJECT_ROOT` resolves to the git root. Sentinel hash is consistent across all sessions in the same repo.

**Severity: LOW**
Claude Code typically opens at the git root when launched via `claude` from the repo root. This scenario primarily affects CI pipelines and non-standard launch configurations.

---

### 3.4 Moved or Cloned Project

**Scenario:** The project directory is relocated (e.g., `mv ~/old-path ~/new-path`) without re-running `setup.sh`.

**jmunch behaviour:**
No path integrity check. After relocation, `cwd` and `git rev-parse --show-toplevel` both resolve to the new path. The hook computes the correct hash for the new location. Old `/tmp/jmunch-ready-<old-hash>` sentinels from the old location are simply absent — a normal re-index is triggered. This is benign but provides no guidance to the user about the root cause.

**CMM hooks behaviour:**
The BASH_SOURCE-based path integrity check compares the directory derived from the hook's own file path (registered at `setup.sh` time) against the current git root. After a `mv`, these diverge and the hook prints an actionable error:
```
cmm-hooks: path mismatch — hooks registered for '<old-path>' but git root is '<new-path>'.
Project was moved or cloned. Re-run: bash setup.sh --project --force
```

**Severity: LOW**
Functional impact is a silent re-index rather than a confusing error. The CMM approach adds UX clarity but the jmunch approach does not cause data corruption.

---

## 4. Hooks Not Affected

The following hooks in `../jmunch-claude-code-setup/hooks/project/` do not use the CWD/HASH/SENTINEL pattern and are unaffected by the path stability issues described above:

- `agent-jcodemunch-gate.sh` — gates agent access to jCodeMunch tools; no sentinel hash
- `track-genuine-savings.sh` — records deferred-tool savings metrics; no sentinel hash
- `track-genuine-savings-ctx.sh` — context-mode savings metrics; no sentinel hash

These hooks operate on tool output or tool metadata only and do not need a stable project-root hash.

---

## 5. Recommended Patch

Replace the CWD computation block at the top of each of the four affected hooks (`jmunch-session-gate.sh`, `jmunch-session-start.sh`, `jmunch-sentinel-writer.sh`, `reindex-after-commit.sh`) with the following. The `cwd` stdin read is superseded by git-based root detection and can be removed entirely.

### Before (current jmunch pattern)

```bash
INPUT=$(cat)
CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
if [ -z "$CWD" ]; then
  CWD=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
HASH=$(echo "$CWD" | md5 -q 2>/dev/null || echo "$CWD" | md5sum 2>/dev/null | cut -c1-32)
SENTINEL="/tmp/jmunch-ready-${HASH}"
```

### After (stable sentinel hash — adapted from cmm-claude-code-setup `session-gate.sh` lines 15–50)

```bash
# --- Stable Sentinel Path Computation ---
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
    PROJECT_ROOT="$(pwd -P)"
fi

# --- Git Worktree Detection ---
if [ -n "$PROJECT_ROOT" ]; then
    _GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --git-dir 2>/dev/null)"
    _GIT_COMMON="$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null)"
    [ "${_GIT_DIR:0:1}" != "/" ]    && _GIT_DIR="$PROJECT_ROOT/$_GIT_DIR"
    [ "${_GIT_COMMON:0:1}" != "/" ] && _GIT_COMMON="$PROJECT_ROOT/$_GIT_COMMON"
    if [ "$_GIT_DIR" != "$_GIT_COMMON" ]; then
        _MAIN_ROOT="$(cd "$_GIT_COMMON/.." 2>/dev/null && pwd -P)"
        [ -n "$_MAIN_ROOT" ] && PROJECT_ROOT="$_MAIN_ROOT"
    fi
fi

HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')
SENTINEL="/tmp/jmunch-ready-${HASH}"
```

For hooks that also read other fields from stdin (e.g., `jmunch-session-gate.sh` reads `tool_name`, `jmunch-sentinel-writer.sh` reads `tool_name`, `reindex-after-commit.sh` reads `tool_input.command`), keep the `INPUT=$(cat)` line at the top and update only the CWD/HASH/SENTINEL derivation block.

### Notes on Applying the Patch

- The sentinel prefix should remain `jmunch-ready-` (not `cmm-session-ready-`) to keep it jmunch-branded and avoid collisions with CMM sentinels in shared `/tmp`.
- The `python3` dependency for stdin parsing can be retained for `tool_name` and `tool_input` extraction; only the CWD line is eliminated.
- The path integrity check (BASH_SOURCE comparison) is optional for jmunch since jmunch hooks may be manually installed rather than via a `setup.sh` that registers absolute paths.

---

## 6. Summary Table

| Issue | Affected Hooks | Severity | Fix Available |
|---|---|---|---|
| Worktree sentinel mismatch | session-gate, session-start, sentinel-writer, reindex-after-commit | HIGH | Yes — patch in §5 |
| Submodule root mismatch | session-gate, session-start, sentinel-writer, reindex-after-commit | MEDIUM | Yes — patch in §5 |
| CWD != git root | session-gate, session-start, sentinel-writer, reindex-after-commit | LOW | Yes — patch in §5 |
| No path integrity check | session-gate, session-start, sentinel-writer, reindex-after-commit | LOW | Optional |
