#!/bin/bash
# Benchmark configuration — sourced by all benchmark scripts
BENCH_REPOS=("expressjs/express" "go-chi/chi" "httpie/cli" "redis/redis" "meilisearch/meilisearch")
BENCH_VARIANTS=("baseline" "cmm-cold" "cmm-cache")
BENCH_RUNS=10
BENCH_RESULTS_DIR="$(dirname "$0")/../results"
BENCH_PROMPTS_DIR="$(dirname "$0")/../prompts"
CLAUDE_SESSIONS_DIR="$HOME/.config/claude-code/projects"
# Repos cloned OUTSIDE the project tree to avoid CMM indexing them as part of this project
BENCH_REPOS_DIR="${BENCH_REPOS_DIR:-$HOME/.cache/cmm-benchmarks/repos}"
