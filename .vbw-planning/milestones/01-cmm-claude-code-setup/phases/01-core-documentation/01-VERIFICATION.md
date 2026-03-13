---
phase: 01
tier: standard
result: PARTIAL
passed: 20
failed: 3
total: 23
date: 2026-03-12
---

## Must-Have Checks

| # | ID | Truth/Condition | Status | Evidence |
|---|----|--------------------|--------|----------|
| 1 | MH-01 | README.md exists at project root | PASS | `/Users/ahby/Sources/cmm-claude-code-setup/README.md` present, 201 lines |
| 2 | MH-02 | Shachar Bard attribution at very top (line 5, blockquote above all other content) | PASS | Line 5: blockquote crediting Shachar Bard with links to `https://github.com/shacharbard` and `https://github.com/shacharbard/jmunch-claude-code-setup` |
| 3 | MH-03 | CMM install is binary download (NOT npm) | PASS | README Quick Start uses `tar xzf` + `mv codebase-memory-mcp ~/.local/bin/`; `npm` not mentioned anywhere |
| 4 | MH-04 | Quick Start section present | PASS | `## Quick Start` at line 22 |
| 5 | MH-05 | Repository Structure section present | PASS | `## Repository Structure` at line 51 |
| 6 | MH-06 | Enforcement stack table present | PASS | Table at lines 13-20 with 6 rows (CLAUDE.md rules, PreToolUse nudge, Session gate, Agent spawn gate, PostToolUse trackers, Statusline) |
| 7 | MH-07 | No separate statusline script file in repo | PASS | `find` returns no `statusline*` file; code is inline snippet only. Reference to `statusline-cmm.sh` is in a JSON example showing how user would register it, not a file committed to repo |
| 8 | MH-08 | All 14 CMM tool names correct in README | FAIL | README only mentions 8/14 tools: `index_repository`, `search_graph`, `get_code_snippet`, `trace_call_path`, `get_architecture`, `query_graph`, `detect_changes`, `search_code`. Missing: `index_status`, `list_projects`, `get_graph_schema`, `manage_adr`, `ingest_traces`, `delete_project` |
| 9 | MH-09 | Credits section with Shachar Bard and DeusData | PASS | `## Credits` at line 191 credits both `codebase-memory-mcp` by DeusData and `jmunch-claude-code-setup` by Shachar Bard |
| 10 | MH-10 | MIT License mentioned | PASS | Line 198: "licensed under the [MIT License](LICENSE)" |
| 11 | MH-11 | docs/setup-guide.md exists | PASS | `/Users/ahby/Sources/cmm-claude-code-setup/docs/setup-guide.md` present, 612 lines |
| 12 | MH-12 | Binary install from GitHub releases (not npm) in setup-guide.md | PASS | Line 26: "single Go binary. Download it from GitHub releases — no npm, no Docker, no Node.js required." |
| 13 | MH-13 | All 14 CMM tools listed in allowedTools | PASS | All 14 tool names present under `allowedTools` in setup-guide.md Step 3 (lines 136-150) |
| 14 | MH-14 | Global hooks: cmm-nudge.sh, reindex-after-edit.sh | PASS | Both listed in Step 5 global hook reference table (lines 218-219) |
| 15 | MH-15 | Project hooks: cmm-session-start.sh, cmm-session-gate.sh, cmm-sentinel-writer.sh, agent-cmm-gate.sh, track-cmm-calls.sh | PASS | All 5 listed in Step 6 project hook reference table (lines 276-280) |
| 16 | MH-16 | Troubleshooting section present in setup-guide.md | PASS | `## Troubleshooting` at line 506 with 7 sub-sections |
| 17 | MH-17 | Tool reference table present in setup-guide.md | PASS | `## Tool Reference` at line 405, organized in 3 categories covering all 14 tools |
| 18 | MH-18 | Recommended Workflows section present in setup-guide.md | PASS | `## Recommended Workflows` at line 438 with 6 workflow patterns |

## Artifact Checks

| # | ID | Artifact | Exists | Contains | Status |
|---|----|---------|----|---------|--------|
| 19 | ART-01 | README.md | true | Subagent instructions template | PASS |
| 20 | ART-02 | README.md | true | Requirements section (Claude Code, jq, python3, bc) | PASS |
| 21 | ART-03 | docs/setup-guide.md | true | Step-by-step numbered sections (Step 1-7) | PASS |
| 22 | ART-04 | docs/setup-guide.md | true | Session lifecycle / data flow diagram | PASS |

## Convention Compliance

| # | ID | Convention | File | Status | Detail |
|---|----|-----------|----|--------|--------|
| 23 | CON-01 | Step-by-step numbered sections | docs/setup-guide.md | PASS | Steps 1-7 all present at section heading level |
| 24 | CON-02 | Code blocks use triple backticks with language tags | docs/setup-guide.md | PASS | Verified `bash`, `json`, `markdown` language tags used on code blocks |
| 25 | CON-03 | Horizontal rules separate major sections | docs/setup-guide.md | PASS | 12 `---` separators found between major steps |
| 26 | CON-04 | Blockquotes for "Why this matters" callouts | docs/setup-guide.md | PASS | Multiple `>` blockquotes present including "Why this matters" callouts |
| 27 | CON-05 | JSON config keys use camelCase | docs/setup-guide.md | PASS | `mcpServers`, `allowedTools`, `PreToolUse`, `PostToolUse`, `SessionStart` — all camelCase |
| 28 | CON-06 | Hooks use array-of-objects format with type discriminator | docs/setup-guide.md | PASS | All hook entries use `{"type": "command", "command": "..."}` format |

## Anti-Pattern Scan

| # | ID | Pattern | Status | Evidence |
|---|----|---------|--------|----------|
| 29 | AP-01 | npm install mentioned for CMM | PASS | "npm" not found in README.md; setup-guide.md explicitly says "no npm" |
| 30 | AP-02 | Separate statusline script file committed to repo | PASS | No `statusline*.sh` file found in repo; code is inline example only |
| 31 | AP-03 | Missing attribution before content sections | PASS | Attribution blockquote at line 5, before `## What codebase-memory-mcp Does` at line 7 |

## Summary

Tier: standard | Result: PARTIAL | Passed: 20/23 | Failed: [MH-08]

**Critical finding (MH-08):** The README.md only references 8 of the 14 required CMM tool names. The missing 6 tools (`index_status`, `list_projects`, `get_graph_schema`, `manage_adr`, `ingest_traces`, `delete_project`) are all fully documented in `docs/setup-guide.md` but do not appear in the README itself. The plan required all 14 tool names to be correct in the README. This may be acceptable given the README's purpose as an overview document rather than a reference, but it technically fails the stated must-have.

All other checks pass. The `docs/setup-guide.md` is complete and correct — all 14 tools listed in `allowedTools`, all 7 required hook scripts present, troubleshooting and workflow sections included. The README attribution, enforcement stack table, Quick Start, and Repository Structure are all correct and complete.
