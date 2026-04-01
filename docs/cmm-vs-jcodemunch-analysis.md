# CMM vs jCodeMunch: Comparative Analysis

A detailed evaluation of two approaches to code indexing and searching for Claude Code, comparing codebase-memory-mcp (CMM) and jCodeMunch + jDocMunch.

## Architecture

| Dimension | **codebase-memory-mcp (CMM)** | **jCodeMunch + jDocMunch** |
|-----------|------|-----------|
| **Language** | Go (compiled binary, 154 MB) | Python (pip/uv install) |
| **Parser** | tree-sitter + C FFI (vendored grammars) | tree-sitter via `tree-sitter-language-pack` |
| **Languages** | 64 | 14+ (34 emerging) |
| **Storage** | SQLite per-project (WAL mode) | JSON files + cached raw source |
| **Data model** | Knowledge graph (nodes + edges, Cypher queries) | Flat symbol index (hash map lookup) |
| **Indexing** | 18-pass pipeline with call resolution | 2-pass (AST walk + overload disambiguation) |
| **Retrieval** | Graph traversal, regex search, Cypher | O(1) byte-offset seek, weighted text search |

## What Each Does Well

### CMM excels at structural understanding

- Call graph traversal (`trace_call_path`) — who calls what, full dependency chains
- Cross-service HTTP linking (REST route -> handler -> caller)
- Change impact analysis (`detect_changes`) — maps git diff to blast radius with risk levels
- Community detection (Louvain clustering for module boundaries)
- Architecture overview in a single call (`get_architecture`)
- Cypher-like queries for complex relationship patterns

### jCodeMunch excels at precise retrieval

- O(1) symbol fetch via byte offsets (no graph traversal needed)
- Sliced file reads (`get_file_content` with `start_line`/`end_line`) — the "sliced edit workflow"
- Weighted multi-signal search (name, signature, summary, keywords, docstring)
- Optional AI-generated summaries (Claude Haiku or Gemini Flash)
- jDocMunch adds first-class documentation indexing (Markdown, MDX, RST sections)
- Batch symbol retrieval (`get_symbols` — multiple in one call)

## Token Savings Comparison

| Metric | **CMM** | **jCodeMunch** |
|--------|---------|----------------|
| **Claimed reduction** | 99.2% (5 structural queries: 3.4K vs 412K tokens) | 99-99.5% (single symbol: 200 vs 40K tokens) |
| **Savings tracking** | `savings.json` with `_meta` per response (tokens_saved, baseline_tokens, cost_avoided, reduction_ratio) | `_savings.json` with `_meta` per response (tokens_saved, total_tokens_saved, cost_avoided) |
| **Baseline estimation** | Sum of source file sizes for affected files / 4 | `os.stat()` on cached file / 4 |
| **Genuine vs optimistic** | Tracks all tool calls (no filtering yet) | Setup hooks distinguish "genuine" savings (retrieval tools) from "optimistic" (index/outline tools) |
| **Benchmark suite** | Formal: 5 repos x 5 tasks x 3 variants x n runs, JSONL + CSV output | Per-repo markdown reports (Express, FastAPI, Gin) — no automated multi-run suite |

### Real tracked example (jmunch setup)

```
total_genuine_tokens_saved: 920,376 across 44 calls
  get_file_content: 414K (8 calls)
  get_symbol: 261K (23 calls)
  search_symbols: 243K (12 calls)
```

### CMM benchmark data (raw CSV)

```
3,542,707 total tokens across 13 runs
  cache_read: 2,709,504 (76% — 10x cheaper than input)
  cache_creation: 804,392
  input: 221, output: 28,590
```

## Enforcement Approach

Both setup repos use nearly identical hook patterns (the CMM setup is adapted from jmunch's):

| Hook | **cmm-claude-code-setup** | **jmunch-claude-code-setup** |
|------|--------------------------|------------------------------|
| Session gate | Blocks all tools until index ready | Same pattern |
| Read nudge | **Blocking** (exit 2) on 50+ code extensions | **Blocking** (exit 2) on .py/.ts/.md |
| Agent gate | Blocks spawn without CMM keywords | Same pattern |
| Reindex after edit | Not implemented | Debounced (30s) nudge |
| Reindex after commit | Not implemented | Hard block (marks sentinel stale) |
| Savings tracking | Call counter only (no genuine/optimistic split) | Genuine savings filter + JSONL history |
| Statusline | Call counts (`CMM:87 sg:32 cs:19`) | Token savings (`JCM:920.376K today:45.2K`) |

> **Note on Read blocking scope:** The CMM version blocks Read calls on pure code file extensions only (`.py`, `.ts`, `.go`, `.rs`, etc.) and allows config, data, and documentation files through. jmunch splits blocking across two hooks: jcodemunch-nudge.sh blocks code files, while jdocmunch-nudge.sh blocks documentation files (`.md`, `.mdx`, `.rst`). Both exit 0 (allow) when their respective tools are not installed.

## Tool Sets

### CMM (14 MCP tools)

| Tool | Purpose |
|------|---------|
| `index_repository` | Build/refresh the knowledge graph |
| `index_status` | Check if index exists and is current |
| `list_projects` | List all indexed projects |
| `delete_project` | Purge a project's graph |
| `get_architecture` | Codebase overview (languages, packages, hotspots, entry points, routes, clusters) |
| `get_graph_schema` | Node/edge label counts, relationship patterns |
| `search_graph` | Find functions/classes by name/regex, filter by degree |
| `search_code` | Text search in files (grep-like) |
| `query_graph` | Cypher-like graph queries |
| `get_code_snippet` | Fetch function/class source by qualified name |
| `trace_call_path` | Trace who calls what, call chains |
| `detect_changes` | Map git diff to affected symbols + risk |
| `manage_adr` | Persistent Architecture Decision Record |
| `ingest_traces` | Validate/enrich edges with OpenTelemetry data |

### jCodeMunch (12 MCP tools)

| Tool | Purpose |
|------|---------|
| `index_repo` | Index a GitHub repo via API |
| `index_folder` | Index a local directory |
| `invalidate_cache` | Delete index + raw files |
| `list_repos` | List all indexed repos |
| `get_file_tree` | Nested directory structure |
| `get_file_outline` | Hierarchical symbol tree |
| `get_file_content` | Raw cached content (with optional line range) |
| `get_repo_outline` | High-level overview |
| `get_symbol` | O(1) byte-offset symbol retrieval |
| `get_symbols` | Batch symbol retrieval |
| `search_symbols` | Weighted multi-signal search |
| `search_text` | Full-text grep with context |

### jDocMunch (10 MCP tools)

| Tool | Purpose |
|------|---------|
| `index_local` | Index local documentation |
| `index_repo` | Index remote doc repo |
| `list_repos` | List indexed doc repos |
| `delete_index` | Remove index |
| `get_toc` | Table of contents for a document |
| `get_toc_tree` | Tree of all documents |
| `get_document_outline` | Sections in a document |
| `search_sections` | Find documentation sections |
| `get_section` | Fetch specific section |
| `get_section_context` | Section + ancestors |

## Graph Schema (CMM)

### Node types (13+)

Function, Method, Class, Interface, Module, Enum, Type, Variable, Route, File, Folder, Package, Community

### Edge types (24+)

CALLS, USAGE, IMPORTS, DEFINES, DEFINES_METHOD, TESTS, TESTS_FILE, INHERITS, DECORATES, USES_TYPE, THROWS/RAISES, READS/WRITES, CONFIGURES, MEMBER_OF, HTTP_CALLS, HANDLES, ASYNC_CALLS, IMPLEMENTS, OVERRIDE, FILE_CHANGES_WITH, CONTAINS_FILE, CONTAINS_FOLDER, CONTAINS_PACKAGE

### Call resolution strategies (priority order)

1. **Import map lookup** (0.95 confidence) — resolve via `localName -> module.Function`
2. **Same-module match** (0.90 confidence) — look in `moduleQN.calleeName`
3. **Unique name** (0.75 confidence) — single project-wide match
4. **Suffix match** (0.60-0.70 confidence) — multi-candidate scoring

## Performance

| Operation | **CMM** | **jCodeMunch** |
|-----------|---------|----------------|
| Fresh index (medium repo) | ~6s (49K nodes) | <2s (small repos) |
| Incremental reindex | ~1.2s | Hash-based skip |
| Symbol retrieval | <10ms | <5ms (O(1) byte-seek) |
| Graph/Cypher query | <1ms | N/A |
| Text search | <10ms (regex) | 10-50ms |
| Dead code detection | ~150ms | N/A |
| Call trace (depth=5) | <10ms | N/A |

## Key Tradeoffs

| | **CMM** | **jCodeMunch** |
|---|---------|----------------|
| **Depth of analysis** | Deep — call chains, blast radius, clustering, cross-service | Shallow — symbol-level, no relationship traversal |
| **Speed** | Fresh index ~6s (49K nodes), queries <10ms | Fresh index <2s (small repos), retrieval <5ms |
| **Installation** | Single Go binary (large but self-contained) | `pip install` / `uvx` (Python dependency chain) |
| **Resource usage** | SQLite DB per project (can grow large) | JSON + raw file cache (lighter) |
| **Doc support** | None (code only) | jDocMunch handles .md/.mdx/.rst sections |
| **Edit workflow** | `get_code_snippet` -> Edit | `get_symbol` -> `get_file_content(start, end)` -> Edit (sliced) |
| **Maturity of savings** | Built into binary (`savings.json`), `_meta` in responses | Built into server (`_savings.json`), `_meta` in responses; setup adds genuine/optimistic filtering |

## When to Use Which

### Use CMM when

- You need to understand architecture (call chains, blast radius, entry points)
- Working across multiple services (HTTP_CALLS edges)
- Refactoring (trace all callers before changing a function)
- Large polyglot codebases (64 language support)
- Pre-commit impact analysis

### Use jCodeMunch when

- You need fast, precise symbol retrieval with minimal overhead
- The "sliced edit workflow" matters (read only the lines you'll change)
- Documentation indexing is important (jDocMunch)
- You want AI-generated function summaries
- Lighter footprint is preferred (Python, JSON storage)

## Bottom Line

Both achieve ~99% token reduction for their core use case. The difference is **what questions they can answer**:

- **jCodeMunch** answers: "Give me this function's code" — extremely well, with byte-level precision
- **CMM** answers: "What happens if I change this function?" — with graph-powered call chains, blast radius, and cross-service awareness

They're complementary rather than competitive. jCodeMunch is a **precision retrieval** tool; CMM is a **structural analysis** engine. The setup repos provide nearly identical enforcement patterns because the CMM setup was directly adapted from jmunch's pioneering hook architecture.

---

*Analysis conducted 2026-03-16. Based on source code review of codebase-memory-mcp, jcodemunch-mcp, jdocmunch-mcp, cmm-claude-code-setup, and jmunch-claude-code-setup.*
