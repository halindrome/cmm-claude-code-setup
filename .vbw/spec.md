# ccs-vbw2

## Goals

A hook-based enforcement layer that makes Claude Code use codebase-memory-mcp (CMM) as its core code-intelligence tool, with Context Mode and VBW as optional, auto-detected add-ons. For Claude Code users who install it via setup.sh.

This milestone: update the stack to work well with VBW 2 (new conventions, e.g. `.vbw/` instead of `.vbw-planning/`).

QA contract: GitHub issue #102 (https://github.com/halindrome/cmm-claude-code-setup/issues/102); branch feature/102-vbw2-compatibility off develop. Keep the issue acceptance criteria in sync with Requirements.

Field evidence (2026-10-27, worker-simulator): ../cmm-claude-code-setup/.vbw-planning/todo-details.json items c4e1b7a2 (enforcer patch + 11 test cases) and d81f3c06 (tool-gap measurements, options).

## Non-goals

## Constraints

- VBW 2 reference is the installed plugin (~/.config/claude-code/plugins/cache/vbw-marketplace/vbw/2.1.18); no fork or sibling checkout.

## Requirements

- R1 [auto] make measure counts CMM vs Read/Grep/Glob calls inside VBW 2 workflow agents (from workflow subagent transcripts) and does not score those runs as enforcement bypasses
- R2 [auto] ctx-execute-enforcer allows Bash from vbw:* agents and bare vbw CLI calls, while still blocking the main thread, other agents, and compound vbw commands
- R3 [auto] setup.sh detects VBW 2 separately from VBW 1 and reports its version
- R4 [auto] No stack gate (session-gate, grep-cmm-gate, cmm-nudge, agent-cmm-gate) leaves a vbw:* agent without a permitted route
- R5 [auto] A VBW 2 agent can run CMM queries (search_graph, trace_path, get_code_snippet, search_code) within its tool allowlist and get results
- R6 [auto] All 7 VBW 2 agent types get CMM-first code-search guidance they can act on with their allowed tools
- R7 [auto] docs/vbw2-extension-proposal.md covers the problem, the worker-simulator measurements, proposed extension points (configurable extra tools incl. MCP, MCP inheritance, skills, rule injection, a map provider) and how this stack uses each
- R8 [human] The VBW 2 extension proposal is ready to file upstream
- R9 [auto] CONTRIBUTING.md and CLAUDE.md document the VBW 2 + /qa-cycle PR sequence: feature/* branch off develop before the first VBW step, a GitHub issue mirroring the requirements as the QA contract, push and PR to develop from the main session (VBW never pushes), /qa-cycle rounds with their own fix commits, keep-the-changes then vbw prove, accept, ship
- R10 [human] The PR to develop is approved through /qa-cycle (clean round, GitHub issue as contract), and every QA fix commit is kept and re-proven by VBW
- R11 [auto] VBW 2 mapping scouts get codebase structure from CMM, and .vbw/map.md points later agents to the live CMM graph

<!-- One requirement per line: an id, how it is proved, and a user-observable
     statement. [auto] = a check can prove it; [human] = only a person can judge it.
- R1 [auto] A visitor can sign up with an email address
- R2 [human] The landing page feels trustworthy
-->

## Commands

<!-- The project's own commands, which every proof runs once you approve them.
     One per line: a name, then the command as words, or as a JSON array when
     an argument contains spaces. Edit or delete lines, then vbw spec sync.
- test: npm test
- build: ["make", "release build"]
-->
- test: make test

## Clean copy

<!-- Git-ignored paths the proof's clean copy leaves out, such as a huge data
     folder or caches. One per line, relative to the project root; the rest of
     the ignored environment is still copied in. Edit lines, then vbw spec sync.
- data/
-->
