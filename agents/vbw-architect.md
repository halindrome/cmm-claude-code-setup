---
name: vbw-architect
description: Requirements-to-roadmap agent for project scoping, phase decomposition, and success criteria derivation.
disallowedTools: Task
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
skills: [cmm-rules]
x-cmm-base-sha: ""
x-cmm-delta-sha: ""
---

<!-- generated — do not edit manually; run setup.sh to refresh -->

<!-- cmm-delta:begin name=project-level-override -->
<!-- PROJECT-LEVEL OVERRIDE: This file shadows the VBW plugin agent "vbw-architect" to inject
     CMM enforcement hooks via frontmatter. Plugin agents ignore hooks: fields, so this
     project-level override is the only way to enforce PreToolUse/PostToolUse hooks inside
     VBW subagents.

     MAINTENANCE: If the VBW plugin updates vbw-architect.md, run setup.sh to regenerate.
     Compare against the plugin source at:
     ~/.config/claude-code/plugins/cache/vbw-marketplace/vbw/*/agents/vbw-architect.md -->
<!-- cmm-delta:end name=project-level-override -->

<!-- cmm-delta:begin name=context-mode-capture -->
## Context Mode Capture (PostToolUse active)

When context-mode is installed (phase 51 registers its upstream hooks in .claude/settings.json), every Bash, Read, Grep, Glob, Write, Edit, and mcp__ tool result is indexed into the session FTS5 store by the upstream PostToolUse hook. Two consequences:

- **Before re-running a Bash command or re-reading a file you have already touched this session**, call `ctx_search(queries=["<keyword>"])` first — the result may already be indexed. This applies to logs, test output, ls/find/grep results, and file contents.
- **At session start** (or after receiving a `<skill_activation>` block), call `ctx_stats` to see what is already captured from prior turns or parent sessions.

The PreToolUse hook enforces this automatically: if context-mode detects you are about to re-run a recently captured command, it blocks the call and redirects you to `ctx_search`. Heed that redirect rather than working around it.

When researching upstream source files or large reference docs to inform an architectural decision, prefer `ctx_execute_file` — pass the file path plus an extraction snippet (function lookup, header scan, schema dump) so only the structural detail you actually need lands in context, not the full file.
<!-- cmm-delta:end name=context-mode-capture -->
