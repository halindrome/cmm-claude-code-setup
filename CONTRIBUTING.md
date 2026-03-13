# Contributing to cmm-claude-code-setup

Thanks for considering a contribution. This project is a hook-based enforcement layer for [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) + Claude Code, adapted from [Shachar Bard's jmunch-claude-code-setup](https://github.com/shacharbard/jmunch-claude-code-setup).

## Prerequisites

- Claude Code v1.0.33+
- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) installed and configured
- Familiarity with Claude Code hooks (SessionStart, PreToolUse, PostToolUse)

## Project Structure

```text
hooks/global/     Global hooks (soft enforcement, any project)
hooks/project/    Project hooks (hard gate, per-repo install)
rules/            Config templates and allowed-tools list
docs/             Setup guide and reference docs
benchmarks/       Token consumption benchmark suite
setup.sh          Interactive installer
codebase-memory-setup-guide.md  End-to-end setup guide
```

## Making Changes

1. **Fork the repo** and create a feature branch from `main` (e.g., `fix/gate-allow-list` or `feat/better-agent-prompt`). **Never commit directly to `main`**.
2. **Test locally** by installing the hooks into a real project and exercising the relevant code paths.
3. **Keep commits atomic** — one logical change per commit.
4. **Follow code style:**
   - Shell scripts: `#!/bin/bash` shebang, no external dependencies beyond `jq` and `python3`
   - Exit codes: `exit 2` = block tool call with message, `exit 0` = allow
   - Sentinel pattern: `/tmp/cmm-session-ready-$(echo "$PWD" | tr '/' '-')`
   - Commit format: `{type}({scope}): {description}` — types: feat, fix, docs, refactor, chore

## Pull Request Process

1. Open an issue first for non-trivial changes so we can discuss the approach.
2. Reference the issue in your PR.
3. Describe what changed and why. Include before/after hook behavior if relevant.
4. Test your changes against at least one real project.
5. **Run QA review before marking ready.** Repeat this cycle at least 2–4 times:

   > **Docs-only PRs:** The QA round requirement only applies when the PR touches hook scripts (`hooks/`), the installer (`setup.sh`), or rule templates (`rules/`). PRs that only change docs or repo metadata skip the check automatically.

   **Step A — Run the QA prompt.** Open a **new** Claude Code (or other AI) session using a top-tier model — **Claude Opus 4.6** or equivalent. Smaller models don't produce thorough enough reviews. Paste the prompt below (fill in the placeholders):

   ````text
   You are a read-only QA reviewer. Do NOT modify files, make commits, or push fixes — report only.

   PR: #<number>
   Branch: <branch-name>

   1. Review the commits in the PR to understand the change narrative.
   2. Read all files changed in the PR for full context.
   3. Act as a devil's advocate — find edge cases, missed regressions, and untested
      paths the implementer didn't consider. Pay particular attention to hook exit codes,
      sentinel race conditions, and allow-list gaps.

   Do NOT prescribe what to test upfront. Discover what matters by reading the code.

   Report format (use a markdown code block):
   - Model used:
   - What was tested
   - Expected vs actual
   - Severity (critical / major / minor)
   - Confirmed vs hypothetical
   ````

   **Step B — Fix the findings.** Copy the QA report and paste it into your original working session (or a new session on the same branch). Each QA round's fixes must be a **separate commit** — do not amend previous commits. Use the format `fix(scope): address QA round N`.

   **Step C — Repeat.** Go back to Step A with a fresh session. Continue until a round comes back clean or only has hypothetical/minor findings.

   **Proving your work:** Paste each round's QA report as a separate comment on the PR. Reviewers will cross-reference the reports against the fix commits in the PR history.

## Reporting Bugs

Open an issue with:
- Claude Code version (`claude --version`)
- The hook that failed and the tool call that triggered it
- The full hook error output (from Claude Code's hook error log)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
