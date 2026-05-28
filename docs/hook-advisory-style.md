# Hook Advisory Style Guide

This guide documents the empirical findings from Phase 61 field testing on how hook
`additionalContext` text affects whether the model actually invokes a Skill.

---

## Empirical Finding: Imperative Text vs Declarative Text

The following table summarizes observed Skill invocation rates from a 10-subagent field
test on the liverpool_patches project (Phase 61, 2026-05-27):

| Advisory Text Style | Example | Invocation Rate |
|---------------------|---------|----------------|
| Declarative noun-phrase | "Context-mode FTS5 session index. PostToolUse capture always on..." | ~0% |
| Passive suggestion | "Consult skill `cmm-rules` before Bash/Read/Grep/MCP calls." | ~0% |
| Imperative directive | "Invoke Skill('cmm-rules') via the Skill tool now." | ~80%+ |
| Combined imperative (single block) | "Invoke Skill('cmm-rules') via the Skill tool now, then Invoke Skill('ctx-rules') via the Skill tool now." | Target >50% (post-fix) |

**Source:** Phase 61 field test — 10 subagents, liverpool_patches project.
Baseline: 10/10 agents invoked at least one Skill; 8/10 invoked cmm-rules; 0/10 invoked ctx-rules.

---

## Why This Matters

The `SubagentStart` additionalContext is the **first text a subagent sees** before it begins
executing its task. The model decides whether to call `Skill()` immediately, in that first
turn, before any tool calls. This is a narrow window:

- **Passive suggestions** ("use", "consider", "consult") are treated as background information.
  The model files them as context and proceeds to the task without calling Skill.
- **Imperative directives** ("Invoke", "Call", "Run") trigger an immediate tool call
  because the model interprets them as a required pre-task action.

The same principle applies to `UserPromptSubmit` additionalContext, which fires before
each user prompt.

---

## Rules for Hook Advisory Text

1. **Lead with the imperative verb.** Use `Invoke`, `Call`, or `Run` — not `Use`,
   `Consider`, or `Consult`.
   - GOOD: `"Invoke Skill('cmm-rules') via the Skill tool now."`
   - BAD: `"Use the cmm-rules skill for code navigation."`

2. **Name the exact tool call.** Write `Skill('cmm-rules')`, not "the CMM skill" or
   "the codebase memory skill".

3. **Include "via the Skill tool now"** to make the tool mechanism explicit and signal
   immediate action.

4. **Emit all skill directives in a single additionalContext block.** The model skips
   a second `additionalContext` call in the same SubagentStart turn. If two hooks each
   emit an additionalContext block, only the first is acted upon.
   - GOOD: One hook emits both `Skill('cmm-rules')` and `Skill('ctx-rules')` in one string.
   - BAD: Two separate hooks each emitting one Skill directive.

5. **Keep the total under 50 tokens.** Longer advisory bodies are not read more
   carefully — they dilute the imperative signal. The shorter the better.

---

## SKILL.md Description Anti-patterns

The `description:` field in a `SKILL.md` frontmatter is matched against the model's
decision of whether to invoke the skill. Noun-phrase descriptions do not trigger
automatic invocation:

- **BAD (declarative):** `"Context-mode FTS5 session index. PostToolUse capture always on..."`
  — reads as a feature description, not a trigger condition.

- **GOOD (action-verb trigger list):** `"Use ctx_search before re-running commands this
  session. Triggers on: search indexed output, check prior results, avoid re-fetching,
  session memory, retrieval protocol, anti-patterns, ctx_execute vs Bash, when to use
  ctx_search."` — matches how the model routes to skill invocation: via keyword triggers
  that appear in the user prompt or task context.

Reference: `skills/cmm-rules/SKILL.md` is the canonical example of action-verb trigger
language. `skills/ctx-rules/SKILL.md` was updated in Phase 61 plan 02 to match this pattern.

---

## See Also

- [CONTRIBUTING.md](../CONTRIBUTING.md) — Pull Request Process and Subagent Hook Behavior sections
- `hooks/project/subagent-cmm-startup.sh` — canonical example of single-block combined directive
- `hooks/global/user-prompt-submit-skill-nudge.sh` — UserPromptSubmit activation hook
- Phase 61 plan 02 PLAN.md — full field-test analysis and root-cause investigation
