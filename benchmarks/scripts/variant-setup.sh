#!/bin/bash
# Variant setup/teardown — configures .mcp.json for baseline, cmm-cold, or cmm-cache runs

# MECHANISM: Toggle CMM by swapping .mcp.json in the project root.
#
# Two template files must exist before running benchmarks:
#   .mcp.json.baseline  — {"mcpServers":{}}        (no MCP tools)
#   .mcp.json.cmm       — {"mcpServers":{"codebase-memory-mcp":{...}}}
#
# Each benchmark run restores from backup on teardown.
#
# CMM index location: ~/.config/claude-code/projects/<hash>/databases/<repo_hash>.db
# The DB path is computed by Claude Code from the project root path. For cold runs
# we remove all *.db files under the relevant project dir. Set REPO_PATH before calling
# setup_variant cmm-cold.

MCP_JSON="${MCP_JSON:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.mcp.json}"

# Template directory: where .mcp.json.cmm, .mcp.json.ctx, etc. live (project root)
_BENCH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_TEMPLATE_DIR="${BENCH_TEMPLATE_DIR:-$(cd "$_BENCH_SCRIPT_DIR" && git rev-parse --show-toplevel 2>/dev/null)}"
BENCH_TEMPLATE_DIR="${BENCH_TEMPLATE_DIR:-$(cd "$_BENCH_SCRIPT_DIR/../.." && pwd)}"

setup_variant() {
  local variant="$1"
  local MCP_BACKUP="${MCP_JSON}.active_backup"

  case "$variant" in
    baseline)
      # Save current .mcp.json then replace with empty mcpServers config
      cp "$MCP_JSON" "$MCP_BACKUP" 2>/dev/null || true
      echo '{"mcpServers":{}}' > "$MCP_JSON"
      echo "[variant] baseline — CMM disabled (.mcp.json → empty mcpServers)"
      ;;

    cmm-cold)
      # Restore CMM config and purge any existing index for the repo
      cp "$MCP_JSON" "$MCP_BACKUP" 2>/dev/null || true
      if [ -f "${BENCH_TEMPLATE_DIR}/.mcp.json.cmm" ]; then
        cp "${BENCH_TEMPLATE_DIR}/.mcp.json.cmm" "$MCP_JSON"
      else
        echo "[warn] .mcp.json.cmm not found — CMM may not be configured" >&2
      fi

      # Delete CMM index databases so the next run indexes from scratch (cold).
      # REPO_PATH must be set by the caller to the repo being benchmarked.
      if [ -n "${REPO_PATH:-}" ]; then
        local sessions_dir="${CLAUDE_SESSIONS_DIR:-$HOME/.config/claude-code/projects}"
        # CMM stores DBs under the session project dir matching the repo path hash.
        # Remove all *.db files that could correspond to this repo's index.
        find "$sessions_dir" -name "*.db" -path "*/databases/*" -delete 2>/dev/null || true
        echo "[variant] cmm-cold — CMM enabled, index purged for fresh indexing"
      else
        echo "[warn] REPO_PATH not set — skipping index purge (cmm-cold may be warm)" >&2
        echo "[variant] cmm-cold — CMM enabled (index not purged)"
      fi
      ;;

    cmm-cache)
      # Restore CMM config; index is expected to already exist (warm cache).
      cp "$MCP_JSON" "$MCP_BACKUP" 2>/dev/null || true
      if [ -f "${BENCH_TEMPLATE_DIR}/.mcp.json.cmm" ]; then
        cp "${BENCH_TEMPLATE_DIR}/.mcp.json.cmm" "$MCP_JSON"
      else
        echo "[warn] .mcp.json.cmm not found — CMM may not be configured" >&2
      fi
      echo "[variant] cmm-cache — CMM enabled, existing index retained (warm cache)"
      ;;

    *)
      echo "[error] Unknown variant: $variant (expected: baseline, cmm-cold, cmm-cache)" >&2
      return 1
      ;;
  esac
}

teardown_variant() {
  local MCP_BACKUP="${MCP_JSON}.active_backup"
  # Restore .mcp.json from backup saved during setup_variant
  if [ -f "$MCP_BACKUP" ]; then
    mv "$MCP_BACKUP" "$MCP_JSON"
    echo "[teardown] .mcp.json restored from backup"
  else
    echo "[warn] No backup found at $MCP_BACKUP — .mcp.json not restored" >&2
  fi
}
