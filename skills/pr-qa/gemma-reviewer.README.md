# gemma-reviewer.sh

Second-opinion PR QA reviewer via **local Gemma-3-e4b** running in LM Studio.
Invoked by `/pr-qa <PR> [TARGET] --double`; produces a findings file that
SKILL.md tag-merges with the Claude reviewer's output into a single PR
comment. Each finding is prefixed `[gemma]`.

---

## Prerequisites

1. **LM Studio** installed — https://lmstudio.ai
2. **Gemma-3-e4b model loaded** inside LM Studio. Model reference:
   https://lmstudio.ai/models/google/gemma-4-e4b (Google Gemma 3, ~4B
   effective, up to 128k context).
3. **Local server running** — LM Studio → *Developer* tab → *Start Server*.
   The default endpoint is `http://localhost:1234/v1/chat/completions`
   (OpenAI-compatible).
4. `curl`, `jq`, and `git` on `PATH`.
5. `gh` on `PATH` is optional; without it the PR description is omitted
   from the prompt but the review still runs from the diff + file contents.

## Environment variables

| Var | Default | Purpose |
|-----|---------|---------|
| `LM_STUDIO_URL` | `http://localhost:1234/v1/chat/completions` | Override the chat-completions endpoint (e.g., to point at a remote LM Studio instance). |
| `GEMMA_MODEL` | `gemma-3-e4b` | Override the model identifier sent in the request body. Must match the loaded model in LM Studio. |
| `MR_TARGET_BRANCH` | *(unset)* | If set, used as `origin/$MR_TARGET_BRANCH` for the diff base. SKILL.md exports this before invoking the wrapper. |

## Flags

| Flag | Required | Purpose |
|------|----------|---------|
| `--mr <N>` | yes | PR number (passed through to the prompt) |
| `--target <name>` | yes | Target key from `base-branches.json` (display only) |
| `--round <N>` | yes | Current QA round number |
| `--contract-file <path>` | yes | Path to a file containing the resolved contract block (GitHub issue AC or synthesized) |
| `--skip-contract` | no | When present, tells Gemma to skip the Contract Verification table |
| `--output <path>` | yes | Where to write the findings markdown |
| `--endpoint <url>` | no | Override `LM_STUDIO_URL` for this invocation |
| `--model <name>` | no | Override `GEMMA_MODEL` for this invocation |

## Canary logging

Immediately after argument validation — BEFORE any network work — the
wrapper emits a `[gemma] start …` line to **stderr** with the timestamp,
PR, target, round, model, endpoint, and `skip_contract` flag. On every
termination path an EXIT trap emits `[gemma] end ts=… exit=N`.

This makes silent-termination (0-byte stdout + 0-byte stderr) distinguishable
from empty-model-response (wrapper completed, LM Studio returned no content).
When troubleshooting from saved `/tmp/gemma-*.log` captures:

| Start line? | End line? | Interpretation |
|-------------|-----------|----------------|
| no          | no        | wrapper never ran (not executable, PATH issue, shell-level crash before `set -euo pipefail`) |
| yes         | no        | killed / SIGSEGV / `exec` replaced shell mid-run |
| yes         | yes, exit=0 | completed successfully; missing findings = empty model response, NOT a wrapper bug |
| yes         | yes, exit≠0 | wrapper exited with that code — cross-reference the Exit codes table below |

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success — findings written to `--output` |
| `1` | HTTP / network / curl failure (LM Studio unreachable) |
| `2` | Empty or malformed response (no `.choices[0].message.content`) |
| `3` | LM Studio returned a structured `.error` in the response body |
| `64` | Bad arguments |

SKILL.md treats **any non-zero exit** as a non-blocking Gemma failure: the
round continues with Claude-only findings and a `⚠ Gemma second-opinion
review failed` note is appended to the PR comment.

## Example invocation (manual)

```bash
cd .
git fetch origin
export MR_TARGET_BRANCH=develop
.claude/skills/pr-qa/gemma-reviewer.sh \
  --mr 42 \
  --target default \
  --round 1 \
  --contract-file /tmp/pr-42-contract.md \
  --output /tmp/pr-42-gemma.md
```

The normal invocation path is via `/pr-qa <PR> --double` — SKILL.md
builds the contract file, changes directory, and calls this script for you.

## Chunking

A rough byte-based heuristic (`~4 bytes/token`) targets a 120k-token budget
under Gemma-3-e4b's 128k ceiling (~8k headroom for framing + response).

1. If the combined prompt (diff + changed files + contract + framing) fits:
   single POST.
2. Otherwise: per-commit splits via `git rev-list BASE..HEAD`.
3. Otherwise: per-file splits within each commit.
4. Otherwise: truncate the offending file to head-200 + tail-100 lines and
   emit `[gemma] WARNING: truncated <file>` in the output.

## Limits / deferrals

- **No tool use.** Gemma-3-e4b does not reliably emit valid `tool_call` JSON
  on diff prompts, so this wrapper is text-in / text-out. Do not add `tools`
  / `tool_choice` to the payload.
- **Fail-open.** A Gemma failure never blocks the QA round; SKILL.md
  proceeds with Claude-only findings and notes the failure in the PR comment.
- **128k context ceiling.** Diffs that chunk down below per-file size still
  have individual file truncation as the last-resort fallback.
