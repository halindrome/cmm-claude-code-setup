# CMM + Context Mode Setup for Claude Code

Hooks, rules, and enforcement layer for two complementary MCP servers:

- **[codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp)** (by [DeusData](https://github.com/DeusData)) — persistent code knowledge graph across 155 languages with cross-repo intelligence and gRPC/GraphQL/tRPC service detection; replaces file-reading with precise graph queries, saving ~99% of tokens on code exploration
- **[Context Mode MCP](https://github.com/mksglu/context-mode)** *(optional)* — execution sandboxing + SQLite session persistence; routes tool outputs through isolated subprocesses to keep large outputs out of the context window (~98% context reduction)

Together they eliminate the two main token sinks in long Claude Code sessions: redundant file reads (CMM) and bloated tool output (Context Mode).

> **Credit where it's due:** The hook-based enforcement approach and repository structure are adapted from [jmunch-claude-code-setup](https://github.com/shacharbard/jmunch-claude-code-setup) by [Shachar Bard](https://github.com/shacharbard). This repo does not contain either MCP server — it provides the enforcement and tracking layer that makes Claude actually use them. All the clever indexing, knowledge graph construction, and execution sandboxing is the MCP authors' work.

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
| Code exploration | CMM (`search_graph`, `get_code_snippet`, `trace_call_path`) | Finding functions, call chains, architecture — always |
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

Setup handles the rest automatically: it installs global hooks and rules (to `$CLAUDE_CONFIG_DIR/` or `~/.claude/`), project hooks and rules (to `.claude/`), detects whether CMM is registered with Claude Code and creates `.mcp.json` if needed, adds all 14 CMM tool names to `.claude/settings.json` (the tool allowlist), and optionally sets up Context Mode — all interactively with prompts at each step.

```bash
# setup.sh options
bash setup.sh --help

  --project         Install project hooks, rules, and settings into current directory
  --global          Install global hooks and rules into ~/.claude/
  --all             Install both
  --force           Overwrite existing files
  --dry-run         Preview changes without writing anything
  --skip-mcp-check  Skip MCP availability prompts (for CI/automation)
```

See [docs/setup-guide.md](docs/setup-guide.md) for the full step-by-step walkthrough.

### Team workflows: shared graph snapshots

CMM (upstream v0.6.1+) supports a team-sharing bootstrap artifact at `.codebase-memory/graph.db.zst`. When this file is present in a repo, CMM's `index_repository` auto-imports it as a starting point instead of indexing from scratch — so teammates who clone the repo can hydrate a fresh local graph from the snapshot in seconds rather than waiting through a full first-time index. The artifact is produced and consumed by CMM itself; this project does not generate or manage it. See the [CMM upstream docs](https://github.com/DeusData/codebase-memory-mcp) for snapshot creation, retention, and CI publishing patterns.

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
    "mcp__codebase-memory-mcp__trace_call_path": 14,
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
  TRACE=$(jq -r '.by_tool["mcp__codebase-memory-mcp__trace_call_path"] // 0' "$COUNTS_FILE")
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
- Use mcp__codebase-memory-mcp__trace_call_path to understand call chains and dependencies
- Use mcp__codebase-memory-mcp__get_architecture for codebase orientation (languages, packages, hotspots, routes)
- Use mcp__codebase-memory-mcp__detect_changes to assess impact of your modifications
- Full Read only when: editing 6+ functions in same file, need imports/globals, file <50 lines, non-code files
```

The `agent-cmm-gate.sh` hook enforces this — spawning is blocked if these instructions (or equivalent `ctx_*` keywords) are missing.

## Context Mode MCP — Optional Add-on

[Context Mode MCP](https://github.com/mksglu/context-mode) reduces context window usage by ~98% by routing tool outputs through sandboxes and persisting session state via SQLite. CMM works fully without it — Context Mode is an additive layer for long sessions where context bloat becomes a bottleneck.

All three Context Mode hooks are included in this repo and **gracefully no-op** when Context Mode is not installed — so you can install them unconditionally and enable Context Mode later.

### Install

```bash
# 1. Install Context Mode (pin @latest so `npx` re-resolves instead of reusing a stale global)
npm install -g context-mode@latest

# 2. Register with Claude Code — always pin `@latest` so npx fetches the newest
#    version each launch rather than reusing whatever version is cached globally.
#    Project-scoped (recommended — only activates in this project):
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

- **PostToolUse** — fires on `Bash`, `Read`, `Write`, `Edit`, `Glob`, `Grep`, `Skill`, `Agent`, `Task*`, `EnterPlanMode`/`ExitPlanMode`, `EnterWorktree`, and the broad `mcp__*` prefix. Upstream `posttooluse.mjs` delegates to `extractEvents()` which persists **semantic session events** (file reads, prompts, rules, subagent completions, task updates, intents, decisions) into a SQLite FTS5 session DB. **Note:** in current upstream `context-mode` (≤1.0.89), the extractor does NOT persist raw `mcp__*` tool outputs — jira, grafana, sentry, or other external-data MCP responses fire the hook but produce zero extractable events, so they are **not** searchable via `ctx_search`. Tracked as a known gap; see the follow-up note below.
- **PreToolUse** — cache-redirect for Bash, WebFetch, Read, Grep, Agent, and context-mode's own `ctx_execute*` tools when the output of a prior equivalent call is already indexed in the session DB
- **PreCompact** — writes a session snapshot before Claude Code compacts context
- **SessionStart** — injects prior-session snapshots
- **UserPromptSubmit** — intent processing for submitted prompts

> **Known capture gap (upstream context-mode).** External-data MCP tool outputs (`mcp__jira__*`, `mcp__grafana__*`, `mcp__sentry__*`, etc.) are not indexed by the upstream `extractEvents` function — the hook matcher includes `mcp__` but the extractor's category set is semantic (file/prompt/rule/subagent/task/intent/decision), not raw tool-output. For workflows that rely on re-querying external data, explicitly `ctx_index(content, intent="…")` the tool response in the same turn, or wait for the upstream PR that adds an `mcp_tool_result` category. Field-validated against `context-mode@1.0.89` on 2026-04-22 during a scout run that issued 9 jira/sentry/grafana calls — capture worked for the scout's file-read / rule / subagent events (38.6% context compression) but zero jira/grafana responses were retrievable via `ctx_search`.

Registration uses a small dispatcher helper at `hooks/project/context-mode-hook-dispatch.sh` (installed into `.claude/hooks/` by `setup.sh --project`). The registered command is `bash <abs>/.claude/hooks/context-mode-hook-dispatch.sh <event>`; the dispatcher exec's the global `context-mode` binary when present and falls back to `npx -y context-mode@latest` only when no global install exists. This ensures hooks fire correctly whether or not `context-mode` is globally installed **and** eliminates the ENOTEMPTY race that bare `npx -y @latest` suffers under rapid concurrent hook fires (see "Why a dispatcher" below). The merge is idempotent — re-running `setup.sh --project` does not duplicate entries. Pass `--skip-context-mode` to opt out; no upstream entries are written.

Our own project hooks (`session-gate`, `ctx-execute-enforcer`, `cmm-nudge`, etc.) remain registered ahead of the upstream entries — their additive enforcement runs first.

> **Why a dispatcher (not bare `npx -y context-mode@latest`).** Every tool call triggers both PreToolUse and PostToolUse hooks. In active sessions with rapid Bash/Read/`mcp__*` calls, parallel `npx -y context-mode@latest` invocations race to refresh the `~/.npm/_npx/<hash>/` cache against `@latest` and collide during atomic rename with `ENOTEMPTY`. Claude Code reports these as "non-blocking" (session continues) but the losing hook silently skips capture. The dispatcher short-circuits to the global `context-mode` binary when it's on PATH, avoiding `npx` entirely on the hot path and eliminating the race for the vast majority of setups. Users with no global install still work via the `npx` fallback — the first invocation primes the cache and subsequent calls hit it serially.

> **Matcher-drift heal (overwrites user matcher edits on upstream entries).**
> On every `setup.sh --project` run, the merge finds each upstream entry by substring match on either `hook claude-code <event>` (legacy/npx form) or `context-mode-hook-dispatch.sh <event>` (current form). It rewrites the `matcher` field back to the upstream default if the two diverge; this keeps all installs on the same tool-coverage contract. **User customizations to the `matcher` field on these five entries are overwritten.** User customizations appended to the dispatcher command (e.g. `bash /path/dispatch.sh posttooluse --verbose`) are preserved — the heal only rewrites the command when `context-mode-hook-dispatch.sh <event>` is absent. Early phase-51 installs using the bare-form or npx-launcher commands are rewritten in-place to the dispatcher form on re-run. Matchers on your other (non-upstream) hook entries — including the CMM enforcement hooks and anything you added by hand — are never touched.

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
