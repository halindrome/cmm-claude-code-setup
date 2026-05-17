---
name: pr-qa
description: "Apply the required PR QA process for this repository. Takes a PR number and optional target name as arguments (e.g., /pr-qa 123 or /pr-qa 123 default). Target paths and base branches come from .claude/skills/pr-qa/base-branches.json so base-branch selection is configurable without editing the skill. Orchestrates branch sync, automated QA agent review, fix commits, and PR comment posting across multiple QA rounds."
---

# PR QA Skill

Orchestrate the full PR QA process for a pull request in this repository.

**Usage:** `/pr-qa <PR_NUMBER> [TARGET] [--double]`

`TARGET` defaults to `default` when omitted. Supported targets are defined in `.claude/skills/pr-qa/base-branches.json`. For this single-repo project the only target is `default`.

The optional `--double` flag opts into **multi-model QA** — a second reviewer runs
locally via Qwen3-14b through LM Studio (see
`.claude/skills/pr-qa/qwen-reviewer.README.md`). Default is off: Claude reviews
alone. `--double` is per-invocation and does NOT persist across rounds; pass it
again on round 2 if you want the second opinion again.

---

## Target configuration

The skill reads target paths and base branches from an external config file:

```
.claude/skills/pr-qa/base-branches.json
```

Structure:

- `targets.<name>.path` — working directory for this target (`.` for the root repo)
- `targets.<name>.base_branch` — branch to sync/diff against (`develop` by default)
- `targets.<name>.remote` — git remote (usually `origin`)
- `targets.<name>.scope` — commit-message scope token for fix commits
- `protected_branches` — array; the skill must never push directly to any branch in this list

**Edit this file — not SKILL.md — when branch names change.**

---

## Step 0 — Parse arguments and inspect the PR

Extract `PR_NUMBER`, `TARGET` (default `default`), and the optional `--double` flag from the invocation
arguments. If `PR_NUMBER` is missing, ask for it before proceeding.
Record:

- `DOUBLE=true` if `--double` appears anywhere in the argv, else `DOUBLE=false`.

Load `.claude/skills/pr-qa/base-branches.json` and look up `targets.<TARGET>`. Resolve `<target-path>`, `<base-branch>`, `<remote>`, and `<scope>` from that entry. If the target is not present in the config, ask the user for the path and base branch and offer to add the entry to `base-branches.json`.

Navigate into the target directory and fetch the PR details:

```bash
cd <target-path>
gh pr view <PR_NUMBER>
```

Capture: PR title, source branch name, target branch, list of changed files, and current status (open/draft/etc.).

**Determine branch ownership.** Extract the PR author:

```bash
gh pr view <PR_NUMBER> --json author --jq '.author.login'
```

Then determine the current user:

```bash
gh api user --jq '.login' 2>/dev/null
```

Compare the PR author to the logged-in user. Set `IS_OWN_BRANCH=true` if they match, `IS_OWN_BRANCH=false` otherwise. This controls whether fixes are applied automatically (see Step 3B).

Also get the diff stat to assess scope. Use the PR's **actual target branch** (from `gh pr view`) — not necessarily the config's `base_branch` (report it to the user if they differ):

```bash
cd <target-path>
git fetch <remote>
git diff <remote>/<target-branch>..<remote>/<feature-branch> --stat 2>/dev/null | tail -5
```

---

## Step 0.5 — Resolve the contract (GitHub issue lookup → synthesize → block)

Before any QA round runs, resolve a **contract** for this PR — the criteria the
reviewer will verify against. Four decision branches:

1. **Formal GitHub issue link on the PR.** Run `gh pr view <PR_NUMBER> --json body --jq '.body'`
   and scan the body for `Closes #N`, `Fixes #N`, or `Resolves #N` patterns
   (case-insensitive). If found, extract the issue number and call
   `gh issue view <N> --json title,body`. Capture `title` and `body`.
   Record `contract_source=issue:#<N>`.

2. **Mentioned issue number in title or description.** If no closing keyword, regex-scan
   the PR title + description for bare `#\d+` references. For each match, call
   `gh issue view <N> --json title,body`. If one or more resolve successfully, ask
   the user via AskUserQuestion: *"Is `#<N>` (`<title>`) the intended contract for this
   PR?"* Options: yes (use it) / no — try next candidate (if more) / none of
   these (proceed to synthesis). Record `contract_source=issue:#<N>` on
   confirmation.

3. **Synthesize from PR title + description.** If no issue is found or the user
   declined all candidates, synthesize a contract from the PR title and
   description. Record `contract_source=synthesized`.

4. **BLOCK.** If the PR description is under ~200 characters AND no issue was
   matched, STOP. Display: *"Cannot form a contract for this PR. Link a GitHub
   issue or flesh out the PR description with acceptance criteria, then re-run
   `/pr-qa`."* Do NOT fall back to freeform findings.

Write the resolved contract to a temp file, e.g., `/tmp/qa-contract-<PR>.md`,
formatted as:

```
# Contract (source: <issue:#N | synthesized>)

Issue: <#N or "n/a">
Summary: <PR title or issue title>

## Acceptance criteria
- <criterion 1>
- <criterion 2>
...
```

This file is passed to both the Claude reviewer (via the `## Contract` section
of the Step 3A prompt) and the Qwen wrapper (via `--contract-file`).

---

Examine the changed file list.

**If the PR touches only documentation, CI config, or repo metadata** (e.g., `.md` files, `.github/` workflows, `.gitignore`, `README`, `CLAUDE.md`, `package.json` version bumps only) — announce that the QA round requirement does not apply to this PR and offer to post a note on the PR confirming the exemption. Stop here unless the user wants to continue.

**Otherwise**, continue to Step 2.

---

## Step 2 — Sync the feature branch with the base branch

This is mandatory before any QA round. A branch that is behind its base produces false findings.

```bash
cd <target-path>
git fetch <remote>
git checkout <feature-branch>
git merge <remote>/<target-branch> --no-edit
git push <remote> <feature-branch>
```

After pushing, verify the resulting diff is limited to intended changes:

```bash
cd <target-path>
git diff <remote>/<target-branch>..HEAD --stat
```

Report the diff stat to the user. If the diff contains unintended deletions or reversions after syncing, warn: *"The branch may have been cut from a stale base. Consider rebuilding from the current base tip."* Ask the user to confirm before proceeding.

---

## Step 3 — Run QA Round N

Track the round number (start at 1, increment each time Step 3 is repeated).

### Pre-round-1 only — skip-verification prompt + `--double` reminder

On **round 1 only** (and never on subsequent rounds):

1. Ask via AskUserQuestion: *"Skip Contract Verification for this PR? Default:
   No."* Options (default-first):
   - *"No, run Contract Verification (recommended)"* — sets
     `skip_contract_verification=false`.
   - *"Yes, skip"* — sets `skip_contract_verification=true`.

   Record the answer. It is passed to the reviewer prompt (and to the Qwen
   wrapper via `--skip-contract` when `true`). The same value applies to every
   round in this invocation; the question is NOT re-asked at round 2+.

2. If `DOUBLE=false`, emit this one-line notice (not a question):

   ```
   ◆ Tip: pass --double to run a second-opinion review via local Qwen3-14b
     (LM Studio required). See .claude/skills/pr-qa/qwen-reviewer.README.md.
   ```

   Suppress this notice when `DOUBLE=true` or when the current round is ≥ 2.

### Step 3A — Launch the QA reviewer sub-agent

**Use the Agent tool** to spawn a fresh sub-agent for the QA review. This is the critical step — do NOT display a prompt and ask the user to paste it elsewhere. Call the Agent tool directly.

Use `subagent_type: "pr-qa-reviewer"` (project-local agent authored in
`.claude/agents/pr-qa-reviewer.md` — the unprefixed form resolves to the local agent). Pass a prompt
constructed from the template below (fill in all placeholders before calling
the Agent tool):

```
You are a read-only QA reviewer. Do NOT modify any files, make commits, or push code.

Working directory: <absolute-path-to-target>
PR: #<PR_NUMBER>
Round: <N>
Feature branch: <feature-branch>
Target branch: <target-branch>
skip_contract_verification: <true|false>   # from the pre-round-1 AskUserQuestion

## Contract

<paste the entire contents of /tmp/qa-contract-<PR>.md here — the contract
block produced by Step 0.5, including source tag, issue number, summary, and
the acceptance-criteria list. If skip_contract_verification=true, the
reviewer should skip the per-criterion verification table but still use the
criteria as semantic context.>

## Your process

1. Run `git log <remote>/<target-branch>..HEAD --oneline` to understand the commit narrative.
2. Run `git diff <remote>/<target-branch>..HEAD --stat` to see all changed files.
3. Read each functionally significant changed file in full — not just the diff. Understand
   surrounding context, callers, and invariants. Skip mechanical one-liner additions
   unless you spot something wrong.
4. Run `gh pr view <PR_NUMBER>` for the PR description and any existing comments.
5. Act as devil's advocate: for each change ask — what happens when input is
   empty/null/huge? What if a network call fails mid-flight? What if the user
   navigates away? Are downstream callers of modified functions still compatible?
6. Check test coverage: does any new service or component lack a spec file?

## Hard constraints

- DO NOT modify any files, create commits, or push code
- DO NOT prescribe what to test upfront — discover what matters by reading the code
- DO NOT dismiss findings as "pre-existing" — if a bug is visible in a file touched
  by the PR, report it. The orchestrator decides what to fix.

## PR context

Title: <PR title>
Key changes: <paste bullet summary of what the PR does, from gh pr view output>

## Report format — return findings in exactly this structure

### Finding 1: <Title>
- **Area:** `<file>` (lines X–Y)
- **What was tested:** <description>
- **Expected:** <behavior>
- **Actual / Risk:** <issue>
- **Severity:** critical / major / minor
- **Status:** confirmed / hypothetical

[repeat for each finding]

### Summary
| Severity | Count |
|---|---|
| Critical | N |
| Major | N |
| Minor | N |
| **Total** | **N** |

If no findings, output: ### No Issues Found
```

Wait for the Agent tool to return its report before proceeding.

### Step 3A.2 — Double-review: invoke the Qwen wrapper (when `DOUBLE=true`)

When `DOUBLE=true`, after the Claude reviewer returns, invoke the local Qwen3
second-opinion reviewer via `.claude/skills/pr-qa/qwen-reviewer.sh`:

```bash
# The contract file was produced in Step 0.5.
CONTRACT_FILE=/tmp/qa-contract-<PR_NUMBER>.md
QWEN_OUT=/tmp/qa-qwen-<PR_NUMBER>-r<N>.md

cd <target-path>
MR_TARGET_BRANCH=<target-branch> \
.claude/skills/pr-qa/qwen-reviewer.sh \
  --mr <PR_NUMBER> \
  --target <TARGET> \
  --round <N> \
  --contract-file "$CONTRACT_FILE" \
  $( [ "<skip_contract_verification>" = "true" ] && echo --skip-contract ) \
  --output "$QWEN_OUT"
```

If the wrapper exits non-zero OR `$QWEN_OUT` is empty: treat this as a
**non-blocking failure**. Do NOT retry. Record the failure reason (exit code
and first stderr line) and proceed with Claude-only findings. The PR comment
in Step 3C will include a one-line `⚠ Qwen second-opinion review failed:
<reason>` note. Qwen failure NEVER blocks the round.

### Step 3A.3 — Tag-merge findings (when both reviewers ran)

When both the Claude report and a successful Qwen output are available,
produce a unified report via this merge procedure:

1. **Parse** each report into an ordered list of findings. Each finding has:
   `title`, `area_file` (normalized path), `line_range` (low,high — inclusive;
   0,0 if absent), plus the full markdown body.
2. **Prefix** every Claude finding title with `[claude]` and every Qwen
   finding title with `[qwen]`.
3. **Dedupe overlap.** A Claude finding `C` and a Qwen finding `Q` are the
   "same" iff:
   - `C.area_file == Q.area_file` AND line ranges overlap (any intersection),
     OR
   - their titles are identical after stripping the `[claude]`/`[qwen]`
     prefix and lowercasing.
4. **Merge** overlapping pairs: keep Claude's body (richer); rewrite the
   prefix to `[claude|qwen]`; append a short `_Qwen concurred:_` line with
   the Qwen finding title if its wording differed.
5. **Unmatched** Claude findings keep `[claude]`; unmatched Qwen findings
   keep `[qwen]` and are appended after the merged/Claude list, under a
   sub-heading `### Qwen-only findings`.
6. **Contract verification tables.** If both reports contain a contract table
   AND they agree row-by-row, keep Claude's table. If they disagree, keep
   Claude's but append a `_Qwen differed on:_` note listing the row names.
7. **Observations** (pre-existing bugs in touched files) from either reviewer
   go into a dedicated `## Pre-existing issues discovered` section of the
   merged report.

The merged report replaces the Claude-only report for posting in Step 3C.

### Step 3B — Apply fixes (ownership-gated)

Once the sub-agent returns its report:

**If `IS_OWN_BRANCH=false` (someone else's PR):**

Do NOT apply fixes automatically. Instead:
1. Present the findings to the user.
2. Ask via AskUserQuestion: *"This branch is authored by {author}. Would you like to apply fixes anyway, or just post the QA report for the author to address?"* Options:
   - **"Post report only (Recommended)"** — skip fixes, proceed to Step 3C to post the report. The author applies their own fixes.
   - **"Apply fixes anyway"** — proceed with fixes below, but include a note in the PR comment that fixes were applied by the QA reviewer and the author should review them.
3. If "Post report only" is selected, skip directly to Step 3C.

**If `IS_OWN_BRANCH=true` (your own PR):**

1. Read each finding carefully. For findings marked "hypothetical" or "minor" with no confirmed reproduction, ask the user whether to fix them before proceeding.
2. For confirmed and critical/major findings, proceed to fix them in the repository in this session.
3. Each QA round's fixes must be committed as a **single, separate commit** — do not amend previous commits:

```bash
cd <target-path>
git add <changed-files>
git commit -m "fix(<scope>): address QA round <N>"
git push <remote> <feature-branch>
```

Where `<scope>` is the `scope` value from `base-branches.json` for this target.

If there are no actionable findings (all hypothetical or minor), skip the fix commit.

### Step 3C — Post the QA report to the PR

Post the QA report as a **single comment** on the PR. The report body is:

- The merged report from Step 3A.3 when `DOUBLE=true` and Qwen succeeded, OR
- The Claude-only report (findings title prefix `[claude]` only) otherwise.

When `DOUBLE=true` but the Qwen wrapper failed, append:

```
⚠ Qwen second-opinion review failed: <reason>. Proceeding with Claude-only findings.
```

Construct via a temp file to avoid shell quoting issues:

```bash
cat > /tmp/qa-note.md << 'EOF'
## QA Round <N>

<merged-or-claude-only report body>

<if qwen failed in --double mode: the ⚠ line above>

---
*QA performed by Claude Code (claude-opus-4-7)*<if DOUBLE=true and qwen succeeded: + local Qwen3-14b (LM Studio)>
EOF

cd <target-path>
gh pr comment <PR_NUMBER> --body-file /tmp/qa-note.md
```

### Step 3D — Assess whether to continue

After each round, evaluate the findings:

- **If the round is clean** (no findings, or only hypothetical/minor with nothing to fix): announce the round came back clean. If this is at least round 2, tell the user the PR is ready to mark for review.
- **If critical or major confirmed findings were found and fixed** (own branch): announce that another round is required. Ask: *"Ready to run QA round <N+1>?"* If yes, repeat Step 2 (re-sync if the base has advanced) then repeat Step 3 with an incremented round number.
- **If critical or major findings were reported but not fixed** (someone else's branch, report-only mode): announce the findings have been posted. The QA cycle pauses here — the author needs to apply fixes before further rounds can be meaningful. Tell the user: *"QA report posted. Once {author} addresses the findings, run `/pr-qa {PR_NUMBER}` again to continue QA."*
- **After 4 rounds**: if findings persist beyond round 4, present a summary of remaining open issues and ask the user how to proceed.

> **Staying in sync during QA rounds:** If the target branch advances while QA rounds are in progress, re-run Step 2 (sync) before each new round to keep the diff clean.

---

## Step 4 — Final status report

After the QA cycle ends (clean round or user decision to stop), output a summary:

```
## QA Cycle Complete — PR #<PR_NUMBER>

- Rounds completed: N
- Round N came back: clean / minor-only / hypothetical-only
- Fix commits added: N
- QA reports posted to PR: N

Next steps:
- Mark the PR as ready for review (remove Draft status if applicable)
- Request review from the appropriate team members
```

---

## Notes

- **Never push to protected branches** — the authoritative list is `protected_branches` in `.claude/skills/pr-qa/base-branches.json`. The PR's own target branch is also off-limits regardless of whether it appears in that list. Only push to the feature branch.
- **Each fix commit must be separate** — never amend commits after a QA round is posted.
- **Fresh sub-agent per round** — each Agent tool call is a new invocation with no prior context, which is what produces unbiased findings. Never reuse a session that already reviewed the branch.
- **Switching base branches:** Edit `base-branches.json` to change the base branch. Do not hardcode branch names in SKILL.md.
