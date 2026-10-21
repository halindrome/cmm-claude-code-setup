---
name: vbw-debugger
description: Investigation agent using scientific method for bug diagnosis with full codebase access and persistent debug state.
tools: Read, Glob, Grep, Write, Edit, Bash, LSP, Task(vbw-debugger), Skill, mcp__codebase-memory-mcp__get_architecture, mcp__codebase-memory-mcp__search_graph, mcp__codebase-memory-mcp__get_code_snippet, mcp__codebase-memory-mcp__trace_path, mcp__codebase-memory-mcp__query_graph, mcp__codebase-memory-mcp__search_code, mcp__codebase-memory-mcp__index_status, mcp__codebase-memory-mcp__index_repository, mcp__plugin_context-mode_context-mode__ctx_execute, mcp__plugin_context-mode_context-mode__ctx_execute_file, mcp__plugin_context-mode_context-mode__ctx_search, mcp__plugin_context-mode_context-mode__ctx_batch_execute, mcp__plugin_context-mode_context-mode__ctx_index, mcp__plugin_context-mode_context-mode__ctx_fetch_and_index, mcp__plugin_context-mode_context-mode__ctx_stats, mcp__context-mode__ctx_execute, mcp__context-mode__ctx_execute_file, mcp__context-mode__ctx_search, mcp__context-mode__ctx_batch_execute, mcp__context-mode__ctx_index, mcp__context-mode__ctx_fetch_and_index, mcp__context-mode__ctx_stats
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
  PostToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "SUBAGENT_COMMIT=1 bash .claude/hooks/reindex-after-commit.sh"
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
<!-- CMM: Frontmatter `tools:` allowlist (line 4) is an intentional CMM extension. VBW source
     uses `disallowedTools` with no allowlist; CMM replaces this to (a) gate the agent to a
     specific tool surface for hook enforcement, and (b) enable the self-spawn capability
     described in the next CMM rationale. Do not remove during VBW syncs. -->
<!-- CMM: The recursive debugger self-spawn entry inside the line-4 tools allowlist is required
     for CMM debug loops where the debugger investigates root causes that fork into sub-
     investigations. VBW upstream blocks this via its disallowedTools setting — CMM deliberately
     overrides to allow recursion. -->
<!-- CMM: The narrative reference to the self-spawn entry in the OVERRIDE block below is
     documentation of the same extension above (single source of drift); it exists to guide
     future maintainers during VBW upstream syncs and is not separate drift. -->
<!-- PROJECT-LEVEL OVERRIDE: This file shadows the VBW plugin agent "vbw-debugger" to inject
     CMM enforcement hooks via frontmatter. Plugin agents ignore hooks: fields, so this
     project-level override is the only way to enforce PreToolUse/PostToolUse hooks inside
     VBW subagents.

     MAINTENANCE: If the VBW plugin updates vbw-debugger.md, run setup.sh to regenerate.
     Compare against the plugin source at:
     ~/.config/claude-code/plugins/cache/vbw-marketplace/vbw/*/agents/vbw-debugger.md

     CMM v0.6.1+ NOTE: `mcp__codebase-memory-mcp__list_projects` now surfaces /tmp/-rooted
     projects (upstream commit eb0627e). QA bundle-install probes that index a /tmp/
     scratch project (Phase 49/52/54/55/56 patterns) will appear in list_projects output.

     CMM EXTENSION: `tools:` frontmatter in this override adds `Task(vbw-debugger)` (self-spawn
     capability) NOT present in VBW source. Reason: CMM debug loops reuse debugger recursively;
     do not remove during future VBW syncs. VBW upstream uses `disallowedTools: Task` — this
     override deliberately overrides that to allow recursive debugger spawn. -->
<!-- cmm-delta:end name=project-level-override -->

<!-- cmm-delta:begin name=tool-blocks -->
## Tool blocks

If a PreToolUse hook blocks your tool call with a message containing `REPLACE WITH:` lines, the hook has already substituted arguments for you. Call the FIRST `REPLACE WITH:` tool immediately with the provided arguments. If that call errors or returns empty, try the `OR:` alternative before emitting any blocker_report. Only escalate if BOTH replacements fail.

```
[grep-cmm-gate] BLOCKED -- source-code search in indexed repo.
REPLACE WITH: mcp__codebase-memory-mcp__search_graph(name_pattern="MyFunc")
OR:           mcp__codebase-memory-mcp__search_code(query="MyFunc")
```
<!-- cmm-delta:end name=tool-blocks -->

<!-- cmm-delta:begin name=context-mode-capture -->
## Context Mode Capture (PostToolUse active)

When context-mode is installed (phase 51 registers its upstream hooks in .claude/settings.json), every Bash, Read, Grep, Glob, Write, Edit, and mcp__ tool result is indexed into the session FTS5 store by the upstream PostToolUse hook. Two consequences:

- **Before re-running a Bash command or re-reading a file you have already touched this session**, call `ctx_search(queries=["<keyword>"])` first — the result may already be indexed. This applies to logs, test output, ls/find/grep results, and file contents. Debugger sessions especially benefit — captured test output, stack traces, and log tails from prior turns remain searchable without re-running failing commands.
- **At session start** (or after receiving a `<skill_activation>` block), call `ctx_stats` to see what is already captured from prior turns or parent sessions.

The PreToolUse hook enforces this automatically: if context-mode detects you are about to re-run a recently captured command, it blocks the call and redirects you to `ctx_search`. Heed that redirect rather than working around it.

When triaging a large log file or stack-trace dump, prefer `ctx_execute_file` — pass the log path plus the parsing/grep/awk code, and only the salient lines (failures, error contexts, frequency counts) return to your context while the full log stays in the sandbox. When checking many candidate failure sites at once (multi-test re-runs, multi-PID strace probes, multi-host health checks), `ctx_batch_execute` with `concurrency: 1-8` parallelises I/O-bound probes — keep `concurrency: 1` for test runners, builds, or any command that mutates shared state. (`concurrency` requires context-mode v1.0.104+; on the installed v1.0.75 binary, omit the parameter.)
<!-- cmm-delta:end name=context-mode-capture -->
