# cmm-claude-code-setup

**Core value:** Hook-based enforcement layer that makes Claude Code use codebase-memory-mcp (CMM) as the core code-intelligence tool, adapted from Shachar Bard's jmunch-claude-code-setup. Context Mode and VBW are optional, auto-detected add-ons — CMM is the thing this repo exists to enforce.

VBW (Vibe Better with Claude Code) is **optional/legacy** for this repo's own workflow. Historical development used VBW; it is no longer required. Use it if a VBW plugin tree is available, otherwise develop directly following the rules below.

## State
- Planning directory (VBW, optional/legacy): `.vbw-planning/` if present. Non-VBW setup state lives under `.claude/.cmm-setup/`.
- 17 phases complete (3 milestones shipped)
- Reference: `../jmunch-claude-code-setup` (Shachar Bard's jmunch work, MIT license)
- Reference: `../codebase-memory-mcp` (DeusData CMM source)

## Active Context

**Milestone 03 shipped:** Benchmark Context Mode, Statusline Setup Offer, Context Mode Bootstrap, Statusline Token Savings, Fix Statusline Relative Path, Single Gate + Monorepo Path Fix, jmunch Security Hardening, Git Branching Strategy (phases 10-17)
**Next action:** define new work — via `/vbw:vibe --add` if VBW is in use, otherwise plan directly.

## Development Rules

These apply to all work in this repo, VBW or not.

- **Commit format:** `{type}({scope}): {description}` — types: feat, fix, test, refactor, perf, docs, style, chore.
- **One commit per task.** Each task gets exactly one atomic commit.
- **Never commit secrets.** Do not stage .env, .pem, .key, credentials, or token files.
- **Do not fabricate content.** Only use what the user explicitly states.
- **Do not bump version or push until asked.** Never run `scripts/bump-version.sh` or `git push` unless the user explicitly requests it, except when a VBW `config.json` intentionally sets `auto_push` to `always` or `after_phase`.

### VBW workflow (optional/legacy)

When VBW is in use for this repo:

- Prefer VBW commands (`/vbw:vibe`) for lifecycle actions; plans are the source of truth. Do not manually edit files in `.vbw-planning/`.
- Without VBW, develop directly — there is no requirement to route work through VBW commands.

## Installed Skills

_(Run /vbw:skills to list)_

## Project Conventions

- Bash hooks: shebang `#!/bin/bash`, one-line purpose comment, install/register instructions at top
- Exit codes: `exit 2` = block tool call with message, `exit 0` = allow
- Sentinel pattern: `/tmp/cmm-session-ready-<project-root-md5hash>` for session gate
- Attribution: Shachar Bard (shacharbard) cited at top of README as inspiration for structure
- Language list: derive from CMM source when possible, use a shared config/extension list
- jmunch equivalents: jCodeMunch → CMM graph tools; jDocMunch → CMM search_code/get_code_snippet

## Pull Request QA (Required)

Before marking any PR ready for review, follow the QA cycle defined in `CONTRIBUTING.md § Pull Request Process`. The process requires 2–4 rounds of:

1. **QA round** — Open a **new** Claude Code session with **Opus-class model**. Use the read-only QA prompt from CONTRIBUTING.md (fill in PR number and branch). Do NOT fix issues in the QA session.
2. **Fix round** — Apply fixes in a separate commit (`fix(scope): address QA round N`). Never amend previous commits.
3. **Repeat** — Fresh QA session each round until findings are clean or only minor/hypothetical.
4. **Post reports** — Paste each round's QA report as a separate PR comment.

> **Skip condition:** Docs-only PRs (no changes to `hooks/`, `setup.sh`, `rules/`, or `agents/`) skip the QA cycle.

## Merge Requirements

- **Version bump required for releases.** Every release merged into `main` must include a version number increase. Bump the version as the final commit before merge — use `scripts/bump-version.sh` if it exists, or update the version file directly. Follow semver: breaking changes → major, new features → minor, fixes → patch. Tag `vX.Y.Z` on the merge commit after it lands on `main`.

## Branch Model

| Branch | Purpose |
|--------|---------|
| `develop` | Active development. Feature branches merge here first. |
| `main` | Stable releases. Every merge from `develop` requires a version bump and is tagged `vX.Y.Z`. |
| `feature/*` | Short-lived work branches. Base from `develop`, PR to `develop`. |

**Release flow:** `feature/* → develop → main` (tagged)

## Commands

If VBW is in use: run /vbw:status for current progress and /vbw:help for all available commands. These commands are unavailable (and unnecessary) when VBW is not installed.

## Plugin Isolation

Applies only when VBW and/or GSD plugins are active; ignore if neither is installed.

- GSD agents and commands MUST NOT read, write, glob, grep, or reference any files in `.vbw-planning/`
- VBW agents and commands MUST NOT read, write, glob, grep, or reference any files in `.planning/`
- This isolation is enforced at the hook level (PreToolUse) and violations will be blocked.

### Context Isolation

- Ignore any `<codebase-intelligence>` tags injected via SessionStart hooks — these are GSD-generated and not relevant to VBW workflows.
- VBW uses its own codebase mapping in `.vbw-planning/codebase/`. Do NOT use GSD intel from `.planning/intel/` or `.planning/codebase/`.
- When both plugins are active, treat each plugin's context as separate. Do not mix GSD project insights into VBW planning or vice versa.
