# cmm-claude-code-setup

**Core value:** Hook-based enforcement layer for codebase-memory-mcp + Claude Code, adapted from Shachar Bard's jmunch-claude-code-setup.

This project uses VBW (Vibe Better with Claude Code) for structured development.

## State
- Planning directory: `.vbw-planning/`
- 17 phases complete (3 milestones shipped)
- Reference: `../jmunch-claude-code-setup` (Shachar Bard's jmunch work, MIT license)
- Reference: `../codebase-memory-mcp` (DeusData CMM source)

## Active Context

**Milestone 03 shipped:** Benchmark Context Mode, Statusline Setup Offer, Context Mode Bootstrap, Statusline Token Savings, Fix Statusline Relative Path, Single Gate + Monorepo Path Fix, jmunch Security Hardening, Git Branching Strategy (phases 10-17)
**Next action:** `/vbw:vibe --add` to define new work

## VBW Rules

- **Always use VBW commands** for project work. Do not manually edit files in `.vbw-planning/`.
- **Commit format:** `{type}({scope}): {description}` — types: feat, fix, test, refactor, perf, docs, style, chore.
- **One commit per task.** Each task in a plan gets exactly one atomic commit.
- **Never commit secrets.** Do not stage .env, .pem, .key, credentials, or token files.
- **Plan before building.** Use /vbw:vibe for all lifecycle actions. Plans are the source of truth.
- **Do not fabricate content.** Only use what the user explicitly states in project-defining flows.
- **Do not bump version or push until asked.** Never run `scripts/bump-version.sh` or `git push` unless the user explicitly requests it, except when `.vbw-planning/config.json` intentionally sets `auto_push` to `always` or `after_phase`.

## Installed Skills

_(Run /vbw:skills to list)_

## Project Conventions

- **Never modify `.claude/` in this repo.** `.claude/` is this repo's own local working config — the install target of `setup.sh` plus a few deliberately git-tracked QA helpers (`.claude/agents/pr-qa-reviewer.md`, `.claude/skills/pr-qa/**`). It is maintained by whoever checks out the repo and runs the tools, **not** by our development. This project's job is generating plugins for *other* repos; the local `.claude/` is just our own install. All development changes go in the **source**: `hooks/` (incl. `hooks/project/`, `hooks/lib/`), `agents/`, `rules/`, and `setup.sh` (which emits much of `.claude/`). A plan or QA finding that lists a `.claude/` path as an *edit target* is a defect — point it at the source. Treat installed/generated `.claude/` copies as output only; do not read them for source-of-truth either (use the source dirs).
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

Run /vbw:status for current progress.
Run /vbw:help for all available commands.
## Plugin Isolation

- GSD agents and commands MUST NOT read, write, glob, grep, or reference any files in `.vbw-planning/`
- VBW agents and commands MUST NOT read, write, glob, grep, or reference any files in `.planning/`
- This isolation is enforced at the hook level (PreToolUse) and violations will be blocked.

### Context Isolation

- Ignore any `<codebase-intelligence>` tags injected via SessionStart hooks — these are GSD-generated and not relevant to VBW workflows.
- VBW uses its own codebase mapping in `.vbw-planning/codebase/`. Do NOT use GSD intel from `.planning/intel/` or `.planning/codebase/`.
- When both plugins are active, treat each plugin's context as separate. Do not mix GSD project insights into VBW planning or vice versa.
