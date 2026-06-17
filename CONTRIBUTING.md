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

1. **Fork the repo** and create a feature branch from `develop` (e.g., `fix/gate-allow-list` or `feat/better-agent-prompt`). **Never commit directly to `develop` or `main`**.
2. **Test locally** by installing the hooks into a real project and exercising the relevant code paths.
3. **Keep commits atomic** — one logical change per commit.
4. **Follow code style:**
   - Shell scripts: `#!/bin/bash` shebang, no external dependencies beyond `jq` and `python3`
   - Exit codes: `exit 2` = block tool call with message, `exit 0` = allow
   - Sentinel pattern: `/tmp/cmm-session-ready-<project-root-md5hash>` (hash computed by `session-gate.sh`)
   - Commit format: `{type}({scope}): {description}` — types: feat, fix, docs, refactor, chore

## Branch Model

```
feature/my-work
      │
      ▼  PR → develop
   develop
      │
      ▼  PR → main (version bump required)
    main  ◄── tagged vX.Y.Z
```

| Branch | Base | Target | Rules |
|--------|------|---------|-------|
| `feature/*` | `develop` | `develop` | One feature per branch |
| `develop` | — | `main` | All tests pass |
| `main` | — | — | Version bump required; tagged on merge |

## Pull Request Process

1. Open an issue first for non-trivial changes so we can discuss the approach.
2. Reference the issue in your PR.
3. Describe what changed and why. Include before/after hook behavior if relevant.
4. Test your changes against at least one real project.
5. **Run QA review before marking ready.** Repeat this cycle at least 2–4 times:

   > **Docs-only PRs:** The QA round requirement only applies when the PR touches hook scripts (`hooks/`), the installer (`setup.sh`), rule templates (`rules/`), or agent definitions (`agents/`, including agent frontmatter installed under `.claude/agents/`). PRs that only change docs or repo metadata skip the check automatically.

   **Step A — Run the QA prompt.** Open a **new** Claude Code (or other AI) session using a top-tier model — **Claude Opus 4.6** or equivalent. Smaller models don't produce thorough enough reviews. Paste the prompt below (fill in the placeholders):

   > **Agent gate:** This project's `agent-cmm-gate.sh` hook blocks Agent tool calls whose prompt does not reference codebase-memory-mcp tools. The QA prompt below includes the required CMM tool instructions. If you run QA via an Agent subagent, you must include them or the hook will reject the call.

   ````text
   You are a read-only QA reviewer. Do NOT modify files, make commits, or push fixes — report only.

   PR: #<number>
   Branch: <branch-name>

   Use codebase-memory-mcp (CMM) tools for code exploration. Available tools:

   1. search_graph — Find functions/classes by name pattern, filter by degree
      Example: search_graph(name_pattern=".*Handler.*", label="Function")

   2. get_code_snippet — Retrieve source code for a function/class by name
      Example: get_code_snippet(qualified_name="main.HandleRequest")

   3. trace_path — Trace who calls a function and what it calls
      Example: trace_path(function_name="ProcessOrder", direction="both")

   4. get_architecture — Get codebase architecture overview
      Example: get_architecture(aspects=["packages", "hotspots"])

   5. query_graph — Execute Cypher-like graph queries
      Example: query_graph(query="MATCH (f:Function)-[:CALLS]->(g:Function) WHERE f.name = 'main' RETURN g.name LIMIT 20")

   6. detect_changes — Map uncommitted changes to affected graph symbols
      Example: detect_changes(scope="all")

   7. index_repository — Index or refresh the code graph
      Example: index_repository()

   Workflow: search_graph → trace_path → get_code_snippet
   Prefer these over Read/Grep for understanding code structure and relationships.

   1. Review the commits in the PR to understand the change narrative.
   2. Read all files changed in the PR for full context (use CMM tools first to
      understand structure, then Read for full file context where needed).
   3. Act as a devil's advocate — find edge cases, missed regressions, and untested
      paths the implementer didn't consider. Pay particular attention to hook exit codes,
      sentinel race conditions, and allow-list gaps.

   Do NOT prescribe what to test upfront. Discover what matters by reading the code.

   Post your report directly as markdown (do NOT wrap it in a code block — plain
   markdown renders correctly in GitHub PR comments; a code block prevents formatting):

   ## QA Report — PR #<number> (<brief description>)

   **Model used:** <model>

   ### What Was Tested
   <bullet list of areas reviewed>

   ### Findings
   <per-finding subsections with severity and confirmed/hypothetical label>

   ### Overall Recommendation
   PASS / PASS with minor notes / Needs fixes
   ````

   **Step B — Fix the findings.** Copy the QA report and paste it into your original working session (or a new session on the same branch). Each QA round's fixes must be a **separate commit** — do not amend previous commits. Use the format `fix(scope): address QA round N`.

   **Step C — Repeat.** Go back to Step A with a fresh session. Continue until a round comes back clean or only has hypothetical/minor findings.

   **Proving your work:** Paste each round's QA report as a separate comment on the PR. Reviewers will cross-reference the reports against the fix commits in the PR history.

## Subagent Hook Behavior

Claude Code project-level hooks (defined in `.claude/settings.json`) fire inside subagents automatically. This means `session-gate.sh`, `cmm-query-stale-advisory.sh`, `track-cmm-calls.sh`, and `reindex-after-commit.sh` all run inside Dev, Scout, QA, and Lead agents without any extra configuration.

### The SUBAGENT_COMMIT Bypass

`reindex-after-commit.sh` skips writing the stale sentinel when running inside a VBW team session (detected via `$CLAUDE_CONFIG_DIR/teams/vbw-*` directories). This prevents a commit in one worktree from cascade-stalling parallel agents.

The Dev agent is the exception: Dev commits **should** mark the sentinel stale, because Scout and QA agents need to know the graph is outdated. `.claude/agents/dev.md` adds a PostToolUse:Bash frontmatter hook that sets `SUBAGENT_COMMIT=1` before invoking `reindex-after-commit.sh`. When this env var is set, the team-mode check is skipped and the stale marker is written.

If you add a new agent that makes commits, create `.claude/agents/<name>.md` with the same `SUBAGENT_COMMIT=1` hook:

```yaml
hooks:
  PostToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "SUBAGENT_COMMIT=1 bash .claude/hooks/reindex-after-commit.sh"
```

### SubagentStart Advisory

The `SubagentStart` hook in `.claude/settings.json` fires in the **parent session** (not inside the subagent) when any subagent starts. It runs `subagent-cmm-startup.sh`, which injects CMM index state into the subagent via `additionalContext` JSON output — telling the agent whether the index is ready or stale before it begins work. This is informational only — it never blocks the agent.

SubagentStart hooks cannot intercept tool calls inside the subagent. Use agent frontmatter hooks (`.claude/agents/<name>.md`) for ongoing per-tool enforcement.

### Hook Advisory Style

The wording of `additionalContext` text in SubagentStart and UserPromptSubmit hooks has a measurable impact on whether the model actually invokes a Skill. Imperative directives ("Invoke Skill('cmm-rules') via the Skill tool now") yield 80%+ activation rates; passive suggestions ("Consult skill X") yield ~0%.

See **[docs/hook-advisory-style.md](docs/hook-advisory-style.md)** for the full empirical finding, the 5 rules for hook advisory text, and SKILL.md description anti-patterns.

### Requirements

- Agent frontmatter hooks require **Claude Code v1.0.33+**. On older versions, hooks in `.claude/agents/` are silently ignored. The agent still works; only the `SUBAGENT_COMMIT=1` bypass is lost.
- `.claude/agents/dev.md` is project-specific and **not copied by `setup.sh`**. Users installing this hook layer into their own project should create their own `.claude/agents/` overrides if needed.

### Adding Custom Subagent Hooks

#### Why PostToolUse:Agent Instead of SubagentStop

Claude Code's `SubagentStop` lifecycle event has several reliability gaps that make it unsuitable for critical hook logic (see `docs/setup-guide.md` for full issue details):

- **SubagentStop doesn't fire on `maxTurns`** — the last tool call's hook is silently skipped.
- **SubagentStop doesn't fire on session degradation** — connections that time out after ~2.5h don't trigger cleanup.
- **SubagentStop can't identify which agent stopped** — no `subagent_type` field is available in the event.
- **Prompt-based SubagentStop hooks can't prevent termination** — the subagent receives feedback but gets no turn to respond ([#20221](https://github.com/anthropics/claude-code/issues/20221), closed as "not planned").

**For any logic that must run when a subagent completes, use `PostToolUse:Agent` instead.** This event fires in the parent session after the Agent tool returns, regardless of how the subagent terminated. It receives the full tool result, including `session_id` and exit status.

#### Adding a Hook to settings.json

Register a PostToolUse:Agent hook in `.claude/settings.json`:

```json
{
  "PostToolUse": [
    {
      "matcher": "Agent",
      "hooks": [
        {
          "type": "command",
          "command": "bash /absolute/path/to/your-hook.sh",
          "_comment": "Describe what this hook does"
        }
      ]
    }
  ]
}
```

Requires Claude Code **v1.0.33** or later.

The hook script receives the PostToolUse:Agent event JSON on stdin. Key fields:

| Field | Description |
|-------|-------------|
| `session_id` | Session identifier (correlate with SubagentStart records) |
| `tool_result` | Output returned by the subagent |
| `tool_result.stop_reason` | How the agent stopped: `end_turn`, `error_max_turns`, etc. |

Example hook to detect Dev agent maxTurns:

```bash
#!/bin/bash
EVENT=$(cat)
STOP_REASON=$(echo "$EVENT" | jq -r '.tool_result.stop_reason // empty')
if [ "$STOP_REASON" = "error_max_turns" ]; then
    echo "Warning: Dev agent hit maxTurns — graph may not be marked stale." >&2
fi
exit 0
```

#### Adding a Hook via Agent Frontmatter

Agent-specific hooks can be defined in the agent's `.claude/agents/<name>.md` frontmatter. This is how the Dev agent bypasses team-mode suppression:

```yaml
---
name: dev
hooks:
  PostToolUse:
    - matcher: Bash
      command: "SUBAGENT_COMMIT=1 bash .claude/hooks/reindex-after-commit.sh"
---
```

Step-by-step to add a custom PostToolUse:Agent hook to an agent:

1. Open `.claude/agents/<your-agent>.md`
2. Add a `hooks` block to the YAML frontmatter:
   ```yaml
   hooks:
     PostToolUse:
       - matcher: Agent
         command: "bash .claude/hooks/your-custom-hook.sh"
   ```
3. Create `.claude/hooks/your-custom-hook.sh` — must exit 0 for advisory hooks, exit 2 only if you want to block (block applies to the tool call, not to agent termination)
4. Copy the hook to `hooks/project/` as the canonical source:
   ```bash
   cp .claude/hooks/your-custom-hook.sh hooks/project/your-custom-hook.sh
   ```
5. Both copies must be kept in sync. The `hooks/project/` directory is the source of truth for version control.

#### Hook Exit Codes

| Exit Code | Effect |
|-----------|--------|
| `0` | Advisory — hook ran, no action taken |
| `2` | Block — prevents the tool call (PreToolUse only; PostToolUse exit 2 is ignored) |

For SubagentStop quality gates: **only command-based hooks that exit 2 can gate agent termination.** Prompt-based hooks returning `{"ok": false}` do not prevent termination (Issue #20221).

## Reporting Bugs

Open an issue with:
- Claude Code version (`claude --version`)
- The hook that failed and the tool call that triggered it
- The full hook error output (from Claude Code's hook error log)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
