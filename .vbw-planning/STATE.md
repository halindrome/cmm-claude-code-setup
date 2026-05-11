# State

**Project:** cmm-claude-code-setup

## Current Phase
Phase: 9 of 40 (Cmm Index Offer In Setup)
Plans: 0/0
Progress: 0%
Status: ready

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| Non-blocking nudge hook | 2026-03-12 | Softer enforcement reduces false positives on small files |
| Both global + project hooks | 2026-03-12 | Global=soft enforcement, project=hard gate (mirrors jmunch pattern) |
| No statusline script | 2026-03-12 | README example only; statusline stats vary by user setup |
| CMM call counter not token savings | 2026-03-12 | CMM doesn't expose tokens_saved per call |
| Attribution to Shachar Bard | 2026-03-12 | Author of jmunch-claude-code-setup; cited prominently in README |
| ROADMAP phase number gaps are architectural | 2026-05-07 | ROADMAP.md numbering gaps for phases 37–45, 47, 50 are intentional — those phases were archived into shipped milestones (`milestones/`) and their entries remain in `ROADMAP.md` for historical reference. `roadmap_vs_summaries` checks may continue to flag these as missing-phase-dirs; this is accepted state, not actionable drift. |

## Todos
- setup.sh: warn about large codebase indexing; recommend mode:fast for first index; add optional pre-index step during setup (added 2026-03-13)
- cmm-session-start.sh prompt: mention mode:fast for large repos (added 2026-03-13)
- benchmarks/run.sh: add progress reporting (e.g. "[3/30] variant=cmm-cold repo=express task=02 run=1") so users can estimate time remaining (added 2026-03-14)
- Investigate jmunch's updated track-genuine-savings.sh (JDM savings estimation + JSONL history logging) for ideas on token savings tracking; CMM doesn't expose _meta.tokens_saved — plan: submit PR to CMM that adds tokens_saved to tool responses, then adapt our hooks to consume it (added 2026-03-15)
- cmm-session-start.sh: investigate making the SessionStart hook output a hard stop (stopReason / blocking message) so Claude cannot skip index_repository at session start; current design relies on Claude following soft instructions which is non-deterministic — hook output may need to use a format that forces acknowledgement before proceeding (added 2026-03-16)
- ENFORCEMENT GAP: cmm-nudge.sh is too soft — agents bypass by adding offset/limit to Read calls instead of switching to CMM tools; ctx-execute-enforcer allows ls/git/mkdir which covers most agent Bash usage. Need to harden cmm-nudge to block targeted reads on large code files too, or make it a hard block requiring CMM keyword evidence. Observed in Phase 38 Dev agents (2026-04-04)
- DEAD RULES: The files installed into .claude/rules/ (allowed-tools.txt, mcp-example.json) are reference docs, not functional rules — Claude Code doesn't parse them as behavioral instructions. The actual behavioral guidance (global-claude-md.md) is excluded from install and requires manual user action. Options: (1) move reference docs to docs/ or examples/ and stop installing them as rules; (2) convert global-claude-md.md content into an actual .claude/rules/ file that gets installed and Claude reads automatically; (3) both. The hooks (cmm-nudge, session-gate, ctx-execute-enforcer) are doing the real enforcement work. (added 2026-04-09)
- New phase idea: investigate project-level agent overrides in .claude/agents/ for Claude's built-in subagent slugs so CMM + context-mode hooks apply there too. Slugs per Claude docs: Explore (read-only codebase search), Plan (research during plan mode), general-purpose (multi-step full-tool), statusline-setup (/statusline), claude-code-guide (docs lookup). Open question: does Claude Code honor a project-level .claude/agents/<slug>.md override for built-in slugs the same way it does for plugin agents, or are built-ins non-overridable? If overridable, replicate the VBW agent override pattern (frontmatter PreToolUse:Read/Grep/Bash hooks); if not, document the gap. (added 2026-04-16)
- DEBUG FINDING: Session `358f31be` in codespace shows 61 raw Bash calls bypassing ctx-execute-enforcer — verify whether this was a subagent context (hook not propagated) or the exemption list (ls/git/mkdir/etc) is too permissive. Audit enforcer's exempted command prefixes against real-session usage. (added 2026-04-17)
- DEBUG FINDING: Session `9f16fc98` in codespace shows 43 Reads vs 2 search_graph + 4 get_code_snippet — cmm-nudge.sh may be too lenient on targeted Reads (offset+limit<=100) when the file is code in an indexed repo. Consider tightening: require a preceding CMM call in the same turn before allowing a targeted Read on indexed code. (added 2026-04-17)
- DEBUG FINDING: Across 6 codespace sessions (1,274 tool-uses), zero calls to `get_architecture`, `query_graph`, or `trace_call_path`. These CMM tools are under-promoted despite being in `.claude/rules/cmm-rules.md`. Consider: (a) stronger orientation rule in session-start output, or (b) a PostToolUse nudge after first `search_graph` suggesting `get_architecture` for unfamiliar areas. (added 2026-04-17)
- Investigate PostToolUse hook on ctx_* tools that injects `additionalContext` instructing Claude to summarize the ctx result in one sentence before the next tool call (and answer directly if sufficient) — may reduce redundant ctx_search/ctx_execute chains. User-suggested pattern: `hookSpecificOutput.additionalContext = "STOP — before your next tool call, state in ONE short sentence what this ctx* result told you. If it already answers the user's question, answer directly instead of running another search. If you can't summarize it, re-read the result above — do not run another ctx* call."` (added 2026-04-18)
- Drift detection: at session startup, compare installed .vbw files (especially agent definitions) against local mods; warn if .vbw upstream has been updated since install (added 2026-04-22) (ref:6f269994)
- [HIGH] MCP tool outputs (jira/grafana/sentry) not captured by context-mode PostToolUse; root cause is upstream extractEvents hardcoded categories, not a Phase 51 gap (added 2026-04-22) (ref:9a6d5248)


## Recent Activity
- 2026-03-31: Picked up todo via /vbw:debug: Context Mode: investigate forcing Bash calls through ctx_execute via a PreToolUse hook
- 2026-04-18: Phase 47 (Enforcement Audit + Context-Mode PostToolUse Annotation) closed. Shipped Finding A (ctx-execute-enforcer exemption tightening: removed bare `git log|diff|show` catch-all + `echo|printf`; added per-group track-hook-blocks counters), Finding B (cmm-nudge targeted-Read exemption now requires `/tmp/cmm-recent-<PROJECT_HASH>` touched within 60s), Finding C (rules/cmm-rules.md rewrite + cmm-session-start prompt + new one-shot `cmm-orient-nudge.sh`), Finding D (new `ctx-annotate-nudge.sh` PostToolUse additionalContext hook replacing `ctx-search-nudge.sh`). Merge date placeholder: <fill-on-merge>. **Follow-up debug pass scheduled two weeks after merge** to quantify impact on the three debug-session signals that motivated the phase: 61 raw Bash calls in session 358f31be, 43 Reads vs 2 search_graph in session 9f16fc98, and 0 calls to get_architecture / query_graph / trace_call_path across 1,274 tool-uses. Expected deltas: raw-Bash count down (Finding A), Read:search_graph ratio improved (Finding B), at least a non-zero count of the three under-promoted CMM tools (Findings C + D).

## Blockers
None

