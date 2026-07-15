# CMM Setup for Claude Code

**codebase-memory-mcp (CMM) is the core.** This repo is the hook-based enforcement and tracking layer that makes Claude Code actually use CMM's persistent code knowledge graph instead of re-reading files — saving ~99% of tokens on code exploration. Two add-ons are **optional** and **auto-detected** at install time; each layers on top only when present, and CMM works fully without either:

- **[codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp)** (by [DeusData](https://github.com/DeusData)) — **core, always installed.** Persistent code knowledge graph across 155 languages with cross-repo intelligence and gRPC/GraphQL/tRPC service detection; replaces file-reading with precise graph queries, saving ~99% of tokens on code exploration.
- **[Context Mode MCP](https://github.com/mksglu/context-mode)** *(optional, auto-detected)* — execution sandboxing + SQLite session persistence; routes tool outputs through isolated subprocesses to keep large outputs out of the context window (~98% context reduction). Registered automatically when detected; pass `--skip-context-mode` to opt out. Its hooks no-op gracefully when it is absent.
- **VBW (Vibe Better with Claude Code)** *(optional, auto-detected)* — a structured planning/agent workflow. When a VBW plugin tree is resolvable, setup generates CMM-aware agent overrides; without VBW the bundled agent delta files stay inert and CMM runs on its own.

CMM alone eliminates the biggest token sink in long Claude Code sessions — redundant file reads. Context Mode adds a second layer for bloated tool output; VBW adds structured planning. Neither add-on is required.

> **Credit where it's due:** The hook-based enforcement approach and repository structure are adapted from [jmunch-claude-code-setup](https://github.com/shacharbard/jmunch-claude-code-setup) by [Shachar Bard](https://github.com/shacharbard). This repo does not contain the MCP servers — it provides the enforcement and tracking layer that makes Claude actually use them. All the clever indexing, knowledge graph construction, and execution sandboxing is the MCP authors' work.

## What Each MCP Does

### codebase-memory-mcp (CMM)

Indexes your codebase into a persistent knowledge graph so Claude fetches precise structural results — functions, call chains, architecture overviews — instead of reading entire files. Supports 155 languages (vendored tree-sitter grammars), Cypher-like queries, dead code detection, cross-service HTTP/gRPC/GraphQL/tRPC linking, channel detection (`EMITS`/`LISTENS_ON`) across 8 languages, infrastructure-as-code indexing (Dockerfile, Kubernetes), cross-repo `CROSS_*` edges, LSP-style hybrid type resolution for Go/C/C++, and git diff impact analysis. A single graph query returns what would take dozens of Grep/Read calls.

### Context Mode MCP *(optional)*

Runs commands and processes files in isolated sandboxes so only relevant output enters the conversation. Also persists all tool calls (file edits, git ops, errors) to a local SQLite database indexed with FTS5 full-text search — enabling session resume after context compaction without re-reading history.

Real-world compression examples: Playwright snapshots 56 KB → 299 bytes; GitHub issues (batch of 20) 59 KB → 1.1 KB; access logs 45 KB → 155 bytes.

## How They Work Together

CMM and Context Mode are complementary, not competing:

| Layer | Tool | When to use |
|-------|------|-------------|
| Code exploration | CMM (`search_graph`, `get_code_snippet`, `trace_path`) | Finding functions, call chains, architecture — always |
| Command execution | Context Mode (`ctx_execute`) | Any Bash command producing large output (logs, tests, API responses) |
| Web content | Context Mode (`ctx_fetch_and_index` + `ctx_search`) | URLs referenced more than once in a session |
| Indexed doc search | Context Mode (`ctx_search`) | Querying content previously indexed by Context Mode |
| File search (non-indexed) | Native Grep/Glob | Source code, config, unindexed content |

**Ordering enforced by hooks:** CMM gate fires first (ensures index is ready), then Context Mode gate (routes execution to sandboxes). CMM indexes the codebase; Context Mode sandboxes what happens next.

## Enforcement Stack

| Layer | What | Effect |
|-------|------|--------|
| CLAUDE.md rules | Instructions | Tells Claude when to use CMM and ctx_* tools |
| Session gate (CMM) | Blocking (PreToolUse) | Blocks ALL tools until CMM index is refreshed at session start |
| Session gate (Context Mode) | Blocking (PreToolUse) | Gates tool calls until Context Mode is initialized *(if installed)* |
| Agent spawn gate | Blocking (PreToolUse) | Blocks subagent spawning without MCP instructions in prompt |
| PreToolUse nudge | Non-blocking | Reminds Claude when it tries `Read` on indexed code files |
| PostToolUse logger | Passive | Logs tool calls to SQLite for session resume *(if Context Mode installed)* |
| PostToolUse tracker | Passive | Tracks CMM call counts per tool |
| PreCompact snapshot | Passive | Captures session state before context compression *(if Context Mode installed)* |

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/halindrome/cmm-claude-code-setup
cd cmm-claude-code-setup

# 2. Install CMM binary (macOS/Linux)
curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/scripts/setup.sh | bash
# Or download from: https://github.com/DeusData/codebase-memory-mcp/releases/latest
# Or via npm:       npm install -g codebase-memory-mcp
# Or via pip:       pip install codebase-memory-mcp
# Or via Homebrew:  brew install codebase-memory-mcp

# 3. Run the setup script from your target project directory
cd /path/to/your-project
bash /path/to/cmm-claude-code-setup/setup.sh --all
```

Setup handles the rest automatically: it installs global hooks and rules (to `$CLAUDE_CONFIG_DIR/` or `~/.claude/`), project hooks and rules (to `.claude/`), detects whether CMM is registered with Claude Code and creates `.mcp.json` if needed, writes the CMM (+ Context Mode) tool allowlist to `settings.json`, and optionally sets up Context Mode — all interactively with prompts at each step.

**Tool allowlist (and where it lives):**

The allowlist pre-approves the MCP tool calls so Claude Code doesn't prompt on each use (important for the hooks and subagents that auto-call CMM). It is **not** required for the tools to function — without it they still work, just with a permission prompt.

- **Policy — "complete minus destructive":** every CMM + Context Mode tool is pre-approved **except** the irreversible/system-mutating ones, which must always prompt: CMM `delete_project`, Context Mode `ctx_purge` and `ctx_upgrade`. That's **13** CMM tools and **9** Context Mode tools (written in both the plugin and legacy registration forms). `--skip-context-mode` omits the Context Mode entries.
- **Scope:** Claude Code unions `permissions.allow` across scopes, so `--global` writes the allowlist **once to the global `settings.json`** and every project inherits it — you never need to re-allowlist per project. `--project` writes to `.claude/settings.json`, and is **skipped automatically when the global allowlist already covers every tool** (no duplication). Detection is likewise merged (project + global), so a global allowlist suppresses the per-project "not allowlisted" warning.

**Core vs. optional at install time:**

- **CMM (core)** — hooks, rules, statusline, and the tool allowlist are always installed. This is the enforcement layer's reason for being.
- **Context Mode (optional, auto-detected)** — registered automatically when detected via `detect_context_mode()`; pass `--skip-context-mode` to opt out. Its hooks are installed unconditionally and no-op gracefully when Context Mode is absent, so you can enable it later without re-running setup.
- **VBW (optional, auto-detected)** — setup resolves an active VBW plugin tree (`hooks/lib/vbw-source.sh`) and generates CMM-aware agent overrides only when one is found. The bundled `agents/vbw-*.md` delta files are installed either way but stay inert without VBW; the SessionStart hook self-heals and generates the overrides automatically if VBW is added later.

Non-VBW setup state (Context Mode migration sentinels, optional CMM config) lives under `.claude/.cmm-setup/`, so a CMM-only project needs no `.vbw-planning/` directory (legacy `.vbw-planning/` copies are still read for back-compat).

```bash
# setup.sh options
bash setup.sh --help

  --project         Install project hooks, rules, and settings into current directory
  --global          Install global hooks and rules into ~/.claude/
  --all             Install both
  --force           Overwrite existing files
  --dry-run         Preview changes without writing anything
  --skip-mcp-check  Skip MCP availability prompts (for CI/automation)
  --force-local-cmm Register CMM in project .mcp.json even if globally installed
```

`--project` is global-scope-aware: if `codebase-memory-mcp` is already registered in
`${CLAUDE_CONFIG_DIR:-~/.config/claude-code}/settings.json`, the project `.mcp.json`
entry is skipped to avoid redundancy. Use `--force-local-cmm` for an explicit
per-project pin (e.g., version isolation or CI environment).

See [docs/setup-guide.md](docs/setup-guide.md) for the full step-by-step walkthrough.

### Team workflows: shared graph snapshots

CMM (upstream v0.6.1+) supports a team-sharing bootstrap artifact at `.codebase-memory/graph.db.zst`. When this file is present in a repo, CMM's `index_repository` auto-imports it as a starting point instead of indexing from scratch — so teammates who clone the repo can hydrate a fresh local graph from the snapshot in seconds rather than waiting through a full first-time index. The artifact is produced and consumed by CMM itself; this project does not generate or manage it. See the [CMM upstream docs](https://github.com/DeusData/codebase-memory-mcp) for snapshot creation, retention, and CI publishing patterns.

### Optional CMM tuning

- `CBM_SQLITE_MMAP_SIZE` — overrides the SQLite mmap size used by CMM; useful for very large repos. See CMM upstream docs for default and recommended values.

## Repository Structure

```
hooks/
  global/                               # Install to ~/.claude/hooks/ (all projects)
    cmm-nudge.sh                        # PreToolUse:Read — reminds Claude to use CMM on code files
    reindex-after-edit.sh               # PostToolUse:Write|Edit — prompts re-index after edits
  project/                              # Install to .claude/hooks/ (per project)
    cmm-session-start.sh                # SessionStart — injects index refresh prompt (agent-aware)
    cmm-session-gate.sh                 # PreToolUse:* — blocks all tools until CMM index ready
    cmm-sentinel-writer.sh              # PostToolUse — marks index as refreshed
    reindex-after-commit.sh             # PostToolUse:Bash — marks sentinel stale after git commit; calls touch_project to nudge watcher (5–60s reindex)
    agent-cmm-gate.sh                   # PreToolUse:Agent — blocks agents without MCP instructions
    track-cmm-calls.sh                  # PostToolUse — tracks call counts per CMM tool
    context-mode-sentinel-writer.sh     # PostToolUse:mcp__context-mode__ctx_* — writes sentinel so session-gate unblocks
    # context-mode upstream hooks (PostToolUse capture, PreToolUse cache-redirect,
    # PreCompact snapshot, SessionStart inject, UserPromptSubmit intent) are
    # registered directly in .claude/settings.json via the `context-mode hook
    # claude-code <event>` CLI dispatcher — see "Upstream hook registration
    # (phase 51+)" below.
rules/
  cmm-rules.md                          # CMM tool guidance (installed globally and per-project)
  ctx-rules.md                          # Context Mode tool guidance (ctx_search retrieval protocol)
  project-settings-example.json         # Example .claude/settings.json with all hooks registered
  mcp-example.json                      # Example .mcp.json for project-scoped MCP registration
  allowed-tools.txt                     # CMM + Context Mode tool allowlist for settings.local.json
benchmarks/
  run.sh                                # Benchmark runner (baseline / cmm-cold / cmm-cache)
  README.md                             # Benchmark documentation
docs/
  setup-guide.md                        # Full step-by-step setup guide
```

## How Enforcement Works

### Session Lifecycle

```
Session starts
  -> cmm-session-start.sh injects "run index NOW" prompt (or richer agent init if spawned agent)
  -> cmm-session-gate.sh blocks ALL tools until CMM index done
  -> Claude runs index_repository / index_status
  -> cmm-sentinel-writer.sh marks session as ready
  -> context-mode-session-gate.sh checks Context Mode sentinel (no-op if not installed)
  -> All tools unblocked

Claude explores code
  -> Tries Read on a code file
  -> cmm-nudge.sh fires: use search_graph / get_code_snippet instead
  -> Claude uses CMM graph tools
  -> track-cmm-calls.sh logs the call
  -> context-mode upstream PostToolUse hook captures the event into the session FTS5 index

Claude runs a command
  -> With Context Mode: uses ctx_execute (output sandboxed, only relevant portion enters context)
  -> Without Context Mode: uses Bash (full output enters context)

Claude spawns a subagent
  -> agent-cmm-gate.sh checks prompt for CMM keywords (or ctx_* keywords if Context Mode in use)
  -> Missing? BLOCKED with copy-paste instructions
  -> Present? Allowed

Context window approaches limit
  -> context-mode upstream PreCompact hook fires (if installed)
  -> Snapshots last 20 events + git HEAD into SQLite
  -> After compaction: Claude can query history via ctx_search
```

### Call Tracking (`_call-counts.json`)

The `track-cmm-calls.sh` hook tracks how many times each CMM tool is called. Accumulates across sessions at `~/.cache/codebase-memory-mcp/_call-counts.json`.

```json
{
  "total_calls": 87,
  "by_tool": {
    "mcp__codebase-memory-mcp__search_graph": 32,
    "mcp__codebase-memory-mcp__get_code_snippet": 19,
    "mcp__codebase-memory-mcp__trace_path": 14,
    "mcp__codebase-memory-mcp__get_architecture": 8,
    "mcp__codebase-memory-mcp__query_graph": 6,
    "mcp__codebase-memory-mcp__index_repository": 4
  }
}
```

## Statusline

Display CMM call stats in your Claude Code statusline:

> **Automated install:** Run `bash setup.sh --global` (or `--project`) — setup now
> offers to install the statusline automatically. Use `--skip-statusline` to bypass.

> - **Global install** generates a standalone script showing CMM stats only.
> - **Project install** generates a wrapper that runs your existing global statusline
>   and appends CMM stats (e.g., `my-branch +3 -1 | CMM:5 (sg:3 cs:1 tr:1)`).

### Manual installation

```bash
#!/bin/bash
COUNTS_FILE="$HOME/.cache/codebase-memory-mcp/_call-counts.json"
if [ -f "$COUNTS_FILE" ]; then
  TOTAL=$(jq -r '.total_calls // 0' "$COUNTS_FILE")
  SEARCH=$(jq -r '.by_tool["mcp__codebase-memory-mcp__search_graph"] // 0' "$COUNTS_FILE")
  SNIPPET=$(jq -r '.by_tool["mcp__codebase-memory-mcp__get_code_snippet"] // 0' "$COUNTS_FILE")
  TRACE=$(jq -r '.by_tool["mcp__codebase-memory-mcp__trace_path"] // 0' "$COUNTS_FILE")
  echo "CMM:${TOTAL} (sg:${SEARCH} cs:${SNIPPET} tr:${TRACE})"
else
  echo "CMM:0"
fi
```

Register in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/hooks/statusline-cmm.sh\""
  }
}
```

## Subagent Instructions Template

When spawning subagents, include these instructions to ensure they use CMM:

```
**Code navigation (MANDATORY):** Use codebase-memory-mcp MCP tools for all code exploration.
- Use mcp__codebase-memory-mcp__search_graph to find functions/classes by name pattern — NEVER grep through files to find definitions
- Use mcp__codebase-memory-mcp__get_code_snippet to fetch specific function source code by qualified name
- Use mcp__codebase-memory-mcp__trace_path to understand call chains and dependencies
- Use mcp__codebase-memory-mcp__get_architecture for codebase orientation (languages, packages, hotspots, routes)
- Use mcp__codebase-memory-mcp__detect_changes to assess impact of your modifications
- Full Read only when: editing 6+ functions in same file, need imports/globals, file <50 lines, non-code files
```

The `agent-cmm-gate.sh` hook enforces this — spawning is blocked if these instructions (or equivalent `ctx_*` keywords) are missing.

## Context Mode MCP — Optional Add-on

[Context Mode MCP](https://github.com/mksglu/context-mode) reduces context window usage by ~98% by routing tool outputs through sandboxes and persisting session state via SQLite. CMM works fully without it — Context Mode is an additive layer for long sessions where context bloat becomes a bottleneck.

All three Context Mode hooks are included in this repo and **gracefully no-op** when Context Mode is not installed — so you can install them unconditionally and enable Context Mode later.

### Install

**Recommended — plugin form (upstream v1.0.122+).** This enables upstream's slash commands (`/context-mode:ctx-doctor`, `/ctx-upgrade`, `/ctx-purge`, `/ctx-insight`), automatic hook routing, and the full 11-tool MCP surface. The plugin form exposes Context Mode's MCP tools under the `mcp__plugin_context-mode_context-mode__*` prefix; our hooks register parallel matchers for both this prefix and the legacy `mcp__context-mode__*` prefix, with the plugin form listed first.

```text
# Inside a Claude Code session:
/plugin marketplace add mksglu/context-mode
/plugin install context-mode@context-mode
```

Then run `setup.sh --project` from a shell; it auto-detects the plugin install via `${CLAUDE_PLUGIN_ROOT}` or `~/.claude/plugins/cache/<marketplace>/context-mode/.claude-plugin/plugin.json` and writes the canonical upstream-1.0.122 matcher inventory into `.claude/settings.json`.

If `setup.sh --project` detects an MCP-server-only install (the legacy alternative below), it interactively prompts to migrate to the plugin form. Reply `Y` to migrate, `n` for one-time skip, or `keep` to suppress the prompt on future runs. Pass `--no-migrate` for non-interactive / CI use. The opt-out flag `--skip-context-mode` still works and writes no Context Mode entries to `.claude/settings.json`.

#### Alternative — MCP-server install (legacy)

For installs pinned to a pre-1.0.122 upstream or workflows that cannot use `/plugin`, register Context Mode as a plain MCP server. This path does **not** enable the upstream slash commands (`/context-mode:ctx-doctor`, `/ctx-upgrade`, `/ctx-purge`, `/ctx-insight`); the 11 MCP tools work but you lose the slash-command surface and automatic hook routing.

```bash
# 1. Install Context Mode (pin @latest so `npx` re-resolves instead of reusing a stale global)
npm install -g context-mode@latest

# 2. Register with Claude Code — always pin `@latest` so npx fetches the newest
#    version each launch rather than reusing whatever version is cached globally.
#    Project-scoped (only activates in this project):
claude mcp add --scope project context-mode -- npx -y context-mode@latest
#    Or globally (activates in all projects):
claude mcp add context-mode -- npx -y context-mode@latest

# 3. Hooks are already installed by setup.sh — no extra copy step needed
#    If you installed manually, they're in hooks/project/context-mode-*.sh

# 4. The settings example already includes Context Mode hook entries
#    IMPORTANT: cmm-session-gate must appear before context-mode-session-gate in PreToolUse
#    See rules/project-settings-example.json

# 5. Context Mode rules are enforced by hooks — no manual CLAUDE.md edits needed
```

### Project-Scoped MCP Registration

Both CMM and Context Mode can be activated for a single project only. The `claude mcp add --scope project` command (step 2 above) writes to `.mcp.json` in the project root. You can also edit `.mcp.json` directly:

```json
{
  "mcpServers": {
    "codebase-memory-mcp": {
      "command": "codebase-memory-mcp",
      "args": [],
      "type": "stdio"
    },
    "context-mode": {
      "command": "npx",
      "args": ["-y", "context-mode@latest"]
    }
  }
}
```

The MCP executables live wherever they're installed globally — only the registration is project-scoped.

### What You Get

- Context Mode session gate — fires after CMM gate in PreToolUse; no-ops if not installed
- PostToolUse event logger to `.claude/context-mode.db` — captures file edits, git ops, tool calls
- PreCompact snapshot — records session state before context compression for later resume via `ctx_search`
- CLAUDE.md rules for `ctx_execute`, `ctx_search`, `ctx_fetch_and_index`
- Agent gate accepts `ctx_*` keywords alongside CMM keywords

### Upstream hook registration (phase 51+)

When `setup.sh --project` detects context-mode is installed (or installs it via `.mcp.json`), it also registers context-mode's five upstream hooks in `.claude/settings.json` so the MCP's core capture/redirect machinery fires automatically:

- **PostToolUse** — fires on `Bash`, `Read`, `Write`, `Edit`, `Glob`, `Grep`, `Skill`, `Agent`, `Task*`, `EnterPlanMode`/`ExitPlanMode`, `EnterWorktree`, and the broad `mcp__*` prefix. Upstream `posttooluse.mjs` delegates to `extractEvents()` which persists **semantic session events** (file reads, prompts, rules, subagent completions, task updates, intents, decisions) into a SQLite FTS5 session DB. As of upstream **v1.0.122** ([PR #532](https://github.com/mksglu/context-mode/pull/532), closes [#529](https://github.com/mksglu/context-mode/issues/529)), raw `mcp__*` tool outputs (jira/grafana/sentry/halo responses) are also persisted via the wildcard `mcp__` PostToolUse matcher — resolving the gap previously tracked as [mksglu/context-mode#329](https://github.com/mksglu/context-mode/issues/329). Ongoing regression guard: `tests/test-phase-57-mcp-capture.sh`.
- **PreToolUse** — cache-redirect for Bash, WebFetch, Read, Grep, Agent, and context-mode's own `ctx_execute*` tools when the output of a prior equivalent call is already indexed in the session DB
- **PreCompact** — writes a session snapshot before Claude Code compacts context
- **SessionStart** — injects prior-session snapshots
- **UserPromptSubmit** — intent processing for submitted prompts

> **External-data MCP capture (resolved upstream as of v1.0.122).** External-data MCP tool outputs (`mcp__jira__*`, `mcp__grafana__*`, `mcp__sentry__*`, etc.) are now persisted by upstream's `extractEvents` after [PR #532](https://github.com/mksglu/context-mode/pull/532) added a wildcard `mcp__` matcher to `POST_TOOL_USE_MATCHERS` (closes [#529](https://github.com/mksglu/context-mode/issues/529); resolves the architectural gap historically tracked as [mksglu/context-mode#329](https://github.com/mksglu/context-mode/issues/329)). Installs pinned to a pre-1.0.122 upstream still hit the original gap — upgrade with `/plugin install context-mode@context-mode` (recommended) or `npm install -g context-mode@latest` (legacy MCP-server form) to pick up the fix. Field-validated by `tests/test-phase-57-mcp-capture.sh` against the canonical 1.0.122 matcher inventory.

Registration uses a small dispatcher helper at `hooks/project/context-mode-hook-dispatch.sh` (installed into `.claude/hooks/` by `setup.sh --project`). The registered command is `bash <abs>/.claude/hooks/context-mode-hook-dispatch.sh <event>`; the dispatcher exec's the global `context-mode` binary when present and falls back to `npx -y context-mode@latest` only when no global install exists. This ensures hooks fire correctly whether or not `context-mode` is globally installed **and** eliminates the ENOTEMPTY race that bare `npx -y @latest` suffers under rapid concurrent hook fires (see "Why a dispatcher" below). The merge is idempotent — re-running `setup.sh --project` does not duplicate entries. Pass `--skip-context-mode` to opt out; no upstream entries are written.

Our own project hooks (`session-gate`, `ctx-execute-enforcer`, `cmm-nudge`, etc.) remain registered ahead of the upstream entries — their additive enforcement runs first.

> **Why a dispatcher (not bare `npx -y context-mode@latest`).** Every tool call triggers both PreToolUse and PostToolUse hooks. In active sessions with rapid Bash/Read/`mcp__*` calls, parallel `npx -y context-mode@latest` invocations race to refresh the `~/.npm/_npx/<hash>/` cache against `@latest` and collide during atomic rename with `ENOTEMPTY`. Claude Code reports these as "non-blocking" (session continues) but the losing hook silently skips capture. The dispatcher short-circuits to the global `context-mode` binary when it's on PATH, avoiding `npx` entirely on the hot path and eliminating the race for the vast majority of setups. Users with no global install still work via the `npx` fallback — the first invocation primes the cache and subsequent calls hit it serially.

> **Matcher-drift heal (overwrites user matcher edits on upstream entries).**
> On every `setup.sh --project` run, the merge finds each upstream entry by substring match on either `hook claude-code <event>` (legacy/npx form) or `context-mode-hook-dispatch.sh <event>` (current form). It rewrites the `matcher` field back to the upstream default if the two diverge; this keeps all installs on the same tool-coverage contract. **User customizations to the `matcher` field on these five entries are overwritten.** User customizations appended to the dispatcher command (e.g. `bash /path/dispatch.sh posttooluse --verbose`) are preserved — the heal only rewrites the command when `context-mode-hook-dispatch.sh <event>` is absent. Early phase-51 installs using the bare-form or npx-launcher commands are rewritten in-place to the dispatcher form on re-run. Matchers on your other (non-upstream) hook entries — including the CMM enforcement hooks and anything you added by hand — are never touched.

## VBW (Vibe Better with Claude Code) — Optional Add-on

VBW is a structured planning/agent workflow. It is **optional and auto-detected** — CMM is fully functional without it. When VBW is present, this repo makes its agents CMM-aware; when it is absent, nothing about VBW is required and the bundled agent deltas stay inert.

- **Auto-detection (installed plugins only).** `setup.sh` uses `hooks/lib/vbw-source.sh` (`resolve_vbw_source`) to locate VBW, but only an actual **plugin install** counts as "available": a marketplace install or an active `--plugin-dir` local symlink. A bare **dev-checkout** (a VBW source clone sitting in `~/Sources`) does **not** count — so a project migrating away from VBW isn't handed VBW agents just because source happens to be on disk. Pass `--with-vbw` to opt a dev-checkout back in.
- **Zero VBW footprint when absent.** When VBW is not installed, a `--project` install writes **no VBW files at all**: the `agents/vbw-*.md` deltas are not injected, and the two VBW-only files — `hooks/lib/vbw-source.sh` (the detection library) and `hooks/project/agent-override-generate.sh` (the SessionStart generator) — are not copied and its SessionStart registration is not written. Any VBW artifacts from a prior install (deltas, generated overrides, the two infra files) are moved aside into `.claude/.cmm-setup/vbw-agents.bak/` (reversible). Install VBW (or pass `--with-vbw` for a dev-checkout) and re-run `setup.sh` to enable the overrides.
- **No planning directory required.** A CMM-only project has no `.vbw-planning/`. Setup state that used to live there (Context Mode migration sentinels, optional CMM config) now lives under `.claude/.cmm-setup/`; legacy `.vbw-planning/` copies are still read for back-compat.
- **Migrating an existing install off VBW.** If a project was previously set up with VBW and you re-run `setup.sh --project` on a machine where VBW is no longer resolvable, setup moves any stale generated `.claude/agents/vbw-*.md` overrides aside into `.claude/.cmm-setup/vbw-agents.bak/` (reversible — files are moved, not deleted) so Claude Code stops loading them. The inert delta files and hooks stay in place, so the stack self-heals if VBW returns.

## Uninstalling

Remove the whole stack from a project or globally with `--uninstall` (requires an explicit scope):

```bash
bash setup.sh --uninstall --project --dry-run   # preview what would be removed
bash setup.sh --uninstall --project             # remove from this project
bash setup.sh --uninstall --global              # remove global install
bash setup.sh --uninstall --all --yes           # remove both, no prompt
```

- **What it removes:** the hooks, `hooks/lib/` helpers, rules, skills, VBW agent deltas + generated overrides, the statusline hook, the optional metrics tool, and `.claude/.cmm-setup/` — plus the stack's hook registrations, permission-allowlist entries, and `statusLine` block from `settings.json` / `settings.local.json`.
- **What it preserves:** user-owned hooks, agents, skills, and any other `settings.json` entries the stack did not add are left untouched.
- **Reversible:** removed files are **moved** into a timestamped `.cmm-setup-uninstall-<ts>/` backup dir under the target, and edited JSON files are backed up there first. Delete the backup once you're satisfied.
- **MCP servers:** `.mcp.json` entries for `codebase-memory-mcp` and `context-mode` are **left intact** by default (they're external tools you may want to keep). Pass `--purge-mcp` to remove them too.
- Honors `--dry-run` and `--yes`. Restart any open Claude Code sessions afterward.

## Diagnostics & problem reports

If the enforcement gates feel like they're misfiring — blocking things they shouldn't, or
Claude doesn't seem to be using the CMM/Context-Mode tools the way the rules intend — you can
capture a token-cost report of the gates and attach it to a problem report.

**The tool:** `scripts/analyze-gate-blocks.py` — a standalone, read-only Python CLI (no Claude
session, no network, no writes). It scans your Claude Code session transcripts and reports, per
gate, how often each fired and what it cost in tokens (injected block messages + the follow-up
reasoning), plus high-confidence false-positive blocks.

**Two ways to run it:**

```bash
# A) Straight from a cloned repo (always present):
python3 scripts/analyze-gate-blocks.py --all --share

# B) Installed copy, if you ran setup.sh --with-metrics (opt-in; off by default):
python3 ~/.claude/tools/analyze-gate-blocks.py --all --share     # --global install
python3 .claude/tools/analyze-gate-blocks.py --all --share       # --project install
```

> **Always use `--share` when posting publicly.** It redacts project identities — the
> "Top projects by blocks" list shows opaque ordinals (`project-01`, …) instead of slugs, so no
> usernames, client/project names, or paths leave your machine. All other rows are aggregate and
> non-identifying. (Omit `--share` for full, named output for your own local use.)

Attach the `--share` output to an issue at
<https://github.com/halindrome/cmm-claude-code-setup/issues>.

**Also worth trying first:** just ask Claude directly — *"why aren't you using your CMM /
context-mode rules and tools?"* It can often explain (e.g. the repo isn't indexed, a gate is
failing open, or a rule is being misread) and self-correct without a report.

## Benchmarks

The `benchmarks/` directory contains a reproducible benchmark suite comparing three variants:

- **baseline**: No MCP tools (Claude reads files directly)
- **cmm-cold**: CMM enabled, fresh index each run
- **cmm-cache**: CMM enabled, pre-warmed index

```bash
./benchmarks/run.sh
```

See [benchmarks/README.md](benchmarks/README.md) for prerequisites, configuration, and result interpretation.

## Requirements

- [Claude Code](https://claude.ai/claude-code) CLI
- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) binary
- `python3` (required — used by setup.sh for JSON merging and hook input parsing)
- `jq` (recommended — used by some hooks for JSON parsing)
- [Context Mode MCP](https://github.com/mksglu/context-mode) *(optional)*
- `sqlite3` *(optional — required for Context Mode event logging)*

## Branch Strategy

This project uses a two-branch model:

| Branch | Purpose |
|--------|---------|
| `main` | Stable releases only. Every merge from `develop` requires a version bump. Tagged with `vX.Y.Z`. |
| `develop` | Active development. All feature branches merge here first. |
| `feature/*` | Short-lived branches for individual changes. Branch from `develop`, PR back to `develop`. |

**Release flow:** `feature/* → develop → main` (tagged)

To start new work:
```bash
git checkout develop
git pull origin develop
git checkout -b feature/my-feature
# ... make changes ...
git push origin feature/my-feature
# Open PR targeting develop
```

## Credits

- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) by [DeusData](https://github.com/DeusData)
- [Context Mode MCP](https://github.com/mksglu/context-mode) by [mksglu](https://github.com/mksglu)
- Repository structure and enforcement approach inspired by [jmunch-claude-code-setup](https://github.com/shacharbard/jmunch-claude-code-setup) by [Shachar Bard](https://github.com/shacharbard)

## License

The hooks, rules, and documentation in this repository are licensed under the [MIT License](LICENSE).

This repo does not include either MCP server — only the configuration and enforcement tooling. Each MCP server is a separate project subject to its own license.
