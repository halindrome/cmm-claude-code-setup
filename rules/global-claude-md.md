> Add this section to your `~/.claude/CLAUDE.md` file (global rules, all projects).

## codebase-memory-mcp — Code Navigation (MANDATORY)

[codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) builds a persistent code knowledge graph across 64 languages. Use its tools as the PRIMARY method for code exploration — they return precise structural results in a single call instead of reading entire files. NEVER fall back to Grep or Read for navigating source code when the graph is indexed.

### Tool Reference

- **`get_architecture`**: ALWAYS run first when exploring an unfamiliar codebase or starting a new task. Returns language breakdown, top packages, entry points, routes, hotspots, and cross-service boundaries. Use `aspects` parameter to narrow output.

- **`search_graph`**: ALWAYS use to find functions, classes, or modules by name pattern. Supports regex (`.*Handler$`), degree filters, label filters. NEVER use Grep to search for function/class definitions — `search_graph` is faster and returns connectivity metadata.

- **`get_code_snippet`**: Use to retrieve source code for a specific function or class by qualified name. Returns source, signature, complexity, callers, callees. NEVER read an entire file to get one function — use this instead.

- **`trace_call_path`**: ALWAYS run before refactoring or modifying a function. Shows inbound callers and outbound callees. Use `direction='both'` for full context. Start with `depth=1`, increase only if needed.

- **`search_code`**: Use for text search in source files — string literals, error messages, TODOs, config values, import statements. Scoped to indexed project with pagination. Case-insensitive by default.

- **`query_graph`**: Use for complex Cypher-like relationship queries, edge property filtering, cross-service HTTP_CALLS edges, async dispatch, and change coupling analysis. ALWAYS include a LIMIT clause.

- **`detect_changes`**: Run BEFORE committing to assess blast radius. Maps git diff hunks to affected graph symbols and traces inbound callers with risk classification (CRITICAL/HIGH/MEDIUM/LOW).

- **`index_repository`**: Run at session start and after batch edits. Supports incremental reindex via content hashing. Auto-sync handles updates after initial indexing.

- **`manage_adr`**: Read/update the Architecture Decision Record. ALWAYS check ADR before making architectural changes. Fixed sections: PURPOSE, STACK, ARCHITECTURE, PATTERNS, TRADEOFFS, PHILOSOPHY.

### Workflow Patterns

**Orientation (new area):**
1. `get_architecture(aspects=["packages", "hotspots"])` — understand structure
2. `search_graph(name_pattern=".*relevant.*")` — find key symbols
3. `get_code_snippet(qualified_name="...")` — read specific code

NEVER jump straight to reading files. Orient first.

**Before refactoring:**
1. `trace_call_path(function_name="...", direction="both")` — find all callers/callees
2. `get_code_snippet` for each affected function
3. `detect_changes` after edits — verify blast radius

**Pre-commit:**
1. `detect_changes(scope="unstaged")` — see affected symbols and risk levels
2. `trace_call_path` for any CRITICAL or HIGH risk symbols
3. Review before proceeding

### When Read is Correct

Use `Read` directly when:
- Non-code files (JSON, YAML, TOML, config, HTML templates, Markdown, .env)
- Full file context needed (imports, globals, module-level initialization flow)
- Very small files (under 50 lines)
- Files not yet indexed (new files before `index_repository`)
- Editing 6+ functions in the same file (batch context is more efficient)
- Jupyter notebooks, READMEs, documentation files

## Context Mode MCP — Execution Sandboxing (if installed)

[Context Mode MCP](https://github.com/mksglu/context-mode) sandboxes tool outputs to prevent context bloat and persists session events in a local SQLite database. These rules apply **only when Context Mode MCP is installed** — if it is not installed, skip this section entirely.

### When to use `ctx_execute` vs. raw Bash

- Use `ctx_execute` for any Bash command that produces large output: logs, test output, API responses, file listings, or any command where full stdout would exceed ~50 lines. Raw Bash sends full stdout to context; `ctx_execute` captures only the relevant portion.
- Use raw `Bash` for short commands where full output is needed (< ~50 lines), git commits, interactive operations, or when `ctx_execute` is unavailable.

### When to use `ctx_fetch_and_index` vs. WebFetch

- Use `ctx_fetch_and_index` for any URL that will be referenced more than once in the session (docs, API specs, GitHub issues). It fetches, detects content type, and indexes into SQLite FTS5 for later `ctx_search` queries.
- Use raw `WebFetch` only for one-off URLs or when Context Mode is not installed.

### When to use `ctx_search` vs. Grep

- Use `ctx_search` to query content previously indexed via `ctx_index` or `ctx_fetch_and_index`. Supports fuzzy matching with BM25 ranking and typo-tolerance.
- Use Grep for files NOT indexed by Context Mode (source code, config files, unindexed content).
- Do NOT use `ctx_search` as a replacement for CMM `search_graph` — they serve different purposes.

### Session resume after compaction

- After context compaction, `ctx_search` can query the event history: "what files were edited?"
- Use `ctx_stats` to check session metrics and indexed content.

### Tool priority order (when Context Mode is installed)

- Code exploration: CMM tools first (`search_graph`, `get_code_snippet`, `trace_call_path`)
- Bash execution with large output: `ctx_execute` or `ctx_batch_execute`
- Web content: `ctx_fetch_and_index` → `ctx_search`
- Indexed doc search: `ctx_search`
- File search (non-indexed): Grep/Glob
