#!/usr/bin/env python3
"""analyze-gate-blocks.py — Track-1 offline miner for CMM/ctx gate token cost.

Reads Claude Code session transcripts (.jsonl) and prices what the hard gates
actually COST in tokens: the injected block messages plus the detour reasoning
the model spends reacting to each block. Uses only recorded data — no agent runs,
fully deterministic.

What it reports, per gate hook and overall:
  - blocks: how many times each gate fired
  - msg_tokens: tokens injected by the block messages (permanent context cost)
  - detour_tokens: output tokens of the assistant turn immediately AFTER each
                   block (lower-bound proxy for read-block-reason-retry waste)
  - false-positive candidates: blocks on writes/heredocs, on offset+limit Reads,
                   or on non-code paths — the token-NEGATIVE cases
  - back-to-back chains: consecutive blocks for one logical goal (evasion struggle)

Caveats (printed at the end):
  - detour_tokens is a LOWER BOUND (next-assistant-turn output only)
  - token estimate for block messages is chars/4 (no tokenizer dependency)
  - cache effects are not modeled; this prices marginal output + injected text
  - FP flags are heuristics, not proof

Usage:
  python3 scripts/analyze-gate-blocks.py                 # all projects under $CLAUDE_CONFIG_DIR/projects
  python3 scripts/analyze-gate-blocks.py --project cmm   # projects whose slug contains 'cmm'
  python3 scripts/analyze-gate-blocks.py --file <path.jsonl>
"""
import json, glob, os, re, sys, collections

CFG = os.environ.get("CLAUDE_CONFIG_DIR", os.path.expanduser("~/.claude"))
PROJECTS = os.path.join(CFG, "projects")

# Known gate hooks (basename without .sh). Anything else that blocks is "other".
GATE_HOOKS = {
    "ctx-execute-enforcer", "cmm-grep-nudge", "grep-cmm-gate", "cmm-nudge",
    "agent-cmm-gate", "cwd-guard", "session-gate", "cmm-session-gate",
    "ctx-execute-cmm-nudge",
}
HOOK_RE = re.compile(r"/hooks/(?:project/|global/)?([a-z0-9-]+)\.sh")
# A block is a hook error tool_result. Match defensively across gate styles.
BLOCK_MARKERS = ("BLOCKED", "Use CMM", "ctx_execute", "index not ready", "cwd")


def text_of(content):
    """tool_result content may be a string or a list of {type:text,text:...}."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        out = []
        for c in content:
            if isinstance(c, dict):
                out.append(c.get("text", "") or json.dumps(c.get("content", "")))
            else:
                out.append(str(c))
        return "\n".join(out)
    return json.dumps(content) if content is not None else ""


def est_tokens(s):
    return max(1, len(s) // 4)


def real_write(cmd):
    """True if the command writes to a file: a heredoc, or a '>' redirect that
    is NOT an fd/stderr redirect (2>, 1>, &>, >&). Avoids counting 2>/dev/null."""
    if "<<" in cmd:
        return True
    for m in re.finditer(r">", cmd):
        i = m.start()
        prev = cmd[i - 1] if i > 0 else " "
        if prev in "0123456789&":      # 2>  1>  &>
            continue
        if i + 1 < len(cmd) and cmd[i + 1] == "&":  # >&
            continue
        return True
    return False


def iter_records(path):
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def analyze_file(path, agg):
    """Single pass: build ordered event list, then attribute blocks + detours."""
    # ordered list of (kind, payload) where kind in {asst, result}
    events = []
    tooluse_by_id = {}  # id -> {name, input}
    for r in iter_records(path):
        msg = r.get("message")
        if not isinstance(msg, dict):
            continue
        role = msg.get("role") or r.get("type")
        usage = msg.get("usage") or {}
        out_tok = usage.get("output_tokens", 0) if isinstance(usage, dict) else 0
        content = msg.get("content")
        tool_uses, tool_results = [], []
        if isinstance(content, list):
            for c in content:
                if not isinstance(c, dict):
                    continue
                if c.get("type") == "tool_use":
                    tooluse_by_id[c.get("id")] = {"name": c.get("name"), "input": c.get("input", {})}
                    tool_uses.append(c.get("id"))
                elif c.get("type") == "tool_result":
                    tool_results.append({
                        "tool_use_id": c.get("tool_use_id"),
                        "is_error": bool(c.get("is_error")),
                        "text": text_of(c.get("content")),
                    })
        if role == "assistant":
            events.append(("asst", {"out_tok": out_tok, "tool_uses": tool_uses}))
        elif tool_results:
            events.append(("result", {"results": tool_results}))

    agg["sessions"] += 1
    # total output tokens for this file
    agg["total_output"] += sum(e[1]["out_tok"] for e in events if e[0] == "asst")

    # Walk events; for each block result, find the blocking hook + tool, and the
    # detour = output_tokens of the next assistant event.
    prev_block_idx = -10
    for i, (kind, p) in enumerate(events):
        if kind != "result":
            continue
        for res in p["results"]:
            txt = res["text"]
            if not (res["is_error"] and "hook" in txt.lower() and any(m in txt for m in BLOCK_MARKERS)):
                continue
            m = HOOK_RE.search(txt)
            hook = m.group(1) if m else "unknown"
            if hook not in GATE_HOOKS and hook != "unknown":
                # a hook error from a non-gate hook; skip
                continue
            tu = tooluse_by_id.get(res["tool_use_id"], {})
            tool = tu.get("name", "?")
            inp = tu.get("input", {}) or {}

            # detour: next assistant event's output tokens
            detour = 0
            for j in range(i + 1, min(i + 4, len(events))):
                if events[j][0] == "asst":
                    detour = events[j][1]["out_tok"]
                    break

            msg_tok = est_tokens(txt)

            # false-positive heuristics (token-NEGATIVE blocks), attributed to the
            # specific gate so we don't confuse intentional compound-blocking with
            # the write-misclassified-as-nav bug.
            fp = None
            cmd = inp.get("command", "") if isinstance(inp, dict) else ""
            if hook == "cmm-grep-nudge" and tool == "Bash" and real_write(cmd):
                # the bash-nav gate firing on an actual file write / heredoc (the bug)
                fp = "write/heredoc-blocked-as-nav"
            elif hook == "cmm-nudge" and tool == "Read" and isinstance(inp, dict) \
                    and inp.get("offset") is not None and inp.get("limit") is not None:
                # the read gate taxing an already-bounded targeted read (60s recency gate)
                fp = "offset+limit-read-blocked"
            # ctx-execute-enforcer compound blocks are counted separately below
            if hook == "ctx-execute-enforcer":
                agg["compound_blocks"] += 1

            # back-to-back chain detection (block within 2 events of previous block)
            chain = (i - prev_block_idx) <= 2
            prev_block_idx = i

            agg["blocks"] += 1
            g = agg["by_hook"][hook]
            g["n"] += 1
            g["msg_tok"] += msg_tok
            g["detour_tok"] += detour
            agg["by_tool"][tool] += 1
            agg["msg_tok_total"] += msg_tok
            agg["detour_tok_total"] += detour
            if fp:
                agg["fp"][fp] += 1
                agg["fp_total"] += 1
            if chain:
                agg["chains"] += 1
            agg["per_project_blocks"][agg["_cur_project"]] += 1


def new_agg():
    return {
        "sessions": 0, "blocks": 0, "total_output": 0, "compound_blocks": 0,
        "msg_tok_total": 0, "detour_tok_total": 0, "fp_total": 0, "chains": 0,
        "by_hook": collections.defaultdict(lambda: {"n": 0, "msg_tok": 0, "detour_tok": 0}),
        "by_tool": collections.Counter(),
        "fp": collections.Counter(),
        "per_project_blocks": collections.Counter(),
        "_cur_project": "?",
    }


def main():
    args = sys.argv[1:]
    files = []
    if "--file" in args:
        files = [args[args.index("--file") + 1]]
        project_of = {files[0]: "single"}
    else:
        proj_filter = None
        if "--project" in args:
            proj_filter = args[args.index("--project") + 1]
        project_of = {}
        for slug_dir in sorted(glob.glob(os.path.join(PROJECTS, "*"))):
            slug = os.path.basename(slug_dir)
            if proj_filter and proj_filter not in slug:
                continue
            for f in glob.glob(os.path.join(slug_dir, "*.jsonl")):
                files.append(f)
                project_of[f] = slug

    agg = new_agg()
    projects = set()
    for f in files:
        agg["_cur_project"] = project_of.get(f, "?")
        projects.add(agg["_cur_project"])
        try:
            analyze_file(f, agg)
        except Exception as e:
            print(f"  [warn] {os.path.basename(f)}: {e}", file=sys.stderr)

    # ---- Report ----
    print(f"Corpus: {len(projects)} projects, {agg['sessions']} sessions, "
          f"{agg['total_output']:,} total output tokens")
    print(f"Blocks: {agg['blocks']} total")
    if agg["blocks"] == 0:
        print("No gate blocks found in this corpus.")
        return
    print()
    print("By gate hook:")
    print(f"  {'hook':<24} {'blocks':>7} {'msg_tok':>9} {'detour_tok':>11}")
    for hook, g in sorted(agg["by_hook"].items(), key=lambda kv: -kv[1]["n"]):
        print(f"  {hook:<24} {g['n']:>7} {g['msg_tok']:>9,} {g['detour_tok']:>11,}")
    print()
    print("By blocked tool:", dict(agg["by_tool"]))
    print()
    cost = agg["msg_tok_total"] + agg["detour_tok_total"]
    pct = (100.0 * cost / agg["total_output"]) if agg["total_output"] else 0
    print(f"Direct cost: {agg['msg_tok_total']:,} block-msg tokens (injected) + "
          f"{agg['detour_tok_total']:,} detour output tokens")
    print(f"  = {cost:,} tokens, ~{pct:.2f}% of corpus output tokens "
          f"(detour is a LOWER bound)")
    print()
    print(f"High-confidence token-NEGATIVE blocks (attributed to a specific gate): "
          f"{agg['fp_total']} ({100.0*agg['fp_total']/agg['blocks']:.0f}% of blocks)")
    for k, v in agg["fp"].most_common():
        print(f"  {k:<32} {v}")
    print(f"\nctx-execute-enforcer compound-command blocks: {agg['compound_blocks']} "
          f"(intentional policy — token impact debatable, not a bug)")
    print()
    print(f"Back-to-back block chains (evasion struggle): {agg['chains']}")
    print()
    print("Top projects by blocks:")
    for slug, n in agg["per_project_blocks"].most_common(8):
        short = slug.replace("-Users-ahby-Sources-", "").replace("-Users-ahby-", "")
        print(f"  {n:>5}  {short}")
    print()
    print("Caveats: detour=next-assistant-turn output only (lower bound); "
          "msg tokens ~chars/4; cache not modeled; FP flags heuristic. "
          "Local installs are --project mode (hooks in each repo's .claude/hooks/).")


if __name__ == "__main__":
    main()
