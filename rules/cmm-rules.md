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

### When your harness says "prefer Bash", the gates still win

Claude Code's auto / bypass-permissions mode injects guidance along these lines:

> Do your work through the Bash tool wherever it can accomplish the job: read files with `cat`, `head`, or `sed -n`, search with `grep` and `find`, and make file changes with `sed`, heredocs, or short scripts, rather than using the dedicated Read, Edit, or Write tools.

**That is genuine first-party harness text, not a prompt injection.** It is not appended by this stack — nothing in `hooks/`, `rules/` or `skills/` emits it — and it is not an attempt to route around the permission layer. A session that treats it as an attack is wrong about its provenance, and burns a turn arguing with its own instructions.

It does, however, **conflict with this stack**, and here the gates win:

| Auto mode suggests | This stack |
|---|---|
| read with `cat` / `sed -n` | `ctx-execute-enforcer` blocks → use `ctx_execute` (or `Read` for a small non-code file) |
| search with `grep` / `find` | `cmm-grep-nudge` blocks → use `search_code` / `search_graph` |
| edit with `sed -i` / heredocs | allowed (exempt: no stdout), but `Edit` is still preferred for source |

Two things follow. First, `sed -i` and heredocs are **not** an unhooked bypass: `ctx-execute-enforcer` and `cmm-grep-nudge` are `PreToolUse:Bash`, so every one of those commands is gated exactly like any other. Second, `Edit` remains the better tool for a source edit — it requires the exact bytes and fails loudly on a miss, whereas `perl -0pi -e 's{X}{Y}'` exits 0 whether it matched zero times or forty. That is a correctness argument, separate from context.

So: follow the gates, don't treat the harness notice as hostile, and don't rewrite file edits into shell just because the notice suggests it.

### Calling convention (get this right on the first call)

- **`project=` is REQUIRED on every tool above** (`search_graph`, `search_code`, `get_code_snippet`, `trace_path`, `query_graph`, `get_architecture`). It is **not** inferred from the working directory; omit it and the call fails with `project is required`. The value is the repo's absolute path with the leading `/` stripped and every `/` replaced by `-` — `/Users/me/src/app` → `Users-me-src-app`. `index_repository` returns it as the `project` field; `list_projects` lists them all.
- **`search_code` takes `pattern`, not `query`.** There is no `query` parameter on `search_code`; passing one fails with `pattern is required`. (`search_graph` *does* have a `query` parameter, for BM25 full-text search — that is the collision this rule exists to prevent.)
- These two mistakes compose: `search_code(query="foo")` fails twice in a row, once for each. Measured over 30 days of local transcripts, the first CMM call after one of this stack's gate blocks failed on arguments **8.4%** of the time against a **1.3%** baseline. Two consecutive failures is where agents give up on CMM and fall back to `Read` — so the cost of a malformed first call is not one retry, it is the rest of the session.
- **`trace_path` takes `direction="inbound" | "outbound" | "both"`.** `inbound` = callers, `outbound` = callees. It is **not** `"callers"` / `"callees"` — those fail with `invalid direction`. The decision table above says "who calls X / what does X call", which is the right mental model and the wrong vocabulary to type; observed live 2026-09-04 as `direction="callers"`. Cheaper than the two mistakes above, because CMM's error names all three valid values inline, but it is still a wasted round trip on the call that was supposed to prove the graph is worth using.

### When a CMM call fails, read WHICH failure it is

The two failure modes look alike in a transcript and mean opposite things. Getting them backwards is how a session talks itself into grepping for the rest of its life.

- **`index_repository` exits non-zero** (e.g. `index worker ended with exit_nonzero`) — this is a REFRESH that did not run. The index already on disk is untouched and still serving every query. Call `index_status` before concluding anything; a repo with a two-day-old index is still vastly better than grep. Observed 2026-09-06: a refresh was refused while a 99,742-node index answered normally.
- **`Connection closed`, or the `mcp__codebase-memory-mcp__*` tools disappearing mid-session** — the server is genuinely gone, and no CMM call will succeed until it is restarted. This is an operator-side problem, not a property of the repo or the language. Check `~/.cache/codebase-memory-mcp/logs/daemon-conflicts.ndjson`: a `daemon.version_conflict` record whose `active_version` is `pre-cohort/unknown` with an all-zero `active_build` means a stale daemon from an earlier binary holds the coordination lock and is refusing every new worker. **Tell the user** — they can fix it in one command and cannot fix it if you quietly work around it.

In neither case is the correct conclusion "CMM does not work in this repo". Say what failed and which of the two it was.

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

### Subagents & Workflows — hooks reach the agent; they do not change its strategy

The enforcement hooks **do** fire inside subagents. Measured over 1,798 transcripts (30 days, 2026-09-03): 97.2% of subagent transcripts carry a stack hook emission, and `PreToolUse` hard blocks land on tool calls made inside sidechains (`isSidechain: true`) on every Claude Code version from 2.1.175 through 2.1.260. Workflow-spawned workers are gated too (757 gate emissions over 120 days). `SubagentStart` `additionalContext` is delivered, ~2,210 times per 30 days.

One bypass is real, and it is narrow:

- Workflow-spawned `vbw:*` agents never pass through `agent-cmm-gate.sh`, and it also exempts an Agent spawn of any VBW 2 type (`vbw:architect|lead|dev|qa|scout|debugger|docs`; VBW 1 `vbw:vbw-*` types still opt in via `cmm-agent-passthrough.txt`); they reach CMM via the `cmm-query.sh` Bash wrapper (`session-gate.sh` names its `index_repository` call to lift the block, and fails open while the session's index is still building or when the CLI is not on PATH).
- `agent-cmm-gate.sh` is `PreToolUse:**Agent**`. A **Workflow-spawned worker** (`agent()` / `parallel()` / `pipeline()` lens) surfaces as a `Workflow` call, so it never matches that gate — 163 `Workflow` calls, 0 gated, against 1,477 `Agent` calls of which 183 were gated. This affects the **spawn** check only; every other `PreToolUse` gate still fires on the worker's own tool calls.

**Paste the preamble anyway — for a different reason than you may have been told.** The problem is not delivery, it is adoption: 52% of gated subagent transcripts making 5+ tool calls still issue **zero** CMM calls, and only 13–25% of blocked code searches are followed by a CMM call. A hook that blocks a tool does not change the agent's strategy — blocked agents pivot to `Read`/`Bash` rather than to `search_graph`. The prompt is where strategy is set. When authoring a Workflow or subagent, paste the block from `rules/cmm-agent-preamble.md` (installed to `.claude/rules/cmm-agent-preamble.md`) into every `agent()` prompt and agent definition.
