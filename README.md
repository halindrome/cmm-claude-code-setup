# codebase-memory-mcp Setup for Claude Code

Hooks, rules, and statusline integration for [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) — a powerful MCP server by [DeusData](https://github.com/DeusData) that builds a persistent code knowledge graph across 64 languages, dramatically reducing token usage in Claude Code.

> **Credit where it's due:** The hook-based enforcement approach and repository structure are adapted from [jmunch-claude-code-setup](https://github.com/shacharbard/jmunch-claude-code-setup) by [Shachar Bard](https://github.com/shacharbard). This repo does not contain the codebase-memory-mcp server itself — it provides a companion enforcement and tracking layer that helps Claude Code get the most out of it. All the clever indexing, knowledge graph construction, and structural analysis is [DeusData's](https://github.com/DeusData) work.

## What codebase-memory-mcp Does

[codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) (by DeusData) indexes your codebase into a persistent knowledge graph so Claude fetches precise structural results — functions, call chains, architecture overviews — instead of reading entire files. Supports 64 languages, Cypher-like queries, dead code detection, cross-service HTTP linking, and git diff impact analysis. A single graph query returns what would take dozens of Grep/Read calls, saving ~99% of tokens on code exploration.

This repo provides the full enforcement stack that makes Claude **actually use** these tools instead of falling back to `Read`:

| Layer | What | Effect |
|-------|------|--------|
| CLAUDE.md rules | Instructions | Tells Claude *when* to use codebase-memory-mcp tools |
| PreToolUse nudge hooks | Non-blocking | Reminds Claude when it tries `Read` on code files |
| Session gate | Blocking | Blocks ALL tools until the index is refreshed at session start |
| Agent spawn gate | Blocking | Blocks subagent spawning without MCP instructions in prompt |
| PostToolUse trackers | Passive | Tracks call counts per CMM tool |
| Statusline | Display | Shows CMM call stats in the Claude Code status bar |

## Quick Start

```bash
# 1. Download codebase-memory-mcp binary for your platform
#    Full install docs (macOS/Linux/Windows): https://github.com/DeusData/codebase-memory-mcp#installation
#
#    macOS/Linux one-liner:
#      curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/scripts/setup.sh | bash
#
#    Or download the binary manually from:
#      https://github.com/DeusData/codebase-memory-mcp/releases/latest
#      (darwin-arm64, darwin-amd64, linux-amd64, linux-arm64, windows-amd64)

# 2. Register with Claude Code (auto-detects editor, installs skills)
codebase-memory-mcp install

# 3. Copy hooks to your project
mkdir -p .claude/hooks
cp hooks/project/*.sh .claude/hooks/
cp hooks/global/*.sh .claude/hooks/
chmod +x .claude/hooks/*.sh

# 4. Add settings (merge with your existing .claude/settings.json)
# See rules/project-settings-example.json

# 5. Add CLAUDE.md rules (append to ~/.claude/CLAUDE.md)
# See rules/global-claude-md.md

# 6. Allow MCP tools (add to .claude/settings.local.json)
# Full list (rules/allowed-tools.txt):
#   index_repository, index_status, list_projects, delete_project,
#   get_architecture, get_graph_schema, search_graph, search_code,
#   query_graph, get_code_snippet, trace_call_path, detect_changes,
#   manage_adr, ingest_traces
```

See [docs/setup-guide.md](docs/setup-guide.md) for the full step-by-step walkthrough.

## Repository Structure

```
hooks/
  global/                          # Install to ~/.claude/hooks/ (all projects)
    cmm-nudge.sh                   # PreToolUse:Read — reminds to use CMM tools on code files
    reindex-after-edit.sh          # PostToolUse:Write|Edit — triggers re-index after edits
  project/                         # Install to .claude/hooks/ (per project)
    agent-cmm-gate.sh             # PreToolUse:Agent — blocks agents without MCP instructions
    cmm-session-start.sh          # SessionStart — injects index refresh prompt
    cmm-session-gate.sh           # PreToolUse:* — blocks all tools until index ready
    cmm-sentinel-writer.sh        # PostToolUse — marks index as refreshed
    reindex-after-commit.sh       # PostToolUse:Bash — re-index after git commits
    track-cmm-calls.sh            # PostToolUse — tracks call counts per CMM tool
rules/
  global-claude-md.md              # CLAUDE.md rules for ~/.claude/CLAUDE.md
  project-settings-example.json    # Example .claude/settings.json with all hooks
  mcp-example.json                 # Example .mcp.json for project root
  allowed-tools.txt                # MCP tool allowlist for settings.local.json
docs/
  setup-guide.md                   # Full step-by-step setup guide
```

## How Enforcement Works

### Session Lifecycle

```
Session starts
  -> cmm-session-start.sh injects "run index NOW" prompt
  -> cmm-session-gate.sh blocks ALL tools until index done
  -> Claude runs index_repository
  -> cmm-sentinel-writer.sh marks session as ready
  -> All tools unblocked

Claude needs a function
  -> Tries Read on a code file
  -> cmm-nudge.sh fires: use search_graph / get_code_snippet instead
  -> Claude uses CMM tools
  -> track-cmm-calls.sh logs the call

Claude spawns a subagent
  -> agent-cmm-gate.sh checks prompt for MCP instructions
  -> Missing? BLOCKED with full copy-paste instructions
  -> Present? Allowed

Claude edits a file
  -> reindex-after-edit.sh fires (debounced 30s)
  -> Prompts Claude to re-run index_repository

Claude commits
  -> reindex-after-commit.sh clears sentinel
  -> All tools blocked until re-index
```

### Call Tracking (`_call-counts.json`)

The `track-cmm-calls.sh` hook tracks how many times each codebase-memory-mcp tool is called during your sessions. This provides visibility into which graph tools Claude is actually using and how heavily.

#### Where the file lives

```
~/.cache/codebase-memory-mcp/_call-counts.json
```

This file is created automatically on the first CMM tool call. It accumulates across sessions.

#### What it looks like

```json
{
  "total_calls": 87,
  "by_tool": {
    "mcp__codebase-memory-mcp__search_graph": 32,
    "mcp__codebase-memory-mcp__get_code_snippet": 19,
    "mcp__codebase-memory-mcp__trace_call_path": 14,
    "mcp__codebase-memory-mcp__get_architecture": 8,
    "mcp__codebase-memory-mcp__query_graph": 6,
    "mcp__codebase-memory-mcp__index_repository": 4,
    "mcp__codebase-memory-mcp__detect_changes": 3,
    "mcp__codebase-memory-mcp__search_code": 1
  }
}
```

## Statusline

To display CMM call stats in your Claude Code statusline, read from the call counts file. Here is an example snippet:

```bash
#!/bin/bash
# Example: read CMM call counts for statusline display
COUNTS_FILE="$HOME/.cache/codebase-memory-mcp/_call-counts.json"

if [ -f "$COUNTS_FILE" ]; then
  TOTAL=$(jq -r '.total_calls // 0' "$COUNTS_FILE")
  SEARCH=$(jq -r '.by_tool["mcp__codebase-memory-mcp__search_graph"] // 0' "$COUNTS_FILE")
  SNIPPET=$(jq -r '.by_tool["mcp__codebase-memory-mcp__get_code_snippet"] // 0' "$COUNTS_FILE")
  TRACE=$(jq -r '.by_tool["mcp__codebase-memory-mcp__trace_call_path"] // 0' "$COUNTS_FILE")
  echo "CMM:${TOTAL} (sg:${SEARCH} cs:${SNIPPET} tr:${TRACE})"
else
  echo "CMM:0"
fi
```

Register in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/statusline-cmm.sh\""
  }
}
```

## Subagent Instructions Template

When spawning subagents, include these instructions in the prompt to ensure they use codebase-memory-mcp:

```
**Code navigation (MANDATORY):** Use codebase-memory-mcp MCP tools for all code exploration.
- Use mcp__codebase-memory-mcp__search_graph to find functions/classes by name pattern — NEVER grep through files to find definitions
- Use mcp__codebase-memory-mcp__get_code_snippet to fetch specific function source code by qualified name
- Use mcp__codebase-memory-mcp__trace_call_path to understand call chains and dependencies
- Use mcp__codebase-memory-mcp__get_architecture for codebase orientation (languages, packages, hotspots, routes)
- Use mcp__codebase-memory-mcp__detect_changes to assess impact of your modifications
- Full Read only when: editing 6+ functions in same file, need imports/globals, file <50 lines, non-code files
```

The `agent-cmm-gate.sh` hook enforces this — spawning is blocked if these instructions are missing.

## Requirements

- [Claude Code](https://claude.ai/claude-code) CLI
- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) binary (Go, installed from GitHub releases)
- `jq` for JSON parsing in hooks
- `python3` for hook input parsing
- `bc` for statusline number formatting

## Benchmarks

The `benchmarks/` directory contains a reproducible benchmark suite that measures Claude Code token consumption when answering standard codebase questions — comparing three variants:

- **baseline**: No MCP tools (Claude reads files directly)
- **cmm-cold**: CMM enabled, fresh index each run
- **cmm-cache**: CMM enabled, pre-warmed index

### Quick Start

```bash
./benchmarks/run.sh
```

See [benchmarks/README.md](benchmarks/README.md) for full documentation including prerequisites, configuration, and result interpretation.

## Credits

- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) by [DeusData](https://github.com/DeusData)
- Repository structure and enforcement approach inspired by [jmunch-claude-code-setup](https://github.com/shacharbard/jmunch-claude-code-setup) by [Shachar Bard](https://github.com/shacharbard)

## License

The hooks, rules, statusline snippets, and documentation in this repository are licensed under the [MIT License](LICENSE).

This repo does **not** include the codebase-memory-mcp server itself — only configuration and enforcement tooling that works with it. The MCP server is a separate project by [DeusData](https://github.com/DeusData) and is subject to its own license. See [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) for its terms.
