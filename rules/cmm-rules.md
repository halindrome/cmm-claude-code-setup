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

### Behavior notes (upstream v0.10.8)

- `search_graph` returns at most **200 rows** by default (upstream cap as of v0.10.8); pass `offset` to page or use `query_graph` with Cypher for full scans.
- `search_graph`: use **`name_pattern`** to find a symbol by name. `qn_pattern` matches the whole qualified name — which includes path segments — so in a monorepo it drags in `.scss` variables, vendored `.min.js`, OpenAPI `$ref`s, and anything whose *path* contains the string. A `qn_pattern` search returning rows of unrelated noise means *wrong argument*, not *symbol absent*, and never means *language unsupported*. Re-run with `name_pattern` before concluding anything.
- `search_code` auto-converts multi-word input to a regex (`foo bar` → `foo.*bar`); pass an explicit single-token regex if you need different semantics.
- `list_projects` now returns all registered projects, including those with `/tmp/`-rooted paths (prior versions filtered tmp paths silently). Useful when triaging multiple indexed scratch projects during QA.
- `trace_path` falls back to a `qualified_name` lookup when the bare `function_name` does not resolve — pass the fully-qualified name (e.g. `module.ClassName.method`) if a bare name returns no results.
- As of v0.10.8, the call graph is LSP-resolved (accurate): `trace_path` and `search_graph` `CALLS` edges resolve to the right callee via Hybrid LSP for Python, TS/JS/JSX/TSX, PHP, C#, Go, C/C++/CUDA, Java, Kotlin, Rust, and **Perl**. Prefer the graph tools over manual grep for all of them.
- **Perl is a Hybrid LSP language, not a fallback language** — with one caveat worth knowing. `.pl` and `.pm` are indexed by extension (a `#!…perl` shebang also maps an extensionless file to Perl), and the Perl resolver handles packages, `@ISA` / `use parent` / `use base` inheritance with method-resolution-order dispatch, `SUPER::` calls, Exporter (`use Foo qw(...)`) import maps, `bless` / `ref($class)||$class` self-type inference, and qualified `Pkg::sub` static calls — with a zero-edge guarantee (an unresolved receiver emits no edge rather than a guessed one). Use `search_graph` / `get_code_snippet` on Perl as you would on any other indexed language; do not reach for grep to find a definition.
- **The caveat: Perl does not run the dedicated cross-file LSP pass.** `cbm_pxc_has_cross_lsp()` covers Go, C/C++/CUDA, Python, JS/TS/TSX, PHP, C#, Java, Kotlin and Rust — Perl is not in that switch. Perl's cross-file edges come from the shared symbol registry plus its Exporter/`@ISA` import maps instead, which resolves qualified and inherited calls well but is a different mechanism. So `search_graph` and `get_code_snippet` are as trustworthy on Perl as anywhere; for an exhaustive **caller** set from `trace_path`, confirm with `search_code` before relying on it being complete.
- Languages outside the Hybrid LSP set (e.g. Ruby) still get tree-sitter `CALLS` edges from heuristics — good enough to orient, but confirm a call chain with `search_code` when it matters.
- **Never infer that a language is unsupported from its absence in a list here.** CMM ships 158 vendored tree-sitter grammars; everything it parses is graph-queryable. When unsure whether a language is covered, ask the graph (`get_architecture`, or `search_graph` for a known symbol) — do not fall back to grep on a pessimistic assumption.
- As of v0.10.8, `query_graph` exposes per-function complexity metrics queryable via Cypher: `cyclomatic`, `cognitive`, `param_count`, `loop_depth`, `transitive_loop_depth` (interprocedural worst-case nesting), `linear_scan_in_loop` (O(n²) detection), `alloc_in_loop`, `unguarded_recursion`, and the `recursive` flag. Use these for refactor-candidate and hot-path queries — e.g. `MATCH (f:Function) WHERE f.transitive_loop_depth >= 3 OR f.linear_scan_in_loop >= 1 RETURN f.qualified_name ORDER BY f.transitive_loop_depth DESC`.

`Read` is correct for: non-code files (JSON, YAML, config, Markdown), full-file context (imports, globals), files under 50 lines, and files not yet indexed.

### Monorepo indexing

Always index/query the repository root — pass the monorepo root to `index_repository`, never a subdirectory or sub-package path. Indexing a subtree creates a stray CMM project whose name does not match the root index; the sentinel gate clears silently and all subsequent queries run against the wrong scope.

Before calling `index_repository`, call `list_projects` and check whether any existing entry has a path that is an **ancestor** of (or equal to) the target path. If such an entry exists, use that index rather than creating a new one.

CMM project names are path-derived (`…myrepo-apps-api` vs `…myrepo`), so a subtree entry will **not** match a root-level lookup. Look for ancestor paths, not substring matches — the monorepo root index already covers every file in any subdirectory.

### CMM vs. context-mode

CMM indexes code symbols across sessions (persistent graph of functions/classes/modules). Context-mode captures tool output within one session (FTS5 search over Bash/Read/Grep results). Use CMM for "where is this function defined"; use `ctx_search` for "what did my last test run print".

### Subagents & Workflows — hooks do not reach inside a subagent

The enforcement hooks steer the **main thread only**. They do **not** reach inside a running subagent:

- `PreToolUse` / `PostToolUse` hooks do **not** fire for tool calls made *inside* a subagent (Claude Code issue [#34692](https://github.com/anthropics/claude-code/issues/34692)) — the CMM/grep gates never touch a subagent's `Read`/`Grep`/`Bash`.
- `agent-cmm-gate.sh` (`PreToolUse:Agent`) enforces the preamble on the **main-thread `Agent` tool only**. A **Workflow-spawned worker** (`agent()` / `parallel()` / `pipeline()` lens) surfaces as a `Workflow` call, not an `Agent` call, so it **bypasses the gate**.
- `SubagentStart` `additionalContext` injection is best-effort and not a reliable behavioral lever.

Therefore the subagent's **prompt** (and its `.claude/agents/*.md` `agentType` definition) is the only place CMM/ctx guidance provably lands. When authoring a Workflow or subagent, paste the block from `rules/cmm-agent-preamble.md` (installed to `.claude/rules/cmm-agent-preamble.md`) into every `agent()` prompt and agent definition. Do not rely on hooks to make lens agents use CMM.
