---
phase: 47
round: 01
plan: R01
title: Reconcile plan text with accepted deviations; document unfixable commit merge
type: remediation
autonomous: true
effort_override: balanced
skills_used: [simplify]
files_modified:
  - .vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-02-PLAN.md
  - .vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-03-PLAN.md
  - .vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-04-PLAN.md
forbidden_commands: []
fail_classifications:
  - {id: "DEV-01", type: "process-exception", rationale: "Commit ad4cdfe (47-02) merged two tasks into one atomic commit and is already on develop with five subsequent phase-47 commits (98b4d1f, 838f976, ac8f3b4, f2a8590, c3c1bdd) on top. Un-batching requires an interactive rebase of already-published history, which carries higher risk (forced pushes, disrupting any in-flight work, hook/signing invariants) than the one-commit-per-task violation itself. The plan itself already called out DEVN-01 and the functional outcome is unaffected."}
  - {id: "DEV-02", type: "plan-amendment", rationale: "Plan 47-01 tightened ctx-execute-enforcer.sh so that `echo hello` and bare `git diff HEAD~1` now fall through to the default block. The two legacy test assertions in test-ctx-execute-enforcer.sh asserted the *old* exempt behavior for those exact commands, so preserving them verbatim (as plan 47-02 must_haves.artifacts[1] literally required) would have produced tests that directly contradict the new hook behavior. Replacing them was the only correct path; plan 47-02 should be amended to acknowledge that assertion replacement is expected when the asserted behavior is itself the thing being tightened.", source_plan: "47-02-PLAN.md"}
  - {id: "DEV-04", type: "plan-amendment", rationale: "The 8 ctx-search-nudge references remaining in tests/test-phase-45-bundle-install.sh are *negative* retirement assertions — they assert the nudge is absent from settings.json, setup.sh wiring, and agent frontmatter. They are evidence of retirement, not evidence of wiring. Plan 47-03's verification clause `grep -rn ctx-search-nudge hooks/ tests/` returns zero matches' is a literalist grep that does not distinguish positive assertions from negative ones. The clause should be amended to exempt retirement-assertion fixtures in tests/test-phase-45-bundle-install.sh.", source_plan: "47-03-PLAN.md"}
  - {id: "DEV-05", type: "plan-amendment", rationale: "The 3 residual ctx-search-nudge references in rules/project-settings-example.json (one `_comment` on the replacement matcher) and setup.sh (one comment + one `deprecated_hooks` list entry) are intentional retirement infrastructure. The `deprecated_hooks` entry is functional: setup.sh purges it from target settings.json during install, which is the mechanism that *removes* any stale ctx-search-nudge registration from upgraders. Plan 47-04's implicit zero-match expectation should be amended to acknowledge the deprecated_hooks entry as required retirement plumbing, not residual wiring.", source_plan: "47-04-PLAN.md"}
  - {id: "CONV-02", type: "process-exception", rationale: "CONV-02 is the convention-layer view of the same single underlying issue as DEV-01 (commit ad4cdfe merged two plan-47-02 tasks). Same justification applies: un-batching a commit already on develop and built upon by five subsequent phase-47 commits would require rewriting published history, which is a strictly worse outcome than the violation. No code change can retroactively split that commit without the same rebase risk."}
must_haves:
  truths:
    - "After this round, 47-02-PLAN.md, 47-03-PLAN.md, and 47-04-PLAN.md each carry an explicit amendment block noting which DEV- FAIL is resolved by that amendment and why the original clause was over-literal."
    - "R01-SUMMARY.md frontmatter records the two process-exception justifications (DEV-01, CONV-02) with concrete evidence (commit SHA ad4cdfe, five follow-on commits on develop) so a future auditor can re-verify without re-discovering the context."
  artifacts:
    - path: ".vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-02-PLAN.md"
      provides: "Amended must_haves.artifacts entry for test-ctx-execute-enforcer.sh that replaces the literal 'Preserve every existing assertion' clause with 'Preserve every existing assertion except those asserting behavior that plan 47-01 tightened (`echo hello`, bare `git diff HEAD~1` exemptions) — those must be replaced with assertions of the new blocking behavior.'"
      contains: "R01-AMENDMENT"
    - path: ".vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-03-PLAN.md"
      provides: "Amended verification clause that scopes the `grep -rn ctx-search-nudge hooks/ tests/` zero-match expectation to *active* references, explicitly exempting retirement-assertion fixtures in tests/test-phase-45-bundle-install.sh."
      contains: "R01-AMENDMENT"
    - path: ".vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-04-PLAN.md"
      provides: "Amended verification expectation that the deprecated_hooks list entry and its adjacent comment in setup.sh, plus the single _comment string in rules/project-settings-example.json, are required retirement plumbing and are exempt from any zero-match ctx-search-nudge grep."
      contains: "R01-AMENDMENT"
  key_links: []
---
<objective>
Close the five VERIFICATION.md FAILs from phase 47 QA round 0 by (a) amending three original plan files to reflect what actually shipped, (b) recording two process-exceptions with concrete evidence so DEV-01/CONV-02 cannot be rediscovered as novel findings, and (c) leaving all product code unchanged — none of the five FAILs indicates a real behavioral defect.
</objective>
<context>
VERIFICATION.md PARTIAL (34/39 PASS). Classification rationale, source_plan mapping, and full justifications are in the fail_classifications array above. The product code behind every FAIL is correct and QA rated the functional outcomes acceptable — the failures are plan-text vs. shipped-artifact mismatches (3) and an unfixable historical commit merge (2 views of 1 incident).
</context>
<tasks>
<task type="auto">
  <name>Amend 47-02-PLAN.md for DEV-02</name>
  <files>
    .vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-02-PLAN.md
  </files>
  <action>
Insert an `## R01-AMENDMENT (DEV-02)` section immediately after the existing `## Deviations` / notes section (or at end of body if none). The section must: (1) quote the original must_haves.artifacts[1] preservation clause verbatim; (2) state that plan 47-01 tightened ctx-execute-enforcer.sh so `echo hello` and bare `git diff HEAD~1` now fall through to the default block; (3) rewrite the clause to "Preserve every existing assertion **except** those asserting behavior that plan 47-01 tightened (`echo hello` and bare `git diff HEAD~1` exemptions) — those must be replaced with assertions of the new blocking behavior"; (4) mark DEV-02 resolved-by-amendment. Do not edit the YAML frontmatter (the original must_haves stays frozen as the historical record; the amendment section supersedes it going forward).
  </action>
  <verify>
`grep -c R01-AMENDMENT .vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-02-PLAN.md` returns >= 1. The amendment section cites DEV-02 by ID and names both tightened commands.
  </verify>
  <done>
Amendment section is present in 47-02-PLAN.md, committed in the round-01 dir.
  </done>
</task>
<task type="auto">
  <name>Amend 47-03-PLAN.md for DEV-04</name>
  <files>
    .vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-03-PLAN.md
  </files>
  <action>
Insert an `## R01-AMENDMENT (DEV-04)` section after the existing verification block. The section must: (1) quote the original verification clause `grep -rn ctx-search-nudge hooks/ tests/` returns zero matches verbatim; (2) explain that tests/test-phase-45-bundle-install.sh retains 8 retirement *negative* assertions (the nudge is absent from settings.json, setup.sh wiring, agent frontmatter); (3) rewrite the clause to "`grep -rn ctx-search-nudge hooks/ tests/` returns zero matches **except in tests/test-phase-45-bundle-install.sh, where retirement-assertion fixtures naming ctx-search-nudge are required evidence that the nudge is not re-registered**"; (4) mark DEV-04 resolved-by-amendment. Frontmatter unchanged.
  </action>
  <verify>
`grep -c R01-AMENDMENT .vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-03-PLAN.md` returns >= 1. Amendment section names DEV-04 and tests/test-phase-45-bundle-install.sh explicitly.
  </verify>
  <done>
Amendment section is present in 47-03-PLAN.md.
  </done>
</task>
<task type="auto">
  <name>Amend 47-04-PLAN.md for DEV-05</name>
  <files>
    .vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-04-PLAN.md
  </files>
  <action>
Insert an `## R01-AMENDMENT (DEV-05)` section after the existing verification block. The section must: (1) enumerate the three residual string references (1 _comment in rules/project-settings-example.json naming the replacement matcher, 1 comment in setup.sh, 1 `deprecated_hooks` list entry in setup.sh); (2) explain that the `deprecated_hooks` entry is *functional* — setup.sh purges it from target settings.json during install, which is how upgraders lose any stale ctx-search-nudge registration; (3) codify the exemption as "rules/project-settings-example.json `_comment` fields, setup.sh comments, and the setup.sh `deprecated_hooks` list are exempt from any zero-match ctx-search-nudge grep — they are retirement infrastructure, not active wiring"; (4) mark DEV-05 resolved-by-amendment. Frontmatter unchanged.
  </action>
  <verify>
`grep -c R01-AMENDMENT .vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-04-PLAN.md` returns >= 1. Amendment section names DEV-05, the `deprecated_hooks` list, and both wiring files.
  </verify>
  <done>
Amendment section is present in 47-04-PLAN.md.
  </done>
</task>
<task type="auto">
  <name>Record DEV-01 / CONV-02 process-exceptions in the round summary narrative</name>
  <files>
    .vbw-planning/phases/47-enforcement-audit-ctx-annotation/remediation/qa/round-01/R01-SUMMARY.md
  </files>
  <action>
When writing R01-SUMMARY.md, include a `## Process Exceptions` section that lists DEV-01 and CONV-02, names commit ad4cdfe, lists the five follow-on phase-47 commits on develop (98b4d1f, 838f976, ac8f3b4, f2a8590, c3c1bdd) as evidence that rebasing to split the merge is published-history rewriting, and states the functional outcome was unaffected. Do not attempt to rebase or rewrite history.
  </action>
  <verify>
R01-SUMMARY.md contains `## Process Exceptions`, names DEV-01 and CONV-02, and cites commit ad4cdfe plus at least two follow-on SHAs.
  </verify>
  <done>
Summary section is present and committed.
  </done>
</task>
</tasks>
<verification>
1. `grep -l R01-AMENDMENT .vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-02-PLAN.md .vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-03-PLAN.md .vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-04-PLAN.md` lists all three paths.
2. Each amendment section explicitly references its source DEV- FAIL ID.
3. R01-SUMMARY.md `## Process Exceptions` names commit ad4cdfe and at least two follow-on SHAs.
4. No product code (hooks/, tests/, setup.sh, rules/, agents/) is modified in this round — `git diff --name-only <round-start>..HEAD` shows only planning artifacts under .vbw-planning/phases/47-enforcement-audit-ctx-annotation/.
</verification>
<success_criteria>
- Three plan files carry an R01-AMENDMENT section each, resolving DEV-02, DEV-04, DEV-05 as plan-amendments.
- R01-SUMMARY.md documents DEV-01 and CONV-02 as process-exceptions with commit evidence.
- QA re-verification can re-check each original FAIL against either the amended plan text or the documented process-exception justification.
</success_criteria>
<output>
R01-SUMMARY.md
</output>
