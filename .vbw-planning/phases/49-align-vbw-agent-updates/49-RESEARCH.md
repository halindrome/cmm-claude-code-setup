---
phase: 49
title: Align VBW Agent Updates
type: research
confidence: high
date: 2026-04-20
---

## VBW Release Under Test

- **Version:** v1.35.0 (source: `/Users/ahby/Sources/vibe-better-with-claude-code-vbw/.claude-plugin/plugin.json` line 3)
- **VBW codebase mapping doc:** STRUCTURE.md records "VERSION: Single-line version string (v1.20.1)" — the installed plugin.json at v1.35.0 is the authoritative version; the codebase map is stale.
- **Agents count in VBW source:** 6 agents under `agents/` (same names as this repo tracks)
- **Hooks count:** 22 hooks across 11 event types (hooks.json, ARCHITECTURE.md)
- **This tool's baseline:** Phase 47 shipped 2026-04-18 (enforcement audit + ctx-annotation). Agents were last synced around phase 35–47.

---

## Agent Inventory

All 6 VBW source agents confirmed present in both repos. No additions or removals since this tool's `agents/` dir was established.

| Agent | VBW source frontmatter key fields | CMM override frontmatter key fields | Delta |
|---|---|---|---|
| vbw-dev | `disallowedTools: Task`, no `tools:` allowlist | same frontmatter + hooks block | MATCH (frontmatter only) |
| vbw-scout | `disallowedTools: Bash, Edit, NotebookEdit, Task`, `permissionMode: plan`, `memory: local` | same + hooks block | MATCH (frontmatter only) |
| vbw-lead | `tools: Read, Glob, Grep, Write, Bash, WebFetch, LSP, Skill, Task(vbw-dev)` | same + hooks block | MATCH (frontmatter only) |
| vbw-qa | `disallowedTools: Task`, `permissionMode: plan`, no `tools:` allowlist | `tools: Read, Grep, Glob, Bash, LSP, Skill` (allowlist added by CMM), `permissionMode: plan` | **MISMATCH: CMM adds a tools allowlist that VBW source does not have** |
| vbw-debugger | `disallowedTools: Task`, no `tools:` allowlist | `tools: Read, Glob, Grep, Write, Edit, Bash, LSP, Task(vbw-debugger), Skill` (allowlist added by CMM) | **MISMATCH: CMM adds tools allowlist + Task(vbw-debugger) self-spawn** |
| vbw-docs | `tools: Read, Grep, Glob, Bash, Write, Edit, LSP, Skill` | same + hooks block | MATCH (frontmatter only) |

**No new agent slugs or subagent_type strings** were added between the version range visible in the local repo. VBW still uses exactly `vbw-dev`, `vbw-scout`, `vbw-lead`, `vbw-qa`, `vbw-debugger`, `vbw-docs`.

---

## Agent Frontmatter Changes

### schema fields — no breaking changes observed

VBW frontmatter fields in use: `name`, `description`, `model`, `memory`, `permissionMode`, `tools`, `disallowedTools`. No new required fields were added.

### Body drift — substantial in vbw-dev and vbw-qa

Comparing `agents/vbw-dev.md` in VBW source vs CMM's `agents/vbw-dev.md` body (after frontmatter):

**VBW source body adds (absent in CMM override):**
1. `<skill_no_activation>` block handling (Stage 1 / Skill Activation section) — present in VBW source at line 17–18 of `vbw-dev.md`; absent in CMM body (CMM body line 66 jumps straight to "Otherwise (standalone/ad-hoc mode)").
2. DEVN-05 rule change: VBW source (lines 47–50) requires persisting pre-existing failures to `SUMMARY.md frontmatter pre_existing_issues` as JSON objects; CMM body only says "Note in response" (line 109). This is a **behavioral difference** — CMM dev agents will not write the structured frontmatter key.
3. Stage 3 (Produce Summary): VBW source adds `if plan has must_haves, add ac_results per template (pass/fail/partial); omit otherwise` and `Always emit pre_existing_issues: [] in SUMMARY frontmatter when no DEVN-05 issues were found` — both absent from CMM body.
4. `## Tool blocks` section (VBW source lines 147–156): explains `REPLACE WITH:` message handling when PreToolUse blocks Grep. This is load-bearing for the cmm-grep-nudge hook behavior. CMM body lacks this section — dev agents will not know to follow the replacement instruction.
5. `## Blocked Task Self-Start` section: present in both, but VBW source wording has been updated.

**CMM override body adds (not in VBW source):**
- `## Context Mode Web Fetch` block (lines 73–83) — intentional CMM extension, correct to keep.

**Comparing `agents/vbw-qa.md` body:**

VBW source QA body adds (absent in CMM override):
1. `<skill_no_activation>` handling in Skill Activation — present in VBW source line 17; absent in CMM.
2. `## Debug Session QA Mode` entire section — present in VBW source (lines 41–56). CMM body lacks this mode entirely.
3. Deviation Handling — VBW source has substantially expanded rules including: multi-item deviation line parsing, "plans with no declared deviations" handling, known-issues block handling during remediation, and `pre_existing_issues` array requirement in `qa_verdict` payload. CMM body has a significantly older/shorter version.
4. `## Remediation Round Verification Scope` — present in VBW source (lines 79–86); absent from CMM body.
5. `write-verification.sh` persistence requirement (NON-NEGOTIABLE block) — present in VBW source; CMM body lacks this and incorrectly states QA can write VERIFICATION.md directly.
6. `plans_verified` and `plan_ref` requirements in `## Communication` section — present in VBW source as NON-NEGOTIABLE; absent from CMM body.
7. `## Pre-Existing Failure Handling` standalone section — present in VBW source; absent from CMM body.

**Other agents (scout, lead, debugger, docs):** Body drift is minor but present. VBW source adds `<skill_no_activation>` handling to all agents; CMM bodies lack it.

---

## New/Changed Lifecycle Events

No new hook event types observed between phase 35–47 and current v1.35.0. The 11 event types remain: PreToolUse, PostToolUse, PostToolUseFailure, UserPromptSubmit, SessionStart, SubagentStart, SubagentStop, PreCompact, PostCompact, Notification.

The `hooks:` frontmatter block in CMM agent overrides uses `PreToolUse` and `PostToolUse` — these remain the correct hook event names.

**Confirmed working in VBW v1.35.0:** `SubagentStart` via `subagent-cmm-startup.sh` (installed at `.claude/hooks/subagent-cmm-startup.sh` in this repo). No changes to SubagentStart or SubagentStop event handling.

---

## Orchestration Changes

**skill_no_activation block:** VBW now passes `<skill_no_activation>` in subagent prompts as an explicit signal that the orchestrator decided no installed skills apply. All 6 agents in VBW source handle this. CMM agent body overrides do NOT handle it — they have the older two-branch Skill Activation section (with_activation / otherwise). This means CMM-overridden agents may redundantly scan `<available_skills>` in cases where VBW orchestrator already determined it's unnecessary.

**Pre-existing issues structured output:** VBW v1.35.0 introduced (or formalized) the `pre_existing_issues` JSON array in both `SUMMARY.md` frontmatter (dev agent) and `qa_verdict` payload (QA agent). CMM overrides carry the older prose-only variant. This is a data schema divergence that could affect orchestrator parsing.

**write-verification.sh persistence gate:** QA agent now uses `write-verification.sh` as a hard gate — VERIFICATION.md must not be written directly. CMM's QA body override doesn't include this constraint, meaning CMM QA agents may try to Write VERIFICATION.md directly, which (per VBW source) gets rejected.

**`plan_ref` + `plans_verified` validation:** `write-verification.sh` validates that every check has a `plan_ref` and every plan ID has at least one check. CMM's QA body doesn't mention these requirements, so CMM QA agents won't populate them, causing `write-verification.sh` to reject the payload (exit 1).

---

## Breaking Changes For This Tool

1. **vbw-dev body: DEVN-05 now requires structured frontmatter** — `pre_existing_issues` JSON array in SUMMARY.md. CMM body says "note in response only." Dev executions produce SUMMARYs that miss this key. Risk: orchestrator may fail to parse pre-existing issues across phases. (`agents/vbw-dev.md` body, compare lines 47–50 of VBW source vs lines 101–110 of CMM body)

2. **vbw-dev body: missing `## Tool blocks` section** — When `cmm-grep-nudge.sh` fires and emits `REPLACE WITH:` instructions, CMM dev agents have no protocol for following those instructions. This was likely the intended behavior from phase 35/46 but is not reflected in the agent body. (`agents/vbw-dev.md`, VBW source lines 147–156 absent from CMM)

3. **vbw-qa body: missing `write-verification.sh` NON-NEGOTIABLE gate** — CMM QA agents will attempt to write VERIFICATION.md directly via Write tool. VBW orchestrator rejects this. Phase-scoped QA passes will fail. (`agents/vbw-qa.md` body)

4. **vbw-qa body: missing `plan_ref` + `plans_verified` requirements** — `write-verification.sh` validates these fields and rejects payloads missing them. CMM QA body doesn't tell agents to populate them. (`agents/vbw-qa.md` body, VBW source lines 119–121)

5. **vbw-qa body: missing Debug Session QA Mode** — CMM QA can't operate in debug-session mode. If lead spawns QA with a debug-session description, CMM QA will attempt phase-scoped behavior incorrectly. (`agents/vbw-qa.md` body, VBW source lines 41–56)

6. **All agents: missing `<skill_no_activation>` handling** — CMM overrides don't acknowledge this signal from the orchestrator, so agents may run unnecessary `<available_skills>` scans. Low-severity but causes wasted context and unexpected behavior.

7. **vbw-qa frontmatter: CMM adds `tools: Read, Grep, Glob, Bash, LSP, Skill`** — VBW source uses `disallowedTools: Task` only (no allowlist). CMM's allowlist is more restrictive than intended. If VBW adds a new capability to QA that goes through a new tool name, CMM's allowlist will silently block it. Should convert back to `disallowedTools: Task` to match VBW source. (`agents/vbw-qa.md` frontmatter)

8. **vbw-debugger frontmatter: CMM adds `tools:` allowlist + `Task(vbw-debugger)` self-spawn** — VBW source only has `disallowedTools: Task`. CMM's Task(vbw-debugger) self-spawn capability is not in VBW source. This may be intentional CMM extension, but needs explicit documentation in the override comment block. (`agents/vbw-debugger.md` frontmatter)

---

## Caveman Integration Investigation

### What Is Caveman

Caveman is a **response-verbosity compression framework** adapted from [github.com/JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) by Julius Brussee (MIT license). It is not an MCP server, not a CLI tool, and not a hook. It is a set of prose rules and a prompt-injection pattern.

Three reference files define the rules:
- `references/caveman-language.md` — response language levels (lite/full/ultra), caveman syntax patterns
- `references/caveman-commit.md` — terse Conventional Commits format rules
- `references/caveman-review.md` — terse `L<line>: severity problem. fix.` code review format

Three config flags in `config.json` control it (`defaults.json` lines 50–52):
- `caveman_style`: `none` | `lite` | `full` | `ultra` | `auto` (default: `none`)
- `caveman_commit`: boolean (default: `false`)
- `caveman_review`: boolean (default: `false`)

Introduced in VBW v1.35.0 (CHANGELOG.md line 10, PR #456).

**Token reduction mechanism:** Shorter agent responses = fewer output tokens per turn. Code blocks, URLs, paths, and error text are preserved exactly; only prose structure is compressed.

### VBW Integration

Caveman is a **pure prompt-injection pattern** activated at context compilation time:

1. **`scripts/compile-context.sh`** — `emit_caveman_directive()` (lines 298–322) injects a `### Caveman Language ({level})` block into the compiled context preamble. Reads `caveman_style` from `config.json`; when `auto`, calls `resolve_caveman_level()` which reads `.context-usage` (context window % used) and maps: <50% → none, 50–69% → lite, 70–84% → full, ≥85% → ultra.

2. **`scripts/compaction-instructions.sh`** (lines 213–224) — Re-injects a compaction-priority directive after context compaction. `auto` at compaction time defaults to `full` (context already high).

3. **`scripts/session-start.sh`** (lines 940–954, 1079–1098) — Reads caveman config values and includes them in the SessionStart system prompt block shown to lead/orchestrator.

4. **No hook, no MCP tool, no PreToolUse block.** Activation is purely via compiled context. No `mcp__caveman__*` tool calls exist. Agents follow the injected directive passively — there is no enforcement mechanism.

5. **`/vbw:config caveman_style auto`** sets `auto` mode via the config command. `auto` is the recommended setting for token pressure relief.

### Overlap With CMM + Context Mode

Caveman and CMM+context-mode address **different token budget problems** and are orthogonal:

| Mechanism | What it reduces | How |
|---|---|---|
| CMM graph tools | Input tokens re-read per turn | Routes code navigation to graph index instead of full file reads |
| context-mode `ctx_execute` | Input tokens re-fetched per turn | Indexes command output; retrieves from cache instead of re-running |
| Caveman | Output tokens per turn | Instructs agents to write shorter prose responses |

There is **no functional overlap**. CMM hooks (`cmm-nudge.sh`, `cmm-grep-nudge.sh`) block raw Bash/Grep to reduce input token cost. Caveman reduces output token cost. They can coexist without conflict.

**Key distinction for this repo:** This repo's statusline already tracks per-session call/block counters (input-side). Caveman would add output-side compression. The two metrics remain separate.

One nuance: `auto` mode reads `.context-usage`, which VBW writes via its own statusline/context-tracking pipeline. This repo does not currently write `.context-usage` in VBW's format. If caveman `auto` mode were adopted, a setup step would be needed to ensure `.context-usage` is populated (or the feature would silently stay at `none`).

### Recommended Approach For This Tool

**Caveman: out of scope for phase 48. Reason: feature-additive, not a breaking sync requirement.**

Phase 48 is a sync/alignment pass targeting behavioral regressions in agent bodies and frontmatter. Caveman is a new opt-in feature introduced in v1.35.0 with no default-on behavior (`caveman_style: none`). There is no breakage to fix.

If adopted in a future phase, the integration point would be:
- Add `caveman_style`, `caveman_commit`, `caveman_review` to `config/defaults.json` (or equivalent config schema)
- Copy `references/caveman-language.md`, `references/caveman-commit.md`, `references/caveman-review.md` into this repo's `rules/` or a new `references/` dir
- Add caveman config injection to whatever session-start or context-compilation script this repo uses
- Verify `.context-usage` is written in VBW-compatible format before enabling `auto` mode

No new hook, no new MCP server, no changes to `setup.sh` install steps beyond copying reference files.

---

## Recommended Phase 48 Scope

**Priority 1 — breaking (must fix before next VBW-managed QA run):**

- [ ] **Sync vbw-qa.md body** to VBW v1.35.0 source, preserving CMM hooks frontmatter. Must add: `write-verification.sh` persistence gate, `plan_ref`+`plans_verified` requirements, `Debug Session QA Mode` section, remediation round scope, pre-existing failure handling, expanded deviation rules. Complexity: medium (body rewrite + verification that CMM hooks block still correct).

- [ ] **Sync vbw-dev.md body** to VBW v1.35.0 source, preserving CMM frontmatter + Context Mode Web Fetch extension. Must add: `<skill_no_activation>` handling, structured DEVN-05 `pre_existing_issues` frontmatter requirement, `ac_results` in Stage 3, `## Tool blocks` `REPLACE WITH:` protocol. Complexity: medium (targeted body additions, not full rewrite).

**Priority 2 — behavioral gap (fix before new phases using QA):**

- [ ] **Fix vbw-qa.md frontmatter: revert `tools:` allowlist to `disallowedTools: Task`** to match VBW source and avoid silent capability blocks as VBW evolves. Complexity: trivial.

- [ ] **Add `<skill_no_activation>` handling to all 6 agent bodies** — copy the two-line block from VBW source Skill Activation section. Affects: vbw-scout, vbw-lead, vbw-qa, vbw-dev, vbw-debugger, vbw-docs. Complexity: low (minor text patch per file).

**Priority 3 — documentation / maintenance hygiene:**

- [ ] **Document `Task(vbw-debugger)` in vbw-debugger.md override comment** — the override comment block says "MAINTENANCE: compare against plugin source" but doesn't call out that `Task(vbw-debugger)` is an intentional CMM addition not present in VBW source. Complexity: trivial.

- [ ] **Update `agents/` MAINTENANCE comment plugin path** — all CMM override comments reference `~/.config/claude-code/plugins/cache/vbw-marketplace/vbw/*/agents/` as comparison path. Confirm this path resolves correctly on this machine (actual path confirmed at `/Users/ahby/Sources/vibe-better-with-claude-code-vbw/.claude/agents/`) — update if needed. Complexity: trivial.

- [ ] **Add phase 48 sync note to CHANGELOG.md** after implementation. Complexity: trivial.

**Out of scope:** No new VBW agent types, no renamed agent slugs, no changes to hook event names, no new scripts that CMM hooks interact with. The 22-hook / 11-event-type model is unchanged at v1.35.0.

**Caveman: out of scope for phase 48.** Feature-additive, default-off (`caveman_style: none`), no behavioral regressions if absent. If adopted in a future phase: copy 3 reference `.md` files, add 3 config keys, add context-compilation injection, verify `.context-usage` is written in VBW-compatible format for `auto` mode. No MCP server or hook changes required.
