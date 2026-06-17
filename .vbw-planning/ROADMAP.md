# cmm-claude-code-setup Roadmap

Hook-based enforcement layer for codebase-memory-mcp + Claude Code, adapted from Shachar Bard's jmunch-claude-code-setup.

## Phases
- [x] Phase 1: Core Documentation (archived)
- [x] Phase 2: Global Hooks (archived)
- [x] Phase 3: Project Hooks (archived)
- [x] Phase 4: Rules + Config Templates (archived)
- [x] Phase 5: Setup Script (archived)
- [x] Phase 6: Token Consumption Benchmarks
- [x] Phase 7: Agent Initialization Context
- [x] Phase 8: Context Mode Integration
- [ ] Phase 9: Setup MCP Availability Check
- [ ] Phase 10: Benchmark Context Mode
- [x] Phase 11: Statusline Setup Offer
- [x] Phase 12: Context Mode Bootstrap
- [x] Phase 13: Statusline Token Savings
- [x] Phase 14: Fix Statusline Relative Path
- [ ] Phase 15: Single Gate + Monorepo Path Fix
- [x] Phase 16: jmunch Security Hardening
- [ ] Phase 17: Git Branching Strategy
- [x] Phase 18: Implement Branching Strategy
- [x] Phase 19: Fix Session-Gate CMM Deadlock
- [x] Phase 20: CMM Sentinel Staleness After Commits
- [x] Phase 21: Require index_repository for Stale Sentinel
- [x] Phase 22: Context Mode Monorepo Root Path Fix
- [x] Phase 23: Enforce CMM Hooks Inside Subagents
- [x] Phase 24: Context Mode Integration Verification
- [x] Phase 25: CMM Index and UI Offer in Setup
- [x] Phase 26: Uninstall Option
- [x] Phase 27: CMM Touch Project Post-Commit Hook
- [x] Phase 28: Agent Hook Reliability Audit
- [x] Phase 29: Setup Drift Detection
- [x] Phase 30: Per-Project CMM Call Count Cache
- [x] Phase 31: Context Mode CMM Output Indexing
- [x] Phase 32: ctx_execute Enforcement Hook
- [x] Phase 33: Context Mode Server PATH Detection
- [x] Phase 34: Hard-Block Read on Code Files
- [x] Phase 35: Expand Agent CMM Gate to Explore and Plan
- [x] Phase 36: Hook Block Counter and Statusline Integration
- [x] Phase 46: Source-Code Search CMM Gate
- [x] Phase 48: Setup Statusline Reprompt with Defaults
- [x] Phase 49: Align with VBW Agent Updates (v1.35.0) (superseded by Phase 52)
- [x] Phase 51: Promote Context-Mode Hooks to First-Class
- [x] Phase 52: Audit VBW v1.36.1+ Upstream Changes
- [x] Phase 53: Review Context-Mode Updates for Tool Guidance
- [x] Phase 54: Map VBW v1.36.2 Per-Project Agent Installation Updates
- [x] Phase 55: Sync VBW v1.37.0 Agent and Orchestration Changes
- [x] Phase 56: Sync to CMM Upstream main (v0.6.1+101)
- [x] Phase 57: Sync context-mode integration to upstream v1.0.122
- [x] Phase 58: Prohibit head/tail truncation inside ctx_execute sandbox
- [x] Phase 59: Respect Global CMM on Per-Project Install
- [x] Phase 60: Harden Subagent Hook Envelopes
- [x] Phase 61: Convert CMM/ctx rules to Claude Code Skills
- [x] Phase 62: Restore MCP Tool Grants to Override Agents and Setup Allowlist
- [x] Phase 63: Refresh ctx/cmm Rule Files for Upstream Tool Versions

### Phase 49: Align with VBW Agent Updates (v1.35.0)
> **Superseded by Phase 52** (2026-05-04): Phase 52 absorbs the v1.35.0 alignment scope into a broader audit covering all VBW changes through v1.36.1+ on `origin/main`. Phase 49's specific gaps (vbw-qa write-verification gate, vbw-dev pre_existing_issues rule, `<skill_no_activation>` handling, agent frontmatter `tools:` allowlists) remain in scope and will be addressed inside Phase 52's planning.

**Goal:** Re-sync this tool's agent override bodies and frontmatter with the VBW v1.35.0 source so VBW subagents running under CMM enforcement behave identically to stock VBW. Research (`49-RESEARCH.md`) confirms VBW v1.35.0 is stable on agent inventory (still 6: dev/scout/lead/qa/debugger/docs), hook events, and `subagent_type` strings — the breaking drift is entirely in agent body content and one `tools:` allowlist mismatch. Concrete gaps: (1) `vbw-qa` body is missing the NON-NEGOTIABLE `write-verification.sh` gate, `plan_ref` / `plans_verified` validation, `Debug Session QA Mode` section, and expanded deviation/remediation rules — QA agents currently produce payloads that `write-verification.sh` rejects at exit 1; (2) `vbw-dev` body is missing the DEVN-05 structured `pre_existing_issues` JSON rule and the `## Tool blocks` section explaining how to follow `REPLACE WITH:` instructions emitted by `cmm-grep-nudge.sh` (phase 46); (3) all 6 agents are missing `<skill_no_activation>` handling (two-line addition); (4) `vbw-qa` frontmatter adds a `tools:` allowlist that VBW source does not have — revert to `disallowedTools: Task` only so future VBW tool additions to QA are not silently blocked. **Caveman (VBW v1.35.0 prose-directive compression framework) explicitly out of scope** — orthogonal to CMM/context-mode token reduction (output-side vs input-side), no MCP/hook surface, default-off, no regressions when absent. Future caveman adoption is tracked as a separate follow-up phase.
**Deps:** Phase 47 (enforcement audit established the agent override baseline), Phase 23 (subagent hook frontmatter)
**Reqs:** none (DX / correctness alignment with upstream VBW)
**Success:**
- `agents/vbw-qa.md` body updated to mirror VBW v1.35.0: `write-verification.sh` NON-NEGOTIABLE section added, `plan_ref` + `plans_verified` validation rules included, `Debug Session QA Mode` section ported, deviation/remediation round rules expanded; CMM-specific hooks block preserved
- `agents/vbw-qa.md` frontmatter `tools:` allowlist removed — revert to VBW source shape (`disallowedTools: Task`, `permissionMode: plan`, no `tools:` allowlist)
- `agents/vbw-dev.md` body updated: DEVN-05 rule emits `pre_existing_issues` as JSON frontmatter array; `## Tool blocks` section added explaining how to follow `REPLACE WITH:` instructions from `cmm-grep-nudge.sh`; Stage 3 `ac_results` + empty `pre_existing_issues` rules included
- All 6 CMM agent override bodies (`vbw-dev`, `vbw-scout`, `vbw-lead`, `vbw-qa`, `vbw-debugger`, `vbw-docs`) gain `<skill_no_activation>` handling block
- `agents/vbw-debugger.md` frontmatter `tools:` allowlist reviewed — keep only the CMM-specific Task(vbw-debugger) self-spawn if still required; otherwise revert to VBW source shape
- `CHECKSUMS.sha256` regenerated for all updated agent files
- `setup.sh` re-installs the updated agent files cleanly via `--force`
- Tests: `tests/test-agent-hook-enforcement.sh` extended to assert `write-verification.sh` gate keywords in `vbw-qa` body and `pre_existing_issues` / `Tool blocks` keywords in `vbw-dev` body; `tests/test-phase-49-bundle-install.sh` added following the phase-46/47 bundle-install pattern (fresh install + idempotency on updated agent set)
- Post-release verification: run a VBW Plan+Execute cycle under CMM enforcement and confirm QA agent produces a VERIFICATION.md via `write-verification.sh` without exit 1; Dev agent writes `pre_existing_issues: []` to SUMMARY.md frontmatter when clean

**Research pre-loaded:** `49-RESEARCH.md` — VBW v1.35.0 confirmed; agent inventory stable; body drift concentrated in vbw-qa (most outdated) and vbw-dev; caveman investigation completed and recommended out-of-scope with rationale.

### Phase 46: Source-Code Search CMM Gate
**Goal:** Close two overlapping enforcement gaps where agents search source code via the wrong tool. (A) The `Grep` tool has no PreToolUse block — agents freely run `Grep(pattern="password|PASSWORD|db_pass", type="sh")` instead of `search_code` / `search_graph` (observed 2026-04-08 in gitops). (B) `ctx-execute-enforcer.sh` pushes `Bash` to `ctx_execute` correctly, but has no "but not for code search" carve-out — so `ctx_execute(code="grep -rn 'x' src/")` gets laundered into the blessed path and CMM is never consulted (observed 2026-04-17 in codespace session `16e19082`, post-v1.6.0 reload). Both failures share one shape: a source-code search issued against the wrong tool in an indexed CMM project. Fix with three artifacts modeled on phase-44/45 templates: (1) new `hooks/project/grep-cmm-gate.sh` — PreToolUse on `Grep`, hard-block when `type`/`glob` matches a CMM-indexed language or `path` is inside an indexed repo without a non-code narrow; advisory names `search_code(query=…)` / `search_graph(name_pattern=…)` as the preferred call; (2) new `hooks/project/ctx-execute-cmm-nudge.sh` — PreToolUse on `mcp__context-mode__ctx_execute`, inspects `tool_input.code`; blocks when the command starts with or pipes through `grep|rg|ack|ag|ugrep|find -name` against source; fails open on ambiguous multi-statement scripts or `# cmm-exempt` marker; (3) one-line message update to `ctx-execute-enforcer.sh` suggesting `search_code`/`search_graph` when the Bash command looked like a grep. All three fail-silent when CMM is absent (`.mcp.json` probe). Absorbs the STATE.md todo "MISSING GREP HOOK" (added 2026-04-08). See `46-RESEARCH.md` for full evidence and the non-code extension exemption list.
**Deps:** Phase 34 (hard-block Read on code files — reuses the same language/extension cascade), Phase 44 (webfetch/ctx templates)
**Reqs:** none (enforcement improvement — mirrors phase 45 scope)
**Success:**
- `hooks/project/grep-cmm-gate.sh` created, exit 2 block with actionable advisory naming both `search_code` and `search_graph`
- Grep block fires on: code-language `type` (go/py/sh/ts/…), code-extension `glob` (`*.go`/`*.sh`/`*.py`/`*.ts`/…), and path-only calls into an indexed repo with no non-code narrow
- Grep block does NOT fire on: explicit non-code `type`/`glob`, `# cmm-exempt` marker, files <50 lines (reuse cmm-nudge logic), non-indexed languages, CMM not registered
- `hooks/project/ctx-execute-cmm-nudge.sh` created, exit 2 block when `tool_input.code` pattern-matches a code search against indexed paths
- Allowed `ctx_execute` commands unchanged: `git log`, `npm test`, `pytest`, `curl`, `jq`, test runners, `sqlite3`, `psql`, `cat <config>`, ambiguous multi-statement scripts
- Both hooks registered in `rules/project-settings-example.json`, installed by `setup.sh`, referenced from `rules/cmm-rules.md`
- `ctx-execute-enforcer.sh` block message includes the one-line Grep-in-Bash suffix
- Tests: `tests/test-grep-cmm-gate.sh` (≥8 cases: blocked by type, blocked by glob, blocked by path heuristic, allowed non-code type, allowed exempt marker, allowed small file, allowed no-CMM, search_graph-style symbol pattern → suggests search_graph); `tests/test-ctx-execute-cmm-nudge.sh` (≥9 cases: grep/rg/find blocked, git log / npm test / curl / jq allowed, ambiguous script fails open, exempt marker bypasses); integration smoke extends the phase-45 bundle-install pattern (fresh install + idempotency)
- Follow-up measurement (post-release): re-run the codespace diagnostic probe; target metric is 0 observed `Grep(type=<code-lang>)` calls and 0 observed `ctx_execute(code="grep …src/")` calls in the first session after upgrade

### Phase 6: Token Consumption Benchmarks
**Goal:** Design and implement a benchmark suite that measures Claude Code token consumption when answering standard codebase questions, comparing baseline (no CMM) vs CMM-enabled vs CMM-with-cache — producing reproducible data usable for evaluating the ROI of this tool.
**Deps:** none
**Reqs:** REQ-BENCH-01 through REQ-BENCH-05
**Success:**
- 3-variant benchmark (baseline / CMM / CMM+cache) implemented as runnable shell script
- 5 standardized task prompts defined and documented
- 5 candidate repos from CMM's clone-bench-repos.sh selected and configured
- JSONL token parser extracts input/output/cache tokens per run
- Results emitted as CSV with mean ± stddev across n=10 runs
- Markdown summary report generated from results
- README section added documenting how to run benchmarks

**Research pre-loaded:** `06-RESEARCH.md` — CMM has `scripts/clone-bench-repos.sh` (59+ repos), `scripts/benchmark-index.sh`, and Go testing.B patterns. Repos already available: expressjs/express, go-chi/chi, httpie/cli, redis/redis, meilisearch/meilisearch. Token data lives in `~/.config/claude-code/projects/*/sessions/*.jsonl`.

### Phase 7: Agent Initialization Context
**Goal:** Eliminate the trial-and-error discovery loop that spawned VBW agents experience when starting a session. Agents currently waste multiple turns figuring out that the CMM session gate is blocking their tools and that they need to call `index_status`/`index_repository` first. Fix this by making `cmm-session-start.sh` detect spawned-agent sessions and inject a richer, agent-specific initialization prompt, and by ensuring compiled context files always include actionable CMM tool references.
**Deps:** Phase 3 (Project Hooks), Phase 6 (done)
**Reqs:** none (DX improvement)
**Success:**
- `cmm-session-start.sh` detects spawned agent sessions (via `$CLAUDE_AGENT_ID` or `$CLAUDE_PARENT_SESSION_ID`) and emits a richer initialization prompt explaining the gate, how to unblock it, and where to find the phase task
- Spawned agents no longer waste turns doing discovery before starting work
- Normal human sessions are unaffected (no extra noise)
- Context files include at least one actionable CMM keyword reference

**Research pre-loaded:** `07-RESEARCH.md` — two-gate confusion loop documented; `cmm-session-start.sh` is the injection point; `$CLAUDE_AGENT_ID`/`$CLAUDE_PARENT_SESSION_ID` env vars identify spawned sessions; `agent-cmm-gate.sh` exempts `vbw:*` types from keyword gate.

### Phase 8: Context Mode Integration
**Goal:** Add first-class support for the Context Mode MCP server (execution sandboxing + session persistence via SQLite) as a complementary layer on top of CMM. Context Mode reduces context window consumption by ~98% by routing tool outputs through isolated sandboxes and persisting session state across compaction. Integration requires: (1) new hooks for session restore, event logging, and pre-compaction snapshots, (2) CLAUDE.md rules directing Claude to prefer `ctx_execute`/`ctx_search` over raw Bash/Grep, (3) extending `agent-cmm-gate.sh` to allow `ctx_*` keywords, and (4) an updated installation guide covering Context Mode MCP setup alongside CMM.
**Deps:** Phase 3 (Project Hooks), Phase 7 (Agent Init Context)
**Reqs:** none (DX + performance improvement)
**Success:**
- `context-mode-session-gate.sh` (PreToolUse) extends CMM gate to also restore SQLite state on session start
- `context-mode-event-logger.sh` (PostToolUse) logs tool calls (file edits, git ops, errors) to `.claude/context-mode.db`
- `context-mode-pre-compact.sh` (PreCompact) builds compaction snapshot before context compression
- CLAUDE.md updated with Context Mode rules: prefer `ctx_execute` over Bash, `ctx_search` over Grep for indexed content
- `agent-cmm-gate.sh` updated to allow `ctx_execute`, `ctx_search`, `ctx_index` as unblocking keywords
- README updated with Context Mode setup section and install steps
- CMM gate fires before Context Mode gate (ordering enforced in hook priority)

**Research pre-loaded:** `08-RESEARCH.md` — Context Mode is a separate MCP (not in jmunch); jmunch's hook pattern (SessionStart→PreToolUse→PostToolUse) maps directly; sentinel files coexist (`/tmp/cmm-session-ready-*` + `/tmp/context-mode-ready-*`); SQLite DB at `.claude/context-mode.db`; CMM must unblock first.

### Phase 9: Setup MCP Availability Check
**Goal:** Extend `setup.sh` to detect whether the required MCPs (codebase-memory-mcp and context-mode) are installed and registered on the local machine, and interactively offer to fetch/install them when missing. Currently `setup.sh` only warns about a missing CMM binary without taking action. Phase 9 makes the setup experience self-sufficient.
**Deps:** Phase 5 (Setup Script), Phase 8 (Context Mode Integration)
**Reqs:** none (DX improvement)
**Success:**
- `setup.sh` detects CMM binary via `command -v codebase-memory-mcp` + common fallback paths
- If CMM binary missing: display install instructions and offer to open the download URL or run install command
- `setup.sh` detects whether CMM is registered in `.mcp.json` (project) or global MCP config; if not, offers to run `codebase-memory-mcp install`
- `setup.sh` detects whether CMM tools are in `.claude/settings.local.json` allowlist; if not, offers to add them automatically
- `setup.sh` detects context-mode presence (binary or `.claude/context-mode.db`); if not, asks user if they want context mode and provides `npx @mksglu/context-mode install` command
- All detection is non-blocking — user can skip each step
- Setup ends with a clear summary: what's installed, what still needs manual action

**Research pre-loaded:** `09-RESEARCH.md` — `setup.sh` is 332 lines, currently only warns about missing CMM; detection patterns from `context-mode-session-gate.sh` (binary check + db check); CMM install via `codebase-memory-mcp install`; context-mode via `npx @mksglu/context-mode install`; 14 CMM tools need allowlisting in `settings.local.json`.

### Phase 10: Benchmark Context Mode
**Goal:** Extend the benchmark suite to include Context Mode MCP variants, run the full benchmark suite for the first time, and update the top-level README with actual benchmark results. Currently the suite supports 3 variants (baseline / cmm-cold / cmm-cache) but has never been executed. This phase adds 3 new variants (ctx / cmm+ctx-cold / cmm+ctx-cache), runs all 6 variants, and publishes the results.
**Deps:** Phase 6 (Token Benchmarks), Phase 8 (Context Mode Integration)
**Reqs:** none (measurement + documentation)
**Success:**
- 3 new benchmark variants added: `ctx` (Context Mode only), `cmm+ctx-cold` (both MCPs, fresh index), `cmm+ctx-cache` (both MCPs, warm index)
- `.mcp.json.ctx` and `.mcp.json.cmm+ctx` template files created
- `variant-setup.sh` handles all 6 variants (setup + teardown)
- `generate-report.sh` dynamically handles variable number of variants (no hardcoded 3-variant assumption)
- `config.sh` updated with all 6 variants
- Full benchmark suite run with actual results (at least n=3 runs)
- `benchmarks/README.md` updated with Context Mode variant descriptions and results
- Top-level `README.md` updated with actual benchmark numbers replacing placeholder text

**Research pre-loaded:** `10-RESEARCH.md` — variant-setup.sh uses case blocks for `.mcp.json` swapping; generate-report.sh has hardcoded variant lists that need refactoring; runtime doubles to ~4-8 hours for n=10; Context Mode needs `npx -y context-mode` in `.mcp.json` template.

### Phase 11: Statusline Setup Offer
**Goal:** Extend `setup.sh` to offer installing a CMM-aware status line in the user's Claude Code configuration. The project already has a `statusline-cmm.sh` template documented in the README but not wired into the installer. This phase adds an interactive step that detects existing statusline config, offers to install the CMM status line script, and handles the `statusLine` entry in `settings.json` — with safeguards against overwriting user customizations.
**Deps:** Phase 5 (Setup Script), Phase 9 (Setup MCP Availability Check)
**Reqs:** none (DX improvement)
**Success:**
- `setup.sh` offers to install `statusline-cmm.sh` after hook installation completes
- Detects and warns about existing `statusLine` config before overwriting
- Copies the template script to the hooks directory and makes it executable
- Merges `statusLine` entry into the appropriate `settings.json` (global or project)
- Skippable via `--skip-statusline` flag or interactive decline
- Works for both `--global` and `--project` install modes

**Research pre-loaded:** `11-RESEARCH.md` — `statusline-cmm.sh` exists in README but not in setup.sh; Claude Code statusline is a single `statusLine` entry in settings.json with `type: command`; existing statusline must be detected to avoid silent overwrite; step slots in after `merge_settings_json()` and before `print_next_steps()`.

### Phase 12: Context Mode Bootstrap
**Goal:** Fix the session-gate deadlock where Context Mode is never initialized at session start. Currently `cmm-session-start.sh` writes the CMM sentinel but ignores Context Mode entirely, so every new session in projects with Context Mode installed requires a manual `ctx_stats` call before other tools work. This phase extends `cmm-session-start.sh` to detect Context Mode installation (same logic as `session-gate.sh`) and write the Context Mode sentinel automatically at session start — eliminating the manual bootstrap step.
**Deps:** Phase 14 (Single Gate + Monorepo Path Fix)
**Reqs:** none (bug fix)
**Success:**
- `cmm-session-start.sh` detects Context Mode installation using the same detection logic as `session-gate.sh` (`.mcp.json` check + `.claude/context-mode.db` check)
- When Context Mode is detected, the script writes `/tmp/context-mode-ready-{PROJECT_HASH}` sentinel at session start
- New sessions in Context Mode-enabled projects no longer require a manual `ctx_stats` call
- Detection is symmetric with `session-gate.sh` — same sentinel path formula, same detection heuristics
- If Context Mode is not installed, the script skips the step silently
- Deployed to `../codespace` and any other projects using this hook

**Research pre-loaded:** `12-RESEARCH.md` — root cause is bootstrap asymmetry; `cmm-session-start.sh` handles CMM sentinel but ignores Context Mode; fix is to add Context Mode detection + sentinel write to `cmm-session-start.sh` using same PROJECT_HASH formula as `session-gate.sh`.

### Phase 13: Statusline Token Savings
**Goal:** Revise `statusline-cmm.sh` to read token savings from the new CMM binary's `savings.json` (`~/.cache/codebase-memory-mcp/savings.json`) and display cumulative token savings in the statusline — matching the jmunch statusline pattern (e.g., `CMM:45.2K (today:3.1K)`). The new CMM binary (`codebase-memory-mcp-combined`) writes `total_tokens_saved` and `total_cost_avoided` to `savings.json` via an internal metrics tracker, and attaches per-call `_meta` with `tokens_saved`, `baseline_tokens`, `response_tokens`, `cost_avoided`, and `reduction_ratio` in tool responses for `search_graph` and `get_code_snippet`. This phase may also need to account for a future CMM "project mode" that could change how/where stats are tracked.
**Deps:** Phase 11 (Statusline Setup Offer)
**Reqs:** none (DX improvement)
**Success:**
- `statusline-cmm.sh` reads `~/.cache/codebase-memory-mcp/savings.json` for cumulative token savings
- Token savings displayed in human-friendly format (K/M suffixes) alongside existing call counts
- Cost avoided optionally shown (e.g., `$0.68 saved`)
- Graceful fallback when `savings.json` doesn't exist (new binary not yet active)
- Compatible with jmunch statusline wrapper pattern (L4 savings line)
- Ready to adapt when CMM project mode lands (savings may become per-project)

### Phase 14: Fix Statusline Relative Path
**Goal:** Fix GitHub Issue #4 — when `setup.sh --project` installs the statusline, it writes a relative path (`.claude/hooks/statusline-cmm.sh`) into `.claude/settings.local.json`. This breaks when Claude Code operates from a subdirectory (e.g., monorepo submodule). The fix converts the project-mode path to absolute before writing, matching how global-mode already works.
**Deps:** Phase 11 (Statusline Setup Offer)
**Reqs:** none (bug fix)
**Success:**
- `setup.sh` writes an absolute path for the statusline command in project-mode installs
- Statusline works correctly when Claude Code cwd is a subdirectory of the project
- Global-mode installs remain unaffected
- Existing tests updated to verify absolute path in project-mode output

**Research pre-loaded:** `14-RESEARCH.md` — root cause is line 859 passing relative `.claude` to `_run_install_statusline_for_target`; fix: use `$(pwd)/.claude` at the call site.

### Phase 15: Single Gate + Monorepo Path Fix
**Goal:** Merge the two PreToolUse session gates (`cmm-session-gate.sh` and `context-mode-session-gate.sh`) into a single `session-gate.sh` with integrated CMM + Context Mode checks. Fix sentinel path computation to use a stable project-root-anchored path instead of `$PWD`, which breaks in monorepo/submodule scenarios where the user navigates into subdirectories. Also update `setup.sh` to check `.mcp.json` before offering Context Mode integration — respecting project-level opt-outs even when Context Mode is installed globally.
**Deps:** Phase 8 (Context Mode Integration), Phase 9 (Setup MCP Availability Check)
**Reqs:** none (bug fix + architecture)
**Success:**
- `cmm-session-gate.sh` and `context-mode-session-gate.sh` merged into a single `session-gate.sh` with two integrated sentinel checks (CMM first, Context Mode second)
- Old gate hooks removed; `settings.json` template and `setup.sh` updated to register only the single hook
- Sentinel uses a stable project-root-anchored identifier (not raw `$PWD`) so navigation into submodules does not break the gate
- `setup.sh` checks `.mcp.json` before offering to add Context Mode support — if the project's `.mcp.json` exists but does not include context-mode, the user is asked whether they want it (not assumed)
- Deploys cleanly via `setup.sh --project --force`
- `../bugfix` project updated to use the merged gate

**Research pre-loaded:** `15-RESEARCH.md` — dual gate confirmed; sentinel uses raw `$PWD`; Context Mode sentinel writer missing; hook commands use relative paths (safe for project root CWD but fragile in submodule navigation); setup.sh already checks `.mcp.json` for CMM but not for Context Mode presence check.

### Phase 16: jmunch Security Hardening
**Goal:** Evaluate jmunch-claude-code-setup's security improvements against this repository and implement the two applicable gaps: (1) git remote verification in `setup.sh` to warn if running from an unexpected clone source, and (2) SHA256 checksum generation and a `--verify` flag in `setup.sh` for post-install integrity checking of installed hooks and rules. Research (15-RESEARCH.md) confirms cmm already has 7 of jmunch's 8 security practices; only these two items are missing.
**Deps:** Phase 5 (Setup Script), Phase 14 (Single Gate)
**Reqs:** none (security hardening)
**Success:**
- `setup.sh` includes a `verify_repo_remote()` function that checks the git remote origin matches an expected pattern and prompts for confirmation if it doesn't
- `setup.sh` accepts a `--verify` flag that runs SHA256 integrity checks against a checked-in `CHECKSUMS.sha256` file
- `scripts/generate-checksums.sh` script added to regenerate `CHECKSUMS.sha256` before releases
- `CHECKSUMS.sha256` committed with checksums covering all files in `hooks/`, `rules/`, and `setup.sh`
- Both features are non-blocking by default (warn + confirm; skip gracefully if checksum file absent)

**Research pre-loaded:** `16-RESEARCH.md` — jmunch has 8 security features; cmm already has 7; two gaps: remote verification (~20 lines in setup.sh) and SHA256 `--verify` option (~80 lines + new generate-checksums.sh script).

### Phase 17: Git Branching Strategy
**Goal:** Restructure the repository from a single `main` branch to a production/develop model: rename `main` to `production` (protected release branch), create a `develop` branch for active development, introduce `version.txt` as the canonical version file, and create `scripts/bump-version.sh` to automate semantic version bumps. All future releases are tagged exclusively on `production`. Update CLAUDE.md and CONTRIBUTING.md to document the new branch/tag conventions and workflow.
**Deps:** none
**Reqs:** none (repository hygiene)
**Success:**
- `production` branch exists and holds all current commits from `main`; `main` either renamed or aliased
- `develop` branch exists, branched from `production`, as the default working branch
- `version.txt` committed to repo root with version `1.0.0` (v1.0.0 milestone release)
- `scripts/bump-version.sh` script created: accepts `major|minor|patch` arg, bumps `version.txt`, commits, and optionally tags on `production`
- Existing semantic tags (v0.1.0, v0.2.0, v0.5.0, v0.5.1) remain valid and point to correct commits
- `stable` tag updated (or created) pointing to `v1.0.0` on `production`
- CLAUDE.md updated to reflect: development happens on `develop`, merges to `production` trigger a version tag, no direct pushes to `production`
- CONTRIBUTING.md updated with branch model diagram and PR flow (feature → develop → production)

**Research pre-loaded:** `17-RESEARCH.md` — current state: single `main` branch, 4 tags (v0.1.0–v0.5.1), no version.txt, no bump-version.sh; jmunch uses same single-branch pattern; recommended: rename main→production, create develop, add version.txt at 1.0.0, write bump-version.sh. User confirmed 1.0.0 as the stable release target.

### Phase 21: Stale Sentinel Soft Advisory
**Goal:** When `reindex-after-commit.sh` marks the CMM sentinel `stale` after a commit, the gate currently treats stale the same as absent — blocking all tools until `index_repository` is called. This is too aggressive: the graph is still usable (just potentially one commit behind), and Claude should decide when to reindex, not be hard-blocked. Fix this by changing stale-sentinel behavior to a soft advisory: a stale sentinel opens the gate fully (tools work normally), and a PostToolUse hook on CMM tools appends a live-checked note to tool output if the sentinel is still stale at call time. If Claude already called `index_repository` before the first CMM search, no advisory appears. `reindex-after-commit.sh` continues to write `stale` unchanged — it is the signal source; the gate and CMM hooks are the response layer.
**Deps:** Phase 20 (stale sentinel mechanism must exist; Phase 21 changes how the gate responds to it)
**Reqs:** none (UX improvement / correctness fix)
**Success:**
- `session-gate.sh` opens the gate when the sentinel content is `stale` (not just `ready` or absent); stale ≠ blocked
- A PostToolUse hook on CMM query tools (search_graph, get_code_snippet, query_graph, trace_call_path) checks the sentinel at call time: if stale, appends `⚠ CMM index may be stale — run index_repository for up-to-date results.`; if not stale, no note added
- `reindex-after-commit.sh` behavior unchanged: still writes `stale` to the sentinel after a successful git commit
- `cmm-session-start.sh` updated to mention the stale advisory behavior in its guidance
- After a commit, tools continue to work; first CMM search includes the advisory note; after `index_repository` is called, subsequent CMM searches have no note

### Phase 22: Context Mode Monorepo Root Path Fix
**Goal:** Fix Context Mode hooks (`context-mode-event-logger.sh` and `context-mode-pre-compact.sh`) that use a relative path `.claude/context-mode.db`, causing the database to be created in whichever directory Claude Code happens to run from. In monorepo/submodule scenarios where Claude opens from a sub-directory, the database and `.claude/` folder land in the sub-module instead of the monorepo root. The fix mirrors what Phase 15 did for sentinel paths: compute `PROJECT_ROOT` via superproject walking (`git rev-parse --show-superproject-working-tree || git rev-parse --show-toplevel`) and anchor the database path to `${PROJECT_ROOT}/.claude/context-mode.db`. Also fix `setup.sh` to use the absolute path when checking for an existing Context Mode database.
**Deps:** Phase 15 (Single Gate + Monorepo Path Fix — established the superproject walk pattern)
**Reqs:** none (bug fix)
**Success:**
- `context-mode-event-logger.sh` computes `PROJECT_ROOT` via superproject walk and uses `${PROJECT_ROOT}/.claude/context-mode.db` instead of relative `.claude/context-mode.db`
- `context-mode-pre-compact.sh` applies the same fix
- `setup.sh` uses absolute project-root path when checking for existing Context Mode database
- Opening Claude Code from any sub-directory of a monorepo creates the database in the monorepo root's `.claude/` folder, not the sub-directory's
- No new `.claude/` folders are created in sub-modules
- Existing installs can be remediated by re-running `setup.sh --project --force`

**Research pre-loaded:** `22-RESEARCH.md` — root cause confirmed: event-logger and pre-compact hooks use relative `DB=".claude/context-mode.db"` (no PROJECT_ROOT compute); sentinel computation is already correct (Phase 15 fix); setup.sh line 372 also uses relative path; fix is to copy superproject walk pattern from session-gate.sh into the two Context Mode hooks and setup.sh.

### Phase 28: Agent Hook Reliability Audit
**Goal:** Investigate and address known reliability gaps in Claude Code's agent hook lifecycle events (SubagentStop, TeammateIdle, TaskCompleted). Research from a prior session confirmed: SubagentStop doesn't fire when subagents hit maxTurns limits, crash, or sessions degrade after ~2.5h (issue #16047); prompt-based SubagentStop hooks can't prevent termination (#20221); SubagentStop can't identify which subagent finished (#7881); Skills stop hooks never fire (#19225). This phase audits all agent lifecycle hooks used by this project, implements PostToolUse:Agent fallbacks where SubagentStop is unreliable, and documents the known limitations and workarounds.
**Deps:** Phase 23 (Enforce CMM Hooks Inside Subagents — must know which hooks exist in agent frontmatter)
**Reqs:** none (reliability / correctness)
**Success:**
- Audit of all SubagentStop, TeammateIdle, and TaskCompleted hooks used by this project's hook layer
- PostToolUse:Agent fallback hooks added where SubagentStop reliability is needed (e.g., cleanup, state finalization)
- Known Claude Code issues (#16047, #20221, #7881, #19225) documented with version-specific workarounds
- setup-guide.md updated with agent hook reliability caveats and recommended patterns
- Test coverage for the fallback paths (stubbed agent completion scenarios)

## Progress
| Phase | Done | Status | Date |
|-------|------|--------|------|
| 1 - Core Documentation | archived | complete | 2026-03-12 |
| 2 - Global Hooks | archived | complete | 2026-03-12 |
| 3 - Project Hooks | archived | complete | 2026-03-12 |
| 4 - Rules + Config Templates | 1/1 | complete | 2026-03-20 |
| 5 - Setup Script | 1/1 | complete | 2026-03-20 |
| 6 - Token Benchmarks | 1/3 | in progress | - |
| 7 - Agent Init Context | 1/1 | complete | 2026-03-20 |
| 8 - Context Mode Integration | 3/3 | complete | 2026-03-14 |
| 9 - Setup MCP Availability Check | 1/1 | complete | 2026-03-14 |
| 10 - Benchmark Context Mode | 4/4 | complete | 2026-03-23 |
| 11 - Statusline Setup Offer | 4/4 | complete | 2026-03-24 |
| 12 - Context Mode Bootstrap | 2/2 | complete | 2026-03-25 |
| 13 - Statusline Token Savings | 3/3 | complete | 2026-03-29 |
| 14 - Fix Statusline Relative Path | 1/1 | complete | 2026-03-16 |
| 15 - Single Gate + Monorepo Path Fix | 2/2 | complete | 2026-03-31 |
| 16 - jmunch Security Hardening | 2/2 | complete | 2026-03-17 |
| 17 - Git Branching Strategy | 3/3 | complete | 2026-04-01 |
| 18 - Implement Branching Strategy | 3/3 | complete | 2026-03-17 |
| 19 - Fix Session-Gate CMM Deadlock | 1/1 | complete | 2026-03-18 |
| 20 - CMM Sentinel Staleness After Commits | 3/3 | complete | 2026-03-18 |
| 21 - Require index_repository for Stale Sentinel | 0/? | pending | — |
| 22 - Context Mode Monorepo Root Path Fix | 0/? | pending | — |
| 23 - Enforce CMM Hooks Inside Subagents | 0/? | pending | — |
| 24 - Context Mode Integration Verification | 0/? | pending | — |
| 25 - CMM Index and UI Offer in Setup | 0/? | pending | — |
| 26 - Uninstall Option | 0/? | pending | — |
| 27 - CMM Touch Project Post-Commit Hook | 4/4 | complete | 2026-03-23 |
| 28 - Agent Hook Reliability Audit | 4/4 | complete | 2026-04-16 |
| 51 - Promote Context-Mode Hooks to First-Class | 4/4 | complete | 2026-04-22 |
| 52 - Audit VBW v1.36.1+ Upstream Changes | 2/2 | complete | 2026-05-04 |
| 53 - Review Context-Mode Updates for Tool Guidance | 1/1 | complete | 2026-05-04 |
| 55 - Sync VBW v1.37.0 Agent and Orchestration Changes | 1/1 | complete | 2026-05-11 |
| 56 - Sync to CMM Upstream main (v0.6.1+101) | 4/4 | complete | 2026-05-11 |
| 57 - Sync context-mode integration to upstream v1.0.122 | 2/2 | complete | 2026-05-17 |
| 58 - Prohibit head/tail truncation inside ctx_execute sandbox | 1/1 | complete | 2026-05-17 |
| 59 - Respect Global CMM on Per-Project Install | 1/1 | complete | 2026-05-18 |
| 60 - Harden Subagent Hook Envelopes | 1/1 | complete | 2026-05-21 |
| 61 - Convert CMM/ctx rules to Claude Code Skills | 2/2 | complete | 2026-05-28 |
| 62 - Restore MCP Tool Grants to Override Agents and Setup Allowlist | 1/1 | complete | 2026-05-29 |
| 63 - Refresh ctx/cmm Rule Files for Upstream Tool Versions | 1/1 | complete | 2026-06-17 |

### Phase 23: Enforce CMM Hooks Inside Subagents
**Goal:** Hooks registered in `settings.json` (session gate, stale advisory, CMM call tracker) do not fire inside VBW subagents (Dev, Scout, Lead, QA). These agents make CMM queries and file edits without the enforcement layer active — they can query a stale index silently, bypass the session gate, and skip call tracking. This is a correctness gap: the tooling is designed to guarantee all CMM usage is accurate and tracked, but that guarantee breaks down exactly when subagents are doing the most work. Fix this by using the mechanisms from Claude Code's subagent hooks API: inject the session gate check via `SubagentStart` context injection, and add the stale advisory and CMM call tracking hooks to VBW agent frontmatter files so they fire inside each agent's execution context.
**Deps:** Phase 21 (stale advisory hook must exist), Phase 22 (monorepo path fix should be in place)
**Reqs:** none (correctness / enforcement coverage)
**Success:**
- VBW agent frontmatter files (`.claude/agents/vbw-dev.md`, `vbw-scout.md`, `vbw-lead.md`, `vbw-qa.md`) include PostToolUse hooks for `cmm-query-stale-advisory.sh` and `track-cmm-calls.sh`
- A `SubagentStart` hook in `settings.json` injects CMM sentinel state into subagent context so agents know if the index is stale before they start
- The session gate (`session-gate.sh`) continues to be a parent-session-only PreToolUse hook (subagents should not be re-gated — they inherit a ready state from the parent), but the *advisory* and *tracking* hooks fire inside agents
- `setup.sh` updated to write agent frontmatter files with hooks alongside the existing hook copy step
- Verified: a Dev agent doing `search_graph` after a stale-marking commit receives the stale advisory in its context

**Reference:** `~/Downloads/subagent-hooks-guide.md` — describes frontmatter hooks (Approach 1) and SubagentStart context injection (Approach 2); recommended approach is Approach 1 for advisory/tracking + Approach 2 for state injection.

### Phase 24: Context Mode Integration Verification
**Goal:** Review the context-mode sibling repository to understand its tool surface and initialization flow; verify that `session-gate.sh` Phase 3, `context-mode-sentinel-writer.sh`, `context-mode-event-logger.sh`, and `context-mode-pre-compact.sh` correctly integrate with Context Mode in both the primary Claude Code session and in VBW subagents; fix the confirmed gap where `ctx_search` is missing from the `context-mode-sentinel-writer.sh` PostToolUse matcher.
**Deps:** Phase 23 (subagent hooks must be in place for subagent verification to be meaningful)
**Reqs:** none (verification + correctness fix)
**Success:**
- Context Mode tool surface documented: all 9 tools (`ctx_execute`, `ctx_execute_file`, `ctx_batch_execute`, `ctx_index`, `ctx_search`, `ctx_fetch_and_index`, `ctx_stats`, `ctx_doctor`, `ctx_upgrade`) verified against session-gate Phase 3 allow-list
- `ctx_search` added to `context-mode-sentinel-writer.sh` PostToolUse matcher in both `.claude/settings.json` and `rules/project-settings-example.json`
- Subagent behavior verified: CM sentinel in `/tmp/` is shared across parent/subagent boundary; no SubagentStart equivalent needed for Context Mode (unlike CMM)
- `setup.sh` updated to register the corrected `context-mode-sentinel-writer.sh` matcher if context-mode is installed

**Research pre-loaded:** `24-RESEARCH.md` — Context Mode exposes 9 tools; session-gate Phase 3 allow-list covers all 9 (confirmed); `ctx_search` missing from sentinel writer matcher is the only confirmed functional gap; Phase 2 `mcp__context-mode__*` wildcard makes Phase 3 dead code for prefixed names (cosmetic, functionally correct); subagent hook behavior is correct — CM sentinel shared across parent/subagent via `/tmp/`.

### Phase 25: CMM Index and UI Offer in Setup
**Goal:** Extend `setup.sh` with two new interactive offers at the end of a project installation: (1) run `index_repository` immediately via `codebase-memory-mcp cli index_repository` to build the code graph, and (2) enable the graph visualization UI via `codebase-memory-mcp --ui=true [--port=N]`, which persists to `~/.cache/codebase-memory-mcp/config.json` and activates on next MCP server start. Both offers follow the existing detect→prompt→execute pattern from `install_statusline()`. The setup script should also display a brief description of what the UI provides (browser-based graph visualization at `http://localhost:9749`) so users can make an informed choice.
**Deps:** Phase 9 (Setup MCP Availability Check), Phase 19 (Fix Session-Gate CMM Deadlock)
**Reqs:** none (DX improvement)
**Success:**
- `install_index_offer()` added after `install_allowlist()`: guards on `CMM_BINARY_STATUS=ok` + CMM registered + project install + TTY + not `--skip-mcp-check`; runs `codebase-memory-mcp cli index_repository {"repo_path":"$(pwd)"}` on acceptance; graceful fallback warning on failure
- `install_ui_offer()` added after `install_index_offer()`: guards same as index offer; prompts with a one-line description of the UI; if accepted, asks for port (default 9749, `[Enter] to accept`); runs `codebase-memory-mcp --ui=true --port=N` to persist; reports `[ok] Graph UI enabled — open http://localhost:N after next Claude Code restart`
- Both offers support `--skip-index` / `--skip-ui` flags respectively
- `--dry-run` prints `[DRY RUN] Would run: ...` for each without executing
- `print_next_steps()` removes the generic `index_repository` bullet (already handled by the offer)
- UI config persistence verified: `~/.cache/codebase-memory-mcp/config.json` receives `{"ui_enabled":true,"ui_port":N}`
- `--global`-only installs skip both offers silently (global hooks don't scope to a project)

**Research pre-loaded:** `25-01-RESEARCH.md` — CLI confirmed: `codebase-memory-mcp cli <tool> [json]`; UI flags `--ui=true/false --port=N` persist to `~/.cache/codebase-memory-mcp/config.json` (fields: `ui_enabled`, `ui_port`); insertion point between `install_allowlist()` and `print_next_steps()`; guard pattern mirrors `install_statusline()`.

### Phase 26: Uninstall Option
**Goal:** Add `--uninstall` support to `setup.sh` (or a companion `uninstall.sh`) that reverses both project-level and global installations symmetrically. Project uninstall removes hook scripts from `.claude/hooks/`, rules from `.claude/rules/`, the CMM block from `.mcp.json`, hook registrations from `.claude/settings.local.json`, the allowlist entries, and the `statusLine` key. Global uninstall removes the two global hooks and their registrations from the global `settings.json`. All removals use a backup-first strategy and warn before touching user-modifiable files.
**Deps:** Phase 5 (Setup Script), Phase 9 (Setup MCP Availability Check), Phase 11 (Statusline Setup Offer)
**Reqs:** none (operational completeness)
**Success:**
- `setup.sh --uninstall [--project] [--global] [--all]` accepted as valid invocation (mirrors install flags)
- Project uninstall: removes 13 hook scripts from `.claude/hooks/`, removes rules from `.claude/rules/` (with warning if user-modified), removes CMM server entry from `.mcp.json` (preserves other servers), removes hook registrations (SessionStart, PreToolUse, PostToolUse, PreCompact, SubagentStart) from `.claude/settings.local.json`, removes 14 CMM + 9 context-mode tool allowlist entries, removes `statusLine` key if it points to the CMM script
- Global uninstall: removes `cmm-nudge.sh` and `reindex-after-edit.sh` from global hooks dir, removes their registrations from global `settings.json`
- Backup strategy: timestamped `.bak` copies of any settings file before mutation (`settings.local.json.bak-YYYYMMDD-HHMMSS`)
- `--dry-run` shows exactly what would be removed without touching anything
- `--force` skips confirmation prompts; default (interactive) prompts once before proceeding
- Cleans up `/tmp/cmm-session-ready-*` sentinel files for the project
- Prints a clear summary: files removed, files backed up, entries cleaned from JSON, anything skipped

**Research pre-loaded:** `26-01-RESEARCH.md` — 13 project hooks, 2 global hooks; settings.json mutations cover 5 hook types + allowlist (14 CMM + 9 ctx-mode tools) + statusLine; `.mcp.json` is merged (must preserve other servers); rules files are user-modifiable (warn before removing); `codebase-memory-mcp uninstall` only handles MCP registration, not hooks/rules/settings.

### Phase 27: CMM Touch Project Post-Commit Hook
**Goal:** Integrate the new CMM `touch_project` command into post-commit hooks so that codebase indexes stay up to date automatically after every commit. The `touch_project` command is a non-blocking fire-and-forget call that resets the CMM adaptive poll timer, triggering re-indexing within 5–60s. This phase enhances the existing `reindex-after-commit.sh` hook to call `touch_project` in addition to marking the sentinel stale, and adds comprehensive testing for monorepo/submodule scenarios where project name resolution and hook propagation across submodule boundaries are critical.
**Deps:** Phase 20 (CMM Sentinel Staleness After Commits), Phase 15 (Single Gate + Monorepo Path Fix)
**Reqs:** none (DX + index freshness improvement)
**Success:**
- `reindex-after-commit.sh` (or new `cmm-touch-project.sh`) calls `touch_project` with correct project name after each commit
- Project name resolution works for: standalone repos, monorepo root, and individual submodules
- Submodule commits propagate touch to the correct CMM project (parent vs submodule, depending on indexing strategy)
- Test suite covers: single repo baseline, monorepo root commits, submodule commits, cross-submodule commits
- Tests run against `../monorepo` test environment (6 submodules in `apps/` + `mcp-server/`)
- Edge cases tested: nested submodules, `.git` file (not directory) detection, `core.hooksPath` propagation
- Documentation updated with Touch Project hook usage and monorepo guidance
- No regressions in existing sentinel staleness flow (Phase 20)

**Research pre-loaded:** `27-RESEARCH.md` — `touch_project` is non-blocking (resets adaptive poll timer); existing `reindex-after-commit.sh` marks sentinel stale but doesn't trigger reindex; monorepo at `../monorepo` has 6 submodules in 2 patterns; submodule `.git` is a file pointing to parent's `.git/modules/`; `core.hooksPath` needed for submodule hook installation.

### Phase 18: Implement Branching Strategy
**Goal:** Actually implement the production/develop branch model that phase 17 planned but never executed. Create `version.txt` at 1.0.0, create `scripts/bump-version.sh` for semantic version bumps, update README/CLAUDE.md/CONTRIBUTING.md to document the branch model going forward, and create local `production` + `develop` branches with `v1.0.0` and `stable` tags. No remote operations — user handles GitHub rename and push.
**Deps:** none
**Reqs:** none (repository hygiene + documentation)
**Success:**
- `version.txt` committed at `1.0.0` in repo root
- `scripts/bump-version.sh` created, executable, accepts `major|minor|patch`, updates `version.txt`
- `README.md` updated with a Branch Strategy section documenting production/develop/feature flow
- `CLAUDE.md` Merge Requirements updated to reference `production` instead of `main`; Branch Model section added
- `CONTRIBUTING.md` Making Changes updated to reference `develop` as base; Branch Model section added with flow diagram
- Local branch `production` created pointing to main HEAD
- Local branch `develop` created pointing to main HEAD
- Annotated tag `v1.0.0` created on main HEAD
- Annotated tag `stable` created pointing to v1.0.0
- No remote pushes (user controls GitHub rename timing)

**Research pre-loaded:** `18-RESEARCH.md` — VERSION file exists at 0.6.1 (leave untouched); version.txt is new; no CI/CD so branch rename is safe; three-plan wave: plan 01 (version infra), plan 02 (docs, wave 1 parallel), plan 03 (git operations, wave 2).

### Phase 19: Fix Session-Gate CMM Deadlock
**Goal:** Fix the deadlock in `session-gate.sh` where a stale CMM index causes the gate to block ALL tools — including `index_status` and `index_repository` — making it impossible for the agent to self-unblock. The fix adds `mcp__codebase-memory-mcp__*` to Phase 2 of the gate (the early-pass block that runs before the sentinel exists) so the CMM bootstrap tools always pass through unconditionally.
**Deps:** none
**Reqs:** none (bug fix)
**Success:**
- `session-gate.sh` (canonical + installed copy) allows `mcp__codebase-memory-mcp__index_status` and `mcp__codebase-memory-mcp__index_repository` through even when sentinel does not yet exist
- All other CMM tools (`mcp__codebase-memory-mcp__*`) also pass Phase 2 unconditionally so no CMM tool can become a gate dependency
- Existing gate behavior for non-CMM tools is unchanged
- The gate still blocks Bash, Read, Glob, Grep etc. until the sentinel is written (CMM-first enforcement preserved)
- `setup.sh` installs the fixed hook correctly

**Research pre-loaded:** `19-01-RESEARCH.md` — root cause is Phase 2 allowlist missing wildcard `mcp__codebase-memory-mcp__*`; Phase 3 already has the wildcard but only runs after sentinel exists; fix is single-line addition to Phase 2 early-pass block; low risk.

### Phase 20: CMM Sentinel Staleness After Commits
**Goal:** Once a session sentinel is written it never expires — even after agents commit files the sentinel stays "ready", so subsequent CMM queries return stale graph data and `detect_changes` blast-radius checks are unreliable. Implement a `reindex-after-commit.sh` PostToolUse hook (triggered on Bash git-commit output) that writes `stale` into the sentinel, and update `session-gate.sh` to treat a stale sentinel as absent (forces reindex before the gate opens). In team mode (VBW worktree agents active), gate agents bypass the gate so a teammate commit doesn't cascade-stall other agents; staleness is still written so the main session reindexes after the team finishes.
**Deps:** Phase 19 (gate wildcard must be in place before adding staleness; otherwise stale sentinel blocks all CMM tools)
**Reqs:** none (correctness fix)
**Success:**
- `reindex-after-commit.sh` created in `hooks/project/` and installed; registered as PostToolUse on `Bash`
- Hook detects successful `git commit` in stdout and writes `stale` to the sentinel file
- Hook does NOT mark stale for non-commit Bash calls (git add, git status, etc.)
- `session-gate.sh` Phase 2 treats `stale` sentinel content as absent (forces `index_status`/`index_repository` before opening)
- In team mode (worktree agents present: `$CLAUDE_CONFIG_DIR/teams/vbw-*` dirs exist), gate agents bypass the stale check so commits don't cascade-stall teammates
- Main session hits stale sentinel after team cleanup and reindexes automatically
- `setup.sh` installs the new hook and registers it in settings.json

### Phase 29: Setup Drift Detection
**Goal:** Enhance `setup.sh` so that running `--project` (or `--global`) without `--force` performs drift detection on all `copy_file`-managed files: compares each installed file against the source, reports identical files as `[ok] unchanged`, warns about mismatched files with mtime direction info (source newer vs local mods), and interactively prompts to overwrite each differing file one at a time. Non-interactive sessions (no tty) fall back to skip. `--force` bypasses prompts as before. Optionally show a pre-scan summary of drifted files before per-file prompts.
**Deps:** Phase 5 (Setup Script)
**Reqs:** none (DX improvement)
**Success:**
- `copy_file` enhanced with `cmp -s` content comparison: identical files print `[ok] unchanged`, differing files print `[warn]` with mtime context
- Mtime direction shown using bash `-nt` operator (POSIX-portable, no `stat` portability issues)
- Interactive per-file `[y/N]` overwrite prompt for each differing file, gated on `[ -t 0 ]` tty check
- Non-interactive mode falls back to `[skip]` (matching current behavior)
- `--force` still overwrites unconditionally with no prompts
- Pre-scan summary showing count of unchanged/changed/new files before per-file prompts
- `--help` text updated to document the drift-detection behavior
- JSON-merged files (`.mcp.json`, `settings.json`, `statusline-cmm.sh`) excluded from drift detection (they have their own idempotency logic)

**Research pre-loaded:** `29-RESEARCH.md` — `copy_file` (lines 55–68) is the single chokepoint; all hook and rules files pass through it; `cmp -s` + `-nt` operator is POSIX-portable; statusline prompt pattern (lines 874–903) is the UX template; ~25 lines net addition to `copy_file`; JSON-merged files excluded.

### Phase 30: Per-Project CMM Call Count Cache
**Goal:** Partition the CMM call-count cache (`_call-counts.json`) by project root so each project tracks its own CMM tool usage independently. Currently `track-cmm-calls.sh` writes a single global file and `statusline-cmm.sh` reads it, causing all projects to display identical call counts in the statusline. Fix both the write side (per-project cache files keyed by MD5 hash of project root, matching CMM's existing `.db` naming convention) and the read side (statusline resolves the correct per-project file via `git rev-parse --show-toplevel`). Update `setup.sh` to install the new versions.
**Deps:** Phase 11 (Statusline Setup Offer), Phase 14 (Fix Statusline Relative Path)
**Reqs:** none (bug fix)
**Success:**
- `track-cmm-calls.sh` writes to `~/.cache/codebase-memory-mcp/_call-counts-<md5hash>.json` where `<md5hash>` is derived from `git rev-parse --show-toplevel`
- `statusline-cmm.sh` (both global and project mode) reads the per-project cache file using the same hash derivation
- Two concurrent Claude Code sessions on different projects show independent call counts
- Fallback: if not inside a git repo, falls back to the existing global `_call-counts.json` path
- `setup.sh` installs the updated hooks correctly for both global and project modes
- Existing global `_call-counts.json` left in place (not migrated, not deleted) — new sessions simply ignore it
- Tests verify per-project isolation and fallback behavior

### Phase 31: Context Mode CMM Output Indexing
**Goal:** Enable CMM tool results to survive context compaction by routing them through Context Mode's `ctx_batch_execute` using the CMM CLI (`codebase-memory-mcp cli <tool> [json]`). Context Mode's `ctx_batch_execute` auto-indexes all command output into its FTS5 `ContentStore` (line 1449 of `server.ts`: `store.index({ content: stdout, source })`), making results queryable via `ctx_search` after compaction. CMM has a fully functional CLI that mirrors every MCP tool. By updating the CLAUDE.md rules to prefer `ctx_batch_execute` with CMM CLI commands over direct MCP tool calls (when Context Mode is installed), CMM results flow into the existing FTS5 pipeline with zero new hooks or SQLite writes. This is a rules-only change — no new hook scripts, no setup.sh changes, no settings.json changes.
**Deps:** Phase 8 (Context Mode Integration)
**Reqs:** none (DX improvement — context preservation after compaction)
**Success:**
- `rules/global-claude-md.md` updated: when Context Mode is installed, prefer `ctx_batch_execute` with CMM CLI for queries whose results should survive compaction (search_graph, get_code_snippet, trace_call_path, get_architecture)
- Rule includes example patterns: `ctx_batch_execute({ commands: [{ label: "search_graph: Handler", command: "codebase-memory-mcp cli search_graph '{...}'" }], queries: ["Handler classes"] })`
- Rule clarifies when to use direct MCP calls vs CLI-through-ctx_batch_execute: use direct MCP for quick lookups; use ctx_batch_execute for results that need to persist across compaction or that you'll search again later
- Existing direct MCP tool usage remains valid — this is guidance, not enforcement
- `ctx_search` can recall CMM results after compaction by searching for function names, tool names, or source labels
- No new hooks, no settings.json changes, no setup.sh changes
- Tests verify: CMM CLI via ctx_batch_execute produces indexed content queryable by ctx_search

**Research pre-loaded:** `31-RESEARCH.md` — CMM CLI confirmed working (`codebase-memory-mcp cli search_graph '{...}'`); `ctx_batch_execute` auto-indexes stdout via `store.index()` at line 1449 of server.ts; Context Mode's `ContentStore` uses FTS5 with full content in `chunks` table at `~/.context-mode/content/<hash>.db`; event logger already classifies CMM as `cmm_call` but only stores metadata; no hook changes needed — routing through ctx_batch_execute uses the existing indexing pipeline.

### Phase 32: ctx_execute Enforcement Hook
**Goal:** Create a `PreToolUse:Bash` hook (`ctx-execute-redirect.sh`) that conditionally blocks raw Bash commands likely to produce large output and redirects Claude to use Context Mode's `ctx_execute` instead. CLAUDE.md soft instructions are proven ineffective (488 Bash / 0 ctx_execute in real sessions). The hook uses the exit-2 blocking pattern (same as `session-gate.sh`) with a command-pattern classifier: exempt known-safe short/write commands (git commits, file mutations, navigation), block known-large-output commands (test runners, curl, find, log viewers), and provide the exact `mcp__context-mode__ctx_execute` invocation in the redirect message. Only activates when Context Mode is installed (sentinel check). Supports `# ctx-exempt` bypass marker in the command string.
**Deps:** Phase 8 (Context Mode Integration)
**Reqs:** none (enforcement improvement)
**Success:**
- `hooks/project/ctx-execute-redirect.sh` created: parses `tool_input.command` from stdin JSON, classifies command, exits 2 with redirect message or exits 0 to allow
- Guard: only activates when Context Mode sentinel exists (`/tmp/context-mode-ready-*`); passes through silently when Context Mode not installed
- Exempt patterns: `git (add|commit|push|merge|rebase|reset|checkout|branch|tag|stash|cherry-pick)`, `mv|cp|rm|mkdir|rmdir|touch|chmod|chown|ln`, `pwd|echo|which|date|whoami|id`, single-word commands (no spaces)
- Block patterns: test runners (`npm test|pytest|jest|go test|cargo test`), API calls (`curl|wget|gh api`), log/diff (`git log|git diff|git show|journalctl|tail`), directory traversal (`find|ls -la|du`), build commands (`make|cargo build|npm run build`)
- Redirect message includes exact `mcp__context-mode__ctx_execute(language="shell", code="<command>")` invocation
- `# ctx-exempt` marker in command bypasses blocking
- Fails open (exit 0) on JSON parse errors
- Registered in `rules/project-settings-example.json` as PreToolUse matcher on `Bash`
- `setup.sh` installs automatically via existing `install_project()` glob
- Tests verify: blocked commands get redirect message, exempt commands pass through, missing sentinel passes through

**Research pre-loaded:** `32-01-RESEARCH.md` — Exit-2 blocking pattern confirmed via session-gate.sh; Context Mode registered as server key `context-mode` in .mcp.json so tool name is `mcp__context-mode__ctx_execute`; hook coexists with existing PreToolUse:Bash hooks; Context Mode's own pretooluse.mjs uses soft `guidanceOnce` (fires once, Claude ignores after); guard requires both CM installed check and sentinel existence.

### Phase 33: Context Mode Server PATH Detection
**Goal:** Enhance `setup.sh` to detect `context-mode-server` (or `context-mode`) in the user's PATH and prefer the local binary for Context Mode MCP registration over the `npx` fallback. Currently, `.mcp.json` registration for Context Mode uses a hardcoded `npx @anthropic/context-mode` command. If the user has built or installed the Context Mode server binary locally (e.g., from a cloned repo at `../context-mode`), the setup script should detect this and register it as the MCP command instead, providing faster startup and no npm resolution overhead.
**Deps:** Phase 8 (Context Mode Integration), Phase 9 (Setup MCP Availability Check)
**Reqs:** none (DX improvement)
**Success:**
- `setup.sh` adds a `detect_context_mode_binary()` function (mirrors `detect_cmm_binary()` pattern): checks `command -v context-mode-server`, then fallback paths (`~/.local/bin`, `node_modules/.bin`, `../context-mode/dist`)
- When binary found: `.mcp.json` Context Mode entry uses the binary path directly instead of `npx`
- When binary not found: falls back to existing `npx @anthropic/context-mode` registration (no change)
- `--skip-mcp-check` flag suppresses detection (consistent with CMM detection)
- Detection result stored in `CTX_MODE_BINARY_STATUS` and `CTX_MODE_BINARY_PATH` (mirrors CMM variables)
- `print_next_steps()` shows which Context Mode command was registered (binary vs npx)
- `--dry-run` prints detection result without writing
- Existing Context Mode installations are not overwritten unless `--force` is used

### Phase 34: Hard-Block Read on Code Files
**Goal:** Upgrade `cmm-nudge.sh` from a soft advisory (exit 0) to a hard-blocking PreToolUse:Read hook that prevents Claude from reading entire code files when CMM graph tools would be more efficient. Modeled after jmunch's `jcodemunch-nudge.sh` pattern: block Read on 40+ code file extensions (.py, .ts, .tsx, .js, .go, .rs, .java, .rb, .c, .cpp, .swift, .sh, etc.) and redirect to `search_graph` for finding symbols, `get_code_snippet` for retrieving specific functions, and `trace_call_path` for understanding relationships. Include clear exemptions: files <50 lines, CLAUDE.md, planning/config files (.vbw-planning/, .claude/, .planning/), non-indexed languages, and when CMM is not installed. The block message must include the exact "sliced edit workflow" instructions: get_code_snippet (find function) -> Read with start_line/end_line (narrow context) -> Edit. This addresses the proven failure of soft CLAUDE.md instructions — the same pattern that led to 488/0 ctx_execute usage.
**Deps:** Phase 2 (Global Hooks)
**Reqs:** none (enforcement upgrade)
**Success:**
- `hooks/global/cmm-nudge.sh` upgraded from exit 0 to exit 2 for code files, or replaced with a new `cmm-read-gate.sh`
- Block message includes: (1) `search_graph` for finding by name, (2) `get_code_snippet` for reading specific functions, (3) sliced edit workflow for modifications, (4) when full Read IS allowed (<50 lines, 6+ functions in same file, imports/globals needed, non-code files)
- Exemptions: files <50 lines (wc -l check), CLAUDE.md/CONTRIBUTING.md/README.md, files in .vbw-planning/ .claude/ .planning/ node_modules/, non-code extensions (json, yaml, toml, md, txt, html, css, env, cfg, ini, lock)
- Falls back to allow (exit 0) when CMM is not registered in .mcp.json or global settings
- `# cmm-exempt` bypass marker supported (consistent with other hooks)
- Tests verify: code file blocked, small code file allowed, config file allowed, planning file allowed, CMM not installed allowed, bypass marker allowed

### Phase 35: Expand Agent CMM Gate to Explore and Plan
**Goal:** Remove Explore and Plan from the `agent-cmm-gate.sh` exemption list so that these agent types are also required to include CMM tool references in their prompts. Currently, `agent-cmm-gate.sh` line 18 exempts `Explore|Plan` — these agents frequently perform code exploration tasks that would benefit from CMM graph tools (search_graph, get_architecture, trace_call_path) but are allowed to fall back to raw Grep/Glob/Read without CMM guidance. The Explore agent in particular is the primary code exploration tool and should be the strongest CMM user. The block message should be tailored to each agent type: Explore agents should prioritize `get_architecture` and `search_graph`; Plan agents should use `get_architecture` for structural understanding and `trace_call_path` for dependency analysis.
**Deps:** Phase 23 (Enforce CMM Hooks Inside Subagents)
**Reqs:** none (enforcement expansion)
**Success:**
- `agent-cmm-gate.sh` updated: Explore and Plan removed from the exempt case statement (line 18)
- Block message for Explore agents includes: `get_architecture(aspects=["packages","hotspots"])` as first step, `search_graph` for symbol discovery, `get_code_snippet` for reading specific code
- Block message for Plan agents includes: `get_architecture` for structural context, `trace_call_path` for dependency analysis before planning
- VBW agent types (`vbw:*`) remain exempt (they have their own prompt injection via VBW's context compiler)
- `claude-code-guide` and `statusline-setup` remain exempt (non-coding tasks)
- Tests updated: verify Explore agent blocked without CMM keywords, Plan agent blocked without CMM keywords, VBW agents still exempt
- Existing tests for general/dev agents still pass

### Phase 36: Hook Block Counter and Statusline Integration
**Goal:** Add a block-counter mechanism that tracks how many times `cmm-nudge.sh` (Read gate) and `ctx-execute-enforcer.sh` (Bash gate) block tool calls, both in the parent session and inside subagents. This provides concrete observability into whether the enforcement hooks are actually firing and how frequently Claude attempts to bypass them. Integrate the block counts into the statusline so users see real-time data like `CMM:47 Blk:R12/B8` (47 CMM calls, 12 Read blocks, 8 Bash blocks). The counter uses the same per-project hash-keyed cache pattern as `track-cmm-calls.sh`.
**Deps:** Phase 34 (Hard-Block Read), Phase 32 (ctx_execute Enforcement Hook), Phase 23 (Subagent Hook Enforcement)
**Reqs:** none (observability improvement)
**Success:**
- `hooks/project/track-hook-blocks.sh` created: a lightweight PostToolUse-style counter that `cmm-nudge.sh` and `ctx-execute-enforcer.sh` call inline (via source or append) when they block — writes to `~/.cache/codebase-memory-mcp/_block-counts-<hash>.json` with `{read_blocks, bash_blocks, total_blocks, by_hook}`
- Alternative: each blocking hook appends a counter increment directly (no separate script — just `echo` to the cache file before `exit 2`)
- `statusline-cmm.sh` (both heredocs in setup.sh) updated to read block counts alongside CMM call counts: display format `CMM:N Blk:RN/BN`
- Block counts work inside subagents (frontmatter hooks in `.claude/agents/` fire the same blocking code)
- Block counter resets per session (or accumulates — design choice based on what's most useful)
- Tests verify: block count increments on blocked Read, block count increments on blocked Bash, statusline displays block data

### Phase 48: Setup Statusline Reprompt with Defaults
**Goal:** When `setup.sh --project` runs and the statusline enhancement is already installed, re-prompt the user for the six component options (`cmm_total`, `cmm_details`, `blocks_total`, `block_details`, `ctx_total`, `ctx_details`) instead of silently skipping them, and show each prompt with the currently-selected value as the default so accepting Enter keeps the existing choice. Today, `install_statusline` in `setup.sh` has two gates: phase 1 detects an existing `statusLine` key in `.claude/settings.json` and asks "Overwrite? [y/N]"; phase 2 then checks for `~/.cache/codebase-memory-mcp/_statusline-config-<hash>.json` and, if present (and `RECONFIGURE_STATUSLINE=false`), silently skips all six component prompts — printing only `[info] Statusline config found`. That second skip is the bug: users have no way to adjust their component selections without remembering the `--reconfigure-statusline` flag. The fix is scoped to `install_statusline`: change phase 2's skip condition so it reads the existing six values, and always re-enters the prompt block when interactive and not `--yes`. Each `read -r` prompt uses the current value to compute a `[Y/n]` vs `[y/N]` hint; an empty Enter response maps to "keep current" (not hard-coded `true`); `--yes` and `--force` continue to non-interactively skip. Preserve `--reconfigure-statusline` for the edge case where settings were wiped but the config file survives. See `48-RESEARCH.md` for line-numbered walkthrough of the current flow and the prompt-helper shape the implementation should adopt.
**Deps:** Phase 13 (Statusline Token Savings), Phase 36 (Hook Block Counter and Statusline Integration)
**Reqs:** none (usability fix)
**Success:**
- `install_statusline` in setup.sh: when the statusline-config cache file exists, interactive session, `--yes` not set, and user is not running `--force`, re-enter the six component prompts instead of skipping.
- Each re-prompt shows `[Y/n]` or `[y/N]` based on the currently-stored value from `~/.cache/codebase-memory-mcp/_statusline-config-<hash>.json`. Empty Enter preserves the current value.
- `--yes` and `--force` continue to non-interactively install without re-prompting (automation path unchanged).
- `--reconfigure-statusline` still works for the settings-wiped-config-survived edge case.
- A new regression test (added to `tests/test-phase-47-bundle-install.sh` or a new `tests/test-phase-48-statusline-reprompt.sh`) scripts a second `setup.sh --project` run against a scratch project where the statusline is already installed, feeds scripted `y`/`n`/Enter responses, and asserts the resulting config JSON reflects the scripted choices (with Enter preserving the previous value).
- Existing statusline tests continue to pass with no changes (they all use `--force` or `--yes`).
- No behavior change for fresh installs (phase 2 first-time prompts are unchanged).

### Phase 51: Promote Context-Mode Hooks to First-Class
**Goal:** Make context-mode a first-class operative when `setup.sh --project` runs. Today, `setup.sh` registers context-mode as an MCP server in `.mcp.json` and installs our own thin wrappers (`context-mode-event-logger.sh`, `context-mode-pre-compact.sh`, `ctx-execute-enforcer.sh`, `ctx-annotate-nudge.sh`, etc.) but never merges context-mode's upstream `hooks/hooks.json` into `.claude/settings.json` — so the essential PreToolUse cache-redirect (Bash/WebFetch/Read/Grep/Agent), PostToolUse FTS5 capture (broad `mcp__` + tool matcher), PreCompact snapshot, SessionStart injection, and UserPromptSubmit nudge never fire. Phase 51 fixes this by registering context-mode's upstream hooks alongside our own via the `context-mode hook claude-code <event>` CLI dispatcher (confirmed in `context-mode/src/cli.ts` lines 38–73), which resolves the hook bundle independent of `${CLAUDE_PLUGIN_ROOT}` so the same command works for npx-cache installs. Redundant bash wrappers (`context-mode-event-logger.sh`, `context-mode-pre-compact.sh`) are deprecated and removed in favor of upstream `.mjs` equivalents. Our own enforcement layer (session-gate, CMM gates, ctx-execute-enforcer) is preserved — it is additive and runs before upstream capture. Agent body text across all 7 agents (`vbw-dev`, `vbw-scout`, `vbw-lead`, `vbw-qa`, `vbw-debugger`, `vbw-architect`, `vbw-docs`) gains a "Context-Mode Capture (PostToolUse active)" section reminding agents to call `ctx_search` before re-running commands whose output has already been captured. See `51-RESEARCH.md` for the full hook inventory, matcher-collision table, agent-update list, and edge-case risk analysis. Plugin-detect-and-defer (skip our registration when context-mode is already installed as a CC plugin) is explicitly out of scope — tracked as a follow-up phase.
**Deps:** Phase 8 (Context Mode Integration), Phase 28 (Agent Hook Reliability Audit), Phase 47 (enforcement audit baseline)
**Reqs:** none (core functionality preservation — today's installs silently lose context-mode's capture/guide behavior)
**Success:**
- `setup.sh --project` registers context-mode's five upstream hook matchers (PostToolUse broad capture, PreToolUse Bash/WebFetch/Read/Grep/Agent/ctx_*, PreCompact, SessionStart, UserPromptSubmit) in `.claude/settings.json` via the `context-mode hook claude-code <event>` CLI dispatcher, merged idempotently (re-running setup mustn't duplicate entries)
- Deprecated wrappers `context-mode-event-logger.sh` and `context-mode-pre-compact.sh` removed (both are duplicates of upstream `posttooluse.mjs` / `precompact.mjs`); `deprecated_hooks` list updated so re-running setup on existing installs cleans them up
- Matcher-collision handling: our PreToolUse hooks (session-gate, ctx-execute-enforcer, cmm-nudge, etc.) retain registration order ahead of upstream pretooluse.mjs so additive enforcement is preserved; SessionStart coexistence documented (our `cmm-session-start.sh` and upstream `sessionstart.mjs` inject different data — both fire)
- `--skip-context-mode` flag honored: no upstream hooks registered, existing wrappers remain removed (still deprecated)
- All 7 agent override bodies in `agents/` gain a "Context-Mode Capture (PostToolUse active)" subsection: "context-mode is capturing tool output in real time; prefer `ctx_search(queries=[...])` before re-running Bash/WebFetch/Read commands whose output is likely still indexed"
- `rules/ctx-rules.md` updated to document the new always-on capture behavior (vs. today's opt-in via `intent=` param on `ctx_execute`)
- Re-install safety: running `setup.sh --project` a second time does not duplicate hook entries, does not re-install deprecated wrappers, and respects existing user customizations in `.claude/settings.json` (non-context-mode matchers untouched)
- Regression test covers: merge idempotency (second setup run produces no diff in settings.json), `--skip-context-mode` path (no upstream entries written), deprecated-wrapper cleanup (wrapper files removed on re-install if present from prior version)

### Phase 53: Review Context-Mode Updates for Tool Guidance
**Goal:** Diff our currently-installed context-mode (v1.0.75 at `~/.local/bin/context-mode-server` and the npx-cached install) against `../context-mode` `origin/main` (v1.0.107, ~120 commits in range), focused on whether our tool-use guidance still matches reality. Scope is the user's question: which of our user-facing tool-use docs and agent overrides drift from the current upstream? Confirmed scope of impact (per `53-RESEARCH.md`): **2 files need text changes plus 3-4 agent overrides need a verification pass**, and **0 of our 16 hooks need changes** (upstream deleted its duplicate `hooks.json` in commit `ece3abb`, which actually reduces overlap with our enforcement layer). Concrete deltas to absorb: (1) tool list expands from the 6 tools currently documented in `rules/ctx-rules.md` (`ctx_execute`, `ctx_search`, `ctx_index`, `ctx_fetch_and_index`, `ctx_batch_execute`, `ctx_stats`) to 11 tools — add `ctx_execute_file`, `ctx_doctor`, `ctx_upgrade`, `ctx_purge`, `ctx_insight` (verify each tool's earliest version vs the installed v1.0.75 binary before promoting it as a stable directive); (2) `intent=` parameter semantics are stale — it is now a search-mode trigger gated on the `INTENT_SEARCH_THRESHOLD = 5_000` byte threshold at `src/server.ts:1187`, not a simple indexing toggle, and our rules still describe the older behavior; (3) `ctx_batch_execute` `concurrency: 1-8` parameter (added v1.0.104, commit `1d991a2`) is missing from our guidance — concrete win for I/O-bound batches (network calls, multi-fetch); (4) `label` field on batch commands is required, not optional — our examples treat it as optional. Out of scope: refactoring upstream context-mode, contributing changes back, upgrading our installed binary to v1.0.107 (separate operational task — the user can run `npm install -g context-mode@latest` independently when ready). Phase 51's hook layer is unaffected; this is a pure docs/guidance refresh.
**Deps:** Phase 51 (Promote Context-Mode Hooks to First-Class — established the hook layer and `setup.sh` integration this audit verifies still applies)
**Reqs:** none (correctness/maintenance alignment with upstream context-mode)
**Success:**
- `53-RESEARCH.md` produced: per-commit impact table for the v1.0.75 → v1.0.107 range, classifying each commit into one of {`affects-rules-md`, `affects-hooks`, `affects-agents`, `internal-no-impact`}
- Tool surface delta verified: every newly-added tool in our updated `rules/ctx-rules.md` was confirmed to exist in the installed v1.0.75 binary (or explicitly noted as "available in upstream main only — install upgrade required to use")
- `rules/ctx-rules.md` updated with: (a) full 11-tool list, (b) corrected `intent=` semantics (search-mode trigger at 5KB threshold), (c) `ctx_batch_execute` `concurrency: 1-8` guidance for I/O-bound batches, (d) batch `label` field documented as required, (e) any tool that requires upgrading past v1.0.75 explicitly flagged so users on older installs don't get failed tool calls
- `rules/cmm-rules.md` confirmed unchanged (Scout: no updates needed — context-mode tool changes don't affect CMM/context-mode boundary doc)
- Agent override audit: `agents/vbw-{scout,dev,debugger}.md` updated to reference `ctx_execute_file` and `concurrency` where relevant; `agents/vbw-{lead,qa,docs,architect}.md` verification pass completed and either updated or explicitly noted as "no change needed"
- Hook audit: confirmed 0 of `hooks/{global,project}/*` need changes — upstream's `hooks.json` deletion (commit `ece3abb`) reduces matcher overlap with our enforcement layer; no upstream hook changes touch our PreToolUse blocks or PostToolUse capture wrappers
- Drift-detection follow-up captured: the existing STATE.md todo (`ref:6f269994`, "compare installed .vbw files against local mods; warn if .vbw upstream has been updated since install") should extend to context-mode source — note as a candidate next phase if this manual audit proves painful to repeat
- Optional: a one-line `setup.sh` advisory printed when the installed `context-mode-server` is more than N minor versions behind `npm view context-mode version` — leave to user judgement whether to include in this phase

**Research pre-loaded:** `53-RESEARCH.md` — installed binary at `~/.local/bin/context-mode-server` reports v1.0.75 vs upstream `main` at v1.0.107; ~120 commits in range; 0 hooks need changes; `rules/cmm-rules.md` unchanged; rules/ctx-rules.md and 3-4 agent overrides need updates as enumerated above.

### Phase 52: Audit VBW v1.36.1+ Upstream Changes
**Goal:** Diff installed VBW v1.36.1 (`/Users/ahby/.config/claude-code/plugins/cache/vbw-marketplace/vbw/1.36.1`) against `../vibe-better-with-claude-code-vbw` `origin/main` (~30 commits, 25 files, +3,664/-156 lines spanning PR #564 release through PR #573 linked-roadmap-drift fix), categorize every change by impact area (state-drift repair, UAT remediation artifact stabilization, QA gate validation, phase-detect / state-updater hardening, agent prompt updates), and decide for each whether: (a) the upstream fix resolves a live issue we are currently hitting (notably the `state_vs_filesystem`, `roadmap_vs_summaries`, `state_vs_state` drift warnings emitted by phase-detect at session start), (b) the change touches surface our hooks/agents intercept (e.g., new validators that our PreToolUse blocks must allow, new artifact paths our cmm-nudge / ctx-execute-enforcer must exempt), (c) the change is internal to VBW workflow with no impact on us, or (d) the change requires a corresponding update to our setup.sh/agents/rules. Absorbs Phase 49's v1.35.0 alignment scope (vbw-qa write-verification gate, vbw-dev pre_existing_issues rule, `<skill_no_activation>` handling, agent frontmatter `tools:` allowlists) so the audit covers v1.35.0 → latest in one pass. Out of scope: refactoring VBW itself, contributing fixes upstream, or upgrading to a yet-unreleased VBW version (we wait for the next packaged release before triggering plugin re-install). Concrete starting evidence: `git log --oneline 168c2606..origin/main` in the VBW source repo lists the 30 commits; `git diff --stat 168c2606..origin/main` shows the 25 changed files concentrated in `scripts/` (9 files, ~1,475 lines), `tests/` + `testing/` (12 files, ~1,899 lines), `references/` (2 files, 23 lines), and `commands/` (2 files, 87 lines).
**Deps:** Phase 47 (Enforcement Audit established the agent override baseline that this audit extends), Phase 51 (Context-Mode hook promotion — relevant because context-mode capture interacts with VBW's new state-reconciliation scripts)
**Reqs:** none (correctness/maintenance alignment with upstream VBW)
**Success:**
- `52-RESEARCH.md` produced: per-commit and per-file impact table covering all ~30 commits since `168c2606` (v1.36.1 release tag), classifying each into one of {`absorbs-our-issue`, `affects-our-hooks`, `vbw-internal-no-impact`, `requires-our-update`}
- State-drift repair (`reconcile-state-md.sh`, `state-updater.sh +292`, `verify-state-consistency.sh +99`) evaluated against the live `state_vs_filesystem` / `roadmap_vs_summaries` / `state_vs_roadmap` warnings currently in our session — confirmed whether re-running `setup.sh --project` after the next VBW release fixes them, or whether we need a one-off reconciliation
- UAT remediation artifact path stabilization (`uat-remediation-state.sh +180`, `validate-uat-remediation-artifact.sh` NEW +297, `uat-utils.sh` NEW +52) reviewed against our remediation phase outputs — confirmed our existing remediation rounds remain readable and our `host-repository` artifact-path guidance still holds
- QA gate validation (`qa-result-gate.sh +125`, `commands/qa.md` +4) reviewed against our `vbw-qa.md` agent override — confirmed our override still produces gate-compatible payloads, or list the override deltas needed
- Phase-detect changes (`phase-detect.sh +163`, `phase-state-utils.sh` NEW +210, `references/phase-detection.md` +22, `commands/vibe.md` +83) reviewed against any custom routing we depend on — confirmed our `/vbw:vibe` invocations still route correctly
- Phase 49's v1.35.0 alignment items (vbw-qa write-verification gate, vbw-dev pre_existing_issues rule, `<skill_no_activation>` block on all 6 CMM agent overrides, agent frontmatter `tools:` allowlist revert) merged into the Phase 52 plan — Phase 49 marked complete-by-supersession in roadmap once Phase 52 ships
- For each `affects-our-hooks` or `requires-our-update` change, an actionable plan task is produced (which file we touch, what the change is, how we test it)
- Drift-detection follow-up captured: existing STATE.md todo (`ref:6f269994`, added 2026-04-22) — "compare installed .vbw files against local mods; warn if .vbw upstream has been updated since install" — referenced as a candidate next phase if Phase 52 confirms the manual diff workflow is too painful to repeat
- No-op confirmation for items judged `vbw-internal-no-impact` is recorded with one-line rationale per item (don't silently drop)

**Research pre-loaded:** `52-RESEARCH.md` will be generated by the Add Phase Scout spawn — confirmed inputs are `git log 168c2606..origin/main` and `git diff --stat 168c2606..origin/main` from `../vibe-better-with-claude-code-vbw`; installed plugin path is `~/.config/claude-code/plugins/cache/vbw-marketplace/vbw/1.36.1`.

### Phase 54: Map VBW v1.36.2 Per-Project Agent Installation Updates
**Goal:** Diff this project's agent override files (`agents/vbw-*.md`) and the agent install path in `setup.sh` against VBW v1.36.2 (`/Users/ahby/Sources/vibe-better-with-claude-code-vbw` tag `v1.36.2`, commit `8ea46451`) and bring our per-project install in line with upstream agent contracts. Scope is narrowly the agent-installation surface, not Phase 52's broader audit. Confirmed deltas (per `54-RESEARCH.md`): only `vbw-scout.md` (+27/-14) and `vbw-dev.md` (+12/-3) changed upstream between `168c2606` (v1.36.1) and `v1.36.2`; the other five agents (architect/debugger/docs/lead/qa) are byte-for-byte unchanged at v1.36.2 — any local divergence in those is pre-existing Phase 49/52 carry-forward and explicitly deferred. Two upstream PRs drive the agent-file changes: PR #588 (`fix-586-scout-bash-live-validation`) reworks Scout to permit read-only Bash for live validation under a strict prose policy (`## Live Validation via Bash` section, evidence block) and updates `disallowedTools` from `Bash, Edit, NotebookEdit, Task` to `Edit, NotebookEdit, Task, TaskCreate, Agent, TeamCreate, TeamDelete`; the matching Dev change expands its `disallowedTools` from `Task` alone to `Task, TaskCreate, Agent, TeamCreate, TeamDelete, AskUserQuestion`, adds an `## Available Tools` section, and updates MCP Tool Usage / Constraints prose. Three v1.36.2 changes are confirmed `vbw-internal-no-impact` and require no action on our side: PR #590/#585 (`agent-spawn-guard` scope narrowing — VBW-plugin-internal hook, not shipped via our `setup.sh`), PR #591 (gitnexus skills shipped under VBW's `.claude/skills/` — not referenced by any agent file, no install stub needed), and `reconcile-state-md.sh` (VBW-plugin-private; depends on `phase-state-utils.sh`/`summary-utils.sh`/`uat-utils.sh` helpers we don't ship, so it cannot be invoked from our setup and would no-op without those helpers — STATE.md drift must be repaired manually). Within scope is also a hook-layer gap surfaced during research: `hooks/global/ctx-execute-enforcer.sh` is referenced by the agent frontmatter in `vbw-debugger.md` and `vbw-lead.md` but does not exist at that path — pre-existing, not v1.36.2-introduced, but blocks runtime if the install path is wrong. Out of scope: refactoring upstream VBW, contributing fixes back, the broader Phase 52 v1.35.0+ alignment items (architect/debugger/docs/lead/qa body or `tools:` allowlist work), Option-B Scout Bash enforcement hook (a future hardening choice — for v1.36.2 we match upstream prose-only policy), and any plugin-cache upgrade — the user will manually run plugin re-install after this work merges and validate live.
**Deps:** Phase 52 (broader v1.36.1+ audit established the agent-override baseline this phase extends to v1.36.2), Phase 51 (Context-Mode hook layer that any new Bash hook for Scout would compose with)
**Reqs:** none (correctness/maintenance alignment with upstream VBW v1.36.2)
**Success:**
- `agents/vbw-scout.md` updated: frontmatter `disallowedTools` set to `Edit, NotebookEdit, Task, TaskCreate, Agent, TeamCreate, TeamDelete` (Bash removed); `description` updated to v1.36.2 wording (read-only live validation included); body gains `## Live Validation via Bash` section verbatim from upstream (Allowed / Preflight / Forbidden / Evidence / Fallback rules); `## V2 Role Isolation` text refreshed to reflect new denylist and Bash policy; External Data Validation Policy → Public vs Authenticated APIs subsection updated to mention verified-safe Bash helper scripts and curl wrappers; all CMM hook frontmatter preserved verbatim
- `agents/vbw-dev.md` updated: frontmatter `disallowedTools` set to `Task, TaskCreate, Agent, TeamCreate, TeamDelete, AskUserQuestion`; `description` aligned with upstream v1.36.2 wording; body gains `## Available Tools` section and Constraints denylist footnote per upstream; `## MCP Tool Usage` paragraph refreshed; all CMM hook frontmatter preserved verbatim
- The five unchanged upstream agents (`architect`, `debugger`, `docs`, `lead`, `qa`) confirmed byte-for-byte equal at v1.36.2 vs v1.36.1; any local divergence beyond CMM hook additions explicitly noted as Phase 52 carry-forward (no action this phase)
- `setup.sh` install logic for the agent override block (lines ~1050–1140) confirmed to deploy the updated agents on next `--project` run via the existing `agents/*.md` glob — no install-logic change required
- `hooks/global/ctx-execute-enforcer.sh` reference gap audited: locate the actual source path used by `setup.sh` to install `.claude/hooks/ctx-execute-enforcer.sh`, confirm the runtime file exists post-install, and either fix the reference in `vbw-debugger.md`/`vbw-lead.md` frontmatter or restore the source file under `hooks/global/` — pre-existing gap, not v1.36.2-introduced
- `.vbw-planning/STATE.md` drift repaired: unparseable `## Current Phase` line manually corrected to reflect Phase 54; project-level Todos/Decisions/Blockers preserved; ROADMAP.md gaps for phases 37–45/47/50 acknowledged as architectural numbering (no fix attempted)
- `verify-state-consistency.sh --mode archive` against `.vbw-planning/` after the STATE.md fix shows `state_vs_filesystem` and `state_vs_roadmap` checks passing (archive-mode); `roadmap_vs_summaries` failures for missing-phase-dirs documented as accepted state since those phases were archived/superseded — explicitly recorded so future audits don't re-flag them
- Live validation by user: after this work merges, the user runs the next VBW plugin upgrade (when v1.36.2 lands in `~/.config/claude-code/plugins/cache/vbw-marketplace/vbw/`), reinstalls per-project setup, and confirms Scout's read-only Bash flow and Dev's expanded denylist behave as expected against upstream v1.36.2 plugin code

**Research pre-loaded:** `54-RESEARCH.md` — Scout-generated audit with per-agent diff table, PR-by-PR analysis (#588, #590/#585, #591), `setup.sh` install-path mapping (lines 1050–1140 confirmed sufficient — no logic change), state-drift repair surface analysis (`reconcile-state-md.sh` requires plugin-private helpers, cannot be called from our setup), and a 4-task action plan tagged with classifications (`agent-update-required` ×2, `hook-update-required` ×1 pre-existing, `documentation-update` ×1, `vbw-internal-no-impact` ×2). Verdict mix: minimal upstream agent surface, narrow blast radius, no setup.sh logic changes needed.

### Phase 55: Sync VBW v1.37.0 Agent and Orchestration Changes
**Goal:** Diff this project's agent override files (`agents/vbw-*.md`), per-project orchestration prose, and any installed hooks against VBW v1.37.0 (`/Users/ahby/Sources/vibe-better-with-claude-code-vbw` tag `v1.37.0`, commit `e1cef8f8`) and bring our per-project surface in line with the upstream contracts shipped between v1.36.2 (`8ea46451`) and v1.37.0. Confirmed in-session signals point at four upstream change clusters that may affect our agent overrides and `/vbw:vibe` mirror prose: (1) **PR #633 / fix-628 named non-team subagent guard** — `fix(guards): allow named non-team subagents` plus QA rounds 1–3 and Copilot rounds 1–2; the guard contract around `name`/`team_name` parameter combinations on agent spawns shifted, so our `/vbw:vibe` execute-protocol mirror and any VBW-style "no team_name when not team mode" guidance must match upstream wording or the new guard will reject spawns we still describe the old way. (2) **PR #631 / fix-629 debug UAT AskUserQuestion boundary** — `fix(debug): require UAT AskUserQuestion boundary` plus QA round 1 and Copilot round 1; the UAT inline-execution rule (orchestrator runs `AskUserQuestion` CHECKPOINT loop, no subagent UAT) was tightened upstream and may reshape `vbw-debugger.md` / `vbw-qa.md` body prose and the Verify mode language we mirror under `/vbw:vibe`. (3) **PR #632 / fix-630 compact machine-managed STATE.md todos** — `fix(todos): compact machine-managed state todos` plus QA round 1 and Copilot round 1; STATE.md todo serialization changed, which interacts with our local state-drift situation (Phase 54 manually repaired `## Current Phase`; the hook is now upstream and may either fix the drift on next setup or require us to align our hook output). (4) **PR #627 / fix-626 selected-todo helper + request_copilot_review** — `fix(debug): make selected todo startup deterministic`, `fix(debug): add request_copilot_review tool to fix-issue agent`, plus QA rounds 1–2 and Copilot rounds 1–2; affects `vbw-debugger.md` body and the selected-todo plumbing referenced by `/vbw:resume` and `/vbw:list-todos`. Also in scope: phase-detect UAT flake fix (PR #625) and any other commits between tag `v1.36.2` and `v1.37.0` that touch `agents/`, `commands/`, `references/`, `scripts/`, or hooks installed by per-project `setup.sh`. Out of scope (deferred to a separate phase): wholesale absorption of VBW commands/scripts we don't mirror, plugin-cache version bump (user runs that manually), CMM upstream sync (tracked separately — `codebase-memory-mcp` `main` is now `v0.6.1-101-g2215356` and warrants its own phase), and any caveman or unrelated framework adoption.
**Deps:** Phase 54 (per-project agent install baseline at v1.36.2 — direct upstream from this work), Phase 52 (v1.36.1+ audit established the upstream-diff methodology this phase reuses), Phase 23 (subagent hook frontmatter shape we preserve)
**Reqs:** none (correctness/maintenance alignment with upstream VBW v1.37.0)
**Success:**
- `55-RESEARCH.md` produced: per-commit and per-file impact table covering every change between tag `v1.36.2` (`8ea46451`) and tag `v1.37.0` (`e1cef8f8`) in `../vibe-better-with-claude-code-vbw`, classifying each into one of `{absorbs-our-issue, affects-our-agents, affects-our-vibe-prose, affects-our-hooks, vbw-internal-no-impact, requires-our-update}` and noting whether per-project setup.sh install logic is affected
- For each upstream change to `agents/vbw-*.md` between v1.36.2 and v1.37.0, our local override is updated to mirror the upstream body/frontmatter; all CMM-specific hook frontmatter (`SessionStart`, `PostToolUse`, `Stop`) preserved verbatim and `disallowedTools` / `tools` allowlist deltas matched to upstream shape
- The named non-team subagent guard change (PR #633) is reflected in any `/vbw:vibe` execute-protocol mirror prose under `commands/` or `references/` that still asserts the old `name`/`team_name` combination rules, so our mirror cannot diverge from upstream guard expectations
- The UAT AskUserQuestion boundary tightening (PR #631) is mirrored in `vbw-qa.md` / `vbw-debugger.md` bodies and any Verify-mode prose we mirror, so inline UAT execution remains valid under both the upstream guard and our CMM enforcement layer
- STATE.md machine-managed todo compaction (PR #632) is evaluated against our local state: the hook is either confirmed to repair the drift recorded in Phase 54's success criteria, or a one-off reconciliation script is documented; either way our state-drift carry-forward is closed or formally re-deferred with rationale
- `CHECKSUMS.sha256` regenerated for all updated agent files; `setup.sh` re-installs the updated agents cleanly via `--force` and the existing `agents/*.md` glob (no install-logic change expected)
- Tests: `tests/test-agent-hook-enforcement.sh` extended to assert any new contract keywords introduced by v1.37.0 (e.g., named non-team subagent guard markers, UAT AskUserQuestion boundary phrasing) appear in the updated agent bodies; a `tests/test-phase-55-bundle-install.sh` regression added following the phase-49/52/54 bundle-install pattern (fresh install + idempotency on the updated agent set)
- Post-release verification: user manually upgrades the VBW plugin cache to v1.37.0, reinstalls per-project setup, and runs one Plan+Execute+Verify cycle under CMM enforcement; QA writes a VERIFICATION.md via `write-verification.sh` without exit 1, Dev writes structured `pre_existing_issues`, the named non-team subagent guard accepts our spawn shapes, and UAT runs inline via AskUserQuestion against the new boundary
- CMM upstream sync explicitly recorded as a separate follow-up phase (~100 commits past `v0.6.1` including Windows code search, `search_graph`/`search_code` perf fixes, `trace_path` qualified-name fallback, `list_projects` tmp-prefixed visibility, C# 12 primary-constructor extraction, TS/JS hybrid LSP resolver, BSD support) so it is not silently absorbed here

**Research pre-loaded:** Will be generated by Scout during the planning phase — confirmed inputs are `git log 8ea46451..v1.37.0` and `git diff --stat 8ea46451..v1.37.0` from `../vibe-better-with-claude-code-vbw`; installed plugin path is `~/.config/claude-code/plugins/cache/vbw-marketplace/vbw/1.36.2` (or v1.37.0 once the user upgrades). Key upstream commit shortlist captured in this session: `e1cef8f8` (v1.37.0 release), `ff986c2e` (PR #633 named non-team subagent guard), `6f4f8060` (PR #631 UAT AskUserQuestion boundary), `76e66d1b` (PR #632 compact machine-managed state todos), `083eebaf` (PR #627 selected-todo helper), `ca039c13` (PR #625 phase-detect UAT flake).

### Phase 56: Sync to CMM Upstream main (v0.6.1+101)
**Goal:** Audit ~100 upstream `codebase-memory-mcp` commits since tag `v0.6.1` (HEAD currently `v0.6.1-101-g2215356` at `/Users/ahby/Sources/codebase-memory-mcp` `upstream/main`, fork-mirror at `origin/main`) and bring this project's CMM-aware surface into alignment with that upstream. Confirmed in-session signal cluster from `git log v0.6.1..upstream/main`: (1) **Cross-platform support** — `feat(mcp): add Windows support for code search via PowerShell` (commit `82a9052`), `Add support for NetBSD, FreeBSD, and OpenBSD` (commit `a338ff3`); validates that our `setup.sh`, `is-cmm-ext.sh`, statusline, and hook shebangs do not silently assume macOS/Linux-only paths. (2) **Search engine fixes** — `fix(mcp): search_code converts multi-word patterns to regex` (commit `cc7ef34`), `Fix search_graph query= multi-minute latency: two-step FTS5 subquery` (commit `5f19454`), `Fix search_graph name_pattern= performance: regex cache, LIKE pre-filter, cheap count` (commit `dd0ce49`); user-facing query behavior changed — any agent prose, rule, or hook nudge that documents the old `search_code` literal-pattern shape or `search_graph` long-latency caveats may need refresh. (3) **Trace/list correctness** — `fix(mcp): trace_path falls back to qualified_name lookup` (commit `9818730`), `fix(mcp): list_projects no longer hides tmp-prefixed projects` (commit `eb0627e`); both affect QA workflows in `/tmp/`-rooted scratch projects, which are exactly the install-probe pattern Phase 54/55 used. (4) **Storage/extraction features** — `feat(store): expose mmap_size via CBM_SQLITE_MMAP_SIZE env` (commit `093707c`), `feat(store): use PASSIVE checkpoint to avoid file-shrink under concurrent readers` (commit `2215356`), `feat(extract): C# field/property + C# 12 primary-constructor support` (commit `beef06e`), `feat(lsp): TypeScript / JavaScript / JSX / TSX hybrid LSP resolver` (commit `d1143fb`); evaluate whether our 155-language ext list (Phase 51) or any `cmm-rules.md` guidance needs to acknowledge the new resolvers. (5) **Security/scanner fixes** — `fix(security): block " < > in cbm_validate_shell_arg` (commit `eca433b`), `fix(security): close open scanner alerts` (commit `4fdcdd4`), `fix(security): widen release audit to all files in binaries/` (commit `3305c1f`); confirm no transitive impact on our `hooks/lib/` validation helpers. (6) **Release infrastructure** — `feat(release): auto-publish npm and PyPI wrappers` (commit `4cdc2dc`), `fix(release): atomic publish — un-draft GH release only after registries succeed` (commit `6aab9d5`), `feat: add Kiro CLI support` (#96, commit `404b5f8`), `feat: add persistent artifact storage for team sharing` (commit `8babe67`); informational — do we want our README/setup-guide.md to mention npm/PyPI install paths now available upstream? (7) **UI** — `feat(ui): satellite galaxy radius spacing + cross-galaxy edge rendering` (commit `7290c1f`), `Add multi-galaxy UI layout and cross-repo architecture summary` (commit `b6eefe0`); we don't ship the UI but the statusline / setup prompts may want to acknowledge it.

Scope is the per-project CMM-aware surface only: `is-cmm-ext.sh`, `statusline-cmm.sh`, `rules/cmm-rules.md`, `setup.sh`, agent prose in `agents/vbw-*.md` that names CMM tool semantics, and READMEs. Out of scope: shipping our own copy of CMM, upgrading the user's installed CMM (user-driven), bundling new CMM features behind our hooks (CMM remains an external dependency), VBW upstream sync (Phase 55 ships), and any caveman/AI-framework experiments.

**Deps:** Phase 51 (Promote Context-Mode Hooks to First-Class — established the 155-language extension list and statusline plumbing this audit re-evaluates), Phase 53 (Review Context-Mode Updates for Tool Guidance — established the rule/agent-prose audit pattern this phase reuses), Phase 55 (VBW v1.37.0 sync — direct predecessor; both this and Phase 55 close the "upstream has advanced again" carry-forward identified at branch open).

**Reqs:** none (correctness/maintenance alignment with upstream CMM main).

**Success:**
- `56-RESEARCH.md` produced: per-commit and per-file impact table for every change between tag `v0.6.1` and `upstream/main` HEAD (currently `2215356`) in `/Users/ahby/Sources/codebase-memory-mcp`, classifying each into one of `{affects-our-rules, affects-our-hooks, affects-our-agents, affects-our-setup, affects-our-readme, cmm-internal-no-impact, requires-our-update}` and noting whether the change shifts user-facing CMM tool behavior we document.
- `rules/cmm-rules.md` and any `agents/vbw-*.md` prose that documents `search_code` / `search_graph` / `trace_path` / `list_projects` semantics is updated to reflect the new upstream behavior (multi-word regex auto-conversion, qualified_name fallback, tmp-prefixed visibility, FTS5 perf characteristics). All CMM-specific hook frontmatter preserved verbatim.
- `is-cmm-ext.sh` re-evaluated against the upstream lang specs (commit `7f436b5` "Complete lang specs: add all missing node types across 114 languages" — verify our 155-extension list still matches or document the delta).
- Windows/BSD support audit: confirm `setup.sh`, statusline, and project hooks do not assume macOS/Linux-only paths in ways that silently break on the platforms upstream now supports. At minimum, document any known-incompatible surfaces with a TODO; full Windows/BSD support is out of scope for this phase.
- `CHECKSUMS.sha256` regenerated for any updated agent/rule files; `setup.sh` re-installs cleanly via `--force` on a scratch directory.
- Tests: `tests/test-agent-hook-enforcement.sh` extended with assertions for any new contract keywords introduced by the CMM-rule updates; a `tests/test-phase-56-cmm-sync.sh` regression added if the scope warrants it (mirror the phase-49/52/54/55 bundle-install pattern when applicable).
- README and `codebase-memory-setup-guide.md` reviewed for stale CMM version references; updated to point at the current upstream `v0.6.1+` train (npm/PyPI wrappers if relevant).
- Post-release verification: user upgrades their installed CMM to a build at or near `upstream/main` HEAD, reinstalls per-project setup, and one Plan+Execute+Verify cycle confirms `search_code` multi-word regex / `search_graph` perf fixes / `trace_path` fallback / `list_projects` tmp visibility behave as documented under CMM enforcement.

**Research pre-loaded:** Will be generated by Scout during the planning phase — confirmed inputs are `git log v0.6.1..upstream/main` and `git diff --stat v0.6.1..upstream/main` from `/Users/ahby/Sources/codebase-memory-mcp`. Key upstream commit shortlist captured in this session: `2215356` (PASSIVE checkpoint), `093707c` (mmap_size env), `a338ff3` (BSD support), `82a9052` (Windows code search), `eca433b` (cbm_validate_shell_arg hardening), `cc7ef34` (search_code multi-word regex), `5f19454` (search_graph query perf), `dd0ce49` (search_graph name_pattern perf), `9818730` (trace_path qualified_name fallback), `eb0627e` (list_projects tmp visibility), `beef06e` (C# 12 primary-constructor), `d1143fb` (TS/JS hybrid LSP), `4cdc2dc` (npm/PyPI auto-publish), `8babe67` (team-shared artifact), `404b5f8` (Kiro CLI #96), `7f436b5` (114-lang spec completion).

### Phase 57: Sync context-mode integration to upstream v1.0.122
**Goal:** Bring this project's context-mode integration up to date with upstream `mksglu/context-mode` v1.0.122 (currently at `/Users/ahby/Sources/context-mode`). Our Phase-51 baseline validated against `≤1.0.89`; significant upstream changes have landed since, most notably PR #532 (`feat(hooks): route external MCP tools through PreToolUse`, closes #529) which expanded the canonical PreToolUse/PostToolUse matcher lists and added the wildcard `mcp__` PostToolUse matcher that likely fixes the long-standing #329 "raw mcp__* not captured" gap. Concrete gaps captured in `57-RESEARCH.md`: (1) **Plugin-install form unsupported** — upstream now leads with `/plugin marketplace add mksglu/context-mode` + `/plugin install context-mode@context-mode`, which surfaces tools as `mcp__plugin_context-mode_context-mode__*` rather than `mcp__context-mode__*`; our `track-ctx-calls.sh`, `ctx-execute-enforcer.sh`, and `ctx-execute-cmm-nudge.sh` only match the MCP-server form, so our enforcer/nudge/track hooks silently no-op for plugin-form installs; (2) **Matcher list drift** — upstream's `PRE_TOOL_USE_MATCHERS` adds `mcp__plugin_context-mode_*` entries, and `POST_TOOL_USE_MATCHERS` adds the wildcard `mcp__` matcher; `merge_context_mode_hooks` should heal these on re-run but needs re-verification and `tests/test-phase-51-upstream-hooks.sh` re-baselining; (3) **`ctx-rules.md` documents 6 of 11 MCP tools** — missing `ctx_execute_file`, `ctx_doctor`, `ctx_upgrade`, `ctx_purge`, `ctx_insight`; (4) **Issue #329 status needs re-validation** — upstream 1.0.122 architectural changes (#532, PostToolUse `mcp__` wildcard) look like the fix; confirm and remove the hedged "≤1.0.89" caveat from the Phase-51 CHANGELOG paragraph; (5) **No plugin-aware install mode in `setup.sh`** — needs detection of plugin vs MCP-server form and matcher routing for both. Phase 51 changelog entries explicitly tie our integration to "upstream `extractEvents`" behavior that has now evolved; this phase closes that drift.
**Deps:** Phase 51 (Promote Context-Mode Hooks to First-Class — established `merge_context_mode_hooks`, the dispatcher helper, and the matcher list this phase re-baselines), Phase 32 (ctx_execute Enforcement Hook — establishes the `mcp__context-mode__*` matcher pattern that needs to gain a plugin-form sibling), Phase 46 (Source-Code Search CMM Gate — `ctx-execute-cmm-nudge.sh` is one of the hooks that needs plugin-form matcher coverage).
**Reqs:** none (DX / correctness alignment with upstream context-mode)
**Success:**
- `setup.sh` detects both install forms (MCP-server via `.mcp.json` + plugin via `${CLAUDE_PLUGIN_ROOT}` / `~/.claude/plugins/cache/...`) and routes matcher generation accordingly; explicit `--use-plugin` / `--use-mcp-server` flags supported for unambiguous override
- `hooks/project/track-ctx-calls.sh`, `hooks/project/ctx-execute-enforcer.sh`, and `hooks/project/ctx-execute-cmm-nudge.sh` register matchers for both `mcp__context-mode__*` and `mcp__plugin_context-mode_context-mode__*` so enforcement works regardless of which install path the user followed
- `merge_context_mode_hooks()` in `setup.sh` updated to write the upstream-1.0.122 canonical matcher list (PreToolUse adds plugin-form `mcp__plugin_context-mode_*` entries; PostToolUse adds the wildcard `mcp__` matcher); idempotent on re-run, heals any prior Phase-51 matcher shapes in place
- `tests/test-phase-51-upstream-hooks.sh` re-baselined against the new canonical matcher list; new `tests/test-phase-57-plugin-install.sh` covers plugin-form detection, plugin-form matcher registration, and parallel enforcement coverage following the phase-46/47/51 bundle-install pattern
- `.claude/rules/ctx-rules.md` updated to document all 11 upstream MCP tools (sandbox: `ctx_batch_execute`, `ctx_execute`, `ctx_execute_file`, `ctx_index`, `ctx_search`, `ctx_fetch_and_index`; meta: `ctx_stats`, `ctx_doctor`, `ctx_upgrade`, `ctx_purge`, `ctx_insight`) with retrieval-protocol guidance and clear guardrails on `ctx_purge` (destructive)
- Issue #329 re-validated against upstream 1.0.122: confirm raw `mcp__*` tool outputs (jira/grafana/sentry/halo-class servers) are now captured in the FTS5 DB; if confirmed, the Phase-51 CHANGELOG paragraph is updated to remove the "≤1.0.89" caveat and note 1.0.122 as the fix baseline
- `CHECKSUMS.sha256` regenerated for any updated rule/hook files; `setup.sh` re-installs cleanly via `--force` on a scratch directory under both install paradigms
- README and `codebase-memory-setup-guide.md` reviewed for stale references to the MCP-only install; updated to lead with the `/plugin` install (matching upstream's recommended path) while preserving the MCP-server install as an alternative
- Post-release verification: fresh install under both paradigms (1) `/plugin install context-mode@context-mode` and (2) `claude mcp add context-mode -- npx -y context-mode`; in each, run one Plan+Execute cycle that exercises `ctx_execute` / `ctx_search` / `ctx_index` calls and confirm our statusline call counter, ctx-execute-enforcer block messages, and PostToolUse capture all fire as expected

**Out of scope:** bundling our own copy of upstream context-mode (remains an external dependency), upgrading the user's installed context-mode build (user-driven via `/plugin install` or `npm i -g context-mode`), migrating this project's own internal dev install to `/plugin` form (orthogonal to what end-users get from setup.sh), VBW/CMM upstream sync (Phases 55/56), and any new `cmm-claude-code-setup`-side hooks beyond what is required to track plugin-form tool calls.

**Research pre-loaded:** `57-RESEARCH.md` — captured directly by the orchestrator during the `/vbw:vibe` discovery turn (not via a separate Scout spawn). Findings include the five gaps above with exact file/line citations (`setup.sh:711`, `build/adapters/claude-code/hooks.d.ts` `PRE_TOOL_USE_MATCHERS`/`POST_TOOL_USE_MATCHERS`, `.claude-plugin/plugin.json` v1.0.122), and a recent upstream commit shortlist: `6818c44` (1.0.122 release), `855e330` (#532 PreToolUse external MCP routing — key change), `f918d29` (#537 Windows DEP0190), `c9c6a14` (#535 universal-rule extractors), `362709c` (snapshot raw-prompt safety-net), `b43268e`/`6be10a4` (universal blocker/role markers), `cd012d5`/`ff29948`/`d56a9fc`/`a5556a0` (#534 pi/lifecycle fixes).

### Phase 58: Prohibit head/tail truncation inside ctx_execute sandbox
**Goal:** Add Anti-patterns section to `ctx-rules.md` prohibiting `head`/`tail` inside `ctx_execute`; inside the sandbox all stdout is captured for FTS5 indexing so truncation discards data before it can be searched.
**Deps:** Phase 57 (Sync context-mode integration to upstream v1.0.122 — established the 11-tool ctx-rules.md this phase extends)
**Reqs:** none
**Success:**
- `ctx-rules.md` (both `rules/ctx-rules.md` source and `.claude/rules/ctx-rules.md` installed) has `### Anti-patterns` section after `### Prefer`
- The section accurately describes why `head`/`tail` inside `ctx_execute` is harmful (discards data before FTS5 indexing)
- The section prescribes programmatic analysis as the correct replacement pattern

### Phase 61: Convert CMM/ctx rules to Claude Code Skills
**Goal:** Refactor `rules/cmm-rules.md` and `rules/ctx-rules.md` from project-instruction files (auto-loaded into the main session via `.claude/rules/*.md`) into proper **Claude Code Skills** so VBW subagents can opt into them via `skills:` frontmatter with progressive disclosure (Anthropic's documented "98% token reduction" architecture — ~30 description tokens per inactive subagent vs the current main-session-only inheritance + exit-2-retry-and-learn pattern).

Concretely:
1. Package `cmm-rules.md` and `ctx-rules.md` as Skills under `.claude/skills/cmm-rules/` and `.claude/skills/ctx-rules/` (with `SKILL.md` body + appropriate frontmatter per [docs.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills)).
2. List `skills: [cmm-rules, ctx-rules]` in each VBW subagent's frontmatter where the rules are materially helpful (dev, lead, scout, qa, debugger — likely all of them; pr-qa-reviewer too).
3. Shrink the SubagentStart hook output from "advisory + nothing" (current minimal-injection state after phase-60 backout) to a ~100-token pointer: "Context-mode/CMM is active in this project. Consult the `cmm-rules` and `ctx-rules` skills before issuing Bash, Read, Grep, or MCP tool calls." The skills then load lazily on first relevant tool consideration.
4. Keep the PreToolUse exit-2 hooks (`ctx-execute-enforcer.sh`, `cmm-nudge.sh`, `cmm-grep-nudge.sh`) as the hard backstop regardless — they enforce correctness independent of whether the skill has been consulted.

**Deps:** Phase 60 (Harden subagent hook envelopes — established the JSON SubagentStart envelope this phase will narrow). The phase-60-injection branch (`feature/phase-60-inject-rules-into-subagents`) is abandoned; the actual landed code (`feature/phase-60-harden-subagent-hook-envelopes`, commits `ac8d4ac`, `4d9fcc7`, `0ff5fac`) is what Phase 61 builds on.

**Reqs:** none (DX / token-efficiency — phase-60 research surfaced this as the architecturally preferred shape per Anthropic skill docs and Issue #23885 which notes `additionalContext` doesn't reach the system prompt anyway).

**Success:**
- `.claude/skills/cmm-rules/SKILL.md` exists with the body of `rules/cmm-rules.md` and valid Skill frontmatter (concise `description:` field for progressive disclosure)
- `.claude/skills/ctx-rules/SKILL.md` exists with the body of `rules/ctx-rules.md` and valid Skill frontmatter
- `setup.sh --project` installs both skills into the target project's `.claude/skills/` (mirror the existing `.claude/rules/` install path)
- All VBW agent definition files in `agents/` declare `skills: [cmm-rules, ctx-rules]` in frontmatter (verify each agent body actually benefits — Scout and Docs may need only one of the two; document the rationale per agent)
- `hooks/global/subagent-ctx-startup.sh` SubagentStart output shrinks to a ~100-token pointer that references the skill names rather than re-stating protocol
- `hooks/project/subagent-cmm-startup.sh` does the same — pointer instead of advisory body
- PreToolUse exit-2 hooks unchanged (still block raw Bash/Read on code, still redirect to ctx_execute / CMM tools)
- `tests/test-phase-61-*.sh` asserts: (a) both skill dirs install correctly via setup.sh, (b) agent frontmatter contains the `skills:` field, (c) SubagentStart pointer is short (under ~150 tokens / ~600 bytes), (d) PreToolUse hooks still exit 2 on the violations they used to
- `tests/test-phase-51-upstream-hooks.sh`, `tests/test-subagent-ctx-startup.sh`, and `tests/test-phase-59-cmm-install-scope.sh` continue to pass — no regression
- README and `codebase-memory-setup-guide.md` reflect that rules now live as skills (with the old `.claude/rules/*.md` files kept as-is for main-session inheritance OR removed — open question for Plan mode)
- `CHECKSUMS.sha256` regenerated for changed files

**Out of scope:** changing the *content* of cmm-rules / ctx-rules (this phase is packaging only — separate phase if the rule text needs revision), creating skills for other rules files (none exist), making subagents discover skills dynamically (use the explicit frontmatter `skills:` list per Anthropic's recommended pattern), removing the PreToolUse exit-2 hooks (they remain as the enforcement backstop), and packaging VBW-plugin agent definitions themselves as skills (out of grain — VBW manages its own agents).

**Research deferred to Plan mode.** Multiple open implementation questions exist (skill frontmatter exact schema, whether to keep or remove the `.claude/rules/*.md` files after migration to skills, per-agent skill inclusion rationale, exact size of the SubagentStart pointer text). Plan mode should spawn Scout to verify the Skill packaging contract against current Claude Code docs and existing skills in the ecosystem (`.claude/skills/` examples in `liverpool_patches`, vbw plugin, context-mode plugin) before Lead writes the implementation plan.

### Phase 62: Restore MCP Tool Grants to Override Agents and Setup Allowlist
**Goal:** Two related defects strip CMM / context-mode MCP access from the very places this tool exists to enforce it. (1) Four CMM agent override files in `agents/` — `vbw-lead`, `vbw-debugger`, `vbw-docs`, `vbw-architect` — declare a `tools:` **allowlist** that omits every `mcp__*` tool, while the same overrides ship CMM-enforcement machinery (PostToolUse hooks on `mcp__codebase-memory-mcp__*`, `skills: [cmm-rules, ctx-rules]`, and Read/Grep CMM nudges). The result is self-contradictory: these agents are nagged to orient via `get_architecture → search_graph → get_code_snippet` but the allowlist makes those tools uncallable, so they silently fall back to grep — the exact failure mode observed downstream (a Lead authoring a grep-only plan in `liverpool_patches`, whose `.claude/agents/vbw-lead.md` is byte-identical to this repo's source and was installed by `setup.sh --project`). This completes the partial remediation from Phase 49/52, which reverted only `vbw-qa` to `disallowedTools: Task` and left the other four allowlist agents unfixed. (2) `setup.sh`'s tool-allowlist writer (the `permissions.allow` merge block, ~lines 2500–2536) emits **only** the legacy `mcp__context-mode__*` names and never the now-canonical plugin prefix `mcp__plugin_context-mode_context-mode__*`, so on plugin-form context-mode installs the written allow entries don't match real tool calls — the same legacy-vs-plugin naming drift the hook matchers already handle (setup.sh ~lines 1340–1376, plugin-form listed first). The fix must follow the project's own established convention: enumerate the stable `mcp__codebase-memory-mcp__*` tools, and list **both** context-mode families (plugin-form first, legacy second), consistent with the hook matchers.
**Deps:** Phase 49 (established the allowlist-vs-denylist agent baseline; this phase finishes the four agents 49/52 left), Phase 51 (promoted context-mode plugin form to canonical — defines the plugin prefix), Phase 23 (agent frontmatter CMM-hook contract that the allowlist contradicts)
**Reqs:** none (correctness / enforcement coverage)
**Success:**
- `agents/vbw-lead.md`, `agents/vbw-debugger.md`, `agents/vbw-docs.md`, and `agents/vbw-architect.md` can actually call CMM + context-mode tools. For the agents that carry a scoped `Task(...)` grant (`vbw-lead` → `Task(vbw-dev)`, `vbw-debugger` → `Task(vbw-debugger)`), keep the allowlist form and add the MCP tool names (a pure `disallowedTools` denylist cannot express a scoped Task grant). For `vbw-docs` / `vbw-architect`, either add the MCP names to the allowlist or convert to a `disallowedTools` denylist — Plan mode decides, matching whichever keeps closest to VBW source shape.
- The MCP grant added to each agent enumerates the stable CMM tools (`mcp__codebase-memory-mcp__get_architecture`, `search_graph`, `get_code_snippet`, `trace_path`, `query_graph`, `search_code`, `index_status`, `index_repository`) and the context-mode tools under **both** prefixes (`mcp__plugin_context-mode_context-mode__*` first, then legacy `mcp__context-mode__*`) for the read/run set (`ctx_execute`, `ctx_execute_file`, `ctx_search`, `ctx_batch_execute`, `ctx_index`, `ctx_fetch_and_index`, `ctx_stats`). Destructive/operator tools (`delete_project`, `ctx_purge`, `ctx_upgrade`, `ctx_doctor`) are deliberately excluded. Verify against the live MCP tool names — note the legacy `settings.json` entry `mcp__codebase-memory-mcp__trace_call_path` is stale; the real tool is `trace_path`.
- `setup.sh`'s `permissions.allow` writer also emits the plugin-form context-mode names (`mcp__plugin_context-mode_context-mode__*`) alongside the existing legacy `mcp__context-mode__*` entries, so allowlisting matches real calls on plugin-form installs.
- A spawned `vbw-lead` (and `vbw-debugger`) can successfully call a CMM tool (e.g., `get_architecture`) instead of receiving "No such tool available" — verified in a real subagent spawn or an equivalent frontmatter assertion test.
- `CHECKSUMS.sha256` regenerated for the changed agent files; `setup.sh --force` re-installs the updated agents cleanly and the project copies in `.claude/agents/` match `agents/` source.
- Test coverage asserts each of the four agents grants the CMM `get_architecture` + `search_graph` tool names in frontmatter, and that the setup.sh allowlist writer emits the plugin-form context-mode prefix.

**Research pre-loaded:** `62-RESEARCH.md` — investigation in the originating session verified the exact frontmatter of all seven override agents (4 allowlist / 3 denylist), the setup.sh allowlist-writer line range and its legacy-only context-mode names, the live MCP server/plugin naming (CMM = global server `codebase-memory-mcp`; context-mode = global plugin `mcp__plugin_context-mode_context-mode__*`, with legacy MCP-server form still default-registered by setup.sh), the stale `trace_call_path` name in settings.json, and byte-identical provenance of the downstream `liverpool_patches` install. Plan mode may proceed without re-spawning broad Scout research; a focused verification of current frontmatter and the exact setup.sh line numbers before editing is sufficient.
