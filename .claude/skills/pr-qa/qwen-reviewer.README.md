# qwen-reviewer.sh

Parallel second-opinion PR QA reviewer that drives a local Qwen model through
LM Studio's OpenAI-compatible chat-completions endpoint instead of Gemma.

## Purpose

Identical review role and taxonomy as `gemma-reviewer.sh` — just swaps the
model. Use this when you want a second open-weights reviewer, or when Gemma
is unavailable / returning degraded output. Findings are tagged `[qwen]`
instead of `[gemma]` so the SKILL.md tag-merger can attribute each finding.

## Prerequisites

- LM Studio running locally (default: `http://localhost:1234`)
- `qwen3-14b` loaded in LM Studio (or whatever `QWEN_MODEL` resolves to)
- Same host tooling as gemma-reviewer.sh: `curl`, `jq`, `git`, optionally `gh`

Verify with:

```bash
curl -sf http://localhost:1234/v1/models | jq '.data[].id'
```

## Env vars

| Var | Default | Notes |
|-----|---------|-------|
| `QWEN_MODEL` | `qwen3-14b` | Override via env or `--model`. |
| `LM_STUDIO_URL` | `http://localhost:1234/v1/chat/completions` | Shared with gemma-reviewer.sh. |

## Everything else

Flag set, exit codes, canary interpretation, chunking strategy, and contract
handling are identical to `gemma-reviewer.sh`. See
[`gemma-reviewer.README.md`](./gemma-reviewer.README.md) for those details.
The only observable difference at the output layer is that each finding
title and warning carries `[qwen]` rather than `[gemma]`.
