#!/bin/bash
# agent-override-generate.sh — SessionStart: generate/refresh VBW agent overrides
# Install: registered via hooks.SessionStart in settings.json (see setup.sh)
#
# Purpose: For each VBW agent (vbw-architect, vbw-debugger, vbw-dev, vbw-docs,
#          vbw-lead, vbw-qa, vbw-scout), generates or refreshes
#          PROJECT_ROOT/.claude/agents/vbw-<agent>.md by merging:
#            1. Base body from the resolved VBW source (VBW_AGENTS_DIR)
#            2. Our frontmatter patch (from agents/vbw-<agent>.md delta files)
#            3. Our cmm-delta fenced sections appended to the base body
#          SHA comparison drives idempotency — silent no-op when both SHAs match.
#          Fail-open on all errors. Advisory uses user-visible channel (systemMessage).
#
# V2 resolution: .claude/agents/*.md changes apply next session only.
#                Advisory explicitly says "restart session to apply."
#
# OUTPUT CHANNELS (doc-verified, code.claude.com/docs/en/hooks):
#   SessionStart stdout → Claude's context (NOT user-visible — do NOT use for advisories)
#   stderr              → shown to user only
#   JSON systemMessage  → warning message shown to user (preferred for restart advisory)
#
# Install: cp hooks/project/agent-override-generate.sh .claude/hooks/
#          chmod +x .claude/hooks/agent-override-generate.sh
# Register in .claude/settings.json:
#   "hooks": { "SessionStart": [{ "hooks": [{"type": "command",
#     "command": "bash .claude/hooks/agent-override-generate.sh"}] }] }

set -euo pipefail

# --- Project root detection (shared library with /tmp cache) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/../lib/project-root.sh"
source "${SCRIPT_DIR}/../lib/vbw-source.sh"

# ---------------------------------------------------------------------------
# SHA COMPUTATION UTILITIES
# ---------------------------------------------------------------------------

# _sha256 <text> — compute sha256 of text, print hex digest only
_sha256() {
  local text="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$text" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$text" | shasum -a 256 | awk '{print $1}'
  else
    echo "[agent-override-generate] WARN: no sha256 tool found; SHA stamping disabled" >&2
    echo "unavailable"
  fi
}

# ---------------------------------------------------------------------------
# compute_base_sha <agent_name>
#   Resolve the base body (frontmatter stripped) from $VBW_AGENTS_DIR/vbw-<agent>.md.
#   Prints sha256 hex; returns 1 if file not found.
# ---------------------------------------------------------------------------
compute_base_sha() {
  local agent_name="$1"
  local base_file="${VBW_AGENTS_DIR}/vbw-${agent_name}.md"
  if [ ! -f "$base_file" ]; then
    echo "[agent-override-generate] base file not found: $base_file" >&2
    return 1
  fi
  local body
  body=$(python3 - "$base_file" <<'PYEOF'
import sys, re
text = open(sys.argv[1]).read()
# Strip leading YAML frontmatter (---...---) if present
m = re.match(r'^---\n.*?\n---\n?', text, re.DOTALL)
if m:
    text = text[m.end():]
print(text, end='')
PYEOF
)
  _sha256 "$body"
}

# ---------------------------------------------------------------------------
# compute_delta_sha <agent_name>
#   Compute sha256 of the relevant delta content from
#   SCRIPT_DIR/../../agents/vbw-<agent>.md (frontmatter fields + cmm-delta sections).
#   Prints sha256 hex; returns 1 if file not found.
# ---------------------------------------------------------------------------
compute_delta_sha() {
  local agent_name="$1"
  # Delta file is at SCRIPT_DIR (hooks/project/) → ../../agents/ (repo root agents/)
  local delta_file="${SCRIPT_DIR}/../../agents/vbw-${agent_name}.md"
  delta_file="$(cd "$(dirname "$delta_file")" && pwd -P)/$(basename "$delta_file")" 2>/dev/null || true
  if [ ! -f "$delta_file" ]; then
    echo "[agent-override-generate] delta file not found: $delta_file" >&2
    return 1
  fi
  local content
  content=$(python3 - "$delta_file" <<'PYEOF'
import sys, re

text = open(sys.argv[1]).read()

# Extract YAML frontmatter block (between first --- delimiters)
fm_match = re.match(r'^---\n(.*?\n)---\n?', text, re.DOTALL)
fm_text = fm_match.group(1) if fm_match else ''

# Extract only our CMM-relevant frontmatter keys:
# hooks:, skills:, tools:, disallowedTools:, x-cmm-base-sha, x-cmm-delta-sha
# plus any keys not in the standard VBW set (our extensions)
VBW_BASE_KEYS = {'name', 'description', 'model', 'memory', 'permissionMode'}
our_keys = []
in_block = False
block_lines = []
current_key = None
for line in fm_text.splitlines():
    stripped = line.lstrip()
    if re.match(r'^[a-zA-Z_]', line):
        # Top-level key
        if in_block and current_key:
            our_keys.append((current_key, '\n'.join(block_lines)))
        key = line.split(':')[0].strip()
        if key not in VBW_BASE_KEYS:
            in_block = True
            current_key = key
            block_lines = [line]
        else:
            in_block = False
            current_key = None
            block_lines = []
    elif in_block:
        block_lines.append(line)
if in_block and current_key:
    our_keys.append((current_key, '\n'.join(block_lines)))

# Sort for determinism
our_keys.sort(key=lambda x: x[0])
fm_delta = '\n'.join(v for _, v in our_keys)

# Extract cmm-delta fenced sections from the body
body_part = text[fm_match.end():] if fm_match else text
delta_sections = re.findall(
    r'<!-- cmm-delta:begin[^>]*-->.*?<!-- cmm-delta:end[^>]*-->',
    body_part, re.DOTALL
)
delta_body = '\n'.join(delta_sections)

combined = fm_delta + '\n' + delta_body
print(combined, end='')
PYEOF
)
  _sha256 "$content"
}

# ---------------------------------------------------------------------------
# read_installed_shas <agent_name>
#   Read x-cmm-base-sha and x-cmm-delta-sha from the installed override file.
#   Prints: "<base_sha> <delta_sha>" or "missing missing" if not installed.
# ---------------------------------------------------------------------------
read_installed_shas() {
  local agent_name="$1"
  local installed="${PROJECT_ROOT}/.claude/agents/vbw-${agent_name}.md"
  if [ ! -f "$installed" ]; then
    echo "missing missing"
    return 0
  fi
  python3 - "$installed" <<'PYEOF'
import sys, re
text = open(sys.argv[1]).read()
fm_match = re.match(r'^---\n(.*?\n)---\n?', text, re.DOTALL)
if not fm_match:
    print('missing missing')
    sys.exit(0)
fm = fm_match.group(1)
base_sha = re.search(r'^x-cmm-base-sha:\s*"?([^"\n]+)"?', fm, re.MULTILINE)
delta_sha = re.search(r'^x-cmm-delta-sha:\s*"?([^"\n]+)"?', fm, re.MULTILINE)
bv = base_sha.group(1).strip() if base_sha else 'missing'
dv = delta_sha.group(1).strip() if delta_sha else 'missing'
# Treat empty string as missing
print((bv or 'missing') + ' ' + (dv or 'missing'))
PYEOF
}

# ---------------------------------------------------------------------------
# needs_regen <agent_name> <expected_base_sha> <expected_delta_sha>
#   Returns 0 (yes, regen needed) or 1 (no, SHAs match — skip).
# ---------------------------------------------------------------------------
needs_regen() {
  local agent_name="$1"
  local expected_base="$2"
  local expected_delta="$3"

  local installed_pair
  installed_pair=$(read_installed_shas "$agent_name")
  local installed_base installed_delta
  installed_base="${installed_pair%% *}"
  installed_delta="${installed_pair##* }"

  if [ "$installed_base" = "$expected_base" ] && [ "$installed_delta" = "$expected_delta" ]; then
    return 1  # SHAs match — no regen needed
  fi
  return 0  # regen needed
}
