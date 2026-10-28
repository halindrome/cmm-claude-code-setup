#!/bin/bash
# cmm-query.sh — Bash wrapper over `codebase-memory-mcp cli` for agents without MCP tools
#
# Install: cp hooks/project/cmm-query.sh .claude/hooks/ (+ hooks/lib/); setup.sh does it with VBW 2.
# Register: not a hook. Called by agents:
#   bash <root>/.claude/hooks/cmm-query.sh <tool> '<json args>'
# Injects the project (index_repository: repo_path), always passes --quiet, and
# after a successful index_repository opens the session gate.

ALLOWED="search_graph trace_path get_code_snippet search_code query_graph get_architecture list_projects index_status index_repository"

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" 2>/dev/null && pwd -P)"
source "$_LIB_DIR/project-root.sh"
source "$_LIB_DIR/cmm-registered.sh"

TOOL="${1:-}"
case " $ALLOWED " in
    *" $TOOL "*) [ -n "$TOOL" ] || TOOL="" ;;
    *) TOOL="" ;;
esac
if [ -z "$TOOL" ]; then
    echo "cmm-query: tool '${1:-}' not allowed; use one of: $ALLOWED" >&2
    exit 2
fi

if ! command -v codebase-memory-mcp >/dev/null 2>&1; then
    echo "cmm-query: codebase-memory-mcp not on PATH; install it (see README) and retry" >&2
    exit 127
fi

# Merge project / repo_path into the caller's JSON object (default {}).
if [ "$TOOL" = index_repository ]; then KEY=repo_path; VAL="$PROJECT_ROOT"; else KEY=project; VAL="$(cmm_project_name)"; fi
ARGS="$(KEY="$KEY" VAL="$VAL" python3 -c '
import json, os, sys
raw = sys.argv[1] if len(sys.argv) > 1 else ""
a = json.loads(raw) if raw.strip() else {}
if not isinstance(a, dict):
    raise ValueError("arguments must be a JSON object")
a.setdefault(os.environ["KEY"], os.environ["VAL"])
print(json.dumps(a))' "${2:-}" 2>&1)" || {
    echo "cmm-query: invalid JSON arguments for $TOOL (expected an object): ${2:-}" >&2
    exit 2
}

OUT="$(codebase-memory-mcp cli --quiet "$TOOL" "$ARGS" 2>&1)"
RC=$?
printf '%s\n' "$OUT"

if [ "$TOOL" != index_repository ] && printf '%s' "$OUT" | grep -qiE 'not indexed|not found'; then
    echo "cmm-query: project not indexed; run: $(cmm_query_cmd index_repository)" >&2
    exit 1
fi
if [ "$TOOL" = index_repository ] && [ "$RC" = 0 ] && ! printf '%s' "$OUT" | grep -q '"error"'; then
    echo ready >"$CMM_SENTINEL"
    rm -f "/tmp/cmm-indexing-${PROJECT_HASH}"
fi
exit "$RC"
