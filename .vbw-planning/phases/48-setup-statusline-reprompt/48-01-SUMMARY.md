---
phase: 48
plan: 01
title: "install_statusline re-prompt with current-value defaults on already-installed projects"
status: complete
completed: 2026-04-19
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - b57e432
  - dd3fe91
  - e1957f3
  - 55cf98d
files_modified:
  - setup.sh
  - tests/test-phase-48-statusline-reprompt.sh
  - CHECKSUMS.sha256
deviations:
  - "Task 3 chose the helper-level test strategy over pseudo-TTY feeding (explicitly permitted by the plan as the fallback). _prompt_with_default is exercised in-process via here-string stdin for Cases A/B; --yes end-to-end covers Case C. An additional Case D (--reconfigure-statusline + --yes) was added on top of the planned A/B/C to lock the settings-wiped-but-config-present edge case."
pre_existing_issues: []
---

Fix install_statusline Phase 2 so a second `setup.sh --project` run on an already-installed project re-prompts for all six statusline components using each cached value as the displayed default instead of silently skipping.

## What Was Built

- `_prompt_with_default` helper in setup.sh: pure Bash, prints `[Y/n]` when current=true and `[y/N]` when current=false, maps Enter to the current value (no hard-coded true), accepts y|Y|n|N, falls back to current on anything else.
- Three-branch restructure of install_statusline Phase 2: non-interactive (preserve existing or write all-true defaults), fresh interactive (prompt with true defaults), already-installed interactive (re-prompt with cached values as defaults). --reconfigure-statusline forces the interactive branch when a TTY is present.
- Atomic write-back: the config heredoc now writes to `${sl_config_path}.tmp` and `mv`s into place so a crash mid-write cannot corrupt the cache JSON.
- New regression test (`tests/test-phase-48-statusline-reprompt.sh`, 12 assertions, all passing) that extracts `_prompt_with_default` from setup.sh and drives it directly, plus end-to-end --yes and --reconfigure + --yes coverage.
- Regenerated CHECKSUMS.sha256; `shasum -a 256 -c` passes for every entry.

## Files Modified

- `setup.sh` -- modified: added `_prompt_with_default` helper and rewired install_statusline Phase 2 into three branches with atomic write-back.
- `tests/test-phase-48-statusline-reprompt.sh` -- added: 12-assertion regression test covering Enter-preserves, y/n-flip, unrecognized-input-keeps-current, --yes-preserves-cache, and --reconfigure+--yes-preserves-values.
- `CHECKSUMS.sha256` -- modified: regenerated to reflect the updated setup.sh hash.
