## Code Navigation

Use codebase-memory-mcp tools as the primary method for code exploration.

### CMM Tool Decision Table

| Question / Intent | Use |
|-------------------|-----|
| Unfamiliar area / package map | `get_architecture` |
| Find by name (function, class, module) | `search_graph` |
| Source of a specific symbol | `get_code_snippet` |
| Who calls X / what does X call | `trace_path` |
| Cross-service or graph-wide queries (Cypher) | `query_graph` |
| Text search in code (string literals, error msgs, TODOs) | `search_code` |

Orient first: `get_architecture` → `search_graph` → `get_code_snippet`. Do not jump straight to reading files.

### Behavior notes (upstream v0.7.0)

- `search_graph` returns at most **200 rows** by default (upstream cap as of v0.7.0); pass `offset` to page or use `query_graph` with Cypher for full scans.
- `search_code` auto-converts multi-word input to a regex (`foo bar` → `foo.*bar`); pass an explicit single-token regex if you need different semantics.
- `list_projects` now returns all registered projects, including those with `/tmp/`-rooted paths (prior versions filtered tmp paths silently). Useful when triaging multiple indexed scratch projects during QA.
- `trace_path` falls back to a `qualified_name` lookup when the bare `function_name` does not resolve — pass the fully-qualified name (e.g. `module.ClassName.method`) if a bare name returns no results.
- As of v0.7.0, the call graph is LSP-resolved (accurate): `trace_path` and `search_graph` `CALLS` edges resolve to the right callee via hybrid LSP across six languages (Python, PHP, TS/JS/JSX/TSX, C#, C/C++/CUDA, Go). Prefer these tools over manual grep for call-chain analysis.

`Read` is correct for: non-code files (JSON, YAML, config, Markdown), full-file context (imports, globals), files under 50 lines, and files not yet indexed.

### CMM vs. context-mode

CMM indexes code symbols across sessions (persistent graph of functions/classes/modules). Context-mode captures tool output within one session (FTS5 search over Bash/Read/Grep results). Use CMM for "where is this function defined"; use `ctx_search` for "what did my last test run print".
