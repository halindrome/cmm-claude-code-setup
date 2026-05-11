## Code Navigation

Use codebase-memory-mcp tools as the primary method for code exploration.

### CMM Tool Decision Table

| Question / Intent | Use |
|-------------------|-----|
| Unfamiliar area / package map | `get_architecture` |
| Find by name (function, class, module) | `search_graph` |
| Source of a specific symbol | `get_code_snippet` |
| Who calls X / what does X call | `trace_call_path` |
| Cross-service or graph-wide queries (Cypher) | `query_graph` |
| Text search in code (string literals, error msgs, TODOs) | `search_code` |

Orient first: `get_architecture` → `search_graph` → `get_code_snippet`. Do not jump straight to reading files.

### Behavior notes (upstream v0.6.1+)

- `search_graph` returns at most **200 rows** by default (upstream cap as of v0.6.1+); pass `offset` to page or use `query_graph` with Cypher for full scans.
- `search_code` auto-converts multi-word input to a regex (`foo bar` → `foo.*bar`); pass an explicit single-token regex if you need different semantics.
- `list_projects` now returns all registered projects, including those with `/tmp/`-rooted paths (prior versions filtered tmp paths silently). Useful when triaging multiple indexed scratch projects during QA.

`Read` is correct for: non-code files (JSON, YAML, config, Markdown), full-file context (imports, globals), files under 50 lines, and files not yet indexed.

### CMM vs. context-mode

CMM indexes code symbols across sessions (persistent graph of functions/classes/modules). Context-mode captures tool output within one session (FTS5 search over Bash/Read/Grep results). Use CMM for "where is this function defined"; use `ctx_search` for "what did my last test run print".
