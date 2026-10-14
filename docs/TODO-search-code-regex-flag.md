# TODO — Gate recovery lines emit `search_code` calls that match nothing

**Status:** proposed / not started
**Created:** 2026-10-14
**Origin:** found while replaying the `# cmm-exempt` maintainx calls (branch `fix/hook-redirect-accuracy`)

---

## Problem

When a gate blocks a grep, its message names the CMM call to run instead. For a regex
search term, all three gates suggest:

```
mcp__codebase-memory-mcp__search_code(pattern="a|b", project="…")
```

`search_code` treats `pattern` as a **literal** unless `regex=true` is passed. Observed
2026-10-14 against the maintainx index:

- `search_code(pattern="ScriptAlias|RewriteRule")` → 0 results, with the warning
  *"pattern contains '|' but regex=false, so it is matched literally (not as alternation).
  Pass regex=true for 'foo|bar' to mean 'foo OR bar'."*
- `search_code(pattern="ScriptAlias")` → 36 matches across five `httpd*.conf` files.

So the suggested replacement for the most common grep shape in the replay
(`grep -nE 'a|b|c' file`) silently returns nothing. `rules/cmm-rules.md` records that two
failed CMM calls in a row is where agents abandon CMM for `Read`. An empty result that
looks like "not found" is arguably worse than a failure, because the agent may report it
as a finding.

## Where it is emitted

- `hooks/global/cmm-grep-nudge.sh` — `_cmm_recovery_lines()` (Bash and Grep branches)
- `hooks/project/grep-cmm-gate.sh` — `FIRST_LINE` / `SECOND_LINE` (REPLACE WITH classifier)
- `hooks/project/ctx-execute-cmm-nudge.sh` — the same classifier, duplicated

All three already split the term into identifier vs non-identifier. The non-identifier
branch is the one that needs the flag.

## Proposed fix

1. When the term contains regex metacharacters (`| . * + ? [ ( ) \ ^ $ {`), add `regex=true`
   to the emitted `search_code(...)` call. A bare identifier stays literal.
2. Drop the `search_graph(name_pattern="a|b")` alternative for alternation terms. Check
   what `name_pattern` actually does with `|` before keeping it.
3. Check the rules text against current upstream behaviour: `rules/cmm-rules.md`,
   `skills/cmm-rules/SKILL.md` and `rules/cmm-agent-preamble.md` say `search_code`
   "auto-converts multi-word input to a regex", and none of them mention `regex=true`.
   Add one line to the calling-convention section.
4. `find -name '*.py'` recovery: the find-name classifier strips the wildcards and
   suggests `search_code(pattern=".py")`, which matches any `.py` substring (QA round 2,
   R2-09; pre-existing). Suggest a `file_pattern="*.py"` search, or no search_code line.
5. Tests: assert the emitted line for `grep -nE 'a|b' src/x` contains `regex=true`, and the
   one for `grep -n foo src/x` does not, in each of the three hook suites.

## Acceptance

- Every `search_code` call a block message prints returns the same hits the blocked grep
  would have, for the replay payloads in this repo's history (p01–p26 and the 88 exempted
  calls).
- `make test` green.
