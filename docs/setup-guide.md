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
- **64 languages** — Python, Go, JavaScript, TypeScript, Rust, Java, C++, C#, Ruby, and many more

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

## Step 4: Add CLAUDE.md Rules

The hooks and MCP config make the tools *available*. The CLAUDE.md rules tell Claude *when* to prefer them over `Read`. Add this to your project `CLAUDE.md` or global `~/.claude/CLAUDE.md`:

```markdown
## Code Knowledge Graph — codebase-memory-mcp (when available)

When codebase-memory-mcp tools (`mcp__codebase-memory-mcp__*`) are available, use them as the
**primary tool for code navigation and understanding**.

### Rules

- **Orientation first**: Use `get_architecture` when exploring an unfamiliar codebase or area —
  it provides language breakdown, hotspots, entry points, routes, and cross-service boundaries
- **Search by name**: Use `search_graph` instead of `Grep` when looking for function/class
  definitions — it returns connectivity (callers/callees) and supports regex patterns
- **Fetch specific code**: Use `get_code_snippet` to retrieve individual functions/classes with
  metadata — avoids reading entire files
- **Trace relationships**: Use `trace_call_path` to understand who calls a function and what it
  calls — essential before refactoring
- **Blast radius**: Use `detect_changes` before committing to see which symbols are affected by
  your git changes and their risk classification
- **Text search**: Use `search_code` for string literals, error messages, TODO comments, and
  config values that aren't in the graph as named symbols
- **Complex queries**: Use `query_graph` with Cypher for relationship patterns, edge property
  filtering, and cross-service HTTP/async links
- **Keep index fresh**: Run `index_repository` at session start and after large batch edits.
  The server auto-syncs after initial indexing
- **ADR**: Use `manage_adr` to maintain Architecture Decision Records — fetch before planning
  to validate against ARCHITECTURE, PATTERNS, STACK, and PHILOSOPHY sections

### When Read is correct

- Non-code files (JSON, YAML, config, HTML templates)
- Full file context needed (imports, globals, module-level flow)
- Very small files (<50 lines)
- Files not yet indexed (newly created before next `index_repository`)
- Editing many functions in the same file (batch edit — full Read is cheaper)
```

> **Why this matters:** Without these rules, Claude defaults to `Read` for everything. The rules make the knowledge graph the default for code navigation, with `Read` as the exception.

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
  -> Claude runs index_status, then index_repository if needed
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
│  Injects: "Run index_status, then  │
│  index_repository if stale/missing" │
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

## setup.sh Installer Flags

`setup.sh` automates Steps 1–6 above. Run from the repo root after cloning:

```bash
bash setup.sh [--global] [--project] [--all] [--force] [--dry-run] [--skip-mcp-check] [--skip-statusline]
```

| Flag | Description |
|------|-------------|
| `--global` | Install global hooks to `~/.claude/hooks/` and merge into `~/.claude/settings.json` |
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
