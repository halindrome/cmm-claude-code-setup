# Changelog

All notable changes to cmm-claude-code-setup are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Versions follow [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- `hooks/global/ctx-annotate-nudge.sh` — PostToolUse `additionalContext` nudge for `mcp__context-mode__ctx_(execute|search|index|fetch_and_index)`; emits a "summarize what this ctx_* result told you before running another search" advisory via `hookSpecificOutput.additionalContext` with a 120s per-project cooldown sentinel and `python3 json.dumps` escaping. Replaces the retired stderr-only `ctx-search-nudge.sh`. (Finding D)
- `hooks/global/cmm-orient-nudge.sh` — one-shot-per-session PostToolUse nudge on `mcp__codebase-memory-mcp__search_graph`; names `get_architecture`, `trace_call_path`, and `query_graph` so agents reach the under-promoted CMM tools after their first graph query. Session-scoped sentinel (`/tmp/cmm-orient-nudged-<PROJECT_HASH>-<SESSION_ID>`), `# cmm-exempt` bypass, fail-open on every path. (Finding C)
- `/tmp/cmm-recent-<PROJECT_HASH>` sentinel (touched by `track-cmm-calls.sh`) now gates the `cmm-nudge.sh` targeted-Read exemption — `offset+limit<=100` reads only pass when a CMM call landed within the last 60s. (Finding B)
- `tests/test-phase-47-bundle-install.sh`, `tests/test-ctx-annotate-nudge.sh`, `tests/test-cmm-orient-nudge.sh`; `tests/test-agent-hook-overrides.sh` and `tests/test-agent-hook-enforcement.sh` extended with presence/absence assertions for the new hooks.

### Changed
- `hooks/project/ctx-execute-enforcer.sh` — tightened the Bash exemption list: removed the unbounded `git log|diff|show` catch-all (keep `--stat`/`--oneline`/`--name-only` bounded forms) and dropped `echo`/`printf` from the navigation group. Every exempt arm now calls `track-hook-blocks.sh` with a per-group label (`git-write`, `git-bounded-read`, `filesystem`, `navigation`, `short-reads`, `remote`, `vbw-planning`, `version`) for observability. (Finding A)
- `rules/cmm-rules.md` rewritten around a six-row question-to-tool decision table naming `get_architecture`, `search_graph`, `get_code_snippet`, `trace_call_path`, `query_graph`, and `search_code`; `hooks/project/cmm-session-start.sh` agent-prompt heredoc mirrors the same mapping. (Finding C)
- `rules/project-settings-example.json`, `setup.sh::install_project`, and every `agents/vbw-*.md` frontmatter register the two new PostToolUse matchers; `ctx-search-nudge.sh` added to `deprecated_hooks` so stale installs purge the file and its settings.json entry.

### Removed
- `hooks/global/ctx-search-nudge.sh` and `tests/test-ctx-search-nudge.sh` — superseded by `ctx-annotate-nudge.sh`.

---

## [1.2.0] — 2026-03-24

### Added
- `hooks/lib/is-cmm-ext.sh` — shared extension-check library (67 built-in languages + user-defined extensions from CMM config) replacing duplicated inline case lists in global hooks; cached per repo root via `/tmp/cmm-user-ext-<hash>`
- `touch_project` call in `reindex-after-commit.sh` — nudges the CMM file watcher after every commit so reindexing starts within seconds instead of waiting for the next poll cycle
- `tests/test-touch-project-hook.sh` — 8-test suite covering project name resolution across monorepo submodules, debug logging, and end-to-end CLI invocation with stubbed CMM server
- `tests/setup-test-monorepo.sh` — ephemeral monorepo fixture script for submodule testing
- `tests/test-agent-gate-blocking.sh` — 9-test suite for `agent-cmm-gate.sh` keyword blocking and exemption logic
- `tests/test-team-mode-bypass.sh` — 3-test suite for team-mode sentinel bypass and `SUBAGENT_COMMIT=1` override
- "Agent Hook Reliability and Known Limitations" section in `docs/setup-guide.md` documenting 5 known Claude Code issues (#7881, #20221, #16047, #19225, agent-sdk-ts#58) with recommended patterns
- "Adding Custom Subagent Hooks" guidance in `CONTRIBUTING.md` covering PostToolUse:Agent vs SubagentStop tradeoffs, frontmatter hooks, and exit code table

### Changed
- `cmm-nudge.sh` and `reindex-after-edit.sh` refactored to source `hooks/lib/is-cmm-ext.sh` instead of maintaining separate inline extension lists
- `cmm-session-start.sh` and `session-gate.sh` simplified to use `index_repository` directly (drop two-step `index_status` → `index_repository` flow; incremental indexing is fast when already current)
- Language count updated from 64 to 67 across README, setup-guide, and rules
- `setup.sh` updated to install `hooks/lib/` directory during global installation
- `touch_project` project name derivation uses CMM convention (full path with `/` → `-`) instead of `basename`

### Fixed
- Missing `*.sass` extension restored in shared extension library (regression from inline list extraction)
- Test 8 FAKE_INPUT invalid JSON escape corrected (literal `\n` in single-quoted string)
- Test helper symlink resolution for macOS (`/tmp` → `/private/tmp`)

---

## [1.1.0] — 2026-03-20

### Added
- `cmm-query-stale-advisory.sh` — PostToolUse hook that warns when a CMM graph query runs against a stale index
- `reindex-after-commit.sh` — PostToolUse hook that marks the CMM sentinel stale after `git commit` operations so the session gate re-prompts for a reindex
- `subagent-cmm-startup.sh` — SubagentStart hook that injects CMM index state into **all** spawned subagents via `additionalContext` JSON (broadened from VBW-agent-only to `*` matcher)
- `agent-cmm-gate.sh` — PreToolUse hook that gates Agent tool calls, requiring CMM keyword references in the prompt for code-exploration agents
- Context Mode integration: `context-mode-sentinel-writer.sh`, `context-mode-event-logger.sh`, `context-mode-pre-compact.sh` — session sentinel, event journal, and pre-compact snapshot for Context Mode MCP
- `session-gate.sh` — unified CMM + Context Mode session gate (replaces separate `cmm-session-gate.sh` and `context-mode-session-gate.sh`)
- `ctx_search` added to `context-mode-sentinel-writer.sh` PostToolUse matcher in `rules/project-settings-example.json`

### Fixed
- Stale CMM sentinel now triggers an advisory warning instead of a hard block — reduces friction when the file watcher hasn't caught up after a commit
- Context Mode stale sentinel behaviour made consistent with CMM (warn-only, not block)
- `index_status` no longer clears a stale sentinel — only `index_repository` resets it to `ready`
- `mcp__context-mode__*` tools bypass the CMM sentinel gate unconditionally (Phase 2 of session-gate) so Context Mode tools are never gated by CMM state
- All context-mode hooks (`event-logger`, `pre-compact`, `sentinel-writer`) now use git worktree detection to anchor DB path to the main project root
- `setup.sh` `detect_context_mode()` adds worktree detection so the DB path is stable across worktree sessions
- `subagent-cmm-startup.sh` injects `additionalContext` JSON — previously only printed to stderr; now the advisory reaches the spawned agent's initial context

### Changed
- SubagentStart hook matcher broadened from `dev|scout|lead|qa` to `*` so all subagents (including plain Agent tool calls) receive CMM state context at startup

---

## [1.0.0] — 2026-03-17

First stable release. Milestone 03 shipped: statusline, jmunch security hardening, git branching strategy.

### Added
- `version.txt` at `1.0.0` and `scripts/bump-version.sh` for semantic version management
- Branch model: `production` / `develop` / `feature/*` with annotated `v1.0.0` and `stable` tags
- Branch Strategy section in README, CLAUDE.md, and CONTRIBUTING.md
- QA cycle documentation in CONTRIBUTING.md (2–4 Opus rounds before merge)

### Fixed
- Security hardening from jmunch review: `--verify` flag for checksums, worktree safety analysis
- `setup.sh` deduplicates hooks by basename on reinstall (`--force`) to prevent stale file accumulation
- Hooks use absolute paths so they are found regardless of session CWD (fixes submodule sessions)
- All hooks walk the full git superproject chain for arbitrarily nested submodules
- Sentinel hash uses git worktree main-project root so hash is stable across worktree sessions
- Path integrity check warns when project has moved or been cloned without re-running `setup.sh`
- `setup.sh` writes tool allowlist to `settings.json`, not `settings.local.json`

---

## [0.5.3] — 2026-03-17

### Fixed
- `setup.sh` deduplicates hooks on reinstall

---

## [0.5.2] — 2026-03-17

### Added
- `cmm-session-start.sh` extended with Context Mode bootstrap instructions

### Fixed
- Sentinel hash resolution uses git superproject root in submodule sessions
- Hooks use `pwd -P` to resolve symlinks in path integrity check

---

## [0.5.1] — 2026-03-17

### Fixed
- `setup.sh` treats `.mcp.json` without `context-mode` entry as detect-and-prompt, not opt-out
- Stale sentinel path references corrected in CLAUDE.md and setup guide

---

## [0.5.0] — 2026-03-16

### Added
- `setup.sh` offers to write CMM tool allowlist to `settings.local.json`
- `agent-cmm-gate.sh` exempts non-code short prompts from the keyword gate
- Unified `session-gate.sh` replacing `cmm-session-gate.sh` + `context-mode-session-gate.sh`
- Monorepo path fix: hooks anchor sentinel hash to git superproject root

### Fixed
- Deprecated hook purge uses an explicit list instead of delete-unknown approach

---

## [0.4.2] — 2026-03-16

### Fixed
- Context Mode session gate and event logger path fixes

---

## [0.4.1] — 2026-03-16

### Fixed
- Context Mode integration path and event logger corrections

---

## [0.4.0] — 2026-03-16

### Added
- Context Mode MCP integration: session gate, sentinel writer, event logger, pre-compact hook
- `setup.sh` detects Context Mode installation and offers to register hooks

---

## [0.3.0] — 2026-03-14

Milestone 02 shipped: benchmarks and MCP availability check.

### Added
- Benchmark suite (`benchmarks/`) comparing baseline / CMM / CMM+cache token usage across 3 variants, 5 task prompts, 5 repos
- `setup.sh` MCP availability check with graceful handling when CMM server is offline
- Statusline token savings display (`statusline-cmm.sh`)
- Agent initialization context: `cmm-session-start.sh` detects spawned-agent sessions and injects richer CMM startup instructions

---

## [0.2.0] — 2026-03-12

Milestone 01 shipped: core hook layer.

### Added
- `session-gate.sh` (project) — PreToolUse gate blocking non-CMM tools until `index_repository` or `index_status` confirms the graph is current
- `cmm-sentinel-writer.sh` — PostToolUse hook writing the session sentinel after CMM bootstrap
- `cmm-session-start.sh` — SessionStart hook prompting CMM initialization
- `track-cmm-calls.sh` — PostToolUse hook tracking CMM tool call frequency
- `rules/` — `cmm-rules.md`, `project-settings-example.json`, `allowed-tools.txt`, `mcp-example.json`
- `setup.sh` — automated installer for global and project hooks
- Global hooks: `cmm-nudge.sh` (soft Read-gate advisory), `reindex-after-edit.sh`
