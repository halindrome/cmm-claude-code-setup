# Map: cmm-claude-code-setup (/Users/ahby/Sources/ccs-vbw2)

## Stack and commands
- Bash hooks + `setup.sh` (installer, 3510 lines); a few Python 3 scripts for analysis. No package manager, lockfile, build step, CI (no `.github`). VERSION 1.12.0.
- Install: `./setup.sh` (registers hooks with Claude Code; modifies user config; not run).
- Test: `make test` runs every `tests/test-*.sh` with `bash`, prints PASS/FAIL per file, non-zero on any failure or if none found. Slow (>120 s). Single test: `bash tests/<name>.sh`.
- Measure: `make measure DAYS=30 [MODEL=...]` runs `scripts/analyze-enforcement.py` and `scripts/analyze-antipatterns.py` (read-only over local transcripts).
- Lint: no target. `shellcheck` and `bats` exist in `/opt/homebrew/bin`; `shellcheck -S warning hooks/* setup.sh scripts/*.sh` gave 2 findings (unverified; `hooks/` contains dirs `global`, `lib`, `project`, so the glob needs refining).
- Release scripts: `scripts/bump-version.sh`, `scripts/generate-checksums.sh` (writes `CHECKSUMS.sha256`). Never run bump or push unless asked.

## Structure
- `hooks/global` (7 nudges/reindex), `hooks/lib` (5 helpers), `hooks/project` (20 gates/trackers/session hooks); `rules/`; `agents/` (7 `vbw-*.md`); `skills/{cmm-rules,ctx-rules}`; `scripts/`; `tests/`.
- `setup.sh`: `main()` line 3467, `install_global` 1935, `install_project` 2022, `merge_settings_json` 1568, `vbw_is_available` 204. Line 9 pins "Synced upstream VBW version: 1.37.0".
- Hook flow: Claude Code fires hook; exit 2 blocks, exit 0 allows; session sentinel `/tmp/cmm-session-ready-<md5>`.
- Largest hooks: `hooks/project/agent-override-generate.sh` (599, the VBW1/VBW2 compat point), `ctx-execute-enforcer.sh` (535), `ctx-execute-cmm-nudge.sh` (474), `ctx-payload-guard.sh` (434), `hooks/global/cmm-grep-nudge.sh` (431).

## The requested change: qa-cycle gate (docs-only)
- Already recorded as R9 (auto) and R10 (human) in `.vbw/spec.md` (lines 27-28) and `.vbw/record.json`, commit ea96974.
- R9: `CONTRIBUTING.md` and `CLAUDE.md` document the sequence: `feature/*` off `develop` before the first VBW step; GitHub issue mirroring the requirements as the QA contract; push and open PR to `develop` from the main session (VBW never pushes); `/qa-cycle` rounds, each fix its own commit `fix(scope): address QA round N` (never amend); keep changes, `vbw prove`, accept, ship.
- Gap: `grep -i qa-cycle` on both files returns nothing.
- Edit targets: `CONTRIBUTING.md` "## Pull Request Process" (line 52; step 5 at lines 58-128, "Proving your work" near 128), "## Branch Model" (34), "Making Changes" (23). `CLAUDE.md` "Pull Request QA (Required)", "Branch Model", "VBW workflow (optional/legacy)".
- Reference: `../worker-simulator/.vbw/spec.md:32` (R12, GitLab ticket there) and `record.json` ~2195 (rounds 1-2 fixes kept and re-proven, approved after clean round 3). Its CLAUDE.md and CONTRIBUTING.md have no qa-cycle text. `/qa-cycle` syntax is unverified: do not invent flags. Check the plugin at `~/.config/claude-code/plugins/cache/vbw-marketplace/vbw/2.1.18`.
- **Options:** (A, recommended) add a VBW 2 + `/qa-cycle` subsection after step 5 in `CONTRIBUTING.md` and extend `CLAUDE.md`'s QA section, keeping the manual Opus-session cycle as the non-VBW fallback. (B) Replace the manual cycle: shorter, but breaks non-VBW users (VBW is optional). (C) Detail only in `CONTRIBUTING.md` with a pointer in `CLAUDE.md`: fails R9, which names both files.
- Enforcement alternatives (not needed for R9): a `make qa-gate` script that checks PR comments via `gh` (recommended if enforcement is wanted, no CI dependency), or a hook blocking `gh pr ready`.

## Conventions
- Commit: `{type}({scope}): {description}`, docs use `docs(...)`; one commit per task; attribution trailers per session. Don't hand-edit `.vbw/` or `.vbw-planning/`. No version bump or push unless asked (bump only for `develop` to `main` releases).
- Bash hooks: `#!/bin/bash`, one-line purpose comment `# name.sh — ...`, Install/Register/Matcher block. Branches: `feature/*` to `develop` to `main` (tagged).
- Existing QA text names Claude Opus 4.6 or equivalent and the agent-cmm-gate CMM-keyword requirement for Agent-run QA (`CONTRIBUTING.md` ~line 64); if `/qa-cycle` spawns subagents, that gate applies.
- Conflict: `CLAUDE.md` says docs-only PRs skip the QA cycle (`CONTRIBUTING.md` line 60), but R10 demands `/qa-cycle` for this PR. Recommend: keep the skip rule with an explicit exception for VBW 2 PRs, and tell the user.
- Open questions: does the manual fallback stay (recommended)? Does the clean-round rule replace the "2-4 rounds" minimum? Is a `CHANGELOG.md` entry wanted (optional, unchecked)?

## Tests
- 57 self-contained scripts `tests/test-*.sh` (~12.7k lines), no framework; each has its own `_pass`/`_fail` counters and exits 1 on failure. Most use `set -euo pipefail`, except `test-context-mode-detect.sh`, `test-cmm-orient-nudge.sh`, `test-ctx-execute-cmm-nudge.sh`.
- Fixture pattern: `mktemp -d /tmp/cmm-*-XXXXXX`, `git init`, copy hook, pipe JSON via python3, assert exit 0/2. Helper `tests/setup-test-monorepo.sh`; static fixtures `tests/fixtures/skill-compliance/agent{1,2}.jsonl`. No shared lib.
- Seven phase-named tests (phase-45 to 66) are brittle and hard to locate.
- Covered: PreToolUse and nudge hooks, install/uninstall, analyze/measure scripts.
- Gaps (name-grep heuristic): no refs to `hooks/global/reindex-after-edit.sh`, `hooks/lib/is-cmm-ext.sh`, `scripts/bump-version.sh`; nothing tests the VBW2 compat layer; nothing tests the PR-process docs, so R9 is checked by grep.
- If a script/hook gate is added, add `tests/test-<name>.sh` modeled on `tests/test-cwd-guard.sh` (picked up by `make test`). Docs-only needs no test.
- Not run: the suite is slow and writes temp dirs; no pass/fail result known.

## Risks
- Writes through `.vbw/record.json` are blocked by a VBW guard; use vbw commands. It has an uncommitted lease change that is not user work.
- `CHECKSUMS.sha256` covers only `hooks/`, `rules/`, `agents/`, `setup.sh`, `tests/` (`scripts/generate-checksums.sh:26`); docs edits don't affect it.
- Only `tests/test-cmm-agent-preamble.sh` and `tests/test-cmm-nudge-blocking.sh` mention CONTRIBUTING/CLAUDE.md; grep them before editing (unread).
- Don't edit generated overrides or synced `agents/vbw-*.md` without regenerating. `scripts/__pycache__` is an artifact. User declined keeping VBW 1 support: VBW 1 agent-override behavior may be dropped (VBW 2 only).
- Branch is `feature/102-vbw2-compatibility` (findings variously say `feature/vbw2-compat`); PR goes to `develop`.

