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

set -uo pipefail
# NOTE: -e (errexit) is intentionally omitted. This hook runs at SessionStart;
# a non-zero exit would abort the session. All paths must fail-open (exit 0).
# Per-command failures are handled explicitly with || { ...; } guards.

# Safety net: ensure the script always exits 0 even on unexpected errors.
trap 'exit 0' ERR

# --- Project root detection (shared library with /tmp cache) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# Lib resolution: installed at .claude/hooks/lib/ (sibling lib/ subdir), same
# pattern as session-gate.sh / cmm-sentinel-writer.sh.
_LIB_DIR="${SCRIPT_DIR}/lib"
if [ -f "${_LIB_DIR}/project-root.sh" ]; then
  source "${_LIB_DIR}/project-root.sh"
else
  # Fallback for running from repo source (hooks/project/ → hooks/lib/)
  source "${SCRIPT_DIR}/../lib/project-root.sh" 2>/dev/null || true
fi
if [ -f "${_LIB_DIR}/vbw-source.sh" ]; then
  source "${_LIB_DIR}/vbw-source.sh"
else
  source "${SCRIPT_DIR}/../lib/vbw-source.sh" 2>/dev/null || true
fi

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
# resolve_delta_path <agent_name>
#   Locate the delta file for the given agent using a two-level resolution order:
#     1. INSTALLED: ${SCRIPT_DIR}/../agents-delta/vbw-<agent>.md
#        The hook lives at .claude/hooks/; agents-delta/ is always the sibling dir.
#        This path is SCRIPT_DIR-relative so it works regardless of pwd/PROJECT_ROOT
#        resolution, and does NOT require the cmm-claude-code-setup repo checked out
#        (curl|bash-ready install).
#     2. DEV FALLBACK: ${SCRIPT_DIR}/../../agents/vbw-<agent>.md
#        In-repo source; only works when cmm-claude-code-setup is the repo hosting
#        these hooks (i.e., the hook runs from the repo's hooks/project/ dir).
#   Prints the resolved absolute path and returns 0, or returns 1 if neither exists.
# ---------------------------------------------------------------------------
resolve_delta_path() {
  local agent_name="$1"
  # 1. Installed path (preferred — SCRIPT_DIR-relative, curl|bash-ready)
  #    SCRIPT_DIR = .claude/hooks/  →  ../agents-delta/ = .claude/agents-delta/
  local installed_delta="${SCRIPT_DIR}/../agents-delta/vbw-${agent_name}.md"
  if [ -f "$installed_delta" ]; then
    echo "$installed_delta"
    return 0
  fi
  # 2. Dev fallback (in-repo source when hook runs from hooks/project/)
  local repo_delta="${SCRIPT_DIR}/../../agents/vbw-${agent_name}.md"
  local canon_repo_delta
  canon_repo_delta="$(cd "$(dirname "$repo_delta")" 2>/dev/null && pwd -P)/$(basename "$repo_delta")" 2>/dev/null || true
  if [ -f "${canon_repo_delta:-}" ]; then
    echo "$canon_repo_delta"
    return 0
  fi
  return 1
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
  # Delta resolution order: installed (.claude/agents-delta/) → dev fallback (repo agents/)
  local delta_file
  delta_file=$(resolve_delta_path "$agent_name") || {
    echo "[agent-override-generate] delta file not found for $agent_name (checked .claude/agents-delta/ and repo agents/)" >&2
    return 1
  }
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

# ---------------------------------------------------------------------------
# MERGE FUNCTION
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# generate_override <agent_name> <base_sha> <delta_sha>
#   Merges base VBW body + our delta frontmatter + cmm-delta sections.
#   Writes to PROJECT_ROOT/.claude/agents/vbw-<agent_name>.md.
#   Returns 0 on success, 1 on failure (caller skips and continues).
# ---------------------------------------------------------------------------
generate_override() {
  local agent_name="$1"
  local base_sha="$2"
  local delta_sha="$3"

  local base_file="${VBW_AGENTS_DIR}/vbw-${agent_name}.md"
  local out_file="${PROJECT_ROOT}/.claude/agents/vbw-${agent_name}.md"

  if [ ! -f "$base_file" ]; then
    echo "[agent-override-generate] WARN: base file missing: $base_file — skipping $agent_name" >&2
    return 1
  fi

  # Delta resolution order: installed (.claude/agents-delta/) → dev fallback (repo agents/)
  local delta_file
  delta_file=$(resolve_delta_path "$agent_name") || {
    echo "[agent-override-generate] WARN: delta file missing for $agent_name — skipping" >&2
    return 1
  }

  # Perform the merge via Python (keeps complex YAML/regex logic out of bash)
  local merged
  merged=$(python3 - "$base_file" "$delta_file" "$agent_name" "$base_sha" "$delta_sha" <<'PYEOF'
import sys, re

base_path   = sys.argv[1]
delta_path  = sys.argv[2]
agent_name  = sys.argv[3]
base_sha    = sys.argv[4]
delta_sha   = sys.argv[5]

base_text  = open(base_path).read()
delta_text = open(delta_path).read()

# ---------------------------------------------------------------------------
# 1. Parse base frontmatter and body
# ---------------------------------------------------------------------------
base_fm_match = re.match(r'^---\n(.*?\n)---\n?', base_text, re.DOTALL)
if base_fm_match:
    base_fm_raw = base_fm_match.group(1)
    base_body   = base_text[base_fm_match.end():]
else:
    base_fm_raw = ''
    base_body   = base_text

def parse_fm(text):
    """Return ordered list of (key, raw_block) pairs from YAML frontmatter text."""
    result = []
    current_key = None
    current_lines = []
    for line in text.splitlines():
        if re.match(r'^[a-zA-Z_]', line):
            if current_key is not None:
                result.append((current_key, '\n'.join(current_lines)))
            current_key = line.split(':')[0].strip()
            current_lines = [line]
        else:
            if current_key is not None:
                current_lines.append(line)
    if current_key is not None:
        result.append((current_key, '\n'.join(current_lines)))
    return result

base_fm_pairs = parse_fm(base_fm_raw)
base_fm = dict(base_fm_pairs)

# ---------------------------------------------------------------------------
# 2. Parse delta frontmatter
# ---------------------------------------------------------------------------
delta_fm_match = re.match(r'^---\n(.*?\n)---\n?', delta_text, re.DOTALL)
delta_fm_raw = delta_fm_match.group(1) if delta_fm_match else ''
delta_body_part = delta_text[delta_fm_match.end():] if delta_fm_match else delta_text

delta_fm_pairs = parse_fm(delta_fm_raw)
delta_fm = dict(delta_fm_pairs)

# ---------------------------------------------------------------------------
# 3. Build merged frontmatter
#    - Preserve from base: name, description, model, memory, permissionMode
#    - Take from delta (our CMM extensions): hooks, skills, tools/disallowedTools,
#      x-cmm-base-sha, x-cmm-delta-sha, plus any other our-only keys
#    - Frontmatter tool-grant merge rule:
#        If delta has disallowedTools → use disallowedTools, drop base tools:
#        If delta has tools:          → use tools:, drop base disallowedTools:
#    - Stamp x-cmm-base-sha and x-cmm-delta-sha with computed values
# ---------------------------------------------------------------------------
BASE_PRESERVE_KEYS = ['name', 'description', 'model', 'memory', 'permissionMode']
TOOL_GRANT_KEYS    = {'tools', 'disallowedTools'}

merged_fm_lines = []

# Preserved base keys (in declaration order)
for key in BASE_PRESERVE_KEYS:
    if key in base_fm:
        merged_fm_lines.append(base_fm[key])

# Tool-grant merge rule: delta wins, one key only
if 'disallowedTools' in delta_fm:
    merged_fm_lines.append(delta_fm['disallowedTools'])
elif 'tools' in delta_fm:
    merged_fm_lines.append(delta_fm['tools'])
elif 'disallowedTools' in base_fm:
    merged_fm_lines.append(base_fm['disallowedTools'])
elif 'tools' in base_fm:
    merged_fm_lines.append(base_fm['tools'])

# Our CMM-extension keys from delta (hooks, skills, x-cmm-*, and anything else)
OUR_EXTENSION_KEYS = set(delta_fm.keys()) - {'name', 'description', 'model', 'memory',
                                               'permissionMode', 'x-cmm-base-sha',
                                               'x-cmm-delta-sha'} - TOOL_GRANT_KEYS
# Output in original delta order
for key, block in delta_fm_pairs:
    if key in OUR_EXTENSION_KEYS:
        merged_fm_lines.append(block)

# Stamp SHAs (always regenerated)
merged_fm_lines.append(f'x-cmm-base-sha: "{base_sha}"')
merged_fm_lines.append(f'x-cmm-delta-sha: "{delta_sha}"')

merged_fm = '\n'.join(merged_fm_lines)

# ---------------------------------------------------------------------------
# 4. Extract cmm-delta fenced sections from the delta body
# ---------------------------------------------------------------------------
delta_sections = re.findall(
    r'<!-- cmm-delta:begin[^>]*-->.*?<!-- cmm-delta:end[^>]*-->',
    delta_body_part, re.DOTALL
)
delta_appended = '\n'.join(delta_sections)

# ---------------------------------------------------------------------------
# 5. Build output
#    Header comment → frontmatter → generated banner → base body → delta sections
# ---------------------------------------------------------------------------
lines = []
lines.append('---')
lines.append(merged_fm)
lines.append('---')
lines.append('')
lines.append('<!-- GENERATED by agent-override-generate.sh — do not edit manually.')
lines.append('     Run setup.sh --project or restart session to regenerate. -->')
lines.append('')
# Base body (already stripped of its own frontmatter above)
base_body_stripped = base_body.lstrip('\n')
lines.append(base_body_stripped.rstrip('\n'))
if delta_appended:
    lines.append('')
    lines.append(delta_appended)
lines.append('')

print('\n'.join(lines), end='')
PYEOF
) || {
    echo "[agent-override-generate] ERROR: merge failed for $agent_name" >&2
    return 1
  }

  mkdir -p "${PROJECT_ROOT}/.claude/agents"
  local tmp_out="${out_file}.tmp.$$"
  printf '%s' "$merged" > "$tmp_out"
  mv "$tmp_out" "$out_file"
}

# ---------------------------------------------------------------------------
# MANUAL-EDIT DETECTION
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# manual_edit_detected <agent_name> <base_sha> <delta_sha>
#   Returns 0 if the installed file was manually edited (SHA mismatch that
#   cannot be explained by a VBW/delta update).
#   Strategy: regenerate expected output in memory, sha256 the whole file,
#   compare against sha256 of the installed file. If they differ AND neither
#   base_sha nor delta_sha changed (no upstream update), it is a manual edit.
#
#   Simplified conservative check: if the installed file exists and its
#   x-cmm-base-sha/x-cmm-delta-sha match our expected SHAs (meaning we would
#   have generated this version), compare the installed file's full sha256
#   against a freshly generated output. Any difference = manual edit.
#   Returns 1 (not manually edited) when SHAs are missing/mismatched —
#   that case is handled by needs_regen() as a normal regeneration.
# ---------------------------------------------------------------------------
manual_edit_detected() {
  local agent_name="$1"
  local expected_base="$2"
  local expected_delta="$3"

  local installed="${PROJECT_ROOT}/.claude/agents/vbw-${agent_name}.md"
  [ -f "$installed" ] || return 1  # Not installed — not a manual edit

  # Read installed SHAs
  local installed_pair
  installed_pair=$(read_installed_shas "$agent_name")
  local installed_base="${installed_pair%% *}"
  local installed_delta="${installed_pair##* }"

  # If installed SHAs don't match expected, this is a version update not a manual edit
  if [ "$installed_base" != "$expected_base" ] || [ "$installed_delta" != "$expected_delta" ]; then
    return 1
  fi

  # SHAs stamp says this was our generated version — compare full file content
  # by regenerating expected output in a temp file and diffing
  local delta_file_med
  delta_file_med=$(resolve_delta_path "$agent_name") || return 1  # no delta → not a manual edit

  local tmp_expected
  tmp_expected=$(mktemp /tmp/agent-override-expected.XXXXXX)
  python3 - "${VBW_AGENTS_DIR}/vbw-${agent_name}.md" \
            "$delta_file_med" \
            "$agent_name" "$expected_base" "$expected_delta" \
            > "$tmp_expected" 2>/dev/null <<'PYEOF'
import sys, re

base_path  = sys.argv[1]
delta_path = sys.argv[2]
agent_name = sys.argv[3]
base_sha   = sys.argv[4]
delta_sha  = sys.argv[5]

base_text  = open(base_path).read()
delta_text = open(delta_path).read()

base_fm_match = re.match(r'^---\n(.*?\n)---\n?', base_text, re.DOTALL)
base_fm_raw   = base_fm_match.group(1) if base_fm_match else ''
base_body     = base_text[base_fm_match.end():] if base_fm_match else base_text

def parse_fm(text):
    result = []
    current_key = None
    current_lines = []
    for line in text.splitlines():
        if re.match(r'^[a-zA-Z_]', line):
            if current_key is not None:
                result.append((current_key, '\n'.join(current_lines)))
            current_key = line.split(':')[0].strip()
            current_lines = [line]
        else:
            if current_key is not None:
                current_lines.append(line)
    if current_key is not None:
        result.append((current_key, '\n'.join(current_lines)))
    return result

base_fm_pairs  = parse_fm(base_fm_raw)
base_fm        = dict(base_fm_pairs)

delta_fm_match = re.match(r'^---\n(.*?\n)---\n?', delta_text, re.DOTALL)
delta_fm_raw   = delta_fm_match.group(1) if delta_fm_match else ''
delta_body_part = delta_text[delta_fm_match.end():] if delta_fm_match else delta_text
delta_fm_pairs = parse_fm(delta_fm_raw)
delta_fm       = dict(delta_fm_pairs)

BASE_PRESERVE_KEYS = ['name', 'description', 'model', 'memory', 'permissionMode']
TOOL_GRANT_KEYS    = {'tools', 'disallowedTools'}

merged_fm_lines = []
for key in BASE_PRESERVE_KEYS:
    if key in base_fm:
        merged_fm_lines.append(base_fm[key])

if 'disallowedTools' in delta_fm:
    merged_fm_lines.append(delta_fm['disallowedTools'])
elif 'tools' in delta_fm:
    merged_fm_lines.append(delta_fm['tools'])
elif 'disallowedTools' in base_fm:
    merged_fm_lines.append(base_fm['disallowedTools'])
elif 'tools' in base_fm:
    merged_fm_lines.append(base_fm['tools'])

OUR_EXTENSION_KEYS = set(delta_fm.keys()) - {'name','description','model','memory',
                                               'permissionMode','x-cmm-base-sha',
                                               'x-cmm-delta-sha'} - TOOL_GRANT_KEYS
for key, block in delta_fm_pairs:
    if key in OUR_EXTENSION_KEYS:
        merged_fm_lines.append(block)

merged_fm_lines.append(f'x-cmm-base-sha: "{base_sha}"')
merged_fm_lines.append(f'x-cmm-delta-sha: "{delta_sha}"')
merged_fm = '\n'.join(merged_fm_lines)

delta_sections = re.findall(
    r'<!-- cmm-delta:begin[^>]*-->.*?<!-- cmm-delta:end[^>]*-->',
    delta_body_part, re.DOTALL
)
delta_appended = '\n'.join(delta_sections)

lines = []
lines.append('---')
lines.append(merged_fm)
lines.append('---')
lines.append('')
lines.append('<!-- GENERATED by agent-override-generate.sh — do not edit manually.')
lines.append('     Run setup.sh --project or restart session to regenerate. -->')
lines.append('')
base_body_stripped = base_body.lstrip('\n')
lines.append(base_body_stripped.rstrip('\n'))
if delta_appended:
    lines.append('')
    lines.append(delta_appended)
lines.append('')
print('\n'.join(lines), end='')
PYEOF

  # Compare sha256 of installed vs expected
  local installed_sha expected_sha
  if command -v sha256sum >/dev/null 2>&1; then
    installed_sha=$(sha256sum < "$installed" | awk '{print $1}')
    expected_sha=$(sha256sum  < "$tmp_expected" | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    installed_sha=$(shasum -a 256 < "$installed" | awk '{print $1}')
    expected_sha=$(shasum -a 256  < "$tmp_expected" | awk '{print $1}')
  else
    rm -f "$tmp_expected"
    return 1  # Cannot compare — assume not edited
  fi
  rm -f "$tmp_expected"

  [ "$installed_sha" != "$expected_sha" ]
}

# ---------------------------------------------------------------------------
# MAIN SESSION-START LOOP
# ---------------------------------------------------------------------------

main() {
  # --- Resolve PROJECT_ROOT via lib ---
  # project-root.sh exports PROJECT_ROOT on source
  if [ -z "${PROJECT_ROOT:-}" ]; then
    echo "[agent-override-generate] WARN: PROJECT_ROOT not resolved — skipping override generation" >&2
    exit 0
  fi

  # --- Resolve VBW source ---
  # resolve_vbw_source returns 1 when VBW is absent/disabled. Fail-open: clean no-op.
  if ! resolve_vbw_source 2>/dev/null; then
    # VBW absent or disabled — advisory via systemMessage, then clean no-op
    printf '{"type":"systemMessage","message":"%s"}\n' \
      "CMM agent-override-generate: VBW plugin not found — agent overrides skipped. Install VBW and restart session to generate."
    exit 0
  fi

  # --- Check delta files availability ---
  # If no delta files are found in either location, clean no-op.
  local _any_delta=0
  local _test_agent
  for _test_agent in architect debugger dev docs lead qa scout; do
    if resolve_delta_path "$_test_agent" >/dev/null 2>&1; then
      _any_delta=1
      break
    fi
  done
  if [ "$_any_delta" -eq 0 ]; then
    printf '{"type":"systemMessage","message":"%s"}\n' \
      "CMM agent-override-generate: no delta files found in .claude/agents-delta/ — agent overrides skipped. Run setup.sh --project to install delta files."
    exit 0
  fi

  # Agent names (without vbw- prefix and .md suffix)
  local agents=(architect debugger dev docs lead qa scout)

  local generated=()
  local skipped=()
  local warned=()

  for agent in "${agents[@]}"; do
    # Compute expected SHAs
    local base_sha delta_sha
    base_sha=$(compute_base_sha "$agent" 2>/dev/null) || {
      echo "[agent-override-generate] WARN: cannot compute base SHA for $agent — skipping" >&2
      skipped+=("$agent")
      continue
    }
    delta_sha=$(compute_delta_sha "$agent" 2>/dev/null) || {
      echo "[agent-override-generate] WARN: cannot compute delta SHA for $agent — skipping" >&2
      skipped+=("$agent")
      continue
    }

    # Silent no-op when SHAs match
    if ! needs_regen "$agent" "$base_sha" "$delta_sha"; then
      skipped+=("$agent(sha-match)")
      continue
    fi

    # Manual-edit guard: warn and skip rather than clobber
    if manual_edit_detected "$agent" "$base_sha" "$delta_sha"; then
      local installed_path="${PROJECT_ROOT}/.claude/agents/vbw-${agent}.md"
      warned+=("$agent")
      # Emit warning on user-visible channel (stderr + systemMessage)
      echo "[agent-override-generate] WARN: manually edited — do not edit vbw-${agent}.md. Skipping regeneration." >&2
      continue
    fi

    # Generate the merged override
    if generate_override "$agent" "$base_sha" "$delta_sha"; then
      generated+=("$agent")
    else
      echo "[agent-override-generate] WARN: generation failed for $agent — skipping" >&2
      skipped+=("$agent")
    fi
  done

  # --- Emit advisory if any overrides were generated ---
  if [ ${#generated[@]} -gt 0 ]; then
    local agent_list
    agent_list=$(printf '%s ' "${generated[@]}")
    local warn_notice=""
    if [ ${#warned[@]} -gt 0 ]; then
      local warn_list
      warn_list=$(printf '%s ' "${warned[@]}")
      warn_notice=" (manually edited — skipped: ${warn_list})"
    fi

    # Advisory on stderr (user-visible)
    echo "[agent-override-generate] Generated VBW agent overrides: ${agent_list}(VBW ${VBW_VERSION} / ${VBW_SOURCE_TYPE})${warn_notice}" >&2
    echo "[agent-override-generate] RESTART SESSION to apply updated agent overrides." >&2

    # Advisory as JSON systemMessage (preferred user-visible channel per hook docs)
    local msg="VBW agent overrides updated (${agent_list}— VBW ${VBW_VERSION}/${VBW_SOURCE_TYPE}${warn_notice}). RESTART SESSION to apply."
    printf '{"type":"systemMessage","message":"%s"}\n' \
      "$(printf '%s' "$msg" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read())[1:-1])')"
  fi

  # Warn channel for any manually-edited files (belt-and-suspenders, also above)
  if [ ${#warned[@]} -gt 0 ]; then
    local warn_list
    warn_list=$(printf '%s ' "${warned[@]}")
    local wmsg="CMM agent override(s) have been manually edited and will NOT be auto-regenerated: ${warn_list}. To reset, delete the file(s) and restart session."
    printf '{"type":"systemMessage","message":"%s"}\n' \
      "$(printf '%s' "$wmsg" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read())[1:-1])')"
  fi
}

main "$@"
