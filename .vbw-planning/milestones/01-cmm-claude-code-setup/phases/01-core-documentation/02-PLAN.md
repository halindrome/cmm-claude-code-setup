---
phase: 01
plan: 02
title: "Write docs/setup-guide.md comprehensive walkthrough"
wave: 1
depends_on: []
must_haves:
  - docs/setup-guide.md at project root
  - Migrated and expanded content from codebase-memory-setup-guide.md
  - Step-by-step installation of codebase-memory-mcp (binary download)
  - MCP server registration (project-level and global)
  - Tool allowlist setup
  - Hook installation details (global and project hooks)
  - CLAUDE.md rules integration
  - Troubleshooting section
---

# Plan 02: Write docs/setup-guide.md Comprehensive Walkthrough

## Context

This guide migrates and expands the content from `/Users/ahby/Sources/cmm-claude-code-setup/codebase-memory-setup-guide.md` into a comprehensive step-by-step walkthrough at `docs/setup-guide.md`. The existing guide covers basic CMM setup (install, register, allow tools, auto-index, CLAUDE.md rules, enforcement hooks). The new guide must incorporate all of that PLUS the full hook installation details for this repo's enforcement layer.

Key references:
- `/Users/ahby/Sources/cmm-claude-code-setup/codebase-memory-setup-guide.md` — existing guide content to migrate (do NOT duplicate, migrate into new file)
- `/Users/ahby/Sources/codebase-memory-mcp/README.md` — accurate CMM install method (binary download from GitHub releases, `codebase-memory-mcp install`)
- `/Users/ahby/Sources/jmunch-claude-code-setup/README.md` — enforcement layer structure to mirror

Important details:
- CMM installs as a binary download from GitHub releases (NOT npm). The `codebase-memory-mcp install` command auto-registers with Claude Code.
- Hook scripts live in `hooks/global/` and `hooks/project/` in this repo
- Global hooks install to `~/.claude/hooks/` (apply to all projects)
- Project hooks install to `.claude/hooks/` (per-project enforcement)
- The guide should cover BOTH manual and setup.sh installation paths (note setup.sh will be created in Phase 5, so reference it as "coming soon" or "see setup.sh when available")

## Tasks

- [ ] Task 1: Create `/Users/ahby/Sources/cmm-claude-code-setup/docs/setup-guide.md` with introduction and Steps 1-2. Step 1: Install codebase-memory-mcp — download binary from GitHub releases (link to https://github.com/DeusData/codebase-memory-mcp/releases/latest), extract, move to PATH, run `codebase-memory-mcp install`. Step 2: Verify MCP registration — check `.mcp.json` or `~/.claude/settings.json`, show expected config, mention `/mcp` command to verify. Include the manual registration JSON for both project-level and global options (from the existing guide).

- [ ] Task 2: Write Steps 3-4. Step 3: Allow MCP tools — full list of 14 tool names for `.claude/settings.local.json` `allowedTools` (copy from existing guide: index_repository, index_status, list_projects, get_architecture, get_graph_schema, search_graph, search_code, query_graph, get_code_snippet, trace_call_path, detect_changes, manage_adr, ingest_traces, delete_project). Step 4: Add CLAUDE.md rules — provide the full rules block for `~/.claude/CLAUDE.md` telling Claude when to use CMM tools vs Read (migrate from existing guide Step 5 content).

- [ ] Task 3: Write Steps 5-6 covering hook installation. Step 5: Install global hooks — explain `hooks/global/` directory, list each hook (cmm-nudge.sh, reindex-after-edit.sh), show how to copy to `~/.claude/hooks/`, show the settings.json registration for PreToolUse:Read and PostToolUse:Write|Edit. Step 6: Install project hooks — explain `hooks/project/` directory, list each hook (cmm-session-start.sh, cmm-session-gate.sh, cmm-sentinel-writer.sh, agent-cmm-gate.sh, track-cmm-calls.sh), show how to copy to `.claude/hooks/`, show the settings.json registration with all matchers (SessionStart, PreToolUse:*, PostToolUse). Note these hooks will be created in Phase 2/3 — reference them by name and purpose.

- [ ] Task 4: Write Step 7 (Auto-Index on Session Start) and Tool Reference section. Step 7 explains how the SessionStart hook + session gate work together to ensure indexes are fresh. Include the data flow diagram (session starts -> prompt injection -> gate blocks -> index completes -> sentinel written -> gate opens). Tool reference: table of all 14 CMM tools with brief descriptions (migrate and expand from existing guide).

- [ ] Task 5: Write Recommended Workflows section and Troubleshooting section. Workflows: first-time exploration, finding a function, pre-commit impact analysis, dead code detection (migrate from existing guide). Troubleshooting: command not found, index not found, search returns no results, query undercounts, hooks not firing, sentinel issues (expand from existing guide, add hook-specific troubleshooting).
