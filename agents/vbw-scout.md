---
name: vbw-scout
description: Research agent for web/doc/codebase scanning and read-only live validation. Writes RESEARCH.md files directly.
disallowedTools: Edit, NotebookEdit, Task, TaskCreate, Agent, TeamCreate, TeamDelete
permissionMode: plan
model: inherit
memory: local
hooks:
  PreToolUse:
    - matcher: "Read"
      hooks:
        - type: command
          command: "bash .claude/hooks/cmm-nudge.sh"
    - matcher: "Grep"
      hooks:
        - type: command
          command: "bash .claude/hooks/cmm-grep-nudge.sh"
    - matcher: "WebFetch"
      hooks:
        - type: command
          command: "bash .claude/hooks/webfetch-nudge.sh"
  PostToolUse:
    - matcher: "mcp__codebase-memory-mcp__*"
      hooks:
        - type: command
          command: "bash .claude/hooks/track-cmm-calls.sh"
    - matcher: "mcp__codebase-memory-mcp__search_graph|mcp__codebase-memory-mcp__get_code_snippet|mcp__codebase-memory-mcp__trace_path|mcp__codebase-memory-mcp__query_graph"
      hooks:
        - type: command
          command: "bash .claude/hooks/cmm-query-stale-advisory.sh"
    - matcher: "mcp__codebase-memory-mcp__search_graph"
      hooks:
        - type: command
          command: "bash .claude/hooks/cmm-orient-nudge.sh"
skills: [cmm-rules, ctx-rules]
x-cmm-base-sha: ""
x-cmm-delta-sha: ""
---

<!-- generated — do not edit manually; run setup.sh to refresh -->

<!-- cmm-delta:begin name=project-level-override -->
<!-- PROJECT-LEVEL OVERRIDE: This file shadows the VBW plugin agent "vbw-scout" to inject
     CMM enforcement hooks via frontmatter. Plugin agents ignore hooks: fields, so this
     project-level override is the only way to enforce PreToolUse/PostToolUse hooks inside
     VBW subagents.

     MAINTENANCE: If the VBW plugin updates vbw-scout.md, run setup.sh to regenerate.
     Compare against the plugin source at:
     ~/.config/claude-code/plugins/cache/vbw-marketplace/vbw/*/agents/vbw-scout.md

     CMM v0.6.1+ NOTE: `mcp__codebase-memory-mcp__list_projects` now surfaces /tmp/-rooted
     projects (upstream commit eb0627e). QA bundle-install probes that index a /tmp/
     scratch project (Phase 49/52/54/55/56 patterns) will appear in list_projects output. -->
<!-- cmm-delta:end name=project-level-override -->

<!-- cmm-delta:begin name=ctx-web-fetch -->
## Context Mode Web Fetch

When `mcp__context-mode__ctx_fetch_and_index` is available in your tool list (Context Mode is installed):
- **Prefer `ctx_fetch_and_index` over raw `WebFetch`** for any URL you will reference more than once in this research session (documentation pages, API specs, GitHub issues, data sources). It fetches, detects content type, and indexes into SQLite FTS5 for later `ctx_search` queries.
- Use raw `WebFetch` for one-off URLs or when `ctx_fetch_and_index` is not available.
- After fetching, use `ctx_search` to query indexed content rather than re-fetching the same URL.

When Context Mode is not installed (`mcp__context-mode__ctx_fetch_and_index` not in your available tools): use raw `WebFetch` as normal — no change in behavior.
<!-- cmm-delta:end name=ctx-web-fetch -->

<!-- cmm-delta:begin name=research-output-indexing -->
## Research Output Indexing

After writing findings to the `<output_path>` file and Context Mode is available (`mcp__context-mode__ctx_fetch_and_index` in your tool list):
- Call `mcp__context-mode__ctx_index` on the output_path with `source: "Scout: {output_path filename}"` to index the research findings into the Context Mode FTS5 store.
- This makes the findings searchable via `ctx_search` in later planning stages (Lead, Dev, QA), even after context compaction.
- Only do this when all three conditions are met: (1) `output_path` was provided, (2) Write succeeded, (3) output_path is inside `.vbw-planning/`.
- If `ctx_index` fails, proceed without error — indexing is a non-critical optimization (findings are already on disk).
- Skip indexing in standalone mode (no output_path — findings returned as text, nothing to index).
<!-- cmm-delta:end name=research-output-indexing -->

<!-- cmm-delta:begin name=context-mode-capture -->
## Context Mode Capture (PostToolUse active)

When context-mode is installed (phase 51 registers its upstream hooks in .claude/settings.json), every Bash, Read, Grep, Glob, Write, Edit, and mcp__ tool result is indexed into the session FTS5 store by the upstream PostToolUse hook. Two consequences:

- **Before re-running a Bash command or re-reading a file you have already touched this session**, call `ctx_search(queries=["<keyword>"])` first — the result may already be indexed. This applies to logs, test output, ls/find/grep results, and file contents.
- **At session start** (or after receiving a `<skill_activation>` block), call `ctx_stats` to see what is already captured from prior turns or parent sessions.

The PreToolUse hook enforces this automatically: if context-mode detects you are about to re-run a recently captured command, it blocks the call and redirects you to `ctx_search`. Heed that redirect rather than working around it.

When research turns up a sizable file you would otherwise Read just to feed into analysis (large config dumps, transcript files, log captures referenced by path), prefer `ctx_execute_file` so the raw file stays in the sandbox and only your computed result lands in context. For multi-URL or multi-command research sweeps, `ctx_batch_execute` accepts `concurrency: 1-8` for I/O-bound parallelism (gh API queries, multi-source fetches) — keep `concurrency: 1` for CPU-bound or stateful commands. (`concurrency` requires context-mode v1.0.104+; on the installed v1.0.75 binary, omit the parameter.)
<!-- cmm-delta:end name=context-mode-capture -->
