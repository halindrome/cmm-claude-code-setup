---
phase: 01
plan: 01
title: "Write README.md with Shachar Bard attribution"
wave: 1
depends_on: []
must_haves:
  - README.md at project root
  - Shachar Bard attribution prominently at top (above all other content)
  - Project overview explaining hook-based enforcement for codebase-memory-mcp
  - Quick Start section with installation steps
  - Repository structure overview
  - Statusline integration code snippet (inline, no separate script file)
  - Subagent instructions template
  - Requirements list (Claude Code, jq, python3, bc)
---

# Plan 01: Write README.md with Shachar Bard Attribution

## Context

This is the primary entry point for the project. The README must clearly communicate that this repo is a hook-based enforcement layer for [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) (by DeusData), adapted from [jmunch-claude-code-setup](https://github.com/shacharbard/jmunch-claude-code-setup) by [Shachar Bard](https://github.com/shacharbard). Attribution to Shachar Bard must appear above all other content — this is a hard requirement.

Use `/Users/ahby/Sources/jmunch-claude-code-setup/README.md` as the structural template to mirror. Adapt all jCodeMunch/jDocMunch references to codebase-memory-mcp equivalents. The CMM install method is binary download from GitHub releases (NOT npm).

Key differences from jmunch-claude-code-setup:
- Single MCP server (codebase-memory-mcp) instead of two (jCodeMunch + jDocMunch)
- CMM is a Go binary installed from GitHub releases, not a Python package via uv/pip
- CMM tools use prefix `mcp__codebase-memory-mcp__` (e.g., `search_graph`, `get_code_snippet`, `trace_call_path`, `get_architecture`, `detect_changes`)
- No statusline script file — README contains an example code snippet showing how to integrate CMM call stats into a statusline
- No token savings tracking (CMM doesn't expose tokens_saved) — instead track call counts per tool
- Language list for hooks should be broad and extensible (CMM supports 64 languages)

## Tasks

- [ ] Task 1: Create `/Users/ahby/Sources/cmm-claude-code-setup/README.md` with attribution block at the very top. Format: title line, then immediately a blockquote crediting Shachar Bard (https://github.com/shacharbard) as the creator of jmunch-claude-code-setup which this repo adapts. Link to https://github.com/shacharbard/jmunch-claude-code-setup. Make clear this repo provides the enforcement layer, not the MCP server itself.

- [ ] Task 2: Write "What codebase-memory-mcp Does" section and enforcement layer table. Mirror the jmunch README structure: explain what CMM does (code knowledge graph, 64 languages, structural queries), then show the enforcement stack table (CLAUDE.md rules, PreToolUse nudge, Session gate, Agent spawn gate, PostToolUse trackers, Statusline). Adapt all entries for CMM tools.

- [ ] Task 3: Write Quick Start section and Repository Structure. Quick Start should use: (1) download binary from GitHub releases, (2) `codebase-memory-mcp install`, (3) copy hooks, (4) add settings, (5) add CLAUDE.md rules, (6) allow MCP tools. Repository Structure should show the planned directory layout: `hooks/global/`, `hooks/project/`, `rules/`, `docs/`. Reference `docs/setup-guide.md` for the full walkthrough.

- [ ] Task 4: Write How Enforcement Works section (session lifecycle), Statusline section (code snippet only, no separate file), and Subagent Instructions Template. The statusline snippet should show reading `~/.cache/codebase-memory-mcp/_call-counts.json` and formatting tool call counts. The subagent template should instruct agents to use CMM tools (`search_graph`, `get_code_snippet`, `trace_call_path`, `get_architecture`) instead of Read/Grep.

- [ ] Task 5: Write Requirements section and Credits/License. Requirements: Claude Code CLI, codebase-memory-mcp binary, jq, python3, bc. Credits: codebase-memory-mcp by DeusData, repo structure inspired by Shachar Bard's jmunch-claude-code-setup. License: MIT.
