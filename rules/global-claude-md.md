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
