# Token Benchmark Report

> **Note:** This is an example report generated from `example-raw.csv` (n=1, repo=expressjs/express only).
> A real run uses n=10 and 5 repos. Numbers are representative, not from actual measurements.

**Date:** 2026-03-13
**Claude Version:** claude-sonnet-4-6
**CMM Version:** 1.2.0
**n (runs per variant/repo/task):** 1

---

## Executive Summary

Across 5 standard tasks on expressjs/express, enabling codebase-memory-mcp reduced total token consumption by **54%** (cmm-cold) and **66%** (cmm-cache) compared to the baseline (no MCP tools). Input tokens alone dropped by **93%** in the cmm-cache variant — from ~63,000 input tokens per task to ~4,200.

The cmm-cold variant uses more total tokens than cmm-cache because it incurs `cache_creation` overhead to build the index from scratch each run. In a real workflow where the index is kept warm, the cmm-cache numbers are the relevant comparison.

---

## Summary Table

Total tokens by variant (mean ± stddev across all tasks, n=1):

| Variant | Total Tokens (mean) | Std Dev | vs Baseline |
|---------|---------------------|---------|-------------|
| baseline | 63814 | 10854 | — |
| cmm-cold | 29574 | 6573 | -53.6% |
| cmm-cache | 21974 | 4088 | -65.6% |

---

## Per-Repo Breakdown

Total tokens mean by repo and variant (single repo in this example):

| Repo | baseline | cmm-cold | cmm-cache |
|------|----------|----------|-----------|
| expressjs/express | 63814 | 29574 | 21974 |

---

## Per-Task Breakdown

Total tokens mean by task and variant:

| Task | baseline | cmm-cold | cmm-cache |
|------|----------|----------|-----------|
| 01-find-callers | 62920 | 28720 | 21520 |
| 02-call-graph | 75410 | 35310 | 26110 |
| 03-list-exports | 51680 | 23480 | 17780 |
| 04-find-imports | 49040 | 21440 | 15940 |
| 05-dead-code | 80020 | 38920 | 28520 |

---

## Key Findings

1. **Input token reduction is dramatic.** The cmm-cache variant used an average of 4,220 input tokens per task vs 63,260 for baseline — a **93% reduction**. CMM's graph queries return precise structural results instead of whole-file content.

2. **Dead code detection (task 05) shows the largest absolute savings.** Baseline consumed ~80,000 total tokens for global call analysis; cmm-cache consumed ~28,500. CMM's `search_graph` with `max_degree=0` returns dead code candidates directly.

3. **cmm-cold overhead is real but bounded.** Cache creation tokens (~19,000–25,000 per task) add overhead, but the index is built once per session in practice. After the first run, subsequent calls within the session hit cmm-cache numbers.

---

## Methodology Notes

- **baseline:** Claude Code with no CMM tools. Full file context passed via grep/cat.
- **cmm-cold:** CMM graph tools used; index freshly built (no cache hits).
- **cmm-cache:** CMM graph tools used; index pre-warmed (cache read tokens measured).
- Token counts sourced from Claude API response headers (`x-cache-creation-input-tokens`, `x-cache-read-input-tokens`).
- Each variant/repo/task combination run N times; mean and stddev computed over runs.
- Repos cloned at pinned commits listed in `benchmarks/config.sh`.

---

## CSV Schema Reference

### example-raw.csv

| Column | Type | Description |
|--------|------|-------------|
| variant | string | One of: baseline, cmm-cold, cmm-cache |
| repo | string | GitHub repo slug (owner/name) |
| task | string | Task ID (01–05) |
| run | integer | Run number within variant/repo/task |
| input_tokens | integer | Input tokens billed (excluding cache) |
| output_tokens | integer | Output tokens generated |
| cache_creation | integer | Cache creation tokens (cmm-cold only) |
| cache_read | integer | Cache read tokens (cmm-cache only) |
| total_tokens | integer | Sum of input + output + cache_creation + cache_read |

### example-aggregated.csv

| Column | Type | Description |
|--------|------|-------------|
| variant | string | One of: baseline, cmm-cold, cmm-cache |
| repo | string | GitHub repo slug (owner/name) |
| task | string | Task ID (01–05) |
| n | integer | Number of runs aggregated |
| input_mean | float | Mean input tokens |
| input_stddev | float | Std dev of input tokens |
| output_mean | float | Mean output tokens |
| output_stddev | float | Std dev of output tokens |
| cache_creation_mean | float | Mean cache creation tokens |
| cache_creation_stddev | float | Std dev of cache creation tokens |
| cache_read_mean | float | Mean cache read tokens |
| cache_read_stddev | float | Std dev of cache read tokens |
| total_mean | float | Mean total tokens |
| total_stddev | float | Std dev of total tokens |
