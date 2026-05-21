---
phase: 61
plan: "01"
title: "Package CMM/ctx rules as Claude Code Skills and wire agent frontmatter"
status: complete
completed: 2026-05-21
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - dc8eecf
  - 235df09
  - 1d6d1ec
  - eba2551
  - 17c72ef
files_modified:
  - skills/cmm-rules/SKILL.md
  - skills/ctx-rules/SKILL.md
  - agents/vbw-dev.md
  - agents/vbw-lead.md
  - agents/vbw-scout.md
  - agents/vbw-debugger.md
  - agents/vbw-qa.md
  - agents/vbw-docs.md
  - agents/vbw-architect.md
  - skills/pr-qa/pr-qa-reviewer.md
  - setup.sh
  - hooks/global/subagent-ctx-startup.sh
  - hooks/project/subagent-cmm-startup.sh
  - hooks/global/cmm-nudge.sh
  - hooks/global/cmm-grep-nudge.sh
  - hooks/project/ctx-execute-enforcer.sh
  - tests/test-subagent-ctx-startup.sh
  - CHECKSUMS.sha256
deviations: []
pre_existing_issues: []
ac_results:
  - criterion: "skills/cmm-rules/SKILL.md and skills/ctx-rules/SKILL.md exist with valid name:/description: frontmatter"
    verdict: "pass"
    evidence: "dc8eecf — grep '^name:' returns cmm-rules and ctx-rules respectively"
  - criterion: "Both skill bodies are verbatim lifts of rules/cmm-rules.md and rules/ctx-rules.md"
    verdict: "pass"
    evidence: "dc8eecf — CMM Tool Decision Table and PostToolUse capture present in respective SKILL.md files"
  - criterion: "All 8 agent source files declare the correct skills: field"
    verdict: "pass"
    evidence: "235df09 — grep -l 'skills:' across all 8 agent files returns all 8"
  - criterion: "setup.sh --project installs both skills into .claude/skills/{cmm-rules,ctx-rules}/"
    verdict: "pass"
    evidence: "1d6d1ec — skills install loops added to install_global and install_project; dry-run output mentions skill dirs"
  - criterion: "SubagentStart hook NUDGE_TEXT under 50 tokens; JSON envelope shape preserved"
    verdict: "pass"
    evidence: "eba2551 — new NUDGE_TEXT is 12 tokens; python3 json.loads round-trip exits 0"
  - criterion: "Three PreToolUse hooks each contain 'See skill' reference line"
    verdict: "pass"
    evidence: "eba2551 — grep 'See skill' returns 3 matches across cmm-nudge.sh, cmm-grep-nudge.sh, ctx-execute-enforcer.sh"
  - criterion: "tests/test-subagent-ctx-startup.sh passes with updated a1 and a2"
    verdict: "pass"
    evidence: "eba2551 — 6/6 pass; a1 checks [ctx-startup], a2 checks ctx-rules"
  - criterion: "CHECKSUMS.sha256 verifies clean for all new and modified files"
    verdict: "pass"
    evidence: "17c72ef — shasum -a 256 -c exits 0 (39/39 OK including new skill entries)"
---

## What Was Built

- Packaged `rules/cmm-rules.md` and `rules/ctx-rules.md` as Claude Code Skills under `skills/cmm-rules/` and `skills/ctx-rules/` with YAML frontmatter (`name:` + `description:`) and verbatim rule body
- Added `skills:` frontmatter to all 8 VBW agent source files per the per-agent split (dev/lead/scout/debugger/qa/pr-qa-reviewer get both; docs gets ctx-rules only; architect gets cmm-rules only)
- Added skills install loops to `install_global` and `install_project` in `setup.sh` to copy `skills/*/SKILL.md` to the appropriate `skills/{name}/` destination
- Shrunk SubagentStart hook bodies to thin skill pointers (~12 tokens each vs. ~75 tokens prior); JSON envelope shape (`python3 json.dumps`) unchanged
- Appended `See skill \`<name>\` for the full protocol.` to the exit-2 block of all three PreToolUse enforcement hooks
- Updated test case `a2` in `tests/test-subagent-ctx-startup.sh` to check for `ctx-rules` skill reference instead of `mcp__context-mode__ctx_stats` tool name
- Regenerated `CHECKSUMS.sha256` with updated entries for all modified hooks/agents and three new entries for skill files

## Files Modified

- `skills/cmm-rules/SKILL.md` — new: CMM code navigation skill with decision table and orient-first pattern
- `skills/ctx-rules/SKILL.md` — new: context-mode FTS5 session index skill with retrieval protocol
- `agents/vbw-{dev,lead,scout,debugger,qa}.md` — added `skills: [cmm-rules, ctx-rules]`
- `agents/vbw-docs.md` — added `skills: [ctx-rules]`
- `agents/vbw-architect.md` — added `skills: [cmm-rules]`
- `skills/pr-qa/pr-qa-reviewer.md` — added `skills: [cmm-rules, ctx-rules]`
- `setup.sh` — skills install loops in `install_global` and `install_project`
- `hooks/global/subagent-ctx-startup.sh` — NUDGE_TEXT replaced with skill pointer
- `hooks/project/subagent-cmm-startup.sh` — both ADVISORY branches replaced with skill pointers
- `hooks/global/cmm-nudge.sh` — appended skill ref line to exit-2 heredoc
- `hooks/global/cmm-grep-nudge.sh` — appended skill ref line to exit-2 heredoc
- `hooks/project/ctx-execute-enforcer.sh` — appended skill ref line before exit 2
- `tests/test-subagent-ctx-startup.sh` — a2 updated; TOOL var replaced by SKILL_REF var
- `CHECKSUMS.sha256` — regenerated (39 entries; 3 new skill entries added manually)

## Regression Tests

| Test script | Result |
|---|---|
| `tests/test-phase-51-upstream-hooks.sh` | PASS (20/20) |
| `tests/test-subagent-ctx-startup.sh` | PASS (6/6) |
| `tests/test-phase-59-cmm-install-scope.sh` | PASS (18/18) |
