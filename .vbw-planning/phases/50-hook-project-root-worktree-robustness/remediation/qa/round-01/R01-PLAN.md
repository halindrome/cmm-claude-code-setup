---
phase: 50
round: 01
plan: R01
title: Amend 50-02-PLAN.md to document intentional lib-install skip in test fixture
type: remediation
autonomous: true
effort_override: fast
skills_used: []
files_modified:
  - .vbw-planning/phases/50-hook-project-root-worktree-robustness/50-02-PLAN.md
forbidden_commands: []
fail_classifications:
  - {id: "DEV-01", type: "plan-amendment", rationale: "Plan 50-02 Task 3 step 7 prescribed installing both session-gate.sh AND hooks/lib/project-root.sh into the test fixture. Dev installed only session-gate.sh because installing the lib would cause session-gate's lib-source branch to be taken, making the inline fallback code path untestable and defeating the mandated preflight-fail semantics (which require the fallback to be the code path under test). The deviation is a valid improvement over the original plan text. Amending 50-02-PLAN.md step 7 to reflect the actual approach and the reason (fixture must exercise the inline fallback, so the lib is intentionally omitted) resolves the FAIL.", source_plan: "50-02-PLAN.md"}
known_issues_input:
  - '{"test":"bash scripts/generate-checksums.sh (idempotency)","file":"scripts/generate-checksums.sh","error":"Generator does not glob agents/; re-running drops the 6 agents/vbw-*.md checksum lines added in Phase 49 (commit 9504564). Confirmed: running generator produced 'CHECKSUMS.sha256 &#124; 6 ------' diff. Agent file hashes are correct; gap is in generator coverage, not the checksums."}'
known_issue_resolutions:
  - '{"test":"bash scripts/generate-checksums.sh (idempotency)","file":"scripts/generate-checksums.sh","error":"Generator does not glob agents/; re-running drops the 6 agents/vbw-*.md checksum lines added in Phase 49 (commit 9504564). Confirmed: running generator produced 'CHECKSUMS.sha256 &#124; 6 ------' diff. Agent file hashes are correct; gap is in generator coverage, not the checksums.","disposition":"accepted-process-exception","rationale":"Pre-existing gap introduced by Phase 49 (commit 9504564 manually added agents/vbw-*.md checksum lines that scripts/generate-checksums.sh does not cover). Phase 50 only touches files in hooks/ which the generator does cover correctly. Fixing the generator to glob agents/ is out of Phase 50 scope — it belongs in a dedicated follow-up phase. The committed CHECKSUMS.sha256 is internally consistent (shasum -c passes all 37 entries), so this is non-blocking for Phase 50 shipping."}'
must_haves:
  truths:
    - "50-02-PLAN.md Task 3 step 7 reflects the actual implementation: install only session-gate.sh into the fixture; do NOT install hooks/lib/project-root.sh so the inline fallback is exercised"
    - "No product code, hook code, or test code changes in this remediation round — plan-amendment only"
  artifacts:
    - {path: ".vbw-planning/phases/50-hook-project-root-worktree-robustness/50-02-PLAN.md", provides: "amended step 7 and amendment-resolution note", contains: "inline fallback"}
  key_links:
    - {from: "50-02-PLAN.md", to: "50-VERIFICATION.md", via: "resolves-DEV-01-via-plan-amendment"}
---
<objective>
Resolve DEV-01 by amending the original Plan 50-02 Task 3 step 7 to match the actual (correct) approach: the test fixture installs only `session-gate.sh`, not `hooks/lib/project-root.sh`, so the inline fallback code path is exercised (which is the whole point of the test). Add a short amendment-resolution note explaining the rationale. No code changes.
</objective>
<context>
@.vbw-planning/phases/50-hook-project-root-worktree-robustness/50-VERIFICATION.md
@.vbw-planning/phases/50-hook-project-root-worktree-robustness/50-02-PLAN.md
@.vbw-planning/phases/50-hook-project-root-worktree-robustness/50-02-SUMMARY.md
DEV-01 in 50-VERIFICATION.md is the sole FAIL. The pre-existing generator coverage gap carried in `known_issues_input` is a Phase 49 artifact — Phase 50 did not introduce it and should not block on it.
</context>
<tasks>
<task type="auto">
  <name>Amend 50-02-PLAN.md step 7 and add amendment note</name>
  <files>
    .vbw-planning/phases/50-hook-project-root-worktree-robustness/50-02-PLAN.md
  </files>
  <action>
In `50-02-PLAN.md`, under Task 3 (`Add worktree regression case to tests/test-session-gate-earlyexit.sh`), find step 7 of the recipe. It currently reads:

  `7. Install hooks/project/session-gate.sh into $TMP/codespace/.claude/hooks/session-gate.sh AND install hooks/lib/project-root.sh into $TMP/codespace/.claude/hooks/lib/project-root.sh (mirroring setup.sh install_project behavior for this test's purposes).`

Replace it with:

  `7. Install ONLY hooks/project/session-gate.sh into $TMP/codespace/.claude/hooks/session-gate.sh. Do NOT install hooks/lib/project-root.sh — the fixture must exercise session-gate.sh's inline fallback branch (the "else" branch of the lib-source conditional), which is the code path actually being regression-tested here. Installing the lib would route session-gate through the lib-source branch, making the preflight-fail that the plan mandates impossible to demonstrate.`

Append an amendment-resolution note at the END of `50-02-PLAN.md` (after the closing `</tasks>` through `<output>` blocks, as a new footer section):

```
---

## Amendment — 2026-04-20 (Plan 50 QA Remediation R01, resolves DEV-01)

Task 3 step 7 originally prescribed installing both `session-gate.sh` AND
`hooks/lib/project-root.sh` into the test fixture. The Dev implementation
installed only `session-gate.sh` because installing the lib would cause
session-gate's lib-source branch to be taken, routing around the inline
fallback and making the mandated preflight-fail impossible to demonstrate.
The step text has been updated to reflect the actual (correct) approach.
No code changes — the committed fixture already implements the amended
approach.

Classification: `plan-amendment`.
QA round: R01 (landed 2026-04-20).
```

Do NOT modify any other part of the plan. Do NOT modify the product code, hook code, or test code — this round is strictly a plan-text amendment.
  </action>
  <verify>
- `grep -A1 "^  7\." .vbw-planning/phases/50-hook-project-root-worktree-robustness/50-02-PLAN.md` shows the new step 7 text mentioning "inline fallback" and "Do NOT install".
- `grep -c "## Amendment" .vbw-planning/phases/50-hook-project-root-worktree-robustness/50-02-PLAN.md` returns 1.
- `git diff --stat` shows exactly one file changed: `50-02-PLAN.md`.
- `bash tests/test-session-gate-earlyexit.sh` still passes (this is a documentation-only change so tests should be unaffected).
  </verify>
  <done>
50-02-PLAN.md step 7 amended; amendment note appended at EOF. No other files modified. Test suite still green.
  </done>
</task>
</tasks>
<verification>
1. `git diff --name-only HEAD~1 HEAD` shows only `.vbw-planning/phases/50-hook-project-root-worktree-robustness/50-02-PLAN.md` and the remediation round artifacts (`R01-SUMMARY.md`).
2. `grep -c "inline fallback" .vbw-planning/phases/50-hook-project-root-worktree-robustness/50-02-PLAN.md` >= 1.
3. `bash tests/test-session-gate-earlyexit.sh` passes.
4. The pre-existing known issue (`scripts/generate-checksums.sh` coverage gap) is classified `accepted-process-exception` — QA should verify the disposition is credible (Phase 50 did not introduce it) and omit it from `pre_existing_issues` on re-verification so the registry can clear.
</verification>
<success_criteria>
- DEV-01 resolved via plan-amendment: original `50-02-PLAN.md` Task 3 step 7 updated to reflect actual implementation, with amendment note explaining why.
- No product or test code changes this round.
- Pre-existing generator-coverage known issue carried with `accepted-process-exception` disposition (tracked as tech-debt for a future phase, not a Phase 50 blocker).
</success_criteria>
<output>
R01-SUMMARY.md
</output>
