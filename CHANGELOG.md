# Changelog

All notable changes to cmm-claude-code-setup are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Versions follow [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- **Phase 57: Sync context-mode integration to upstream v1.0.122.** Brings `setup.sh`, `merge_context_mode_hooks`, the three project hooks (`hooks/project/track-ctx-calls.sh`, `hooks/project/ctx-execute-enforcer.sh`, `hooks/project/ctx-execute-cmm-nudge.sh`), and `.claude/rules/ctx-rules.md` in line with upstream `mksglu/context-mode` v1.0.122's canonical matcher inventory and 11-tool MCP surface. Lands in two waves across plans `57-01` and `57-02` (10 atomic commits total).
  - **G1 — Interactive plugin-form migration (plan 57-01).** `setup.sh::detect_context_mode` now emits a four-state classification (`NONE`/`MCP_ONLY`/`PLUGIN`/`BOTH`) by probing `${CLAUDE_PLUGIN_ROOT}` and `~/.claude/plugins/cache/<marketplace>/context-mode/.claude-plugin/plugin.json` independently from the legacy `.mcp.json` probe. When only the MCP-server form is found, setup interactively offers `Y/n/keep` migration to `/plugin install context-mode@context-mode`; on `Y` it removes the redundant `.mcp.json` entry, prints the `/plugin install` instructions for the user's next Claude Code session, and writes a project-state sentinel (`.vbw-planning/.context-mode-migration-pending`, cleared automatically once plugin form is detected). A `keep` reply records `.vbw-planning/.context-mode-form-preference: mcp-server` to suppress future prompts. New `--no-migrate` flag and non-TTY stdin both force the silent `n` branch for CI / `--dry-run`. When BOTH forms are present, plugin wins and the redundant MCP-server entry is offered for cleanup. When NEITHER is present, behavior is unchanged from prior phases.
  - **G2 — Matcher heal, no version gate (plan 57-01).** `merge_context_mode_hooks()` writes the full upstream-1.0.122 canonical matcher set unconditionally: PostToolUse gains the wildcard `mcp__` matcher introduced in upstream [PR #532](https://github.com/mksglu/context-mode/pull/532) (closes [#529](https://github.com/mksglu/context-mode/issues/529)); PreToolUse gains the three plugin-form ctx tool names (`mcp__plugin_context-mode_context-mode__ctx_execute[_file|_batch_execute]`) alongside the existing MCP-server-form matchers. Older context-mode installs receive matchers they don't yet consume (graceful degradation; no hard version requirement). Heal is idempotent across three fixture shapes (Phase-51 baseline, partially-migrated, already-canonical).
  - **G3 — Parallel matchers, plugin form first (plans 57-01 and 57-02).** The three project hooks now register parallel matchers for both install-form tool names — `mcp__plugin_context-mode_context-mode__*|mcp__context-mode__*` in `setup.sh`'s settings.json HEREDOC and `merge_context_mode_hooks` PreToolUse spec, plugin form listed FIRST in every site to document canonical-vs-legacy intent and to win the match during transitional dual-registration states. `ctx-execute-enforcer.sh` gains a `${CLAUDE_PLUGIN_ROOT}` + `~/.claude/plugins/cache` fast-path probe ahead of the legacy `.mcp.json` probe; `ctx-execute-cmm-nudge.sh` python parser and bash gate both accept either form's `ctx_execute` tool name with identical trigger and classification logic. `rules/ctx-rules.md` expanded to cover all 11 upstream MCP tools (6 sandbox + 5 meta); `ctx_purge` carries an explicit destructive-action guardrail in the same caution category as `rm -rf`; `ctx_execute_file` documented as the preferred surface for shell scripts longer than ~50 lines.
  - **G4 — Issue #329 regression test + CHANGELOG closure (plan 57-02).** `tests/test-phase-57-mcp-capture.sh` is the ongoing guard against future upstream regression — fires a plugin-form `mcp__plugin_context-mode_context-mode__ctx_execute` payload through each project hook and asserts no crash, plus verifies the canonical PreToolUse matcher (plugin form first, MCP-server form second) and the wildcard `mcp__` PostToolUse matcher are both written. `tests/test-phase-51-upstream-hooks.sh` re-baselined to the upstream-1.0.122 canonical matcher inventory (20/20 assertions). The Phase 51 Coverage paragraph below drops the pre-1.0.122 hedge and cites v1.0.122 / PR #532 / #529 as the fix baseline. `README.md` and `codebase-memory-setup-guide.md` now lead with `/plugin marketplace add mksglu/context-mode` + `/plugin install context-mode@context-mode` as the recommended install; the MCP-server install (`claude mcp add context-mode -- npx -y context-mode@latest`) is preserved as a labeled alternative. `setup.sh --no-migrate` documented for CI use. `CHECKSUMS.sha256` regenerated for the modified `rules/ctx-rules.md` and the four 57-01 hooks/`setup.sh` files.
- **Phase 51: `setup.sh --project` now registers context-mode's five upstream hooks in `.claude/settings.json` via a small dispatcher helper (`hooks/project/context-mode-hook-dispatch.sh`):** the registered command is `bash <abs>/.claude/hooks/context-mode-hook-dispatch.sh <event>`, which exec's the global `context-mode` binary when present and falls back to `npx -y context-mode@latest` only when no global install exists. This eliminates the ENOTEMPTY race that bare `npx -y context-mode@latest` suffers under rapid concurrent hook fires (every tool call triggers PreToolUse+PostToolUse; parallel npx invocations collide during `~/.npm/_npx/` atomic-rename updates of the `@latest` cache, silently skipping capture on the losing side). Field-observed in real Dev sessions on 2026-04-22 — see `fix(51): replace bare npx with hybrid dispatch helper to eliminate ENOTEMPTY race`. Command-drift heal in `merge_context_mode_hooks()` rewrites both legacy bare-form (`context-mode hook claude-code <event>`) and intermediate npx-form (`npx -y context-mode@latest hook claude-code <event>`) entries in place to the new dispatcher form on re-run, keeping idempotency.

  Coverage: PostToolUse (fires on Bash/Read/Write/Edit/Glob/Grep/Skill/Agent/Task*/EnterPlanMode/ExitPlanMode/EnterWorktree/`mcp__*` — upstream `extractEvents` persists semantic session events into the FTS5 DB: file reads, prompts, rules, subagent completions, task updates, intents, decisions; raw `mcp__*` tool outputs (jira/grafana/sentry/halo responses) are now persisted as of upstream **v1.0.122**, which added a wildcard `mcp__` matcher to `POST_TOOL_USE_MATCHERS` via [PR #532](https://github.com/mksglu/context-mode/pull/532) (closes [#529](https://github.com/mksglu/context-mode/issues/529); resolves the architectural gap previously tracked as [mksglu/context-mode#329](https://github.com/mksglu/context-mode/issues/329)). Ongoing guard against regression: `tests/test-phase-57-mcp-capture.sh` exercises a plugin-form `mcp__plugin_context-mode_context-mode__ctx_execute` payload through our three project hooks and asserts no crash under the upstream-1.0.122 canonical matcher inventory), PreToolUse (cache-redirect for Bash/WebFetch/Read/Grep/Agent/ctx_*), PreCompact (session snapshot), SessionStart (inject prior snapshots), UserPromptSubmit (intent). Previously only our thin bash wrappers fired — context-mode's core capture/redirect never ran. Implemented by new `merge_context_mode_hooks()` function in `setup.sh`; dedup uses sentinel substrings (`hook claude-code <event>` for legacy/npx forms, `context-mode-hook-dispatch.sh <event>` for the current form) so re-running `setup.sh --project` is idempotent and all prior phase-51 forms are healed in-place. Guarded by `INSTALL_CONTEXT_MODE`: `--skip-context-mode` writes no upstream entries. Our PreToolUse hooks (`session-gate`, `ctx-execute-enforcer`, `cmm-nudge`, `cmm-grep-nudge`, `agent-cmm-gate`) remain at lower array indices than the new upstream entry, preserving additive-enforcement ordering. Flags appended to the npx launcher command (e.g. `--verbose`) are preserved on re-run, but the `matcher` field on these five entries is healed back to the upstream default on every run to keep all installs on the same tool-coverage contract (matchers on your other hook entries are untouched — see README "Upstream hook registration"). (`tests/test-phase-51-upstream-hooks.sh`, `tests/test-phase-51-integration.sh`.)
- **Phase 51: `ctx_search`-first retrieval protocol documented across all 7 VBW agents and the top-level ctx/cmm rules files.** Every `agents/vbw-*.md` (scout, dev, lead, qa, debugger, architect, docs) gains a `## Context Mode Capture (PostToolUse active)` subsection inside the `cmm-claude-code-setup: Context Mode extensions` region instructing agents to call `ctx_search` before re-running Bash/Read/Grep and `ctx_stats` at session start. `rules/ctx-rules.md` adds a `### PostToolUse capture (always on)` subsection; `rules/cmm-rules.md` adds a `### CMM vs. context-mode` disambiguation block.

### Removed
- **`hooks/global/ctx-annotate-nudge.sh` and `tests/test-ctx-annotate-nudge.sh` deleted.** The PostToolUse `additionalContext` reminder duplicated retrieval-protocol guidance already loaded into every turn's CLAUDE.md context from `.claude/rules/ctx-rules.md` (Claude Code's built-in `.claude/rules/` loader picks it up natively), and the duplication caused the model to misread the reminder as a turn-terminator — investigations stalled silently mid-protocol after every qualifying ctx_* call. Reword fix `a8e066e` ("avoid STOP turn-terminator misread") changed the wording but did not change behavior, confirming the issue was redundancy, not phrasing. The hook is added to a module-level `DEPRECATED_HOOKS` constant in `setup.sh` and a new shared `purge_deprecated_hooks` helper is now invoked from **both** `install_project()` (project scope: `.claude/hooks/` + `.claude/settings.json`) and `install_global()` (global scope: `$CLAUDE_CONFIG_DIR/hooks/` + `$CLAUDE_CONFIG_DIR/settings.json`); previously only project-scope cleanup ran, so `setup.sh --global` re-runs left retired hook files lingering in the global config dir indefinitely. Frontmatter PostToolUse block stripped from all 7 `agents/vbw-*.md`. The PostToolUse entry is also removed from `rules/project-settings-example.json`. `tests/test-phase-47-bundle-install.sh` gains a parity sub-test that pre-seeds `ctx-annotate-nudge.sh` + a matching settings entry, re-runs setup, and asserts both are gone (directly validates the migration claim, not by analogy with `ctx-search-nudge`). `tests/test-agent-hook-overrides.sh` and `tests/test-agent-hook-enforcement.sh` updated to assert absence/non-registration instead of presence; the must-not list in `test-agent-hook-overrides.sh` is split into "parent-only" and "retired-from-frontmatter" sub-lists with comments so historical context is recoverable from the test source.
- **Phase 51: Deprecated bash wrappers `hooks/project/context-mode-event-logger.sh` and `hooks/project/context-mode-pre-compact.sh`** deleted from the repository (plus their dedicated regression test `tests/test-event-logger-fastpath.sh`). They were functional duplicates of context-mode's upstream `posttooluse.mjs` and `precompact.mjs` — running both risked double-writes to the context-mode SQLite DB. Their entry in `setup.sh`'s `deprecated_hooks` list is retained so re-running `setup.sh --project` on a pre-phase-51 install still deletes the wrapper files from `.claude/hooks/` and prunes their `settings.json` entries.

### Fixed
- **Phase 50: Hook project-root resolution no longer returns a path inside `.git/modules/<name>/` when a worktree's git pointer has been orphaned by a submodule deinit.** Fixes spurious `cmm-hooks: path mismatch` (exit 2) in `session-gate.sh` for sessions launched from such worktrees (e.g. codespaces created before a submodule was removed). Affects: `hooks/lib/project-root.sh`, `hooks/project/session-gate.sh` (inline fallback now does the full superproject walk), and four inline hooks (`track-hook-blocks.sh`, `reindex-after-commit.sh`, `context-mode-pre-compact.sh`, `context-mode-event-logger.sh`). Regression tests added (`tests/test-project-root-lib.sh`, `tests/test-session-gate-earlyexit.sh`).

### Changed
- **Phase 49: Aligned agent overrides (`agents/vbw-*.md`) with VBW v1.35.0.** **Consumer-visible behavior change:** after upgrade, `vbw-qa` agents persist `VERIFICATION.md` via the VBW-shipped `write-verification.sh` gate — direct `Write` on a phase's VERIFICATION.md is now blocked. Synced `vbw-qa.md` body (`write-verification.sh` persistence gate, `plan_ref`/`plans_verified` validation, `## Debug Session QA Mode`, `## Remediation Round Verification Scope`, `## Pre-Existing Failure Handling`, expanded Deviation Handling, `pre_existing_issues` JSON array in `qa_verdict`). Synced `vbw-dev.md` body (DEVN-05 structured `pre_existing_issues` persistence, Stage 3 `ac_results` emission, SUMMARY description update). Added `<skill_no_activation>` orchestrator-signal handling to all 6 VBW agents (`vbw-dev`, `vbw-scout`, `vbw-lead`, `vbw-qa`, `vbw-debugger`, `vbw-docs`). Reverted the CMM-added `tools:` allowlist on `vbw-qa` to `disallowedTools: Task` only (matching VBW source). Documented the CMM-only `Task(vbw-debugger)` self-spawn in the `vbw-debugger` MAINTENANCE override comment so future VBW syncs preserve it. All CMM extensions preserved: `hooks:` frontmatter blocks, MAINTENANCE override comments, `## Context Mode Web Fetch` block in `vbw-dev`, `## Tool blocks` section. Regenerated `CHECKSUMS.sha256` to include the 6 synced agent files and added `tests/test-phase-49-agent-sync.sh` asserting both sync markers and preserved CMM extensions. **`vbw-caveman` alignment deferred to a future phase** (deliberately out of scope).

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
