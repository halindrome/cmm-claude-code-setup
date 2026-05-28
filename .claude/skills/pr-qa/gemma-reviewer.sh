#!/usr/bin/env bash
# gemma-reviewer.sh — second-opinion PR QA reviewer via local Gemma-3-e4b
# through LM Studio's OpenAI-compatible chat-completions endpoint.
#
# Invoked by /pr-qa when `--double` is passed. Produces a findings markdown
# file (same taxonomy as the Claude reviewer) with each finding title
# prefixed `[gemma]`. SKILL.md tag-merges Claude + Gemma findings into a
# single PR comment.
#
# ---------------------------------------------------------------------------
# TOOL-USE DEFERRED
# ---------------------------------------------------------------------------
# Gemma-3-e4b does NOT reliably emit valid tool_call JSON on diff prompts.
# This wrapper implements Shape A: feed the diff + concatenated changed-file
# contents as plain text and ask for findings in return. No read_file / grep /
# mcp tools are exposed to the model.
#
# A future phase may enable tool use IF Gemma-3-e4b crosses a 90% valid
# tool_call JSON bar on representative diff prompts. Until then, do NOT add
# `tools:` / `tool_choice:` to the POST payload — it will either be ignored
# or produce malformed JSON that breaks the pipeline.
# ---------------------------------------------------------------------------

set -euo pipefail

# -------- defaults --------
LM_STUDIO_URL="${LM_STUDIO_URL:-http://localhost:1234/v1/chat/completions}"
GEMMA_MODEL="${GEMMA_MODEL:-gemma-3-e4b}"

# 128k model ceiling; 120k token budget leaves ~8k headroom for system prompt
# framing + response. Byte-based heuristic: ~4 bytes/token → 480000 bytes.
TOKEN_BUDGET=120000
BYTE_BUDGET=$((TOKEN_BUDGET * 4))

# -------- arg parsing --------
MR=""
TARGET=""
ROUND=""
CONTRACT_FILE=""
SKIP_CONTRACT="false"
OUTPUT=""

usage() {
  cat >&2 <<'USAGE'
Usage: gemma-reviewer.sh --mr <N> --target <name> --round <N> \
           --contract-file <path> [--skip-contract] --output <path> \
           [--endpoint URL] [--model NAME]

Env:
  LM_STUDIO_URL   Override the chat-completions endpoint
                  (default: http://localhost:1234/v1/chat/completions)
  GEMMA_MODEL     Override the model name (default: gemma-3-e4b)

Exit codes:
  0  success
  1  HTTP / network / curl failure
  2  empty or malformed response (no .choices[0].message.content)
  3  LM Studio returned a structured error in the response body
  64 bad arguments
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mr) MR="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --round) ROUND="$2"; shift 2 ;;
    --contract-file) CONTRACT_FILE="$2"; shift 2 ;;
    --skip-contract) SKIP_CONTRACT="true"; shift 1 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --endpoint) LM_STUDIO_URL="$2"; shift 2 ;;
    --model) GEMMA_MODEL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 64 ;;
  esac
done

for v in MR TARGET ROUND CONTRACT_FILE OUTPUT; do
  if [[ -z "${!v:-}" ]]; then
    echo "Missing required arg: --${v,,}" >&2
    usage; exit 64
  fi
done

# -------- canary startup line --------
# Emit an unambiguous "wrapper is alive" line to stderr BEFORE any work, and
# arrange for an "exit=N" line on any termination path. Makes silent-termination
# (0-byte stdout + 0-byte stderr) distinguishable from empty-model-response
# (wrapper completed, LM Studio returned no content) during post-mortem.
echo "[gemma] start ts=$(date -u +%Y-%m-%dT%H:%M:%SZ) mr=${MR} target=${TARGET} round=${ROUND} model=${GEMMA_MODEL} endpoint=${LM_STUDIO_URL} skip_contract=${SKIP_CONTRACT}" >&2
_gemma_canary_end() {
  local rc=$?
  echo "[gemma] end ts=$(date -u +%Y-%m-%dT%H:%M:%SZ) exit=${rc}" >&2
  return $rc
}
trap '_gemma_canary_end' EXIT

if [[ ! -f "$CONTRACT_FILE" ]]; then
  echo "Contract file not found: $CONTRACT_FILE" >&2
  exit 64
fi

for bin in curl jq git; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Required binary not found on PATH: $bin" >&2
    exit 1
  fi
done

# -------- gather payload --------
# Determine the git base for the diff. Assume caller cd'd into the target
# worktree and has fetched the target remote. Fall back to origin/main.
BASE_REF="origin/main"
# Prefer the PR's tracked upstream-target if the caller exported it.
if [[ -n "${MR_TARGET_BRANCH:-}" ]]; then
  BASE_REF="origin/${MR_TARGET_BRANCH}"
fi

DIFF_FILE="$(mktemp)"
FILES_FILE="$(mktemp)"
CHANGED_LIST="$(mktemp)"
trap 'rm -f "$DIFF_FILE" "$FILES_FILE" "$CHANGED_LIST"; _gemma_canary_end' EXIT

git diff "${BASE_REF}..HEAD" > "$DIFF_FILE" 2>/dev/null || {
  echo "[gemma] ERROR: git diff ${BASE_REF}..HEAD failed" >&2
  exit 1
}

git diff --name-only "${BASE_REF}..HEAD" > "$CHANGED_LIST" 2>/dev/null || true

# PR description (best-effort; tolerate gh failures)
PR_DESC_FILE="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$DIFF_FILE' '$FILES_FILE' '$CHANGED_LIST' '$PR_DESC_FILE'; _gemma_canary_end" EXIT
if command -v gh >/dev/null 2>&1; then
  gh pr view "$MR" --json body --jq '.body // ""' > "$PR_DESC_FILE" 2>/dev/null || echo "" > "$PR_DESC_FILE"
else
  echo "" > "$PR_DESC_FILE"
fi

# Concatenate changed-file contents (filter: skip binaries + large generated).
# Keep text extensions the reviewer actually cares about.
{
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ ! -f "$f" ]] && continue
    case "$f" in
      *.png|*.jpg|*.jpeg|*.gif|*.ico|*.pdf|*.zip|*.tar|*.gz|*.bz2|*.xz) continue ;;
      *.lock|package-lock.json|yarn.lock|pnpm-lock.yaml) continue ;;
      */node_modules/*|*/dist/*|*/build/*|*/.next/*) continue ;;
    esac
    printf '\n===== FILE: %s =====\n' "$f"
    cat "$f"
  done < "$CHANGED_LIST"
} > "$FILES_FILE"

# -------- build reviewer prompt --------
# Mirrors the 4-axis finding taxonomy from .claude/agents/pr-qa-reviewer.md.
# Kept embedded here (rather than read-at-runtime) so the wrapper is
# self-contained and survives a missing/renamed agent file.
SYSTEM_PROMPT="You are a devil's-advocate PR reviewer. Assume every change is AI-generated slop until proven otherwise. You cannot open tools — you only see the diff, the changed-file contents, the PR description, and the contract below.

Produce findings using this 4-axis taxonomy:
  - contract     : a requirement from the contract is not met
  - regression   : a behavior that previously worked is now broken
  - observation  : a pre-existing bug visible in a file the PR touches
  - quality      : style / clarity / test-gap concerns

For each finding, emit a markdown block exactly like this:

### Finding N: <title>
- **Area:** \`<file>\` (lines X-Y)
- **Axis:** contract | regression | observation | quality
- **Expected:** <what should happen>
- **Actual / Risk:** <what you observed>
- **Severity:** critical | major | minor
- **Status:** confirmed | hypothetical

If no findings in this chunk, output exactly: ### No Issues Found

Contract verification: if skip_contract_verification is false, first produce a per-criterion table (satisfied / partially-satisfied / not-satisfied / not-applicable) with one row per acceptance criterion. If the contract block is 'SKIP' or skip_contract_verification is true, omit the table."

build_user_prompt() {
  local diff_chunk="$1"
  local files_chunk="$2"
  local contract
  if [[ "$SKIP_CONTRACT" == "true" ]]; then
    contract="SKIP"
  else
    contract="$(cat "$CONTRACT_FILE")"
  fi

  cat <<EOF
PR: #${MR}
Target: ${TARGET}
Round: ${ROUND}
skip_contract_verification: ${SKIP_CONTRACT}

## Contract
${contract}

## PR description
$(cat "$PR_DESC_FILE")

## Diff
\`\`\`diff
${diff_chunk}
\`\`\`

## Changed file contents
${files_chunk}
EOF
}

# -------- POST helper --------
post_to_lmstudio() {
  local user_prompt="$1"
  local payload
  payload=$(jq -n \
    --arg model "$GEMMA_MODEL" \
    --arg sys "$SYSTEM_PROMPT" \
    --arg usr "$user_prompt" \
    --argjson max_tokens "${MAX_TOKENS:-8192}" \
    '{model:$model, temperature:0.2, max_tokens:$max_tokens, messages:[{role:"system",content:$sys},{role:"user",content:$usr}]}')

  local http_code response_file
  response_file="$(mktemp)"
  # --http1.1: LM Studio's OpenAI-compatible endpoint hangs under HTTP/2
  # negotiation on some libcurl builds (observed on macOS). Pin HTTP/1.1.
  # --max-time: defense-in-depth bound; keeps the wrapper from hanging
  # forever if the server stops responding mid-stream.
  http_code=$(curl -sS --http1.1 --max-time "${LM_STUDIO_TIMEOUT:-900}" \
    -o "$response_file" -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -X POST "$LM_STUDIO_URL" \
    --data "$payload" 2>/dev/null || echo "000")

  if [[ "$http_code" == "000" ]] || [[ "$http_code" -ge 500 ]] || [[ "$http_code" -ge 400 && "$http_code" -lt 500 ]]; then
    echo "[gemma] ERROR: LM Studio POST failed (HTTP ${http_code}) at ${LM_STUDIO_URL}" >&2
    rm -f "$response_file"
    return 1
  fi

  # Structured error body?
  if jq -e '.error' "$response_file" >/dev/null 2>&1; then
    local err
    err=$(jq -r '.error.message // .error' "$response_file")
    echo "[gemma] ERROR: LM Studio returned error: ${err}" >&2
    rm -f "$response_file"
    return 3
  fi

  local content finish_reason reasoning
  content=$(jq -r '.choices[0].message.content // empty' "$response_file" 2>/dev/null || true)
  finish_reason=$(jq -r '.choices[0].finish_reason // "unknown"' "$response_file" 2>/dev/null || echo unknown)

  if [[ -z "$content" ]]; then
    # Reasoning-model fallback. When a reasoning model (qwen3, etc.) exhausts
    # its max_tokens inside `<think>` and never emits visible content, LM
    # Studio returns content="" with finish_reason="length" and the full
    # chain-of-thought under message.reasoning_content. Surface that as a
    # best-effort findings proxy rather than losing the whole review — with
    # a visible banner so the caller knows the output is raw reasoning, not
    # finalized findings.
    reasoning=$(jq -r '.choices[0].message.reasoning_content // empty' "$response_file" 2>/dev/null || true)
    if [[ -n "$reasoning" ]]; then
      echo "[gemma] NOTICE: content empty (finish_reason=${finish_reason}); falling back to reasoning_content. Consider raising MAX_TOKENS for this model." >&2
      content="> **⚠ Reasoning-content fallback** — the model produced no finalized \`content\` field (\`finish_reason=${finish_reason}\`). The text below is the raw chain-of-thought; treat as informational, not finalized findings.

${reasoning}"
    fi
  fi

  rm -f "$response_file"
  if [[ -z "$content" ]]; then
    echo "[gemma] ERROR: empty or malformed response (no .choices[0].message.content OR .reasoning_content)" >&2
    return 2
  fi

  printf '%s' "$content"
}

# -------- chunking --------
# Strategy:
#   1. Single POST if total byte size ≤ BYTE_BUDGET.
#   2. Else: per-commit splits via `git rev-list BASE..HEAD`.
#   3. Else: per-file splits within each commit.
#   4. Else: truncate a single over-budget file to head 200 + tail 100 lines
#      and emit "[gemma] WARNING: truncated <file>" in the output.

total_bytes() {
  # diff + files + contract + user-prompt framing overhead
  local d=$(wc -c < "$DIFF_FILE" | tr -d ' ')
  local f=$(wc -c < "$FILES_FILE" | tr -d ' ')
  local c=$(wc -c < "$CONTRACT_FILE" | tr -d ' ')
  echo $((d + f + c + 4096))
}

: > "$OUTPUT"
append_out() { printf '%s\n' "$1" >> "$OUTPUT"; }
append_out_tagged() {
  # Prefix each "### Finding" title with [gemma]
  sed -E 's/^### Finding ([0-9]+): /### Finding \1: [gemma] /' >> "$OUTPUT"
}

TOTAL=$(total_bytes)

run_single_pass() {
  local diff_chunk files_chunk user_prompt content
  diff_chunk=$(cat "$DIFF_FILE")
  files_chunk=$(cat "$FILES_FILE")
  user_prompt=$(build_user_prompt "$diff_chunk" "$files_chunk")
  if ! content=$(post_to_lmstudio "$user_prompt"); then
    return $?
  fi
  printf '%s' "$content" | append_out_tagged
}

run_per_commit() {
  local commits c diff_c files_c user_prompt content tmp_diff tmp_files
  commits=$(git rev-list --reverse "${BASE_REF}..HEAD")
  local any_ok=0
  for c in $commits; do
    tmp_diff="$(mktemp)"; tmp_files="$(mktemp)"
    git show --format= "$c" > "$tmp_diff" 2>/dev/null || true
    # Files changed in this commit
    {
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        [[ ! -f "$f" ]] && continue
        case "$f" in
          *.png|*.jpg|*.jpeg|*.gif|*.ico|*.pdf|*.zip|*.tar|*.gz|*.bz2|*.xz) continue ;;
        esac
        printf '\n===== FILE: %s (commit %s) =====\n' "$f" "$c"
        cat "$f"
      done < <(git diff-tree --no-commit-id --name-only -r "$c")
    } > "$tmp_files"

    local sz
    sz=$(( $(wc -c < "$tmp_diff") + $(wc -c < "$tmp_files") + 4096 ))
    if (( sz <= BYTE_BUDGET )); then
      diff_c=$(cat "$tmp_diff"); files_c=$(cat "$tmp_files")
      user_prompt=$(build_user_prompt "$diff_c" "$files_c")
      append_out ""
      append_out "<!-- gemma chunk: commit ${c} -->"
      if content=$(post_to_lmstudio "$user_prompt"); then
        printf '%s' "$content" | append_out_tagged
        any_ok=1
      else
        append_out "[gemma] WARNING: chunk failed for commit ${c}"
      fi
    else
      # Per-file within this commit
      run_per_file_in_commit "$c" "$tmp_diff" && any_ok=1 || true
    fi
    rm -f "$tmp_diff" "$tmp_files"
  done
  [[ $any_ok -eq 1 ]]
}

run_per_file_in_commit() {
  local c="$1" commit_diff="$2"
  local f content user_prompt sz tmp_files
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ ! -f "$f" ]] && continue
    tmp_files="$(mktemp)"
    printf '\n===== FILE: %s (commit %s) =====\n' "$f" "$c" > "$tmp_files"
    cat "$f" >> "$tmp_files"
    sz=$(( $(wc -c < "$tmp_files") + $(wc -c < "$commit_diff") + 4096 ))
    if (( sz > BYTE_BUDGET )); then
      # Truncate: head 200 + tail 100 lines
      {
        printf '\n===== FILE: %s (commit %s, TRUNCATED) =====\n' "$f" "$c"
        head -n 200 "$f"
        printf '\n... [TRUNCATED] ...\n'
        tail -n 100 "$f"
      } > "$tmp_files"
      append_out "[gemma] WARNING: truncated ${f}"
    fi
    user_prompt=$(build_user_prompt "$(cat "$commit_diff")" "$(cat "$tmp_files")")
    append_out ""
    append_out "<!-- gemma chunk: commit ${c} file ${f} -->"
    if content=$(post_to_lmstudio "$user_prompt"); then
      printf '%s' "$content" | append_out_tagged
    else
      append_out "[gemma] WARNING: chunk failed for ${f} in ${c}"
    fi
    rm -f "$tmp_files"
  done < <(git diff-tree --no-commit-id --name-only -r "$c")
}

if (( TOTAL <= BYTE_BUDGET )); then
  append_out "<!-- gemma single-pass review (${TOTAL} bytes, budget ${BYTE_BUDGET}) -->"
  run_single_pass
else
  append_out "<!-- gemma chunked review (${TOTAL} bytes > budget ${BYTE_BUDGET}) -->"
  run_per_commit || {
    echo "[gemma] ERROR: all chunks failed" >&2
    exit 1
  }
fi

exit 0
