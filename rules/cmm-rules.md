## Code Navigation

Use codebase-memory-mcp tools as the primary method for code exploration.

- `search_graph` — find functions, classes, modules by name pattern
- `get_code_snippet` — retrieve source for a specific function/class
- `trace_call_path` — callers and callees before refactoring
- `search_code` — text search in source files (string literals, TODOs, imports)
- `get_architecture` — codebase overview (run first in unfamiliar areas)
- `detect_changes` — blast radius check before committing

Orient first: `get_architecture` → `search_graph` → `get_code_snippet`. Do not jump straight to reading files.

`Read` is correct for: non-code files (JSON, YAML, config, Markdown), full-file context (imports, globals), files under 50 lines, and files not yet indexed.
