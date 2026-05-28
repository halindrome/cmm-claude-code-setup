#!/usr/bin/env bash
# qwen-reviewer.sh — thin shim over gemma-reviewer.sh that runs the same
# second-opinion PR QA review against the locally-loaded Qwen model
# (default: qwen3-14b) instead of Gemma.
#
# Why a shim instead of a separate implementation:
# gemma-reviewer.sh already supports --model override and speaks the generic
# OpenAI-compatible chat-completions shape, so swapping the model name is
# sufficient. Post-processing rewrites "[gemma]" tags to "[qwen]" so the
# SKILL.md tag-merger stays unambiguous about which reviewer produced which
# finding. See qwen-reviewer.README.md for the delta from gemma-reviewer.

set -euo pipefail

# -------- defaults --------
LM_STUDIO_URL="${LM_STUDIO_URL:-http://localhost:1234/v1/chat/completions}"
QWEN_MODEL="${QWEN_MODEL:-qwen3-14b}"

# Qwen3 is a reasoning model — it consumes tokens in <think>…</think> before
# emitting any user-visible `content`. At the default 8192 ceiling used by
# gemma-reviewer.sh, full-diff prompts exhaust reasoning tokens and produce
# empty content. Local qwen3-14b has a 40960-token context; set a higher
# ceiling here so the delegated call to gemma-reviewer.sh uses it via the
# MAX_TOKENS env var. Override with QWEN_MAX_TOKENS if a specific PR needs
# more / less room.
QWEN_MAX_TOKENS="${QWEN_MAX_TOKENS:-24000}"

# Reasoning models are SLOWER than direct-completion models — they spend
# wall-clock time on `<think>…</think>` tokens before emitting visible
# content. Give the delegated call more headroom than Gemma's default so
# `curl --max-time` doesn't kill the connection mid-stream.
QWEN_TIMEOUT="${QWEN_TIMEOUT:-1200}"

# -------- arg parsing --------
MR=""
TARGET=""
ROUND=""
CONTRACT_FILE=""
SKIP_CONTRACT_FLAG=""
OUTPUT=""
ENDPOINT_OVERRIDE=""
MODEL_OVERRIDE=""

usage() {
  cat >&2 <<'USAGE'
Usage: qwen-reviewer.sh --mr <N> --target <name> --round <N> \
           --contract-file <path> [--skip-contract] --output <path> \
           [--endpoint URL] [--model NAME]

Thin shim over gemma-reviewer.sh. Defaults --model to $QWEN_MODEL
(default: qwen3-14b). Output tags are rewritten [gemma] -> [qwen].

Env:
  LM_STUDIO_URL   Chat-completions endpoint (default: http://localhost:1234/v1/chat/completions)
  QWEN_MODEL      Model name (default: qwen3-14b)

Exit codes: same as gemma-reviewer.sh (0 ok, 1 net, 2 empty, 3 lmstudio err, 64 bad args).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mr) MR="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --round) ROUND="$2"; shift 2 ;;
    --contract-file) CONTRACT_FILE="$2"; shift 2 ;;
    --skip-contract) SKIP_CONTRACT_FLAG="--skip-contract"; shift 1 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --endpoint) ENDPOINT_OVERRIDE="$2"; shift 2 ;;
    --model) MODEL_OVERRIDE="$2"; shift 2 ;;
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

# Resolve effective model + endpoint
EFFECTIVE_MODEL="${MODEL_OVERRIDE:-$QWEN_MODEL}"
EFFECTIVE_ENDPOINT="${ENDPOINT_OVERRIDE:-$LM_STUDIO_URL}"

# -------- canary --------
echo "[qwen] start ts=$(date -u +%Y-%m-%dT%H:%M:%SZ) mr=${MR} target=${TARGET} round=${ROUND} model=${EFFECTIVE_MODEL} endpoint=${EFFECTIVE_ENDPOINT}" >&2

TMP_OUT="$(mktemp)"
_qwen_cleanup() {
  local rc=$?
  rm -f "$TMP_OUT"
  echo "[qwen] end ts=$(date -u +%Y-%m-%dT%H:%M:%SZ) exit=${rc}" >&2
  return $rc
}
trap '_qwen_cleanup' EXIT

# Locate sibling gemma-reviewer.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEMMA="${SCRIPT_DIR}/gemma-reviewer.sh"
if [[ ! -x "$GEMMA" ]]; then
  echo "[qwen] ERROR: gemma-reviewer.sh not found or not executable at ${GEMMA}" >&2
  exit 1
fi

# Invoke gemma-reviewer.sh with our model + endpoint, capturing its output
# to a temp file. Stderr (including gemma's canary) passes through.
set +e
MAX_TOKENS="$QWEN_MAX_TOKENS" LM_STUDIO_TIMEOUT="$QWEN_TIMEOUT" "$GEMMA" \
  --mr "$MR" \
  --target "$TARGET" \
  --round "$ROUND" \
  --contract-file "$CONTRACT_FILE" \
  ${SKIP_CONTRACT_FLAG:+$SKIP_CONTRACT_FLAG} \
  --output "$TMP_OUT" \
  --endpoint "$EFFECTIVE_ENDPOINT" \
  --model "$EFFECTIVE_MODEL"
INNER_RC=$?
set -e

# Post-process: rewrite literal [gemma] -> [qwen] in the findings file,
# then move to the caller-requested output path. Use sed with a sentinel
# temp to preserve exit code on failure.
if [[ -s "$TMP_OUT" ]]; then
  sed 's/\[gemma\]/[qwen]/g' "$TMP_OUT" > "${OUTPUT}" || {
    echo "[qwen] ERROR: failed to rewrite gemma->qwen tags into ${OUTPUT}" >&2
    exit 1
  }
else
  # Inner wrapper produced an empty/missing file; mirror that to OUTPUT so
  # the caller sees the same emptiness the inner wrapper produced.
  : > "${OUTPUT}"
fi

exit "$INNER_RC"
