---
name: cmm-rules
description: Code navigation via codebase-memory-mcp. CMM Tool Decision Table, orient-first pattern (get_architecture→search_graph→get_code_snippet), behavior notes, CMM vs context-mode.
---

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
- The call graph is LSP-resolved (accurate) via Hybrid LSP for Python, TS/JS/JSX/TSX, PHP, C#, Go, C/C++/CUDA, Java, Kotlin, Rust, and **Perl**. Prefer the graph tools over manual grep for all of them.
- **Perl is a Hybrid LSP language, not a fallback language** — with one caveat. `.pl` and `.pm` are indexed by extension (a `#!…perl` shebang also maps an extensionless file to Perl); packages, `@ISA` / `use parent` / `use base` inheritance with MRO dispatch, `SUPER::` calls, Exporter (`use Foo qw(...)`) import maps, `bless` / `ref($class)||$class` self-type inference, and qualified `Pkg::sub` static calls all resolve, with a zero-edge guarantee on unresolved receivers. Use `search_graph` / `get_code_snippet` on Perl as on any indexed language.
- **The caveat: Perl does not run the dedicated cross-file LSP pass** (`cbm_pxc_has_cross_lsp()` omits it). Its cross-file edges come from the shared symbol registry plus Exporter/`@ISA` import maps — a different mechanism that resolves qualified and inherited calls well. Confirm an exhaustive `trace_path` **caller** set with `search_code` before relying on it being complete.
- **Never infer that a language is unsupported from its absence in a list here.** CMM ships 158 vendored tree-sitter grammars; everything it parses is graph-queryable. When unsure, ask the graph (`get_architecture`, or `search_graph` for a known symbol) — do not fall back to grep on a pessimistic assumption.

`Read` is correct for: non-code files (JSON, YAML, config, Markdown), full-file context (imports, globals), files under 50 lines, and files not yet indexed.

### CMM vs. context-mode

CMM indexes code symbols across sessions (persistent graph of functions/classes/modules). Context-mode captures tool output within one session (FTS5 search over Bash/Read/Grep results). Use CMM for "where is this function defined"; use `ctx_search` for "what did my last test run print".

### Subagents & Workflows — hooks reach the agent; they do not change its strategy

`PreToolUse` / `PostToolUse` hooks **do** fire for tool calls made inside a subagent — measured across 1,798 transcripts, on every Claude Code version from 2.1.175 to 2.1.260, Workflow-spawned workers included. The one real bypass is narrow: `agent-cmm-gate.sh` is `PreToolUse:Agent`, so a Workflow-spawned worker (a `Workflow` call) never matches that **spawn** check; its own tool calls are still gated. What hooks do not do is change strategy — 52% of gated subagent transcripts still make zero CMM calls, and a blocked `Grep` becomes a `Read` more often than a `search_graph`. Paste the block from `rules/cmm-agent-preamble.md` into every `agent()` prompt and agent definition: the prompt is where strategy is set.
