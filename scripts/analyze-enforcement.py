#!/usr/bin/env python3
"""Measure whether the cmm-claude-code-setup enforcement stack reaches the
conversation stream, and whether agents change behaviour when it does.

Corpus: ~/.config/claude-code/projects/**/*.jsonl, records with timestamp
within the last N days (default 30).

Tiers:
  main      project/<sid>.jsonl
  agent     project/<sid>/subagents/agent-*.jsonl        (Agent/Task tool)
  workflow  project/<sid>/subagents/workflows/<run>/agent-*.jsonl

Hook emissions are classified by CONTENT FINGERPRINT (strings emitted by
hooks/{global,project}/*.sh in this repo), never by hookName -- other hook
suites (cmux, codeisland, context-mode-soak) are installed on the same machine.

Measurement limit: a hook that exits 0 silently leaves no transcript trace.
Everything below counts hooks that EMITTED.
"""
import json, os, re, sys, time, collections

ROOT = os.path.expanduser("~/.config/claude-code/projects")
DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 30
CUTOFF = time.time() - DAYS * 86400

# ---------------------------------------------------------------- fingerprints
# (id, kind, substring) -- kind: gate=hard block, nudge=advisory, inject=startup
STACK_FP = [
    ("cmm-session-start",      "inject", "Code Discovery Protocol"),
    ("cmm-grep-nudge",         "gate",   "BLOCKED: Use CMM tools"),
    ("grep-cmm-gate",          "gate",   "[grep-cmm-gate] BLOCKED"),
    ("ctx-execute-cmm-nudge",  "gate",   "[ctx-execute-cmm-nudge] BLOCKED"),
    ("ctx-execute-enforcer",   "gate",   "BLOCKED: Route this command through ctx_execute"),
    ("ctx-execute-enforcer",   "gate",   "BLOCKED: Compound shell command cannot be exempted"),
    ("agent-cmm-gate",         "gate",   "BLOCKED: Agent prompt does not reference codebase-memory-mcp"),
    ("session-gate",           "gate",   "BLOCKED: CMM index not refreshed"),
    ("session-gate",           "gate",   "BLOCKED: Context Mode is installed but not yet initialized"),
    ("index-root-gate",        "gate",   "[index-root-gate] BLOCKED"),
    ("cwd-guard",              "gate",   "BLOCKED: persistent 'cd' detected"),
    ("webfetch-nudge",         "gate",   "BLOCKED: Use Context Mode instead of WebFetch"),
    ("subagent-cmm-startup",   "inject", "Prefer CMM graph tools"),
    ("subagent-ctx-startup",   "inject", "[ctx-startup] Context Mode is active"),
    ("skill-nudge",            "nudge",  "Invoke Skill('cmm-rules')"),
    ("cmm-read-nudge",         "nudge",  "is usually cheaper than re-reading the whole file"),
    ("cmm-orient-nudge",       "nudge",  "First search_graph call this session"),
    ("cmm-stale-advisory",     "nudge",  "CMM index may be stale"),
    ("reindex-after-edit",     "nudge",  "Consider refreshing the CMM index"),
    ("ctx-plugin-protection",  "inject", "<context_window_protection>"),
]

CODE_EXT = {".py",".js",".ts",".tsx",".jsx",".go",".rs",".java",".kt",".rb",".php",
            ".c",".h",".cc",".cpp",".hpp",".cs",".swift",".m",".mm",".scala",".pl",
            ".pm",".sh",".bash",".zsh",".sql",".vue",".svelte",".lua",".ex",".exs"}

# bash commands that are code-exploration shaped (the gap the TODO doc named)
EXPLORE_RE = re.compile(
    r"(?:^|[|;&]\s*)(?:sudo\s+)?(grep|egrep|rg|ag|ack|find|cat|sed|awk|ls|head|tail|wc)\b")

CMM_PREFIX = "mcp__codebase-memory-mcp__"
CTX_PREFIXES = ("mcp__plugin_context-mode_context-mode__", "mcp__context-mode__")
RAW_TOOLS = {"Read", "Grep", "Glob"}


def classify_hook(text):
    """-> list of (hook_id, kind); empty means not ours."""
    hits = []
    for hid, kind, fp in STACK_FP:
        if fp in text:
            hits.append((hid, kind))
    return hits


def tier_of(relpath):
    parts = relpath.split(os.sep)
    if len(parts) == 2:
        return "main"
    if "workflows" in parts:
        return "workflow"
    if "subagents" in parts:
        return "agent"
    return "other"


def flatten(content):
    """Message content -> plain text."""
    if isinstance(content, str):
        return content
    out = []
    if isinstance(content, list):
        for b in content:
            if isinstance(b, str):
                out.append(b)
            elif isinstance(b, dict):
                if "text" in b and isinstance(b["text"], str):
                    out.append(b["text"])
                c = b.get("content")
                if isinstance(c, str):
                    out.append(c)
                elif isinstance(c, list):
                    out.append(flatten(c))
    return "\n".join(out)


# ---------------------------------------------------------------- accumulators
S = lambda: collections.defaultdict(int)
tier_stats = collections.defaultdict(S)
tier_sessions = collections.defaultdict(set)
tier_stack_sessions = collections.defaultdict(set)
hook_by_tier = collections.defaultdict(collections.Counter)
gate_by_tier_version = collections.defaultdict(collections.Counter)
tools_by_tier = collections.defaultdict(collections.Counter)
after_block = collections.defaultdict(collections.Counter)          # tier -> next-bucket
after_block_gate = collections.defaultdict(collections.Counter)     # (tier,hid) -> next-bucket
spawn_gate = collections.defaultdict(S)   # tier -> Agent/Workflow spawn gating
eligible = collections.defaultdict(S)   # eligible calls / covered calls
proj_stack = collections.Counter()
versions_seen = collections.defaultdict(collections.Counter)
# per-session behaviour rows for the adoption table
sess_rows = []

files = []
for dirpath, dirnames, fnames in os.walk(ROOT):
    for fn in fnames:
        if not fn.endswith(".jsonl"):
            continue
        p = os.path.join(dirpath, fn)
        try:
            if os.path.getmtime(p) < CUTOFF:
                continue
        except OSError:
            continue
        files.append(p)

print(f"corpus: {len(files)} transcripts touched in last {DAYS}d\n")

for path in files:
    rel = os.path.relpath(path, ROOT)
    tier = tier_of(rel)
    project = rel.split(os.sep)[0]
    sid = rel.split(os.sep)[1] if len(rel.split(os.sep)) > 1 else rel

    stack_seen = set()
    tool_seq = []          # (tool_name, tool_use_id, is_explore_eligible)
    blocked_ids = collections.defaultdict(set)   # tool_use_id -> {gate hook ids}
    hookrecs = []
    version = None
    cwd = None
    nrec = 0

    try:
        fh = open(path, errors="replace")
    except OSError:
        continue
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            ts = r.get("timestamp")
            if ts:
                # ISO8601 Z
                try:
                    t = time.mktime(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S"))
                except Exception:
                    t = None
                if t is not None and t < CUTOFF - 86400:  # tz slack
                    continue
            nrec += 1
            version = r.get("version") or version
            cwd = r.get("cwd") or cwd
            typ = r.get("type")

            if typ == "attachment":
                a = r.get("attachment") or {}
                at = a.get("type")
                if at in ("hook_success", "hook_error", "hook_additional_context"):
                    txt = a.get("content")
                    txt = flatten(txt) if not isinstance(txt, str) else txt
                    if isinstance(a.get("content"), list):
                        txt = "\n".join(x if isinstance(x, str) else json.dumps(x)
                                        for x in a["content"])
                    hits = classify_hook(txt or "")
                    if hits:
                        for hid, kind in hits:
                            hookrecs.append((hid, kind, a.get("toolUseID")))
                            stack_seen.add(hid)
                    else:
                        hook_by_tier[tier]["<other-hook-suite>"] += 1

            elif typ == "assistant":
                msg = r.get("message") or {}
                for b in (msg.get("content") or []):
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        name = b.get("name", "?")
                        inp = b.get("input") or {}
                        elig = False
                        if name == "Grep":
                            elig = True
                        elif name == "Read":
                            fp = str(inp.get("file_path", ""))
                            elig = os.path.splitext(fp)[1].lower() in CODE_EXT
                        elif name == "Bash":
                            cmd = str(inp.get("command", ""))
                            elig = bool(EXPLORE_RE.search(cmd))
                        tool_seq.append((name, b.get("id"), elig))
                        tools_by_tier[tier][name] += 1

            elif typ == "user":
                msg = r.get("message") or {}
                for b in (msg.get("content") or []):
                    if isinstance(b, dict) and b.get("type") == "tool_result":
                        txt = flatten(b.get("content"))
                        hits = classify_hook(txt or "")
                        if any(k == "gate" for _, k in hits):
                            for hid, kind in hits:
                                if kind == "gate":
                                    blocked_ids[b.get("tool_use_id")].add(hid)
                                    hookrecs.append((hid, "gate", b.get("tool_use_id")))
                                    stack_seen.add(hid)

    if nrec == 0:
        continue

    tier_sessions[tier].add((project, sid, os.path.basename(path)))
    st = tier_stats[tier]
    st["records"] += nrec
    st["tool_calls"] += len(tool_seq)
    if version:
        versions_seen[tier][version] += 1

    for name, _tid, _e in tool_seq:
        if name.startswith(CMM_PREFIX):
            st["cmm_calls"] += 1
        elif name.startswith(CTX_PREFIXES):
            st["ctx_calls"] += 1
        elif name in RAW_TOOLS or name == "Bash":
            st["raw_calls"] += 1

    # hook coverage
    hooked_tool_ids = {tid for _h, _k, tid in hookrecs if tid}
    for name, tid, elig in tool_seq:
        if elig:
            eligible[tier]["eligible"] += 1
            if tid in hooked_tool_ids or tid in blocked_ids:
                eligible[tier]["covered"] += 1

    # what happened right after a hard block -- split per gate
    for i, (name, tid, _e) in enumerate(tool_seq):
        if tid in blocked_ids and i + 1 < len(tool_seq):
            nxt = tool_seq[i + 1][0]
            if nxt.startswith(CMM_PREFIX):
                bucket = "CMM"
            elif nxt.startswith(CTX_PREFIXES):
                bucket = "ctx"
            elif nxt in RAW_TOOLS or nxt == "Bash":
                bucket = "raw (Read/Grep/Glob/Bash)"
            else:
                bucket = "other"
            after_block[tier][bucket] += 1
            for hid in blocked_ids[tid]:
                after_block_gate[(tier, hid)][bucket] += 1

    # spawn gating: did agent-cmm-gate ever attach to an Agent vs a Workflow tool_use?
    for name, tid, _e in tool_seq:
        if name in ("Agent", "Task", "Workflow"):
            spawn_gate[tier][f"{name}:calls"] += 1
            if "agent-cmm-gate" in blocked_ids.get(tid, ()) or (
                    tid in hooked_tool_ids and any(
                        h == "agent-cmm-gate" and t == tid for h, _k, t in hookrecs)):
                spawn_gate[tier][f"{name}:gated"] += 1

    if stack_seen:
        tier_stack_sessions[tier].add((project, sid, os.path.basename(path)))
        proj_stack[project] += 1
        for hid, kind, _t in hookrecs:
            hook_by_tier[tier][hid] += 1
            if kind == "gate" and version:
                gate_by_tier_version[tier][version] += 1
        st["stack_tool_calls"] += len(tool_seq)
        for name, _t, _e in tool_seq:
            if name.startswith(CMM_PREFIX):
                st["stack_cmm"] += 1
            elif name.startswith(CTX_PREFIXES):
                st["stack_ctx"] += 1
            elif name in RAW_TOOLS or name == "Bash":
                st["stack_raw"] += 1
        sess_rows.append((tier, project, os.path.basename(path), version,
                          len(tool_seq),
                          sum(1 for n, _, _ in tool_seq if n.startswith(CMM_PREFIX)),
                          sum(1 for n, _, _ in tool_seq if n.startswith(CTX_PREFIXES)),
                          sum(1 for n, _, _ in tool_seq if n in RAW_TOOLS or n == "Bash"),
                          sorted(stack_seen)))

# ---------------------------------------------------------------- report
def pct(a, b):
    return f"{100.0*a/b:5.1f}%" if b else "    n/a"

print("=" * 78)
print("1. REACH -- transcripts carrying a stack hook emission")
print("=" * 78)
print(f"{'tier':10} {'transcripts':>12} {'w/ stack hook':>14} {'share':>8}")
for tier in ("main", "agent", "workflow", "other"):
    n = len(tier_sessions[tier]); s = len(tier_stack_sessions[tier])
    if n:
        print(f"{tier:10} {n:12d} {s:14d} {pct(s,n):>8}")

print()
print("=" * 78)
print("2. WHICH stack hooks emitted, by tier (emission count)")
print("=" * 78)
for tier in ("main", "agent", "workflow"):
    if not hook_by_tier[tier]:
        continue
    print(f"\n-- {tier} --")
    for hid, c in hook_by_tier[tier].most_common():
        kinds = {k for h, k, _f in STACK_FP if h == hid}
        print(f"   {c:7d}  {hid:24} {'/'.join(sorted(kinds))}")

print()
print("=" * 78)
print("3. HARD GATES inside subagents, by Claude Code version")
print("=" * 78)
for tier in ("main", "agent", "workflow"):
    if gate_by_tier_version[tier]:
        print(f"-- {tier} --")
        for v, c in sorted(gate_by_tier_version[tier].items()):
            print(f"   {v:12} {c:6d} gate emissions   (transcripts on this version: "
                  f"{versions_seen[tier][v]})")

print()
print("=" * 78)
print("4. COVERAGE -- eligible calls (Grep / code Read / explore-shaped Bash)")
print("   that actually drew a stack hook on that same tool_use_id")
print("=" * 78)
print(f"{'tier':10} {'eligible':>10} {'covered':>10} {'rate':>8}")
for tier in ("main", "agent", "workflow"):
    e = eligible[tier]["eligible"]; c = eligible[tier]["covered"]
    if e:
        print(f"{tier:10} {e:10d} {c:10d} {pct(c,e):>8}")

print()
print("=" * 78)
print("5. ADOPTION -- tool mix in stack-enabled transcripts")
print("=" * 78)
print(f"{'tier':10} {'tools':>9} {'CMM':>8} {'ctx':>8} {'raw':>9} {'CMM%':>7} {'ctx%':>7}")
for tier in ("main", "agent", "workflow"):
    st = tier_stats[tier]
    t = st["stack_tool_calls"]
    if t:
        print(f"{tier:10} {t:9d} {st['stack_cmm']:8d} {st['stack_ctx']:8d} "
              f"{st['stack_raw']:9d} {pct(st['stack_cmm'],t):>7} {pct(st['stack_ctx'],t):>7}")

print()
print("=" * 78)
print("6. REDIRECT -- next tool call immediately after a hard block")
print("=" * 78)
for tier in ("main", "agent", "workflow"):
    if after_block[tier]:
        tot = sum(after_block[tier].values())
        print(f"-- {tier} (n={tot}) --")
        for k, c in after_block[tier].most_common():
            print(f"   {c:6d} {pct(c,tot):>7}  {k}")

print()
print("=" * 78)
print("6b. REDIRECT split PER GATE (which gate actually changes behaviour)")
print("=" * 78)
print(f"{'tier':9} {'gate':24} {'n':>6} {'->CMM':>7} {'->ctx':>7} {'->raw':>7} {'->other':>8}")
for (tier, hid), ctr in sorted(after_block_gate.items(),
                              key=lambda kv: -sum(kv[1].values())):
    tot = sum(ctr.values())
    if tot < 10:
        continue
    print(f"{tier:9} {hid:24} {tot:6d} "
          f"{pct(ctr['CMM'],tot):>7} {pct(ctr['ctx'],tot):>7} "
          f"{pct(ctr['raw (Read/Grep/Glob/Bash)'],tot):>7} {pct(ctr['other'],tot):>8}")

print()
print("=" * 78)
print("6c. SPAWN GATING -- does agent-cmm-gate attach to Agent vs Workflow calls?")
print("=" * 78)
for tier in ("main", "agent", "workflow"):
    if spawn_gate[tier]:
        row = " | ".join(f"{k}={v}" for k, v in sorted(spawn_gate[tier].items()))
        print(f"   {tier:9} {row}")

print()
print("=" * 78)
print("7. ZERO-CMM sessions despite the stack firing")
print("=" * 78)
for tier in ("main", "agent", "workflow"):
    rows = [r for r in sess_rows if r[0] == tier and r[4] >= 5]
    if not rows:
        continue
    zero = [r for r in rows if r[5] == 0]
    zeroctx = [r for r in rows if r[6] == 0]
    print(f"{tier:10} transcripts with >=5 tool calls: {len(rows):5d} | "
          f"zero CMM: {len(zero):5d} ({pct(len(zero),len(rows)).strip()}) | "
          f"zero ctx: {len(zeroctx):5d} ({pct(len(zeroctx),len(rows)).strip()})")

print()
print("=" * 78)
print("8. TOP PROJECTS by stack-enabled transcript count")
print("=" * 78)
for p, c in proj_stack.most_common(15):
    print(f"   {c:6d}  {p}")
