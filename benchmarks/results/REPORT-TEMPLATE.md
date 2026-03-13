# Token Benchmark Report

**Date:** YYYY-MM-DD
**Claude Version:** claude-XXXXXX
**CMM Version:** X.X.X
**n (runs per variant/repo/task):** N

---

## Executive Summary

_Fill in high-level findings here. Compare total token usage across variants. Note which variant performed best and by how much._

---

## Summary Table

Total tokens by variant (mean ± stddev across all repos and tasks):

| Variant | Total Tokens (mean) | Std Dev | vs Baseline |
|---------|---------------------|---------|-------------|
| baseline | XXXXX | XXXXX | — |
| cmm-cold | XXXXX | XXXXX | +X% / −X% |
| cmm-cache | XXXXX | XXXXX | +X% / −X% |

---

## Per-Repo Breakdown

Total tokens mean by repo and variant:

| Repo | baseline | cmm-cold | cmm-cache |
|------|----------|----------|-----------|
| expressjs/express | XXXXX | XXXXX | XXXXX |
| go-chi/chi | XXXXX | XXXXX | XXXXX |
| httpie/cli | XXXXX | XXXXX | XXXXX |
| redis/redis | XXXXX | XXXXX | XXXXX |
| meilisearch/meilisearch | XXXXX | XXXXX | XXXXX |

---

## Per-Task Breakdown

Total tokens mean by task and variant:

| Task | baseline | cmm-cold | cmm-cache |
|------|----------|----------|-----------|
| 01-find-callers | XXXXX | XXXXX | XXXXX |
| 02-call-graph | XXXXX | XXXXX | XXXXX |
| 03-list-exports | XXXXX | XXXXX | XXXXX |
| 04-find-imports | XXXXX | XXXXX | XXXXX |
| 05-dead-code | XXXXX | XXXXX | XXXXX |

---

## Key Findings

_Fill in manually after analysis._

1.
2.
3.

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

### sample-raw.csv

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

### sample-aggregated.csv

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
