# Benchmark Suite

Measures Claude Code token consumption when answering standard codebase questions — comparing six variants:

- **baseline**: No MCP tools. Claude reads files directly via grep/cat.
- **cmm-cold**: CMM enabled, fresh index per run. Includes indexing overhead.
- **cmm-cache**: CMM enabled, pre-warmed index. Cache hit rate should be high.
- **ctx**: Context Mode enabled (no CMM). Measures execution sandboxing overhead.
- **cmm+ctx-cold**: CMM + Context Mode both enabled, fresh CMM index per run.
- **cmm+ctx-cache**: CMM + Context Mode both enabled, pre-warmed CMM index.

5 repos × 5 tasks × 6 variants × 10 runs = 1,500 data points by default.
(ctx variants require context-mode-mcp to be installed. Run without ctx variants: 3 variants × 10 runs = 750 data points.)

---

## Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| `jq` | Required | Parse JSONL session logs |
| `claude` CLI | Required | Run benchmark prompts |
| `codebase-memory-mcp` | Required (cmm variants) | Graph tools for cmm-cold/cmm-cache runs |
| `context-mode-mcp` | Optional (ctx variants) | Execution sandboxing for ctx/cmm+ctx runs |
| `git` | Required | Shallow-clone benchmark repos |
| `awk` | Standard | Aggregation and report generation (included on all Unix systems) |

**Install claude CLI:**

```bash
# via npm
npm install -g @anthropic-ai/claude-code

# or via Homebrew
brew install claude-code
```

**Install codebase-memory-mcp:**

```bash
# macOS/Linux one-liner
curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/scripts/setup.sh | bash
```

**Install context-mode-mcp** *(optional — required for ctx and cmm+ctx variants)*:

```bash
npm install -g @ubos-ai/context-mode
```

---

## Quick Start

```bash
# Step 1: Clone benchmark repos (first time only, shallow clones)
./benchmarks/scripts/setup-repos.sh

# Step 2: Run full benchmark suite (~2–4 hours for n=10 runs)
./benchmarks/run.sh

# Step 3: View report
cat benchmarks/results/REPORT-*.md
```

To run a single repo only (faster, useful for testing):

```bash
./benchmarks/run.sh --repo expressjs/express
```

To reduce the run count:

```bash
./benchmarks/run.sh --runs 3
```

---

## Configuration

All settings live in `benchmarks/config.sh`. Source it in scripts with:

```bash
source "$(dirname "$0")/../config.sh"
```

| Variable | Default | Description |
|----------|---------|-------------|
| `BENCH_REPOS` | 5 repos | GitHub slugs of benchmark repos (owner/name) |
| `BENCH_VARIANTS` | `baseline cmm-cold cmm-cache` | Variants to run |
| `BENCH_RUNS` | `10` | Number of runs per variant/repo/task combination |
| `BENCH_RESULTS_DIR` | `benchmarks/results` | Output directory for CSV and report files |
| `BENCH_PROMPTS_DIR` | `benchmarks/prompts` | Directory containing task prompt files |
| `BENCH_REPOS_DIR` | `benchmarks/repos` | Directory where repos are cloned |
| `CLAUDE_SESSIONS_DIR` | `~/.config/claude-code/projects` | Claude Code session JSONL directory |

**To change run count:** Edit `BENCH_RUNS` in `config.sh`, or pass `--runs N` to `run.sh`.

**To add a repo:**

1. Add `owner/name` to the `BENCH_REPOS` array in `config.sh`.
2. Add per-task search terms for the repo in `benchmarks/prompts/repo-overrides.json`.
3. Re-run `./benchmarks/scripts/setup-repos.sh` to clone it.

---

## Variants

### baseline

CMM MCP tools are **disabled**. The `.mcp.json` is replaced with `{"mcpServers":{}}` for the duration of the run. Claude answers using only file reads, grep, and other non-graph tools.

Token profile: high input tokens (Claude reads whole files), low or zero cache tokens.

### cmm-cold

CMM MCP tools are **enabled**. Before each run, the CMM index for the repo is deleted so indexing happens from scratch. This measures the full cost including index-build overhead.

Token profile: moderate input tokens, high `cache_creation` tokens (index build), zero `cache_read`.

### cmm-cache

CMM MCP tools are **enabled**. The existing CMM index is retained (pre-warmed from a prior run). Cache hits are expected to be high.

Token profile: low input tokens, zero `cache_creation`, high `cache_read` tokens.

### Context Mode Variants

The following three variants require `context-mode-mcp` to be installed (`npm install -g @ubos-ai/context-mode`). They can be skipped; the remaining 3 variants run without Context Mode.

### ctx

Context Mode MCP only — no CMM tools. The `.mcp.json` is replaced with config for context-mode only.

Token profile: input/output tokens similar to baseline (no code indexing), but execution sandboxing via `ctx_execute`, `ctx_search`, `ctx_fetch_and_index`. Measures Context Mode overhead in isolation.

### cmm+ctx-cold

CMM + Context Mode both enabled. CMM index is purged before each run (fresh indexing). Measures combined cost of code indexing + execution sandboxing.

Token profile: high `cache_creation` tokens (CMM index build) + execution cost, low `cache_read`.

### cmm+ctx-cache

CMM + Context Mode both enabled. CMM index is retained (pre-warmed). Measures combined benefit of cached code indexing + execution sandboxing.

Token profile: low input tokens (indexed queries), high `cache_read` (CMM cache hits).

**Variant switching mechanism:** Each variant swaps `.mcp.json` via `benchmarks/scripts/variant-setup.sh`. Template files must exist at the project root before running:

- `.mcp.json.baseline` — `{"mcpServers":{}}` (no MCP tools)
- `.mcp.json.cmm` — `{"mcpServers":{"codebase-memory-mcp":{...}}}` (your CMM config)
- `.mcp.json.ctx` — `{"mcpServers":{"context-mode":{...}}}` (Context Mode only)
- `.mcp.json.cmm+ctx` — `{"mcpServers":{"codebase-memory-mcp":{...},"context-mode":{...}}}` (both MCPs)

---

## The 5 Benchmark Tasks

Task prompts live in `benchmarks/prompts/`. The `{SEARCH_TERM}` placeholder is filled per-repo from `repo-overrides.json`.

| Task | File | Description |
|------|------|-------------|
| 01-find-callers | `01-find-callers.txt` | List all functions that call a given function, with file path and line number |
| 02-call-graph | `02-call-graph.txt` | Show the 3-level call graph from the main entry point |
| 03-list-exports | `03-list-exports.txt` | List all publicly exported functions/classes matching a term |
| 04-find-imports | `04-find-imports.txt` | Find files that import a given module/package |
| 05-dead-code | `05-dead-code.txt` | Identify functions defined but never called (potential dead code) |

**Complexity notes:** Tasks 01, 03, and 04 are medium–low complexity. Tasks 02 and 05 are high complexity — they require global call graph traversal and are where CMM's advantage is largest.

---

## Results Interpretation

### CSV Schema

**Raw CSV** (`results/raw-YYYYMMDD-HHMMSS.csv`): one row per run.

| Column | Description |
|--------|-------------|
| `variant` | One of: `baseline`, `cmm-cold`, `cmm-cache` |
| `repo` | GitHub slug (e.g. `expressjs/express`) |
| `task` | Task ID (e.g. `01`) |
| `run` | Run number within the variant/repo/task group |
| `input_tokens` | Billed input tokens (excludes cache) |
| `output_tokens` | Output tokens generated |
| `cache_creation` | Cache creation tokens (cmm-cold index build overhead) |
| `cache_read` | Cache read tokens (cmm-cache hits) |
| `total_tokens` | Sum of all token columns |

**Aggregated CSV** (`results/aggregated-YYYYMMDD-HHMMSS.csv`): one row per variant/repo/task group.

Columns: `variant, repo, task, n, input_mean, input_stddev, output_mean, output_stddev, cache_creation_mean, cache_creation_stddev, cache_read_mean, cache_read_stddev, total_mean, total_stddev`

### Comparison Table

The report's Summary Table shows mean total tokens per variant across all repos and tasks, plus a `vs Baseline` percentage column.

**What "token reduction %" means:** The percentage change in mean total tokens compared to baseline. A negative percentage (e.g. `-85%`) means CMM consumed fewer tokens. A positive percentage means the variant used more tokens than baseline (can happen with cmm-cold due to cache_creation overhead).

**Interpreting cache tokens:** `cache_read` tokens are billed at a lower rate than `input_tokens`. When comparing cost (not just token counts), account for Anthropic's cache read discount (~10× cheaper than input tokens).

---

## Troubleshooting

**Rate limits:** If runs fail with 429 errors, increase `RUN_DELAY` in `benchmarks/scripts/run-benchmarks.sh` (default: 5 seconds between runs).

**Session not found:** The runner calls `find-session.sh --after <timestamp>`. Verify that `claude --print "<prompt>"` creates a JSONL session file under `~/.config/claude-code/projects/`. Check that the claude CLI version supports `--print`.

**CMM not indexing:** If cmm-cold runs show zero cache_creation tokens, CMM may not be indexing. Run `index_repository` manually in a Claude Code session for the target repo, then re-check that the `.mcp.json.cmm` template is correctly configured.

**Slow runs:** Use `--repo expressjs/express` to test a single small repo before running all five. Also try `--runs 1` to verify the pipeline produces output before committing to a full run.

**Variant not switching:** Check that `.mcp.json.baseline` and `.mcp.json.cmm` exist in the project root. The `variant-setup.sh` script logs `[warn] .mcp.json.cmm not found` if the CMM template is missing.

**Context Mode not initializing:** If ctx or cmm+ctx variants fail with `context-mode: command not found`, install context-mode-mcp:

```bash
npm install -g @ubos-ai/context-mode
```

Verify installation: `context-mode --version`. Also confirm `.mcp.json.ctx` and `.mcp.json.cmm+ctx` template files exist at the project root.

**Context Mode SQLite errors:** Context Mode stores session state in `.claude/context-mode.db`. If ctx variants fail with SQLite errors, check that the `.claude/` directory has write permissions. To reset session state, delete the database:

```bash
rm -f .claude/context-mode.db
```

---

## Extending

### Adding a new repo

1. Add the GitHub slug to `BENCH_REPOS` in `benchmarks/config.sh`:
   ```bash
   BENCH_REPOS=("expressjs/express" "go-chi/chi" "httpie/cli" "redis/redis" "meilisearch/meilisearch" "your-org/your-repo")
   ```
2. Add per-task search terms to `benchmarks/prompts/repo-overrides.json`:
   ```json
   "your-org/your-repo": {
     "01": "functionName",
     "02": "entryPoint",
     "03": "ModuleName",
     "04": "importedPackage",
     "05": "deprecated"
   }
   ```
3. Clone the repo:
   ```bash
   ./benchmarks/scripts/setup-repos.sh
   ```

### Adding a new prompt

1. Create a new file in `benchmarks/prompts/` with the naming convention `NN-description.txt` (e.g. `06-architecture.txt`).
2. Use `{SEARCH_TERM}` as a placeholder if the prompt needs a repo-specific term.
3. Add the task number to the `for task_num in` loop in `benchmarks/scripts/run-benchmarks.sh`.
4. Add repo-specific terms to `repo-overrides.json` for each repo.

### Adding a new variant

1. Add the variant name to `BENCH_VARIANTS` in `config.sh`.
2. Add a `case` block in `benchmarks/scripts/variant-setup.sh` implementing `setup_variant` and `teardown_variant` for the new variant.
3. Create a `.mcp.json.<variant>` template file at the project root with the desired MCP server configuration.
   - **No-purge variants** (e.g. `ctx`): no index deletion needed — just swap `.mcp.json`.
   - **Purge variants** (e.g. `cmm+ctx-cold`): add index deletion logic mirroring the `cmm-cold` case block.
4. Update the error message in `setup_variant` to list the new variant name.
5. Document the new variant in `benchmarks/README.md` following the style of the existing variant descriptions.

Use `ctx` as the reference for a "no-purge" variant (Context Mode only, no CMM index to manage) and `cmm+ctx-cold` as the reference for a "purge" variant (CMM index deleted before each run).

---

## Results

See [REPORT-2026-03-14.md](results/REPORT-2026-03-14.md) for the first full run with all 6 variants on expressjs/express (n=3).

Key findings:
- All 6 variants within ~45% of baseline in total tokens on expressjs/express
- `cmm+ctx-cold` was closest to baseline (+2.5%)
- Task 05 (dead-code) dominates token variance across all variants
- `cache_read` tokens are 70–86% of total — actual cost difference is smaller than raw counts suggest (~10× cache read discount)
- Full multi-repo runs needed for statistically significant conclusions

---

## See Also

- `benchmarks/results/example-raw.csv` — example raw output
- `benchmarks/results/example-aggregated.csv` — example aggregated output
- `benchmarks/results/example-REPORT.md` — example report with realistic numbers
- `benchmarks/results/REPORT-TEMPLATE.md` — report template used by `generate-report.sh`
