# Changelog

All notable changes to cmm-claude-code-setup are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Versions follow [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- **`hooks/project/ctx-payload-guard.sh` — PreToolUse hook that blocks output truncation *inside* Context Mode payloads.** Measured over 1,798 transcripts (30 days): `ctx_execute` carried a strong anti-pattern (`cmd | head/tail`, stdout redirected to a file) in **24.3%** of its 21,436 shell payloads, and **0.1%** of those were caught by any hook. That near-zero was by construction, not by accident: `ctx-execute-cmm-nudge.sh` was the only `PreToolUse` hook inspecting a ctx payload, its matcher covered `ctx_execute` alone, and its `is_simple_single_statement()` rejects any payload containing `|` — so every truncating payload fell straight through the one gate that could have seen it. Truncation inside `ctx_execute` is strictly worse than in `Bash`, because the discarded bytes were the ones the FTS5 index was going to capture: they are gone, unsearchable, and `intent=` goes inert below the 5 KB search-mode threshold. The guard matches all six ctx tool names (plugin and legacy MCP-server forms), dispatches on the exact `tool_name` from stdin rather than trusting matcher anchoring, and scans only `shell`/absent `language` payloads — `>` is a comparison in the 668 JavaScript, 639 Python and 103 Perl payloads measured. **Only stdout leaving the pipeline is blocked:** the detector reads the file descriptor, so `2> err.log`, `2>/dev/null`, `2>&1`, `3> trace.log` and `>&2` are stream hygiene and always pass, while `> out.log`, `1> out.log`, `&> all.log` and `>> run.txt` block. Also passing: `| tee` (stdout still flows), bare `head file` / `tail -f`, a redirect whose target is read back by a later command, heredoc and `echo`/`printf` file *authoring* (nothing was going to print), and `$(cmd | head -1)` value extraction. Each block prints the payload with the truncation stripped and `intent=` added, so the correct call can be pasted directly; the batch variant names `commands[i]` and offers `queries=` instead. Operator bypass is a **new** marker, `# ctx-truncate-ok` — deliberately not the enforcer's `# ctx-exempt`, which is matched as a bare substring anywhere in a command and would hand agents a master key to that hook's 2,510 blocks. New `tests/test-ctx-payload-guard.sh` (72 assertions). `CHECKSUMS.sha256` regenerated.
- **`hooks/project/ctx-shell-compat.sh` — advisory hook warning that `language="shell"` payloads run `$SHELL`, not bash.** context-mode resolves one `shell` runtime — `$SHELL` when its basename is allowlisted, else bash (`src/runtime.ts` `detectRuntimes()`) — so on a default macOS install every shell payload executes under **zsh**, and there is no `bash` key in the RuntimeMap, so `language="bash"` cannot select bash either (14 measured calls tried; none got it). Agents write bash and get zsh: `${!var}` indirect expansion appears in 141 payloads and **18.6%** of them fail with `zsh: bad substitution`, the highest failure rate of any construct measured, each costing a full retry. The hook names the zsh-safe form for `${!var}` → `${(P)var}`, `mapfile`/`readarray` → `"${(@f)$(cmd)}"`, `declare -n`, `${var^^}` → `${var:u}`, and `read -a` → `read -A`. It **always exits 0**: unlike truncation, a dialect hit can be legitimate (`${!x}` inside a heredoc bound for a remote bash), and a gate naming no usable alternative sends 90–95% of its blocks straight back to raw tools (measured on `cwd-guard`). Scale stated honestly in the hook header — only 0.7% of ctx calls carry any shell-error signature, far smaller than the truncation gap. The unquoted word-split check (`for f in $files`) is included *because* it does not appear in that 0.7%: zsh does not split an unquoted `$var`, so the loop iterates **once** over the whole string, returns a plausible wrong answer, and reports nothing. New `tests/test-ctx-shell-compat.sh` (29 assertions), led by the property that matters most — the hook must never exit non-zero. `CHECKSUMS.sha256` regenerated.
- **`scripts/analyze-enforcement.py` and `scripts/analyze-antipatterns.py`, plus a `make measure` target.** Read-only passes over `~/.config/claude-code/projects/**/*.jsonl` recording enforcement reach/coverage and anti-pattern rates per surface, so the effect of the new gates can be judged against a recorded baseline rather than an impression. The report separates **STRONG** signals (`| head/tail`, stdout-to-file) from **WEAK** ones (`sed -n 'a,bp'`, `awk 'NR<=N'`, `grep -m N`): once `| head` is gated the cheapest evasion is exactly those, and WEAK already stands at 3,147 occurrences in `ctx_execute`, so a fall in STRONG with a rise in WEAK is **migration, not improvement**. Both headers document the measurement's limit: a hook that exits 0 leaves no transcript trace, so these count hooks that *emitted*, and absence of an emission is not proof a hook did not run. `analyze-antipatterns.py --selftest` runs the classifier cases that double as the executable spec for the guard's detector; `tests/test-measure-scripts.sh` pins the count so it cannot drift unnoticed.

### Changed
- **The stale "hooks do not reach inside a subagent" claim is corrected across the rules, skills, README, CONTRIBUTING and two hook headers.** The repo cited Claude Code issue [#34692](https://github.com/anthropics/claude-code/issues/34692) to assert that `PreToolUse`/`PostToolUse` hooks never fire for tool calls made inside a subagent, and that `SubagentStart` `additionalContext` is "empirically not surfaced/actioned". Both are false as measured: **97.2%** of subagent transcripts carry a stack hook emission, hard blocks land on tool calls made inside sidechains (`isSidechain: true`) on every Claude Code version from 2.1.175 to 2.1.260, and Workflow workers are gated too (757 emissions). **One half survives and is kept, scoped to the one gate it applies to:** a Workflow spawn surfaces as a `Workflow` call, not an `Agent` call, so it does not hit `PreToolUse:Agent` and `agent-cmm-gate.sh` is bypassed (163 Workflow calls, 0 gated, against 1,477 Agent calls with 183 gated). The requirement to paste `rules/cmm-agent-preamble.md` into every `agent()` prompt and `.claude/agents/*.md` definition is **unchanged**, but re-justified on adoption rather than reach: 52% of gated subagent transcripts with ≥5 tool calls make zero CMM calls, so the preamble earns its place by getting CMM *used*, not by being the only thing that arrives. Two test assertions that pinned the old wording (`tests/test-cmm-agent-preamble.sh`, `tests/test-phase-63-rule-refresh.sh`) now pin the new wording so the correction cannot silently regress.
- **`rules/ctx-rules.md` gains a fourth canonical anti-pattern: relying on bash-only syntax in a `language="shell"` payload.** Mirrored into `skills/ctx-rules/SKILL.md` and the copy-region of `rules/cmm-agent-preamble.md`, which is the only place guidance provably lands for a Workflow lens agent. It is the same class as the other three — an assumption about the execution surface that fails without looking like it is about the surface.
- **`hooks/global/cmm-grep-nudge.sh` block messages now echo a ready-to-run call and state that Perl is indexed.** The message previously emitted `search_graph(name_pattern="...")` with a literal placeholder even though the search term was already parsed out of the command; it is now substituted. When the blocked target is Perl, the message says so explicitly: Perl is a fully indexed Hybrid LSP language — packages, `@ISA`/`use parent` inheritance with MRO dispatch, Exporter import maps and `bless` self-type inference all resolve. The wording already existed in `rules/cmm-rules.md` but never reached the moment of blocking, and the observed failure mode was an agent concluding from a bare block that CMM cannot search Perl and falling back to `Read`.

### Fixed
- **`cmm-grep-nudge.sh` no longer blocks `git log --oneline | cat` and friends as "code search".** The command-position rule treated a navigation verb appearing after `|` as navigation, but a verb after a pipe is a **sink consuming upstream output** — `git log | cat`, `git diff --stat | cat`, `dig | cat` and `ls | cat` all blocked for that wrong reason. Pipe sinks are now neutralised before the scan. Fixed as a class rather than by exempting the three commands that were noticed.
- **`ctx-execute-enforcer.sh` no longer teaches the workaround it exists to prevent.** The enforcer echoed the blocked command **verbatim** into its suggested replacement, so `Bash("orb list 2>&1 | head -20")` was answered with `ctx_execute(code="orb list 2>&1 | head -20")` — pipe preserved. Of 2,510 enforcer blocks, 1,501 escalated into a `ctx_*` call and **252 carried the identical anti-pattern through**. The compound branch now strips the truncation from its suggested `code=` and appends `intent=`; without this, the new payload guard would produce two blocks for one intent.
- **The `.cgi` extension gap, and a hook cache that could never see a fix to it.** `.cgi` is in neither the hook's inline code-file list nor CMM's own source: both pick it up **only** from `extra_extensions` in a repo-root `.codebase-memory.json`, so the two agree and a repo without that file fails open consistently — safe, but silently lossy, since the code exists and CMM is blind to it. `setup.sh` now reports source extensions present in the repo but absent from both lists so the config can be written deliberately. Separately, `cmm-grep-nudge.sh`'s extension cache was written once to `/tmp` and never invalidated, so adding `.cgi` to the config had no effect until the cache was manually cleared; the cache key now includes the config's mtime.
- **A registration bug that duplicated `ctx-payload-guard` on every re-install.** `merge_settings_json()` dedups on hook command **basename per matcher entry**, so pairing two hooks inside one entry re-appended the first on each run. Each ctx hook now gets its own entry, with a comment recording why. Verified on a scratch repo: a clean install registers each hook exactly once and stays idempotent across a forced re-run.
- **Nine assertions in `tests/test-phase-66-install-scope.sh` were flapping on a latent SIGPIPE race.** They piped a captured function body into `grep -q` under `set -o pipefail`; `grep -q` exits at the first match and the upstream `echo` takes `SIGPIPE`, so the pipeline returned 141 and the assertion failed — but only once the body crossed the 64 KB pipe buffer, which this branch's additions did (68,097 bytes). Latent since the assertions were written. Rewritten as here-strings; 21/21 stable across five consecutive runs.
- **The Bash enforcer no longer wedges a session when the context-mode MCP server is not actually running.** The Context Mode sentinel `/tmp/context-mode-ready-<hash>` was gated on **existence only**, and `cmm-session-start.sh` writes it from `detect_context_mode`'s on-disk check — which proves the plugin's `installPath` is a directory, not that the MCP server registered. On 2026-08-05 Claude Code re-extracted the plugin cache 0.4s before a session started (its own `plugins/.last_inuse_sweep` fired at the same instant; `node_modules` finished repopulating 15 minutes later). `installPath` existed throughout, so `detect_context_mode` returned installed, the sentinel was written, and `ctx-execute-enforcer.sh` armed — while `ToolSearch` for every `mcp__plugin_context-mode_context-mode__ctx_*` name returned *"No matching deferred tools found"*. The result was 24 minutes of every Bash call blocked and redirected to `ctx_execute`, a tool that did not exist in that session, with no escape hatch. The sentinel now carries a **verdict** rather than merely existing: `cmm-session-start.sh` still writes `ready` (optimistic, on-disk, and enough to open `session-gate.sh`, which checks existence only — so the PR #66 deadlock fix is unaffected), while `context-mode-sentinel-writer.sh` writes `live` — it is PostToolUse on a real `ctx_*` call, so reaching it means the server answered. `ctx-execute-enforcer.sh` arms only on `live` **and** only while that file is fresh (`CTX_ENFORCER_TTL_MIN`, default 30 min); since every `ctx_*` call rewrites it, a server that dies mid-session goes stale and enforcement lifts on its own instead of wedging until restart. Trade-off, stated plainly: enforcement does not arm until the first successful `ctx_*` call of a session — which is the intended rule, the same one `hooks/lib/context-mode-detect.sh` already documents: a hook must not mandate a tool it has never seen work. Four regression assertions in `tests/test-ctx-execute-enforcer.sh` cover unconfirmed `ready`, an empty sentinel, a stale `live`, and fresh `live` as the positive control (76 assertions total, all passing). `CHECKSUMS.sha256` regenerated.
- **`tests/test-agent-hook-enforcement.sh` was reporting 89 passed / 27 failed; now 107 / 0.** None of the 27 were caused by the liveness change above — all predate it — but the suite could not certify that change while it was red, so it is fixed here. Three distinct causes. **(1) The fake project never received `hooks/lib/`.** Both `ctx-execute-enforcer.sh` and `webfetch-nudge.sh` resolve `context-mode-detect.sh` via `<dirname>/lib` then `<dirname>/../lib` and, finding neither, `exit 0` by design — *"partial install, fail open rather than enforce blindly"*. The test copied the hooks but not the library, so 16 enforcement assertions were driving a hook that had disarmed itself before reading their input: they failed for a reason unrelated to what they tested, and would have kept failing however the enforcer behaved. The library is now installed into both fake projects, and the pre-seeded `/tmp/ctx-enforcer-<hash>` cache keeps the verdict host-independent. **(2) The sentinel was seeded with a bare `touch`.** An empty file is not a liveness verdict, so under the new rules it correctly fails open — latent until now, and it would have turned into a confusing false failure the moment cause (1) was fixed. Now seeded `live`. **(3) One assertion tested a defect as if it were a feature:** it required `.claude/context-mode.db` alone to activate enforcement, which is exactly the permanent-latch behaviour `hooks/lib/context-mode-detect.sh` deliberately removed — a session DB survives uninstalling the plugin, so every blocking hook kept firing at `ctx_*` tools that no longer existed. The assertion is inverted to require fail-open, matching the shipped design. Separately, nine assertions greping `agents/*.md` for VBW **base** body content (`skill_no_activation`, `pre_existing_issues`, the v1.37.0 `already_fixed` prose) are **deleted, not skipped**: Phase 49 moved that content into the upstream VBW base, leaving `agents/*.md` a delta, and `tests/test-phase-49-agent-sync.sh` asserts the exact opposite — that those keywords are *absent* from the same files — and passes. Two suites cannot both be right about one file; merged-output coverage belongs to `tests/test-phase-66-generate.sh`, which exercises the generator that performs the merge. Full suite diffed against `HEAD` before and after: the 27 failures are gone and no other suite changed. `CHECKSUMS.sha256` regenerated.

## [1.10.0] — 2026-05-30

### Added
- **`hooks/project/cwd-guard.sh` — PreToolUse:Bash hook preventing persistent shell cwd drift in monorepos (PR #69).** The Bash tool keeps one persistent shell whose working directory survives between calls, so a standalone `cd <subdir>` parks every later call in that subdir. In a git-submodule monorepo this is corrosive: once the shell sits inside a submodule, `git rev-parse --show-toplevel` resolves to the *submodule* root, every CMM/Context-Mode hook computes a different `PROJECT_HASH`, the `/tmp/cmm-session-ready-<hash>` and `/tmp/context-mode-ready-<hash>` sentinels stop matching, and the session gate + enforcer wrongly report "not indexed / not initialized". Drift cannot be detected after the fact (the hook payload's `cwd` is always the session root), only **prevented**. The guard blocks any command whose top-level (non-subshell) effect is a persistent `cd`/`pushd`/`popd` away from the project root, while allowing absolute paths, `git -C <subdir>`, subshell `( cd x && … )`, re-anchoring `cd <root>` / `cd .`, env-assignment-prefixed and option-flag-bearing `cd` forms (parsed correctly), backgrounded `cd … &` (non-persistent), and a `# cwd-exempt` operator bypass; it fails open when `python3` or the project root cannot be resolved. Root detection reuses the shared `hooks/lib/project-root.sh` so the guard anchors to the exact root the sentinel hash is derived from. Registered as `PreToolUse:Bash` in `rules/project-settings-example.json` (installed by setup.sh's wildcard `hooks/project/*.sh` copy loop). New `tests/test-cwd-guard.sh` (22 assertions). Adapted and generalized from a hook drafted downstream in `liverpool_patches`. `CHECKSUMS.sha256` regenerated.

### Fixed
- **Plugin-form context-mode tools no longer deadlock the session gate (PR #66).** `hooks/project/session-gate.sh` recognized only the legacy MCP-server tool form (`mcp__context-mode__*`) and the bare `ctx_*` names — never the plugin-install form (`mcp__plugin_context-mode_context-mode__*`) that `/plugin install context-mode@context-mode` produces. On a fresh plugin-form project the plugin-form ctx tools fell through to the Context Mode sentinel check and were blocked with `exit 2`; the block message instructed the agent to run `ctx_stats`/`ctx_execute` — the very tools just blocked — and the sentinel is only written by `context-mode-sentinel-writer.sh`, a PostToolUse hook that never fires when the PreToolUse gate blocks the call. The result was a circular deadlock whose only escape was manually `touch`-ing `/tmp/context-mode-ready-<hash>`. Adds the `mcp__plugin_context-mode_context-mode__*` bypass to both the Phase 2 (pre-git-traversal) bypass and the Phase 3 Context Mode allow-list, mirroring the dual-form detection `ctx-execute-enforcer.sh` already gained in Phase 57. Regression `Test 6b` in `tests/test-session-gate-earlyexit.sh`.
- **Large-codebase startup no longer freezes behind the first index (PR #67).** `cmm-session-start.sh` deletes the CMM sentinel every session and prompts the agent to run `index_repository` first; until the sentinel is rewritten, `session-gate.sh` hard-blocked every non-allowlisted tool — `Edit`, `Write`, `WebFetch`, and `Skill` (so `cmm-rules`/`ctx-rules` could not even load). On a large, not-yet-indexed repository the first full index is a multi-minute *blocking* call, so the whole session sat frozen behind it. Adds a fail-open-while-indexing path: `cmm-session-start.sh` writes `/tmp/cmm-indexing-<hash>` at session start; while that marker is present **and** fresh (within a 120-minute TTL), `session-gate.sh` emits an advisory and `exit 0` instead of `exit 2`, so tools stay usable while a background index proceeds; `cmm-sentinel-writer.sh` clears the marker when it writes the ready sentinel (real reindex/confirm only). A marker older than the TTL (crashed session / never-completed index) reverts to the hard block. Tests `11b` (fail-open) and `11c` (TTL safety valve) in `tests/test-session-gate-earlyexit.sh`.
- **Shell syntax checks (`bash -n` / `sh -n`) are exempt from the Bash output enforcer (PR #68).** `hooks/project/ctx-execute-enforcer.sh` had no exemption for parse-only syntax checks (`bash -n`, `sh -n`, `zsh -n`, `dash -n`), which emit nothing on success — so they were needlessly routed through `ctx_execute` (pure friction, nothing to sandbox). Adds a "Shell syntax checks" exempt group covering the bare and `<sh> -n <file>` forms; compound commands that merely *start* with a syntax check (e.g. `bash -n x.sh && echo ok`) remain blocked by the upstream compound-shell detector. `git push` was already exempt (git-write group) — the related friction was a trailing `2>&1` making the command compound, not a missing exemption. Four assertions added to `tests/test-ctx-execute-enforcer.sh`.

## [1.9.0] — 2026-05-29

### Fixed
- **Phase 62: Restored CMM + context-mode MCP tool grants to the four override agents and fixed the `setup.sh` allowlist writer (PR #63).** `agents/vbw-lead.md` and `agents/vbw-debugger.md` `tools:` allowlists now enumerate the full CMM tool set (`get_architecture`, `search_graph`, `get_code_snippet`, `trace_path`, `query_graph`, `search_code`, `index_status`, `index_repository`) plus the context-mode read/run tools under both the plugin form (`mcp__plugin_context-mode_context-mode__*`, listed first) and the legacy MCP-server form (`mcp__context-mode__*`), with their scoped `Task(vbw-dev)` / `Task(vbw-debugger)` grants preserved. Previously these allowlists omitted every `mcp__*` tool, so the agents were nagged by their own CMM-enforcement hooks to orient via tools they could not call and silently fell back to grep (observed downstream in `liverpool_patches`, whose installed agents are byte-identical to this repo's source). `agents/vbw-docs.md` and `agents/vbw-architect.md` are converted to a `disallowedTools: Task` denylist (matching the `vbw-scout`/`vbw-dev`/`vbw-qa` convention), granting MCP access without enumerating the surface. `setup.sh`'s `permissions.allow` writer now emits the plugin-form context-mode entries before the legacy entries (matching the hook-matcher convention) and no longer auto-approves the destructive/operator tools `delete_project`, `ctx_doctor`, or `ctx_upgrade`; CMM and context-mode detection thresholds were adjusted to the resulting tool counts (13 / 14). The stale, non-existent `trace_call_path` name is gone (the real tool is `trace_path`). `CHECKSUMS.sha256` regenerated; new `tests/test-phase-62-mcp-grants.sh` (50 assertions) covers grant forms, the full CMM set, plugin-before-legacy ordering, operator-tool exclusion, and detection thresholds. Source-only — `.claude/` untouched.

## [1.8.0] — 2026-05-28

_Reconstructed from the entries recorded in the changelog for the 1.8.0 cycle. Several phases that also shipped in 1.8.0 (52–56, 58–61) and the 1.3.0–1.7.0 releases were not logged as individual changelog entries at the time and are not back-filled here._

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
- `hooks/global/cmm-orient-nudge.sh` — one-shot-per-session PostToolUse nudge on `mcp__codebase-memory-mcp__search_graph`; names `get_architecture`, `trace_path`, and `query_graph` so agents reach the under-promoted CMM tools after their first graph query. Session-scoped sentinel (`/tmp/cmm-orient-nudged-<PROJECT_HASH>-<SESSION_ID>`), `# cmm-exempt` bypass, fail-open on every path. (Finding C)
- `/tmp/cmm-recent-<PROJECT_HASH>` sentinel (touched by `track-cmm-calls.sh`) now gates the `cmm-nudge.sh` targeted-Read exemption — `offset+limit<=100` reads only pass when a CMM call landed within the last 60s. (Finding B)
- `tests/test-phase-47-bundle-install.sh`, `tests/test-ctx-annotate-nudge.sh`, `tests/test-cmm-orient-nudge.sh`; `tests/test-agent-hook-overrides.sh` and `tests/test-agent-hook-enforcement.sh` extended with presence/absence assertions for the new hooks.

### Changed
- `hooks/project/ctx-execute-enforcer.sh` — tightened the Bash exemption list: removed the unbounded `git log|diff|show` catch-all (keep `--stat`/`--oneline`/`--name-only` bounded forms) and dropped `echo`/`printf` from the navigation group. Every exempt arm now calls `track-hook-blocks.sh` with a per-group label (`git-write`, `git-bounded-read`, `filesystem`, `navigation`, `short-reads`, `remote`, `vbw-planning`, `version`) for observability. (Finding A)
- `rules/cmm-rules.md` rewritten around a six-row question-to-tool decision table naming `get_architecture`, `search_graph`, `get_code_snippet`, `trace_path`, `query_graph`, and `search_code`; `hooks/project/cmm-session-start.sh` agent-prompt heredoc mirrors the same mapping. (Finding C)
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
