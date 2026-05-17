# Setting Up codebase-memory-mcp in a Claude Code Project

A step-by-step guide to install, configure, and use codebase-memory-mcp — a code knowledge graph MCP server that indexes your codebase into a queryable graph of functions, classes, modules, and their relationships.

## What This Tool Does

**codebase-memory-mcp** parses your source code and builds a graph database containing:
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
- **Cross-service linking** — HTTP, gRPC, GraphQL, and tRPC service detection with protobuf Route extraction; confidence-scored route ↔ call-site matching
- **Channel detection** (`EMITS` / `LISTENS_ON`) — Socket.IO, EventEmitter, and generic pub-sub patterns across 8 languages with constant resolution
- **Cross-repo intelligence** — `CROSS_*` edges link nodes across multiple repos indexed under the same store; multi-galaxy 3D UI for cross-repo architecture
- **Infrastructure-as-code** — Dockerfiles, Kubernetes manifests, and Kustomize overlays indexed as graph nodes
- **LSP-style hybrid type resolution** for Go, C, and C++ (more languages coming)
- **Team-shared persistent artifact** — the graph database is a single SQLite file that can be committed or shared so teammates skip the local index step
- **155 languages** — vendored tree-sitter grammars compiled into the binary; covers mainstream (Python, Go, TypeScript, Rust, Java, C++, ...) plus newer/niche grammars (Solidity, GDScript, Gleam, PowerShell, Move, Cairo, Pkl, Bicep, ...)

---

## Step 1: Install the MCP Server

codebase-memory-mcp is a Node.js package. Install it globally with npm:

```bash
npm install -g codebase-memory-mcp
```

Verify it works:
```bash
codebase-memory-mcp --help
```

---

## Step 2: Register as an MCP Server

### Option A: Project-level `.mcp.json` (recommended)

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

### Option B: Global registration (all projects)

```bash
claude mcp add codebase-memory-mcp -- codebase-memory-mcp
```

Or add manually to `~/.claude/settings.json` under `mcpServers`.

> **Global-first behavior (Phase 59):** When you run `setup.sh --project`, it checks
> `${CLAUDE_CONFIG_DIR:-~/.config/claude-code}/settings.json` before writing `.mcp.json`.
> If `codebase-memory-mcp` is already registered globally, the project `.mcp.json` entry
> is skipped to avoid redundancy. To override and force a per-project pin (e.g., for CI
> environment isolation or a pinned version), pass `--force-local-cmm`.

---

## Step 3: Allow the MCP Tools

Claude Code needs permission to use each MCP tool. Add these to your project's `.claude/settings.local.json` under `allowedTools`:

```
mcp__codebase-memory-mcp__index_repository
mcp__codebase-memory-mcp__index_status
mcp__codebase-memory-mcp__list_projects
mcp__codebase-memory-mcp__get_architecture
mcp__codebase-memory-mcp__get_graph_schema
mcp__codebase-memory-mcp__search_graph
mcp__codebase-memory-mcp__search_code
mcp__codebase-memory-mcp__query_graph
mcp__codebase-memory-mcp__get_code_snippet
mcp__codebase-memory-mcp__trace_call_path
mcp__codebase-memory-mcp__detect_changes
mcp__codebase-memory-mcp__manage_adr
mcp__codebase-memory-mcp__ingest_traces
mcp__codebase-memory-mcp__delete_project
```

> Without these, Claude will ask for permission on every single tool call.

---

## Step 4: Auto-Index on Session Start

Add a SessionStart hook to `~/.claude/settings.json` so the index is always fresh:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "If codebase-memory-mcp tools are available (mcp__codebase-memory-mcp__*), run mcp__codebase-memory-mcp__index_repository to ensure the code graph is current. Incremental indexing skips unchanged files, so this is fast when already indexed. If the server is not available, skip silently."
          }
        ]
      }
    ]
  }
}
```

> **How it works:** Prompt-type hooks inject instructions into Claude's context at session start. The "If available" phrasing means it's a no-op in projects that don't have the MCP server. Incremental indexing via content hashing means only changed files are re-parsed.

---

## Step 5: Add CLAUDE.md Rules (Tells Claude WHEN to Use It)

The hooks and MCP config make the tools *available*. The CLAUDE.md rules tell Claude *when* to prefer them. Add this to your project or global `~/.claude/CLAUDE.md`:

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

## Step 6: Enforcement Hooks (Optional — Makes Claude Actually Follow the Rules)

Rules in CLAUDE.md are instructions — Claude *should* follow them, but sometimes doesn't. Hooks provide runtime enforcement.

### PreToolUse Nudge (Non-blocking reminder)

This hook fires every time Claude tries to use `Read` on a source code file, injecting a reminder to use the graph tools instead.

Create `~/.claude/hooks/codebase-memory-nudge.sh`:

```bash
#!/bin/bash
# PreToolUse hook: nudge toward codebase-memory-mcp when Read is used on code files

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null)

# Only nudge for common source code files
case "$FILE_PATH" in
  *.py|*.ts|*.tsx|*.js|*.jsx|*.go|*.rs|*.java|*.rb|*.pl|*.pm|*.cgi)
    BASENAME=$(basename "$FILE_PATH")
    echo "codebase-memory reminder: Consider using get_code_snippet or search_graph for '$BASENAME' instead of Read. Use Read only if you need full file context."
    ;;
esac
```

```bash
chmod +x ~/.claude/hooks/codebase-memory-nudge.sh
```

Register in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$HOME/.claude/hooks/codebase-memory-nudge.sh\""
          }
        ]
      }
    ]
  }
}
```

### Re-Index After Edits (Keeps index fresh)

Create `~/.claude/hooks/reindex-after-edit.sh`:

```bash
#!/bin/bash
# PostToolUse:Write|Edit — remind Claude to re-index after code changes

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

[ -z "$FILE" ] && exit 0

# Only trigger for source code file types
case "$FILE" in
  *.py|*.ts|*.tsx|*.js|*.jsx|*.go|*.rs|*.java|*.rb|*.pl|*.pm|*.cgi) ;;
  *) exit 0 ;;
esac

# Debounce: skip if we re-indexed within the last 60 seconds
STAMP="/tmp/cbm-reindex-stamp-$(id -u)"
if [ -f "$STAMP" ]; then
  LAST=$(date -r "$STAMP" +%s 2>/dev/null || echo 0)
  NOW=$(date +%s)
  [ $((NOW - LAST)) -lt 60 ] && exit 0
fi
touch "$STAMP"

echo "Source file modified. Consider running index_repository to keep the code graph fresh."
```

```bash
chmod +x ~/.claude/hooks/reindex-after-edit.sh
```

Register in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$HOME/.claude/hooks/reindex-after-edit.sh\""
          }
        ]
      }
    ]
  }
}
```

---

## Tool Reference

### Indexing & Status

| Tool | Purpose |
|------|---------|
| `index_repository` | Parse source files and build/refresh the code graph. Supports `mode='fast'` for large repos (>50K files). Incremental via content hashing. |
| `index_status` | Check if project is indexed, currently indexing, or not found. Shows node/edge counts. |
| `list_projects` | List all indexed projects with timestamps and counts. |
| `delete_project` | Remove a project's graph data. Irreversible. |

### Navigation & Search

| Tool | Purpose |
|------|---------|
| `get_architecture` | Structural overview: languages, packages, entry points, routes, hotspots, boundaries, clusters, layers, file tree, ADR. Call first on unfamiliar codebases. |
| `search_graph` | Find functions/classes/modules by name pattern. Filter by label, degree, relationship type. Case-insensitive regex. Paginated (10/page). |
| `search_code` | Grep-like text search scoped to indexed project. For string literals, TODOs, config values. Paginated. |
| `get_code_snippet` | Fetch source code for a specific function/class by name. Returns signature, complexity, decorators, docstring, caller/callee counts. |
| `trace_call_path` | BFS traversal of call graph. Who calls it (inbound), what it calls (outbound), or both. Hop-by-hop with edge types. |
| `query_graph` | Cypher queries for complex patterns. Edge property filtering, cross-service links, change coupling. 200-row cap. |
| `get_graph_schema` | Node labels, edge types, relationship patterns, sample names. Understand graph structure before querying. |

### Analysis & Operations

| Tool | Purpose |
|------|---------|
| `detect_changes` | Map git diffs to affected graph symbols + blast radius. Risk classification: CRITICAL (hop 1) → LOW (hop 4+). |
| `manage_adr` | CRUD for Architecture Decision Records. 6 fixed sections: PURPOSE, STACK, ARCHITECTURE, PATTERNS, TRADEOFFS, PHILOSOPHY. |
| `ingest_traces` | Validate HTTP_CALLS edges with OpenTelemetry traces. Boosts confidence scores on matched edges. |

---

## Recommended Workflows

### First-time codebase exploration

```
index_repository → get_architecture(aspects=['all']) → search_graph for key areas
```

### Finding and understanding a function

```
search_graph(name_pattern='.*Order.*') → trace_call_path('processOrder') → get_code_snippet('myapp.services.order.processOrder')
```

### Pre-commit impact analysis

```
detect_changes(scope='staged', depth=3) → review CRITICAL/HIGH risk symbols
```

### Dead code detection

```
search_graph(relationship='CALLS', direction='inbound', max_degree=0, exclude_entry_points=true)
```

### Cross-service HTTP links

```
query_graph("MATCH (a)-[r:HTTP_CALLS]->(b) RETURN a.name, b.name, r.url_path, r.confidence_band LIMIT 20")
```

---

## Complete Hook Registry

Here's the full picture of all hooks, where they live, and what they do:

### Global hooks (`~/.claude/settings.json`)

| Event | Matcher | Script | Type | Effect |
|-------|---------|--------|------|--------|
| SessionStart | — | (prompt) | prompt | Checks index status and runs `index_repository` if needed |
| PreToolUse | Read | `codebase-memory-nudge.sh` | command | Non-blocking reminder for source code files |
| PostToolUse | Write\|Edit | `reindex-after-edit.sh` | command | Prompts re-index after source file changes (debounced 60s) |

### Project hooks (`.claude/hooks/` in your project)

The project-level hooks provide stronger enforcement and agent-aware initialization.
Copy them from `hooks/project/` using `setup.sh` or manually.

| Event | Matcher | Script | Type | Effect |
|-------|---------|--------|------|--------|
| SessionStart | — | `cmm-session-start.sh` | command | Resets CMM sentinel; injects rich init prompt for spawned agents, minimal prompt for human sessions |
| PreToolUse | * | `cmm-session-gate.sh` | command | **Blocks** all tools until CMM sentinel exists; allows indexing tools, ToolSearch, and SendMessage through |
| PreToolUse | Agent | `agent-cmm-gate.sh` | command | **Blocks** Agent tool calls that don't reference CMM keywords; exempts VBW agents with a context note |

#### Agent initialization flow (spawned agents)

When Claude spawns a sub-agent, the sub-agent starts a new session. Here is what happens:

1. `cmm-session-start.sh` fires (SessionStart) — detects `$CLAUDE_AGENT_ID` or
   `$CLAUDE_PARENT_SESSION_ID`, deletes the stale sentinel, and injects the rich agent prompt.
2. The agent's first tool call is blocked by `cmm-session-gate.sh` unless it is one of the
   allow-listed tools: `index_repository`, `index_status`, `delete_project`, `ToolSearch`, `SendMessage`.
3. The agent runs `index_status` (or `index_repository`) — `cmm-sentinel-writer.sh` writes the
   sentinel on success.
4. `cmm-session-gate.sh` passes all subsequent tool calls through.
5. The agent reads `.vbw-planning/STATE.md` to find its active phase/plan and proceeds with
   its task using CMM tools.

If the CMM server is unavailable, the agent (or user) can create the sentinel manually:
```bash
touch "/tmp/cmm-session-ready-$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | cut -d' ' -f1)"
```

---

## Data Flow Summary

```
Session starts
  → SessionStart prompt checks index_status
  → Runs index_repository if needed (incremental — only changed files)

Claude needs a function
  → Tries Read on .py file
  → codebase-memory-nudge.sh fires: "Use get_code_snippet or search_graph instead"
  → Claude uses search_graph → get_code_snippet instead
  → Gets source code + metadata without reading the entire file

Claude needs to understand impact
  → detect_changes maps git diff to graph symbols
  → Returns blast radius with risk classification per hop

Claude edits a file
  → reindex-after-edit.sh fires (debounced 60s)
  → Prompts Claude to re-run index_repository
```

---

## Troubleshooting

**"codebase-memory-mcp: command not found"**
- Ensure the package is installed globally: `npm install -g codebase-memory-mcp`
- Verify `$(npm prefix -g)/bin` is in your PATH

**Index status shows "not found"**
- Run `index_repository` with the repo path: `index_repository(repo_path='/path/to/project')`

**search_graph returns no results**
- Check `index_status` to confirm indexing completed
- Use `get_graph_schema` to see what node labels and edge types exist
- Try broader regex patterns with alternatives: `'handler|hdlr|ctrl'`

**query_graph undercounts with COUNT**
- The 200-row cap applies BEFORE aggregation. Use `search_graph` with `min_degree`/`max_degree` for accurate counting.

**detect_changes shows no affected symbols**
- Ensure git is in PATH and the project has been indexed
- Check that changed files contain supported source code (not just config/docs)

---

## Pairing with Context Mode (optional)

[Context Mode MCP](https://github.com/mksglu/context-mode) complements codebase-memory-mcp by sandboxing tool-output and persisting session state via SQLite FTS5. CMM answers "what does this code do?"; Context Mode answers "what did I just observe in this session?". They are independent — CMM works fully without Context Mode.

### Recommended: plugin form (upstream v1.0.122+)

Inside a Claude Code session:

```text
/plugin marketplace add mksglu/context-mode
/plugin install context-mode@context-mode
```

Then run `setup.sh --project` from a shell — it auto-detects the plugin install via `${CLAUDE_PLUGIN_ROOT}` or `~/.claude/plugins/cache/<marketplace>/context-mode/.claude-plugin/plugin.json` and writes the canonical upstream-1.0.122 matcher inventory into `.claude/settings.json`. The plugin form enables upstream's slash commands (`/context-mode:ctx-doctor`, `/ctx-upgrade`, `/ctx-purge`, `/ctx-insight`) and exposes the MCP tools under the `mcp__plugin_context-mode_context-mode__*` prefix.

If `setup.sh --project` finds an MCP-server-only install, it interactively offers to migrate to plugin form (reply `Y` to migrate, `n` to skip once, `keep` to suppress on future runs). Pass `--no-migrate` to force the silent-skip branch for CI / non-interactive environments. The opt-out flag `--skip-context-mode` continues to work and writes no Context Mode entries.

### Alternative: MCP-server install (legacy)

For installs pinned to a pre-1.0.122 upstream or workflows that cannot use `/plugin`, register Context Mode as a plain MCP server. This path does **not** enable the upstream slash commands; the 11 MCP tools are available but you lose the slash-command surface and automatic hook routing.

```bash
# Install globally so npx hits a stable binary
npm install -g context-mode@latest

# Register with Claude Code (project-scoped recommended)
claude mcp add --scope project context-mode -- npx -y context-mode@latest
```

See the project [README](README.md) "Context Mode MCP — Optional Add-on" section for the full setup walkthrough, matcher-coverage details, and known operational caveats.
