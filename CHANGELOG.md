# Changelog

All notable changes to cmm-claude-code-setup are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Versions follow [Semantic Versioning](https://semver.org/).

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
- `rules/` — `project-settings-example.json`, `global-claude-md.md`, `allowed-tools.txt`, `mcp-example.json`
- `setup.sh` — automated installer for global and project hooks
- Global hooks: `cmm-nudge.sh` (soft Read-gate advisory), `reindex-after-edit.sh`
