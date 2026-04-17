# Setting Up codebase-memory-mcp with Enforcement Hooks

A step-by-step guide to install, configure, and enforce codebase-memory-mcp — a code knowledge graph MCP server that indexes your codebase into a queryable graph of functions, classes, modules, and their relationships. This guide covers both the MCP server setup and the hook-based enforcement layer that ensures Claude actually uses it.

## What This Tool Does

**codebase-memory-mcp** (by [DeusData](https://github.com/DeusData/codebase-memory-mcp)) parses your source code and builds a graph database containing:
- **Nodes**: Functions, Classes, Modules, Methods, Interfaces, Routes, Files, Packages
- **Edges**: CALLS, HTTP_CALLS, ASYNC_CALLS, IMPORTS, DEFINES, IMPLEMENTS, OVERRIDE, USAGE, FILE_CHANGES_WITH

This lets Claude navigate code by relationships (who calls what, what implements what, blast radius of changes) instead of reading entire files. Key capabilities:

- **Architecture overview** — language breakdown, hotspots, entry points, routes, cross-service boundaries
- **Code search** — find functions/classes by name pattern, filter by degree (fan-in/fan-out), dead code detection
- **Call tracing** — trace call paths inbound/outbound with hop-by-hop detail
- **Code snippets** — fetch individual function/class source with metadata (complexity, callers, callees)
- **Change detection** — map git diffs to affected graph symbols and blast radius
- **Architecture Decision Records** — persistent, section-based architectural summaries
- **Cypher queries** — arbitrary graph queries for complex relationship patterns
- **67 languages** — Python, Go, JavaScript, TypeScript, Rust, Java, C++, C#, Ruby, and many more

---

## Step 1: Install codebase-memory-mcp

codebase-memory-mcp is a single Go binary. Download it from GitHub releases — no npm, no Docker, no Node.js required.

### Download the binary

1. Go to the [latest release](https://github.com/DeusData/codebase-memory-mcp/releases/latest)
2. Download the binary for your platform:

| Platform | Binary |
|----------|--------|
| macOS (Apple Silicon) | `codebase-memory-mcp-darwin-arm64.tar.gz` |
| macOS (Intel) | `codebase-memory-mcp-darwin-amd64.tar.gz` |
| Linux (x86_64) | `codebase-memory-mcp-linux-amd64.tar.gz` |
| Linux (ARM64 / Graviton) | `codebase-memory-mcp-linux-arm64.tar.gz` |
| Windows (x86_64) | `codebase-memory-mcp-windows-amd64.zip` |

3. Extract and move to a directory on your PATH:

```bash
tar xzf codebase-memory-mcp-*.tar.gz
mv codebase-memory-mcp ~/.local/bin/   # or /usr/local/bin/
```

### Alternative: automated download

```bash
curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/scripts/setup.sh | bash
```

### Register with Claude Code

Run the install command to auto-register with Claude Code (also supports Cursor, Windsurf, Codex CLI, Gemini CLI, VS Code, and Zed):

```bash
codebase-memory-mcp install
```

This registers the MCP server, installs 4 task-specific skills, and ensures the binary is on your PATH. Use `--dry-run` to preview without making changes.

Verify it works:

```bash
codebase-memory-mcp --help
```

> **Keeping up to date:** Run `codebase-memory-mcp update` to download the latest release, verify checksums, and atomically swap the binary.

---

## Step 2: Verify MCP Registration

After running `codebase-memory-mcp install`, verify the server is registered.

### Check with the `/mcp` command

In Claude Code, type `/mcp` — you should see `codebase-memory-mcp` listed with 14 tools.

### Check the config file

The `install` command writes to your project's `.mcp.json` or global `~/.claude/settings.json`. The expected entry looks like:

```json
{
  "mcpServers": {
    "codebase-memory-mcp": {
      "type": "stdio",
      "command": "codebase-memory-mcp"
    }
  }
}
```

### Manual registration (if not using `install`)

#### Option A: Project-level `.mcp.json` (recommended)

Add to `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "codebase-memory-mcp": {
      "command": "codebase-memory-mcp",
      "args": [],
      "type": "stdio"
    }
  }
}
```

> This makes the tools available whenever Claude Code opens this project.

#### Option B: Global registration (all projects)

```bash
claude mcp add codebase-memory-mcp -- codebase-memory-mcp
```

Or add manually to `~/.claude/settings.json` under `mcpServers`.

> Restart Claude Code after any manual config change. Verify with `/mcp`.

---

## Step 3: Allow the MCP Tools

Claude Code needs permission to use each MCP tool. Add all 14 tools to your project's `.claude/settings.local.json` under `permissions.allow`:

```json
{
  "permissions": {
    "allow": [
      "mcp__codebase-memory-mcp__index_repository",
      "mcp__codebase-memory-mcp__index_status",
      "mcp__codebase-memory-mcp__list_projects",
      "mcp__codebase-memory-mcp__get_architecture",
      "mcp__codebase-memory-mcp__get_graph_schema",
      "mcp__codebase-memory-mcp__search_graph",
      "mcp__codebase-memory-mcp__search_code",
      "mcp__codebase-memory-mcp__query_graph",
      "mcp__codebase-memory-mcp__get_code_snippet",
      "mcp__codebase-memory-mcp__trace_call_path",
      "mcp__codebase-memory-mcp__detect_changes",
      "mcp__codebase-memory-mcp__manage_adr",
      "mcp__codebase-memory-mcp__ingest_traces",
      "mcp__codebase-memory-mcp__delete_project"
    ]
  }
}
```

> **Why this matters:** Without these entries, Claude will ask for permission on every single tool call, which breaks the flow of automated workflows.

---

## Step 4: Rules (Automatic)

The setup script installs `rules/cmm-rules.md` and `rules/ctx-rules.md` automatically — both globally (`$CLAUDE_CONFIG_DIR/rules/`) and per-project (`.claude/rules/`). These rules tell Claude when to prefer CMM tools over `Read` and when to call `ctx_search` before re-indexing content via Context Mode.

> **No manual step needed.** Running `setup.sh --all` (or `--global` / `--project`) handles this. The rules file is a concise 14-line guide covering tool selection and when `Read` is correct.

---

## Step 5: Install Global Hooks

Global hooks apply to **all projects** where codebase-memory-mcp is available. They live in `~/.claude/hooks/`.

This repo provides global hooks in the `hooks/global/` directory. Copy them to your global hooks location:

```bash
mkdir -p ~/.claude/hooks
cp hooks/global/*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
```

### Global Hook Reference

| Hook Script | Event | Purpose |
|-------------|-------|---------|
| `cmm-nudge.sh` | PreToolUse:Read | Non-blocking reminder when Claude tries to `Read` a source code file, suggesting `get_code_snippet` or `search_graph` instead |
| `reindex-after-edit.sh` | PostToolUse:Write\|Edit | Prompts Claude to re-index after source file changes (debounced 60s) |

> **Note:** These hooks will be created in Phase 2 of this project. The names and purposes are documented here for reference.

### Register global hooks in your Claude config `settings.json`

Merge the following into your `${CLAUDE_CONFIG_DIR}/settings.json` (typically `~/.config/claude-code/settings.json` or `~/.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_CONFIG_DIR}/hooks/cmm-nudge.sh\""
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_CONFIG_DIR}/hooks/reindex-after-edit.sh\""
          }
        ]
      }
    ]
  }
}
```

> The `cmm-nudge.sh` hook fires on every `Read` call and checks if the target is a source code file (`.py`, `.ts`, `.go`, `.rs`, `.java`, etc.). If so, it emits a non-blocking reminder to use graph tools instead. The `reindex-after-edit.sh` hook fires after `Write` or `Edit` on source files and reminds Claude to refresh the index (with a 60-second debounce to avoid spam).

---

## Step 6: Install Project Hooks

Project hooks apply to a **single project**. They live in `.claude/hooks/` within the project directory and provide session lifecycle enforcement.

This repo provides project hooks in the `hooks/project/` directory. Copy them to your project:

```bash
mkdir -p .claude/hooks
cp hooks/project/*.sh .claude/hooks/
chmod +x .claude/hooks/*.sh
```

### Project Hook Reference

| Hook Script | Event | Purpose |
|-------------|-------|---------|
| `cmm-session-start.sh` | SessionStart | Injects prompt to check index status and run `index_repository` if needed |
| `cmm-session-gate.sh` | PreToolUse:* | Blocks ALL tools until the index has been refreshed for this session |
| `cmm-sentinel-writer.sh` | PostToolUse | Writes a sentinel file after `index_repository` completes, unblocking the session gate |
| `agent-cmm-gate.sh` | PreToolUse:Agent | Blocks subagent spawning unless the prompt includes CMM tool instructions |
| `track-cmm-calls.sh` | PostToolUse | Tracks call counts per CMM tool to `~/.cache/codebase-memory-mcp/_call-counts.json` |
| `reindex-after-commit.sh` | PostToolUse:Bash | Marks CMM sentinel stale after a `git commit` and calls `touch_project` to nudge the watcher for faster reindexing (5–60s) |

> **Note:** These hooks will be created in Phases 2 and 3 of this project. The names and purposes are documented here for reference.

### Register project hooks in `.claude/settings.json`

Merge the following into your project's `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/cmm-session-start.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/cmm-session-gate.sh"
          }
        ]
      },
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/agent-cmm-gate.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/cmm-sentinel-writer.sh"
          },
          {
            "type": "command",
            "command": "bash .claude/hooks/track-cmm-calls.sh"
          }
        ]
      }
    ]
  }
}
```

### Automated setup (coming soon)

A `setup.sh` script will be provided in a later phase (Phase 5) to automate hook installation, settings merging, and tool allowlisting. Until then, follow the manual steps above.

---

## Step 7: Auto-Index on Session Start

The session lifecycle hooks (Steps 5-6) work together to ensure the code graph is always fresh when you start working.

### How it works

```
Session starts
  -> cmm-session-start.sh injects "check index and refresh" prompt
  -> cmm-session-gate.sh blocks ALL tools until index is ready
  -> Claude runs index_repository (incremental — fast when already indexed)
  -> cmm-sentinel-writer.sh detects index_repository completion, writes sentinel file
  -> cmm-session-gate.sh reads sentinel, unblocks all tools
  -> Session is ready — all tools available
```

### Data flow diagram

```
┌─────────────────┐
│  Session Start   │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  cmm-session-start.sh              │
│  Injects: "Run index_repository    │
│  to ensure graph is current"        │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  cmm-session-gate.sh (PreToolUse)  │
│  Checks for sentinel file           │
│  Missing? -> BLOCK tool + message   │
│  Present? -> ALLOW (exit 0)         │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  Claude runs index_repository       │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  cmm-sentinel-writer.sh            │
│  Detects index_repository in output │
│  Writes sentinel file               │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  Gate opens — all tools unblocked   │
└─────────────────────────────────────┘
```

> **Auto-sync:** After the initial `index_repository` call, the server keeps the graph fresh automatically via background polling. You don't need to manually re-index — the server detects file changes (mtime + size) and triggers incremental re-indexing within seconds. You can still call `index_repository` manually to force an immediate reindex (e.g., after a large `git pull`).

### Post-Commit Reindexing

When Claude Code runs a `git commit`, the `reindex-after-commit.sh` PostToolUse hook fires automatically. It:

1. Marks the CMM sentinel as **stale** — the session gate will warn (non-blocking) until the index is refreshed.
2. Calls `touch_project` to nudge the CMM watcher, so the next poll cycle runs immediately rather than waiting up to 60 seconds.

**Timing:** The CMM watcher reindexes within **5–60 seconds** depending on project size (adaptive interval). Graph queries made immediately after a commit will return pre-commit results during this window.

**Manual override:** To reindex immediately (blocking), call:
```
mcp__codebase-memory-mcp__index_repository
```

**Debug logging:** If `debug_logging: true` is set in `.vbw-planning/config.json`, each `touch_project` call is logged to `/tmp/cmm-touch-project.log` with timestamp, project name, and result.

**Troubleshooting:**
- If the watcher is not running (CMM server restarted), `touch_project` fails silently. The stale sentinel remains as a fallback — the session gate will prompt you to reindex at the start of the next session.
- To verify the watcher is running: call `mcp__codebase-memory-mcp__index_status` and check the response.

---

## Tool Reference

### Indexing & Status

| Tool | Purpose |
|------|---------|
| `index_repository` | Parse source files and build/refresh the code graph. Supports `mode='fast'` for large repos (>50K files). Incremental via content hashing — only changed files are re-parsed. |
| `index_status` | Check if project is indexed, currently indexing, or not found. Shows last indexed timestamp, node/edge counts. |
| `list_projects` | List all indexed projects with `indexed_at` timestamps and node/edge counts. |
| `delete_project` | Remove a project and all its graph data. Irreversible. |

### Navigation & Search

| Tool | Purpose |
|------|---------|
| `get_architecture` | Structural overview: languages, packages, entry points, routes, hotspots, boundaries, clusters, layers, file tree, ADR. Aspects are selectable — use `['all']` for full orientation or pick specific aspects like `['languages', 'packages']`. |
| `search_graph` | Find functions/classes/modules by name pattern. Filter by label, degree, relationship type, file pattern. Case-insensitive regex by default. Paginated (10/page). Use regex alternatives for broad matching: `'handler\|hdlr\|ctrl'`. |
| `search_code` | Grep-like text search scoped to indexed project. For string literals, TODOs, config values, import statements. Case-insensitive by default. Paginated. |
| `get_code_snippet` | Fetch source code for a specific function/class by name (exact, partial, or short name). Returns signature, return type, complexity, decorators, docstring, caller/callee counts. |
| `trace_call_path` | BFS traversal of call graph. Who calls it (inbound), what it calls (outbound), or both. Hop-by-hop with edge types (CALLS, HTTP_CALLS, ASYNC_CALLS, USAGE, OVERRIDE). Depth 1-5. |
| `query_graph` | Cypher-like queries for complex patterns. Edge property filtering (`r.confidence >= 0.6`), cross-service links, change coupling. 200-row cap — use `search_graph` with degree filters for counting. |
| `get_graph_schema` | Node labels, edge types, relationship patterns, sample names. Understand the graph structure before writing queries. |

### Analysis & Operations

| Tool | Purpose |
|------|---------|
| `detect_changes` | Map git diffs to affected graph symbols + blast radius. Scopes: unstaged, staged, all, branch. Risk classification: CRITICAL (hop 1), HIGH (hop 2), MEDIUM (hop 3), LOW (hop 4+). |
| `manage_adr` | CRUD for Architecture Decision Records. Modes: get, store, update, delete. 6 fixed sections: PURPOSE, STACK, ARCHITECTURE, PATTERNS, TRADEOFFS, PHILOSOPHY. Max 8000 chars. Use `include` filter with get to fetch only needed sections. |
| `ingest_traces` | Validate HTTP_CALLS edges with OpenTelemetry JSON traces (OTLP format). Boosts confidence by +0.15 on matched edges, sets `validated_by_trace=true`. |

---

## Recommended Workflows

### First-time codebase exploration

```
index_repository
  -> get_architecture(aspects=['all'])
  -> search_graph for key areas of interest
```

Start with `get_architecture` to get the full picture: language breakdown, top packages, entry points, routes, hotspots, and cross-service boundaries. Then use `search_graph` to drill into specific areas.

### Finding and understanding a function

```
search_graph(name_pattern='.*Order.*')
  -> trace_call_path('processOrder', direction='both')
  -> get_code_snippet('myapp.services.order.processOrder')
```

Use `search_graph` to discover the exact name, `trace_call_path` to understand its context in the call graph, and `get_code_snippet` to read the actual source with metadata.

### Pre-commit impact analysis

```
detect_changes(scope='staged', depth=3)
  -> review CRITICAL/HIGH risk symbols
  -> trace_call_path on high-risk functions for deeper context
```

Run before committing to see which graph symbols are affected by your changes and their risk classification based on call-graph distance.

### Dead code detection

```
search_graph(
  relationship='CALLS',
  direction='inbound',
  max_degree=0,
  exclude_entry_points=true
)
```

Finds functions with zero callers, excluding entry points (route handlers, `main()`, framework-registered functions).

### Cross-service HTTP links

```
query_graph("MATCH (a)-[r:HTTP_CALLS]->(b)
  RETURN a.name, b.name, r.url_path, r.confidence_band
  LIMIT 20")
```

Discover cross-service communication patterns with confidence scoring.

### Architecture Decision Records

```
manage_adr(mode='get')
  -> review current ADR
manage_adr(mode='update', sections={'PATTERNS': '- Pipeline pattern\n- Repository pattern'})
  -> update specific sections (others preserved)
```

Fetch the ADR before planning to validate against ARCHITECTURE, PATTERNS, STACK, and PHILOSOPHY sections.

---

## Troubleshooting

### "codebase-memory-mcp: command not found"

- Ensure the binary is installed: download from [GitHub releases](https://github.com/DeusData/codebase-memory-mcp/releases/latest)
- Verify `~/.local/bin` (or wherever you placed the binary) is in your PATH
- Add to your shell profile if needed: `export PATH="$HOME/.local/bin:$PATH"`
- This is a Go binary — npm, Node.js, and Docker are NOT required

### Index status shows "not found"

- Run `index_repository` with an explicit repo path: `index_repository(repo_path='/path/to/project')`
- Check `list_projects` to see which projects are currently indexed

### search_graph returns no results

- Check `index_status` to confirm indexing completed
- Use `get_graph_schema` to see what node labels and edge types exist
- Try broader regex patterns with alternatives: `'handler|hdlr|ctrl'`
- Search is case-insensitive by default — no need for `(?i)` in `search_graph`

### query_graph undercounts with COUNT

- The 200-row cap applies BEFORE aggregation — `COUNT` on large result sets will silently undercount
- Use `search_graph` with `min_degree`/`max_degree` for accurate fan-in/fan-out counting

### detect_changes shows no affected symbols

- Ensure `git` is in PATH and the project has been indexed
- Check that changed files contain supported source code (not just config/docs)
- Try `scope='all'` to include both staged and unstaged changes

### Hooks not firing

- Verify hook scripts are executable: `chmod +x ~/.claude/hooks/*.sh` and `chmod +x .claude/hooks/*.sh`
- Check that `settings.json` has the correct hook registration (see Steps 5-6)
- Ensure the `matcher` values match the event names exactly (e.g., `Read`, `Write|Edit`, `*`)
- Test a hook manually: `echo '{"tool_name":"Read","tool_input":{"file_path":"test.py"}}' | bash ~/.claude/hooks/cmm-nudge.sh`

### Session gate blocks everything / sentinel issues

- The session gate blocks all tools until `index_repository` completes and the sentinel file is written
- If stuck, check if `cmm-sentinel-writer.sh` is registered as a PostToolUse hook
- The sentinel file is session-scoped — it resets on each new session
- As a temporary workaround, you can manually create the sentinel file (location will be documented when the hook is created in Phase 2)

### Post-commit reindex not happening / touch_project silent failure

- If `touch_project` returns "watcher not running", the CMM server's watcher thread is not active. This can happen after a server restart.
- The stale sentinel acts as a fallback — the session gate will prompt you to run `index_repository` at the start of the next session.
- To check watcher status: call `mcp__codebase-memory-mcp__index_status` — if the server responds, the watcher is likely running.
- To force an immediate reindex: call `mcp__codebase-memory-mcp__index_repository`.
- To enable debug logging: set `"debug_logging": true` in `.vbw-planning/config.json`. Each `touch_project` call will be logged to `/tmp/cmm-touch-project.log`.

### MCP server not connecting

- Run `codebase-memory-mcp --help` to verify the binary works
- Check `.mcp.json` or `~/.claude/settings.json` for correct config
- Restart Claude Code after config changes
- Use `/mcp` in Claude Code to check server status

---

## Complete Hook Registry

Here's the full picture of all hooks, where they live, and what they do:

### Global hooks (`~/.claude/hooks/` via `~/.claude/settings.json`)

| Event | Matcher | Script | Type | Effect |
|-------|---------|--------|------|--------|
| PreToolUse | Read | `cmm-nudge.sh` | command | Non-blocking reminder for source code files |
| PostToolUse | Write\|Edit | `reindex-after-edit.sh` | command | Prompts re-index after source file changes (debounced 60s) |

### Project hooks (`.claude/hooks/` via `.claude/settings.json`)

| Event | Matcher | Script | Type | Effect |
|-------|---------|--------|------|--------|
| SessionStart | — | `cmm-session-start.sh` | command | Injects index refresh prompt |
| PreToolUse | * | `cmm-session-gate.sh` | command | Blocks ALL tools until index refreshed |
| PreToolUse | Agent | `agent-cmm-gate.sh` | command | Blocks agents without CMM instructions |
| PostToolUse | — | `cmm-sentinel-writer.sh` | command | Marks session as ready after index completes |
| PostToolUse | — | `track-cmm-calls.sh` | command | Tracks call counts per CMM tool |
| PostToolUse | Bash | `reindex-after-commit.sh` | command | Marks sentinel stale after `git commit`; calls `touch_project` to nudge watcher |

---

## Data Flow Summary

```
Session starts
  -> SessionStart hook checks index_status
  -> Runs index_repository if needed (incremental — only changed files)
  -> Session gate opens after sentinel is written

Claude needs a function
  -> Tries Read on .py file
  -> cmm-nudge.sh fires: "Use get_code_snippet or search_graph instead"
  -> Claude uses search_graph -> get_code_snippet instead
  -> Gets source code + metadata without reading the entire file

Claude spawns a subagent
  -> agent-cmm-gate.sh checks prompt for CMM tool instructions
  -> Missing? BLOCKED with instructions to add
  -> Present? Allowed

Claude needs to understand impact
  -> detect_changes maps git diff to graph symbols
  -> Returns blast radius with risk classification per hop

Claude edits a file
  -> reindex-after-edit.sh fires (debounced 60s)
  -> Prompts Claude to re-run index_repository
  -> Auto-sync also detects changes in background
```

---

## Agent Hook Reliability and Known Limitations

Claude Code's agent lifecycle hooks (`SubagentStop`, `TeammateIdle`, `TaskCompleted`) have several confirmed reliability gaps. This project deliberately avoids using these hooks for any critical logic and instead relies on `PostToolUse:Agent` fallback hooks.

### Known Issues

**Issue #1 — SubagentStop doesn't fire when maxTurns is reached**
When a subagent hits the `maxTurns` limit, the last tool call's PostToolUse hook is skipped and the agent terminates with `error_max_turns`. Hooks for turns 1 through N−1 fire normally, but the final turn's hook is lost.
- Severity: HIGH
- Reference: [anthropics/claude-agent-sdk-typescript#58](https://github.com/anthropics/claude-agent-sdk-typescript/issues/58)
- Workaround: `subagent-end-track.sh` (PostToolUse:Agent) marks the CMM sentinel stale at the **Agent tool level** — it fires regardless of how the subagent terminated.

**Issue #2 — SubagentStop cannot identify which subagent finished**
When multiple subagents share a session, `SubagentStop` receives only the `session_id` — no `subagent_type` field is propagated. There is no way to distinguish which agent (Dev, Scout, QA) completed.
- Severity: MEDIUM
- Reference: [anthropics/claude-code#7881](https://github.com/anthropics/claude-code/issues/7881)
- Workaround: `subagent-start-track.sh` writes `session_id → subagent_type` to a state file at spawn time; `subagent-end-track.sh` looks up the type at completion time.

**Issue #3 — Prompt-based SubagentStop hooks don't prevent termination**
If a SubagentStop prompt hook returns `{"ok": false, "reason": "..."}`, the subagent receives the feedback message but is given no additional turn to respond — the session terminates anyway.
- Severity: MEDIUM
- Reference: [anthropics/claude-code#20221](https://github.com/anthropics/claude-code/issues/20221)
- Closed as "not planned" (February 2026)
- **Recommendation: Only use command-based (bash script) hooks for SubagentStop gates. Do not use prompt-based SubagentStop hooks for quality enforcement.**

**Issue #4 — SubagentStop doesn't fire on session degradation (~2.5h)**
After approximately 2.5 hours, session protocol timeouts can terminate a subagent without firing SubagentStop. Affects background subagents especially.
- Severity: HIGH
- Reference: claude-code issue #16047
- Workaround: The session-gate.sh PreToolUse hook catches stale sentinels on the next tool call, providing a safety net even when cleanup hooks don't fire.

**Issue #5 — Skills stop hooks never fire**
Claude Code skills (`type: "command"` in settings.json) do not trigger SubagentStop or Stop events when they finish. Not currently applicable to this project (which uses the Agent tool, not skills), but worth noting for future work.
- Reference: claude-code issue #19225

### Recommended Pattern: PostToolUse:Agent Fallbacks

Instead of SubagentStop, this project uses two hooks that fire on every Agent tool invocation:

| Hook | Event | Purpose |
|------|-------|---------|
| `subagent-start-track.sh` | PreToolUse:Agent | Records `session_id`, `subagent_type`, and timestamp to `/tmp/subagent-tracking-<hash>` |
| `subagent-end-track.sh` | PostToolUse:Agent | Correlates end event, logs execution time, marks sentinel stale if Dev agent completed |

This pattern reliably provides start+end tracking and Dev-agent sentinel marking, even when SubagentStop doesn't fire.

#### Example: State File Tracking

```bash
# /tmp/subagent-tracking-<project-hash> — newline-delimited JSON
{"session_id":"abc-123","subagent_type":"dev","started_at":"2026-03-24T14:30:45Z","project_root":"/path/to/project"}
{"session_id":"def-456","subagent_type":"scout","started_at":"2026-03-24T14:35:10Z","project_root":"/path/to/project"}
```

#### Adding a Custom PostToolUse:Agent Hook

To add your own agent completion logic, create a bash hook and register it in `.claude/settings.json`:

```json
{
  "PostToolUse": [
    {
      "matcher": "Agent",
      "hooks": [
        {
          "type": "command",
          "command": "bash /path/to/your-agent-end-hook.sh"
        }
      ]
    }
  ]
}
```

Requires Claude Code v1.0.33+.

### Team-Mode Detection and SUBAGENT_COMMIT Bypass

In VBW team sessions, multiple subagents run in parallel. To prevent one subagent's commit from stalling others, `reindex-after-commit.sh` skips writing the stale sentinel when running inside a VBW team session.

**Detection logic:**
```bash
# reindex-after-commit.sh checks for VBW team directories
if ls "${CLAUDE_CONFIG_DIR}/teams/vbw-"* >/dev/null 2>&1; then
    # In team mode: skip sentinel stale write
    exit 0
fi
```

**Dev agent override:**
The `dev.md` agent frontmatter sets `SUBAGENT_COMMIT=1`, which bypasses the team-mode check so Dev's commits still mark the sentinel stale (triggering Scout/QA awareness):

```yaml
# .claude/agents/dev.md frontmatter
hooks:
  PostToolUse:
    - matcher: Bash
      command: "SUBAGENT_COMMIT=1 bash .claude/hooks/reindex-after-commit.sh"
```

To replicate this bypass for a custom agent, add the same `SUBAGENT_COMMIT=1` prefix to the hook command in your agent's frontmatter.

### Troubleshooting Agent Lifecycle Issues

**Stale graph after maxTurns termination**

If a Dev subagent hits maxTurns and the graph is stale:
1. Check if `subagent-end-track.sh` ran: `cat /tmp/cmm-subagent-track.log` (only populated when `CMM_DEBUG_TRACKING=1`)
2. Manually mark the sentinel stale: `echo stale > /tmp/cmm-session-ready-<hash>`
3. Run `index_repository` at the start of the next session

**touch_project failures**

If the CMM watcher isn't being nudged after commits:
1. Check `/tmp/cmm-touch-project.log` for errors (only populated when `debug_logging: true` in `.vbw-planning/config.json`)
2. Verify the CMM server is running: `mcp__codebase-memory-mcp__index_status`

**SubagentStart advisory not appearing**

If the "index is stale" advisory isn't appearing at subagent startup:
1. Verify `subagent-cmm-startup.sh` is registered in `.claude/settings.json` under `SubagentStart`
2. Check the sentinel file exists: `ls /tmp/cmm-session-ready-*`
3. If no sentinel exists, run `index_repository` to initialize it

**Enable debug tracking**

To log all subagent start/end events to file:
```bash
export CMM_DEBUG_TRACKING=1
# Then start your Claude Code session; events log to /tmp/cmm-subagent-track.log
```

---

## setup.sh Installer Flags

`setup.sh` automates Steps 1–6 above. Run from the repo root after cloning:

```bash
bash setup.sh [--global] [--project] [--all] [--force] [--dry-run] [--skip-mcp-check] [--skip-statusline]
```

| Flag | Description |
|------|-------------|
| `--global` | Install global hooks and rules to `~/.claude/` and merge into `~/.claude/settings.json` |
| `--project` | Install project hooks to `.claude/hooks/`, rules to `.claude/rules/`, create `.mcp.json`, and merge into `.claude/settings.json` |
| `--all` | Install both global and project hooks |
| `--force` | Overwrite existing files (default: skip existing) |
| `--dry-run` | Show what would be done without making changes |
| `--skip-mcp-check` | Bypass all MCP availability checks (useful for CI/automation) |
| `--skip-statusline` | Skip the interactive CMM statusline installation offer |

---

## Step 8: Statusline (CMM Call Stats)

`setup.sh` offers to install a statusline script that displays CMM call counts in the Claude Code status bar. The offer appears interactively after hook installation completes.

### How it works

During `--global` or `--project` install, setup.sh:

1. Checks if a `statusLine` entry already exists in the target `settings.local.json` or `settings.json`.
2. If yes: warns and asks whether to overwrite (defaults to **N**).
3. If no: asks whether to install (defaults to **N** — opt-in only).
4. On confirmation: generates `statusline-cmm.sh` in the hooks directory and writes the `statusLine` entry to `settings.local.json` (personal, gitignored).

### Two modes

**Global install** (`--global`):
Generates a standalone `statusline-cmm.sh` that reads `~/.cache/codebase-memory-mcp/_call-counts.json` and outputs:
```
CMM:5 (sg:3 cs:1 tr:1)
```

**Project install** (`--project`):
Generates a wrapper `statusline-cmm.sh` that discovers the user's existing global `statusLine.command` from global `settings.json`, runs it, and appends CMM stats with a pipe separator:
```
my-branch +3 -1 | CMM:5 (sg:3 cs:1 tr:1)
```
Falls back to CMM-only output when no global statusline is configured.

### Prerequisites

- **jq** must be installed — the statusline script uses it to parse the call-counts JSON.
  - macOS: `brew install jq`
  - Linux: `apt install jq` or `yum install jq`

### Settings.json output

The installer writes the following entry to `settings.local.json` (personal, gitignored):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"/path/to/hooks/statusline-cmm.sh\""
  }
}
```

### Skip the offer

Use `--skip-statusline` to suppress the interactive prompt (useful in automation and CI):

```bash
bash setup.sh --project --skip-statusline
```

### Manual installation

See the **Statusline** section in `README.md` for the standalone script template and manual `settings.json` registration example.
