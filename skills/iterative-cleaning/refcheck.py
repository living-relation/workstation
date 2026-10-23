#!/usr/bin/env python3
"""Stale-reference check for prose docs in a git repo (stdlib only).

Usage (run from the repo root, with -I so the repo cannot shadow stdlib):
    python -I refcheck.py [--terms 'regex'] FILE [FILE ...]

For each file it reports:
  MISSING     a backticked path or markdown link target that no tracked file / disk path matches
  LINE-DRIFT  a `path:123` citation whose line is blank or past the end of the file
  TERM        a line matching the retired-terms regex (names that were renamed, replaced or deleted)

Bare file names (no slash) count as present if any tracked file has that basename, which keeps
noise down. Output is a lead list, not a verdict: read every hit in context.
"""
import os, re, subprocess, sys

args = sys.argv[1:]
terms = None
if args[:1] == ["--terms"]:
    terms, args = args[1], args[2:]
tracked = set(subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout.split("\n"))
bases = {os.path.basename(t) for t in tracked}
EXT = r"\.(md|py|json|csv|html|yml|yaml|txt|bat|sh|ps1|toml|js|ts|c|h|xml|png|cfg|ini)$"
tok = re.compile(r"`([^`\n]+)`|\]\(([^)\s]+)\)")

for f in args:
    try:
        lines = open(f, encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        print(f"== {f}: UNREADABLE")
        continue
    base, out = os.path.dirname(f), []
    for i, l in enumerate(lines, 1):
        for m in tok.finditer(l):
            t = (m.group(1) or m.group(2)).strip()
            if re.search(r"[*<>{}$|\s]|^https?:|^#|^mailto|\.\.\.", t):
                continue
            ref, ln = t, None
            mm = re.match(r"(.+?):(\d+)(?:-\d+)?$", t)
            if mm:
                ref, ln = mm.group(1), int(mm.group(2))
            if "\\" in ref and ref[1:2] == ":":
                continue  # absolute Windows path: outside the repo
            ref = ref.replace("\\", "/").split("#")[0]
            if not re.search(EXT, ref) or ref.startswith(".") or ref.startswith("/"):
                continue
            if "/" not in ref and ref in bases:
                continue
            cands = {os.path.normpath(os.path.join(base, ref)).replace("\\", "/"),
                     os.path.normpath(ref).replace("\\", "/")}
            hit = next((c for c in cands if c in tracked or os.path.exists(c)), None)
            if not hit:
                out.append(f"  L{i} MISSING {t}")
            elif ln and os.path.isfile(hit):
                n = open(hit, encoding="utf-8", errors="replace").read().split("\n")
                if ln > len(n) or not n[ln - 1].strip():
                    out.append(f"  L{i} LINE-DRIFT {t}")
        if terms and re.search(terms, l):
            out.append(f"  L{i} TERM {re.search(terms, l).group(0)}: {l.strip()[:110]}")
    print(f"== {f}: {len(out)} hits")
    print("\n".join(out[:30]))
