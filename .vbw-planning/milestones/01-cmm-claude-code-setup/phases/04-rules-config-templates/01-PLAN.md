---
phase: "04"
plan: "01"
title: "Write rules/global-claude-md.md"
wave: 1
depends_on: []
must_haves:
  - CLAUDE.md section with ## header
  - Rules for all 9 CMM code-nav tools
  - When Read is correct exceptions
  - Imperative tone with ALWAYS/NEVER
  - Workflow patterns section
---

# Plan 01: Write `rules/global-claude-md.md`

## Output File
`rules/global-claude-md.md`

## Purpose
This file contains a CLAUDE.md-ready section that users append to `~/.claude/CLAUDE.md`. It tells Claude WHEN and HOW to use codebase-memory-mcp tools instead of falling back to `Read`/`Grep`.

## Tasks

### Task 1: Create `rules/` directory and write `rules/global-claude-md.md`

Create the file with the exact structure below. The file IS the CLAUDE.md content — no wrapper, no install instructions, just the raw section ready to append.

### Content Structure

**Header (line 1):**
```
## codebase-memory-mcp — Code Navigation (MANDATORY)
```

**Intro paragraph (2-3 sentences):**
State that codebase-memory-mcp is the PRIMARY tool for all code exploration. Claude MUST use CMM graph tools instead of Read/Grep for navigating source code. The graph is pre-indexed and returns precise structural results.

**Tool Reference section — one rule per tool (9 tools):**

Use format: `- **`tool_name`**: <imperative rule>`

The 9 code-nav tools and their rules:

1. **`get_architecture`**: ALWAYS run first when exploring an unfamiliar codebase or starting a new task. Returns language breakdown, top packages, entry points, routes, hotspots, and cross-service boundaries. Use `aspects` parameter to narrow output.

2. **`search_graph`**: ALWAYS use to find functions, classes, or modules by name pattern. Supports regex. NEVER use Grep or Read to search for function/class definitions — `search_graph` is faster and returns connectivity metadata. Chain with `get_code_snippet` for source.

3. **`get_code_snippet`**: Use to retrieve source code for a specific function or class by qualified name. Returns source, signature, complexity, decorators, docstring, and caller/callee counts. NEVER read an entire file to get one function — use this instead.

4. **`trace_call_path`**: ALWAYS run before refactoring or modifying a function. Shows who calls it (inbound) and what it calls (outbound). Use `direction='both'` for full context. Use `depth=1` first, increase only if needed.

5. **`search_code`**: Use for text search (string literals, error messages, TODOs, config values, import statements). This is the CMM alternative to Grep — scoped to indexed files with pagination.

6. **`query_graph`**: Use for complex relationship queries that need Cypher patterns, edge property filtering, or multi-hop joins. Use for cross-service HTTP_CALLS edges, async dispatch, change coupling analysis. ALWAYS include LIMIT clause.

7. **`detect_changes`**: Run BEFORE committing to see blast radius. Maps git diff hunks to affected graph symbols and traces inbound callers with risk classification (CRITICAL/HIGH/MEDIUM/LOW).

8. **`index_repository`**: Run at session start (hook handles this automatically) and after batch edits. Supports incremental reindex via content hashing.

9. **`manage_adr`**: Use to read/update the Architecture Decision Record. Check ADR before making architectural changes. The ADR has 6 fixed sections: PURPOSE, STACK, ARCHITECTURE, PATTERNS, TRADEOFFS, PHILOSOPHY.

**Workflow Patterns section:**

Three named patterns:

1. **Orientation-first**: Start every task with `get_architecture` (aspects=['packages', 'hotspots']) then `search_graph` to locate relevant code. NEVER jump straight to reading files.

2. **Call-path before refactor**: Before modifying any function, run `trace_call_path` with `direction='both'` to understand callers and callees. Then use `get_code_snippet` to read only the functions you need to change.

3. **Pre-commit blast radius**: Before committing, run `detect_changes` to see which symbols are affected and their risk level. Review CRITICAL and HIGH risk items before proceeding.

**When Read is correct section:**

Header: `### When Read is correct`

Bulleted list of exceptions where full `Read` is appropriate:
- Non-code files (JSON, YAML, TOML, config, HTML templates, Markdown, .env)
- Full file context needed (imports, globals, module-level initialization flow)
- Very small files (under 50 lines)
- Files not yet indexed (new files, generated files)
- Editing 6+ functions in the same file (batch edit is cheaper than 6 separate `get_code_snippet` calls)
- Jupyter notebooks, READMEs, documentation files

**Style requirements:**
- Imperative tone throughout: ALWAYS, NEVER, MUST, DO NOT
- Tool names in backticks (e.g., `search_graph`)
- Keep total length under 80 lines to avoid CLAUDE.md truncation
- No install instructions — this IS the content to append
- Use `###` for subsection headers within the `##` section
