# TODO — Workflow-based replacement for VBW Agent-Team tiers

**Status:** proposed / not started
**Created:** 2026-06-05
**Origin:** investigation session in sibling repo `/Users/ahby/Sources/cvx_6033` (Corvex monorepo)
**Owner repo for the fix:** this one (`cmm-claude-code-setup`) — it deploys the agents/hooks/rules that the VBW plugin consumes.

---

## Background / why

Agent Teams (`TeamCreate` / `TaskCreate` teammates) are **broken in this environment and will never be enabled** (`prefer_teams: never` in every `.vbw-planning/config.json`; Agent Teams toggle off). Consequently every VBW command that fans out via teams silently degrades to **solo**:

- `/vbw:map` duo (200–1000 files) and quad (1000+ files) both collapse to solo — the orchestrator maps inline, **zero Scouts spawned**.
- `/vbw:vibe` paths that would use teams likewise serialize or degrade.

So on any real-sized repo, the parallel Scout fan-out that the VBW design intends **never happens** here.

## The discovery (proof it works)

On 2026-06-05 we reproduced quad-mode map on the Corvex monorepo (4,614 source files) using the **Opus 4.8 `Workflow` tool** instead of Agent Teams:

- A workflow script ran `parallel(DOMAINS.map(d => () => agent(prompt, { agentType: 'vbw:vbw-scout' })))` — 4 domain Scouts at once.
- `agentType: 'vbw:vbw-scout'` resolves from the **same registry as the Agent tool**, so it spawns the *real plugin Scout* — no team machinery involved.
- Result: all 7 `.vbw-planning/codebase/*.md` docs written; 4 agents; ~300k subagent tokens; ~3.2 min wall-clock; clean isolated transcripts under `<session>/subagents/workflows/<runId>/agent-*.jsonl`.
- **Critically: the project `.claude/settings.json` enforcement floor (SubagentStart CMM injection + PreToolUse cmm/grep gates) fired for all 4 workflow agents** — same enforcement as Task-spawned subagents. (See companion doc `TODO-cmm-bash-exploration-gap.md` for the CMM-adoption nuance.)

Conclusion: **Workflow is a drop-in substitute for the broken team tiers** — same plugin Scout, same enforcement, deterministic fan-out, with the bonus of cleanly isolated per-agent transcripts.

## Goal

Provide a reusable, low-friction way to run VBW's parallel Scout/agent fan-out via the Workflow tool when teams are disabled, so map (and ideally vibe) get real parallelism here.

## Proposed approach (pick one or stage them)

1. **Ship a named workflow template** (lowest risk, recommended first step).
   Add a workflow script the deploy payload installs into a target repo, e.g. `.claude/workflows/vbw-map.js`, that reproduces quad-mode: 4 `vbw:vbw-scout` agents over the 4 map domains writing the 7 docs, then returns structured findings for the orchestrator to synthesize INDEX/PATTERNS/META. A user/agent runs `Workflow({ name: 'vbw-map' })` (or `Workflow({ scriptPath })`).
   - Reference implementation already exists from the 2026-06-05 run — see the script saved at (cvx session) `…/e9653940-…/workflows/scripts/vbw-map-quad-workflow-*.js`. Port/clean it into this repo under e.g. `workflows/vbw-map.js` and wire `setup.sh` to deploy it.
   - The 4 domains + output paths (must match what `/vbw:map` expects):
     - tech-stack → `STACK.md`, `DEPENDENCIES.md`
     - architecture → `ARCHITECTURE.md`, `STRUCTURE.md`
     - quality → `CONVENTIONS.md`, `TESTING.md`
     - concerns → `CONCERNS.md`
   - Orchestrator still does Step 4–5 synthesis (INDEX.md, PATTERNS.md, META.md) after the workflow returns.

2. **Document the pattern** in `rules/` (or a new `docs/workflow-fanout.md`) so any agent knows: "teams disabled here → use `Workflow` with `agent({ agentType: 'vbw:vbw-scout' })` for parallel fan-out." Add a short trigger note to `rules/cmm-rules.md` or the project settings example.

3. **(Stretch) generalize to vibe.** The same `agent({ agentType })` mechanism can stand in for vibe's Scout/Lead/Dev team spawns. Higher complexity (sequential dependencies, per-stage state, summaries) — scope as a follow-up only after map is proven in daily use.

## Files likely to touch (this repo)

- `workflows/vbw-map.js` (new) — the reusable map workflow script (port from the cvx run).
- `setup.sh` — deploy the workflow into target repos' `.claude/workflows/` (or document manual placement).
- `rules/cmm-rules.md` or a new `docs/workflow-fanout.md` — the "use Workflow when teams are off" guidance.
- `CHANGELOG.md`, `VERSION` / `version.txt` — version bump per repo convention.

## Acceptance criteria

- A fresh session in a target repo can run one command to get a real parallel 4-Scout map without enabling Agent Teams.
- The spawned agents are `vbw:vbw-scout` and the project CMM/ctx hooks fire for them (verify via the telemetry below).
- All 7 domain docs + INDEX/PATTERNS/META are produced; `META.md` records `mapping_mechanism: workflow-tool`.
- Pattern is documented so agents choose Workflow over (broken) teams automatically.

## How to verify (telemetry — from the cvx investigation)

- CMM call counter: `~/.cache/codebase-memory-mcp/_call-counts-<md5 of git toplevel>.json` — non-`index_repository` entries (get_architecture/search_graph/etc.) appearing after a run = Scouts navigated via CMM.
- Workflow agent transcripts: `~/.config/claude-code/projects/<encoded-repo>/<session-id>/subagents/workflows/<runId>/agent-*.jsonl` — grep for `tool_use` names and for SubagentStart CMM-injection + `BLOCKED: Use CMM tools` to confirm enforcement fired.
- (`CLAUDE_CONFIG_DIR` here is `~/.config/claude-code`, NOT `~/.claude`.)

## Caveats / open questions

- Workflow requires **explicit user opt-in** each time (the tool refuses otherwise). A named workflow + clear docs keeps that one-step.
- 4 inherited-model (Opus) Scouts over a large repo is real spend (~300k tokens in the test). Consider defaulting the template's agents to Sonnet for routine maps, Opus for deep ones.
- Synthesis stays orchestrator-side (it reads the 7 docs). Keep it out of the workflow (workflow `ctx_execute` can't persist host files; the Scouts' Write tool can, but cross-doc synthesis wants the full set in one place).
