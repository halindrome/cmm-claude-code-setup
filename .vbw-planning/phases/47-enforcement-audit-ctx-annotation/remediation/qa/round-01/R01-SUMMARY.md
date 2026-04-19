---
phase: 47
round: 01
plan: R01
title: Reconcile plan text with accepted deviations; document unfixable commit merge
type: remediation
status: complete
completed: 2026-04-18
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - 780e7565de94ba938098017fcc92b4d8cf7108de
  - 8789f95e2eeeec914de70bec93f81ffe310453cc
  - c65c0d18442112d577c6a1939dee6f7d64d13deb
  - HEAD  # this summary commit; self-referential hash cannot be recorded in-file
files_modified:
  - .vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-02-PLAN.md
  - .vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-03-PLAN.md
  - .vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-04-PLAN.md
  - .vbw-planning/phases/47-enforcement-audit-ctx-annotation/remediation/qa/round-01/R01-SUMMARY.md
deviations: []
---

Closed phase-47 QA round-0 FAILs by amending three original plans (DEV-02, DEV-04, DEV-05) and documenting two unfixable process-exceptions (DEV-01, CONV-02) — no product code changed; every FAIL was a plan-text vs. shipped-artifact mismatch or a historical-commit-merge issue that a rebase would make strictly worse.

## Task 1: Amend 47-02-PLAN.md for DEV-02

### What Was Built
- Appended an `## R01-AMENDMENT (DEV-02)` section to `47-02-PLAN.md` quoting the original "preserve every existing assertion" clause verbatim, explaining that plan 47-01 tightened `hooks/project/ctx-execute-enforcer.sh` so `echo hello` and bare `git diff HEAD~1` now fall through to the default block, and rewriting the clause to exempt those two tightened behaviors.
- Frontmatter intentionally left frozen as historical record; amendment supersedes going forward.

### Files Modified
- `.vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-02-PLAN.md` -- append: add R01-AMENDMENT section resolving DEV-02 by plan-amendment.

### Deviations
None.

## Task 2: Amend 47-03-PLAN.md for DEV-04

### What Was Built
- Appended an `## R01-AMENDMENT (DEV-04)` section to `47-03-PLAN.md` quoting the original `grep -rn ctx-search-nudge hooks/ tests/` zero-match clause, explaining that `tests/test-phase-45-bundle-install.sh` retains 8 *negative retirement assertions* (nudge absent from settings.json, setup.sh wiring, agent frontmatter), and rewriting the clause to exempt those retirement-assertion fixtures.
- Frontmatter left frozen; amendment supersedes.

### Files Modified
- `.vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-03-PLAN.md` -- append: add R01-AMENDMENT section resolving DEV-04 by plan-amendment.

### Deviations
None.

## Task 3: Amend 47-04-PLAN.md for DEV-05

### What Was Built
- Appended an `## R01-AMENDMENT (DEV-05)` section to `47-04-PLAN.md` enumerating the 3 residual `ctx-search-nudge` references (one `_comment` in `rules/project-settings-example.json`, one comment in `setup.sh`, one `deprecated_hooks` list entry in `setup.sh`), explaining that the `deprecated_hooks` entry is *functional* (setup.sh uses it to purge stale registrations from upgraders' target settings.json), and codifying the exemption as required retirement infrastructure.
- Frontmatter left frozen; amendment supersedes.

### Files Modified
- `.vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-04-PLAN.md` -- append: add R01-AMENDMENT section resolving DEV-05 by plan-amendment.

### Deviations
None.

## Task 4: Record DEV-01 / CONV-02 process-exceptions in the round summary narrative

### What Was Built
- This `R01-SUMMARY.md` with a top-level `## Process Exceptions` section (below) documenting DEV-01 and CONV-02 — two views of the same single underlying incident (commit ad4cdfe merged two plan-47-02 tasks into one atomic commit) — with concrete evidence that un-batching would require rewriting already-published develop history.
- Frontmatter records all four commit SHAs, the four modified files, and status=complete.

### Files Modified
- `.vbw-planning/phases/47-enforcement-audit-ctx-annotation/remediation/qa/round-01/R01-SUMMARY.md` -- create: round summary with process-exceptions narrative.

### Deviations
None.

## Process Exceptions

DEV-01 (one-commit-per-task violation) and CONV-02 (VBW convention-layer view of the same issue) are two surfaces of a single underlying incident: commit **`ad4cdfe`** on `develop` merged two plan-47-02 tasks (ctx-execute-enforcer.sh tightening + test extension) into one atomic commit. The plan's own deviations notes already flagged this as DEVN-01 at execution time.

**Why this cannot be corrected by code change in this round:**
Five subsequent phase-47 commits have been published on top of `ad4cdfe` on `develop`:

1. `98b4d1f` — chore(47-05): install new phase-47 hooks, deprecate ctx-search-nudge
2. `838f976` — chore(47-05): register phase-47 nudges in every VBW agent frontmatter
3. `ac8f3b4` — docs(47-05): regenerate checksums, add CHANGELOG and STATE entries
4. `f2a8590` — test(47-05): extend agent-hook tests + add phase-47 bundle-install suite
5. `c3c1bdd` — docs(47-05): add plan 47-05 SUMMARY.md

Un-batching `ad4cdfe` would require an interactive rebase of already-published history, which carries higher risk than the violation itself: forced pushes to a shared branch, disruption of any in-flight work built on those SHAs, and re-signing every rewritten commit. The functional outcome of `ad4cdfe` is unaffected — both merged tasks landed correctly and are fully verified by the phase-47 test suite.

**Resolution:** DEV-01 and CONV-02 accepted as process-exceptions. A future auditor can re-verify this decision against the commit graph without re-discovering the context.

## Verification Results

All four `<verification>` checks from `R01-PLAN.md` pass:

1. **`grep -l R01-AMENDMENT` on all three plan files** — PASS. All three paths returned: `47-02-PLAN.md`, `47-03-PLAN.md`, `47-04-PLAN.md`.
2. **Each amendment section explicitly references its source DEV- FAIL ID** — PASS. 47-02 cites `(DEV-02)` and names both tightened commands (`echo hello`, bare `git diff HEAD~1`); 47-03 cites `(DEV-04)` and names `tests/test-phase-45-bundle-install.sh`; 47-04 cites `(DEV-05)` and names both `deprecated_hooks` list and the two wiring files.
3. **R01-SUMMARY.md `## Process Exceptions` names commit ad4cdfe and at least two follow-on SHAs** — PASS. Section names `ad4cdfe` plus all five follow-on SHAs (`98b4d1f`, `838f976`, `ac8f3b4`, `f2a8590`, `c3c1bdd`).
4. **No product code modified in this round — `git diff --name-only <round-start>..HEAD` shows only planning artifacts** — PASS. `git diff --name-only HEAD~3..HEAD` returns only the three `.vbw-planning/phases/47-enforcement-audit-ctx-annotation/47-0{2,3,4}-PLAN.md` paths; no changes under `hooks/`, `tests/`, `setup.sh`, `rules/`, or `agents/`.
