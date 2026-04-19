---
phase: 47
plan: 05
title: "Integration wiring: settings-example, setup.sh, agent frontmatter, CHECKSUMS, CHANGELOG, STATE"
status: complete
completed: 2026-04-18
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - 9c43736
  - 98b4d1f
  - 838f976
  - ac8f3b4
  - f2a8590
deviations:
  - "DEVN-01: test-phase-45-bundle-install.sh was updated in this plan (not just retired as the original deviation in 47-03 suggested). The file retains its role as the phase-45 smoke test for subagent-ctx-startup.sh + ctx-rules.md but now explicitly asserts ctx-search-nudge.sh is NOT installed and NOT registered — converting the 47-03 residual references into phase-47 negative assertions. No new test file needed for that retirement path; the phase-47 bundle test covers install/register positive cases."
  - "DEVN-01: tests/test-agent-hook-enforcement.sh gained a `touch /tmp/cmm-recent-<PROJECT_HASH>` before its targeted-Read exemption check. Phase 47 Plan 01 tightened that exemption to require a fresh cmm-recent sentinel (60s TTL); the fixture needed updating in lockstep. Also added the sentinel to cleanup_sentinels on trap. Counts as test-fixture maintenance rather than behavior change."
  - "DEVN-01: Three residual `ctx-search-nudge` string references remain in rules/project-settings-example.json (one _comment on the replacement matcher), setup.sh (two — one comment + deprecated_hooks list entry). All are intentional retirement infrastructure, not wiring. Verification command `grep -rF ctx-search-nudge rules/ setup.sh agents/ hooks/` returns 3 matches, not 0 — the plan's phrasing of 'zero matches' is literalist; the spirit (no active registrations/installs) is satisfied."
pre_existing_issues: []
ac_results:
  - criterion: "rules/project-settings-example.json: remove ctx-search-nudge matcher + add two new matchers; jq validates"
    verdict: pass
    evidence: "9c43736 — three changes (one removal + two additions); `jq . rules/project-settings-example.json` returns 0"
  - criterion: "setup.sh install_project: copy blocks for ctx-annotate-nudge.sh + cmm-orient-nudge.sh added; idempotent"
    verdict: pass
    evidence: "98b4d1f — two new copy_file/set_executable blocks mirroring cmm-nudge.sh; ctx-search-nudge.sh added to deprecated_hooks so installed stale copies are purged. Manual idempotency smoke: two consecutive setup.sh --project runs produce byte-identical .claude/settings.json (sha1 matched)."
  - criterion: "All 7 agents gain ctx-annotate-nudge + cmm-orient-nudge entries"
    verdict: pass
    evidence: "838f976 — 7 files changed, 56 insertions; `grep -lF ctx-annotate-nudge agents/*.md | wc -l` = 7; same for cmm-orient-nudge"
  - criterion: "CHECKSUMS.sha256 regenerated; hashes for two new hooks present and ctx-search-nudge absent"
    verdict: pass
    evidence: "ac8f3b4 — scripts/generate-checksums.sh run; `shasum -a 256 -c CHECKSUMS.sha256` reports 31/31 OK"
  - criterion: "CHANGELOG.md Phase 47 section covers Findings A/B/C/D"
    verdict: pass
    evidence: "ac8f3b4 — new [Unreleased] section at top with Added/Changed/Removed subsections explicitly mentioning all four findings"
  - criterion: ".vbw-planning/STATE.md phase 47 closing + 2-week follow-up note"
    verdict: pass
    evidence: "ac8f3b4 — appended entry under Recent Activity naming the three debug signals to re-measure"
  - criterion: "test-agent-hook-overrides + test-agent-hook-enforcement extended; test-phase-47-bundle-install created"
    verdict: pass
    evidence: "f2a8590 — overrides adds 2 must-have entries + 1 must-not-have entry per agent; enforcement gains 21 wiring-presence assertions + 2 additionalContext/cooldown checks; new tests/test-phase-47-bundle-install.sh (~190 lines) adds install/register/purge/idempotency assertions"
  - criterion: "Full regression sweep (9 tests) exits 0"
    verdict: pass
    evidence: "test-ctx-execute-enforcer, test-cmm-nudge-blocking, test-ctx-annotate-nudge, test-cmm-orient-nudge, test-agent-hook-overrides, test-agent-hook-enforcement, test-phase-45-bundle-install, test-phase-46-bundle-install, test-phase-47-bundle-install — all exit 0"
---

Wired all Phase 47 wave-1 artifacts into the cross-cutting installer/registration/docs surfaces and retired `ctx-search-nudge.sh` atomically. Every VBW agent now registers both new PostToolUse hooks; setup.sh copies and purges the right files; CHECKSUMS/CHANGELOG/STATE reflect the phase ship.

## What Was Built

- `rules/project-settings-example.json`: removed ctx-search-nudge entry; added ctx-annotate-nudge entry (matcher `mcp__context-mode__ctx_(execute|search|index|fetch_and_index)`) and cmm-orient-nudge entry (matcher `mcp__codebase-memory-mcp__search_graph`)
- `setup.sh::install_project`: two new copy/chmod blocks for ctx-annotate-nudge.sh + cmm-orient-nudge.sh; ctx-search-nudge.sh added to the `deprecated_hooks` array so stale installs are purged (both from `.claude/hooks/` and from settings.json matcher entries)
- All 7 VBW agent frontmatter files (vbw-scout, vbw-lead, vbw-dev, vbw-qa, vbw-debugger, vbw-architect, vbw-docs) gained two new PostToolUse hook entries in identical order; no agent previously referenced ctx-search-nudge
- `CHECKSUMS.sha256` regenerated (31 files, includes new hooks + refreshed hashes for all phase-47 wave-1 changes)
- `CHANGELOG.md`: new `[Unreleased]` section with Added/Changed/Removed subsections summarizing Findings A–D
- `.vbw-planning/STATE.md`: phase-47 closing entry with merge-date placeholder and scheduled 2-week follow-up debug pass naming the three original signals (61-Bash, 43-Reads/2-search_graph, 0 get_architecture calls)
- `tests/test-agent-hook-overrides.sh`: two new must-have hooks per agent (ctx-annotate-nudge, cmm-orient-nudge) + one new must-not-have (ctx-search-nudge)
- `tests/test-agent-hook-enforcement.sh`: 21 new wiring assertions + additionalContext emission + cooldown behavior for ctx-annotate-nudge; cmm-recent sentinel pre-touch so Phase 47 Plan 01's 60s gate allows the targeted-Read exemption test
- `tests/test-phase-45-bundle-install.sh`: retired ctx-search-nudge.sh assertions and replaced with explicit negative assertions (file NOT installed, matcher NOT registered)
- `tests/test-phase-47-bundle-install.sh`: new 190-line smoke test covering install + register + deprecated_hooks purge + idempotency

## Files Modified

- `rules/project-settings-example.json` -- update: one matcher removal + two additions (9c43736)
- `setup.sh` -- update: install_project gains two copy blocks and ctx-search-nudge.sh added to deprecated_hooks (98b4d1f)
- `agents/vbw-scout.md`, `agents/vbw-lead.md`, `agents/vbw-dev.md`, `agents/vbw-qa.md`, `agents/vbw-debugger.md`, `agents/vbw-architect.md`, `agents/vbw-docs.md` -- update: two new PostToolUse frontmatter entries each (838f976)
- `CHECKSUMS.sha256` -- regenerated via scripts/generate-checksums.sh (ac8f3b4)
- `CHANGELOG.md` -- update: new [Unreleased] section (ac8f3b4)
- `.vbw-planning/STATE.md` -- update: phase 47 closing entry + 2-week follow-up (ac8f3b4)
- `tests/test-agent-hook-overrides.sh` -- update: extend must-have / must-not-have hook lists (f2a8590)
- `tests/test-agent-hook-enforcement.sh` -- update: wiring + behavior assertions for new hooks; sentinel touch for targeted-Read test (f2a8590)
- `tests/test-phase-45-bundle-install.sh` -- update: retire ctx-search-nudge assertions, add negative assertions (f2a8590)
- `tests/test-phase-47-bundle-install.sh` -- created: integration smoke test for phase-47 bundle install (f2a8590)
