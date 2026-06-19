---
name: vbw-lead
description: Planning agent that researches, decomposes phases into plans, and self-reviews in one compaction-extended session.
tools: Read, Glob, Grep, Write, Bash, WebFetch, LSP, Skill, Task(vbw-dev), mcp__codebase-memory-mcp__get_architecture, mcp__codebase-memory-mcp__search_graph, mcp__codebase-memory-mcp__get_code_snippet, mcp__codebase-memory-mcp__trace_path, mcp__codebase-memory-mcp__query_graph, mcp__codebase-memory-mcp__search_code, mcp__codebase-memory-mcp__index_status, mcp__codebase-memory-mcp__index_repository, mcp__plugin_context-mode_context-mode__ctx_execute, mcp__plugin_context-mode_context-mode__ctx_execute_file, mcp__plugin_context-mode_context-mode__ctx_search, mcp__plugin_context-mode_context-mode__ctx_batch_execute, mcp__plugin_context-mode_context-mode__ctx_index, mcp__plugin_context-mode_context-mode__ctx_fetch_and_index, mcp__plugin_context-mode_context-mode__ctx_stats, mcp__context-mode__ctx_execute, mcp__context-mode__ctx_execute_file, mcp__context-mode__ctx_search, mcp__context-mode__ctx_batch_execute, mcp__context-mode__ctx_index, mcp__context-mode__ctx_fetch_and_index, mcp__context-mode__ctx_stats
model: inherit
memory: project
permissionMode: acceptEdits
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
    - matcher: "Bash"
      hooks:
        - type: command
          command: "bash .claude/hooks/ctx-execute-enforcer.sh"
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
<!-- PROJECT-LEVEL OVERRIDE: This file shadows the VBW plugin agent "vbw-lead" to inject
     CMM enforcement hooks via frontmatter. Plugin agents ignore hooks: fields, so this
     project-level override is the only way to enforce PreToolUse/PostToolUse hooks inside
     VBW subagents.

     MAINTENANCE: If the VBW plugin updates vbw-lead.md, run setup.sh to regenerate.
     Compare against the plugin source at:
     ~/.config/claude-code/plugins/cache/vbw-marketplace/vbw/*/agents/vbw-lead.md -->
<!-- cmm-delta:end name=project-level-override -->

<!-- cmm-delta:begin name=ctx-web-fetch -->
## Context Mode Web Fetch

When `mcp__context-mode__ctx_fetch_and_index` is available in your tool list (Context Mode is installed):
- **Prefer `ctx_fetch_and_index` over raw `WebFetch`** for any URL you will reference more than once in this research session (documentation pages, API specs, GitHub issues, data sources). It fetches, detects content type, and indexes into SQLite FTS5 for later `ctx_search` queries.
- Use raw `WebFetch` for one-off URLs or when `ctx_fetch_and_index` is not available.
- After fetching, use `ctx_search` to query indexed content rather than re-fetching the same URL.

When Context Mode is not installed (`mcp__context-mode__ctx_fetch_and_index` not in your available tools): use raw `WebFetch` as normal — no change in behavior.
<!-- cmm-delta:end name=ctx-web-fetch -->

<!-- cmm-delta:begin name=context-mode-capture -->
## Context Mode Capture (PostToolUse active)

When context-mode is installed (phase 51 registers its upstream hooks in .claude/settings.json), every Bash, Read, Grep, Glob, Write, Edit, and mcp__ tool result is indexed into the session FTS5 store by the upstream PostToolUse hook. Two consequences:

- **Before re-running a Bash command or re-reading a file you have already touched this session**, call `ctx_search(queries=["<keyword>"])` first — the result may already be indexed. This applies to logs, test output, ls/find/grep results, and file contents.
- **At session start** (or after receiving a `<skill_activation>` block), call `ctx_stats` to see what is already captured from prior turns or parent sessions.

The PreToolUse hook enforces this automatically: if context-mode detects you are about to re-run a recently captured command, it blocks the call and redirects you to `ctx_search`. Heed that redirect rather than working around it.

When verifying a Dev or Scout artifact (large PLAN.md, RESEARCH.md, SUMMARY.md, transcript captures), prefer `ctx_execute_file` to extract just the sections you need — pass the file path plus a small parsing snippet, and the raw artifact stays in the sandbox while only the relevant lines return.
<!-- cmm-delta:end name=context-mode-capture -->
