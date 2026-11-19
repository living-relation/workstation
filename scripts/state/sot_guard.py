#!/usr/bin/env python3
"""Source-of-truth guard: the per-repo SoT registry `.claude/sot.json`. Stdlib only.

Agents write and keep sources of truth, only with the owner's yes; this tool proves each edit:
  match <path>          which registry entry a path belongs to (sot, derived or none), as JSON.
  after-edit <path>     run the entry's fast checks; for `report: cells`, list changed CSV cells vs HEAD.
                        A derived (generated) file edited by hand is a warning. Exit 2 on a failure.
  check [--base REF]    run every check of each SoT entry changed vs the merge-base with REF (default:
                        origin/HEAD, else main / master / trunk) plus staged and unstaged changes. A
                        derived file changed without a change to its entry's SoT paths fails. Exit 2.
  lint-registry         warn on entries with no checks, derived globs that overlap SoT paths, paths
                        that match no tracked file; exit 2 when the registry itself is invalid.
No registry: every command exits 0 (check and lint with a note on stderr).
Globs: repo-relative, `*` and `?` stay in one folder, `**` crosses folders, a trailing `/` means the folder.
"""
import argparse
import csv
import io
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REGISTRY = Path(".claude") / "sot.json"
ENTRY_KEYS = {"name", "paths", "checks", "regenerate", "derived", "report"}
REPORTS = {"cells", "lines", "none"}
TRUNKS = ("main", "master", "trunk")
CHECK_TIMEOUT = 600
REPORT_LIMIT = 200


class RegistryError(Exception):
    pass


def configure_output():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True,
                          encoding="utf-8", errors="replace")


def repo_root(start):
    start = Path(start)
    folder = start if start.is_dir() else start.parent
    while not folder.exists() and folder != folder.parent:
        folder = folder.parent
    result = git(folder, "rev-parse", "--show-toplevel")
    if result.returncode != 0 or not result.stdout.strip():
        return None
    return Path(result.stdout.strip()).resolve()


def glob_regex(glob):
    raw = glob.strip()
    key = raw.replace("\\", "/").strip("/").lower()
    if raw.endswith(("/", "\\")):
        key += "/**"
    out, i = [], 0
    while i < len(key):
        c = key[i]
        if key.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
            continue
        if key.startswith("**", i):
            out.append(".*")
            i += 2
            continue
        out.append("[^/]*" if c == "*" else "[^/]" if c == "?" else re.escape(c))
        i += 1
    return re.compile("^" + "".join(out) + "$")


def matches(rel, globs):
    key = rel.replace("\\", "/").strip("/").lower()
    return any(glob_regex(g).match(key) for g in globs)


def _string_list(entry, key, where):
    value = entry.get(key, [])
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, list) or not all(isinstance(v, str) and v.strip() for v in value):
        raise RegistryError("%s: %s must be a list of non-empty strings" % (where, key))
    return value


def _checks(entry, where):
    value = entry.get("checks", [])
    if not isinstance(value, list):
        raise RegistryError("%s: checks must be a list" % where)
    out = []
    for i, item in enumerate(value):
        if isinstance(item, str) and item.strip():
            out.append({"run": item, "fast": False})
        elif isinstance(item, dict) and isinstance(item.get("run"), str) and item["run"].strip():
            fast = item.get("fast", False)
            if not isinstance(fast, bool):
                raise RegistryError("%s: checks[%d].fast must be true or false" % (where, i))
            out.append({"run": item["run"], "fast": fast})
        else:
            raise RegistryError("%s: checks[%d] must be a command or {\"run\": ..., \"fast\": ...}" % (where, i))
    return out


def load_registry(root):
    path = Path(root) / REGISTRY
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise RegistryError("%s: %s" % (REGISTRY.as_posix(), e))
    if not isinstance(data, dict) or not isinstance(data.get("entries"), list):
        raise RegistryError("%s: needs {\"entries\": [...]}" % REGISTRY.as_posix())
    entries = []
    for i, raw in enumerate(data["entries"]):
        where = "entries[%d]" % i
        if not isinstance(raw, dict):
            raise RegistryError("%s must be an object" % where)
        unknown = sorted(set(raw) - ENTRY_KEYS)
        if unknown:
            raise RegistryError("%s: unknown keys %s" % (where, ", ".join(unknown)))
        paths = _string_list(raw, "paths", where)
        if not paths:
            raise RegistryError("%s: paths is required" % where)
        report = raw.get("report", "none")
        if report not in REPORTS:
            raise RegistryError("%s: report must be one of %s" % (where, ", ".join(sorted(REPORTS))))
        entries.append({
            "name": raw.get("name") or paths[0],
            "paths": paths,
            "checks": _checks(raw, where),
            "regenerate": _string_list(raw, "regenerate", where),
            "derived": _string_list(raw, "derived", where),
            "report": report,
        })
    return entries


def relative(root, path):
    full = os.path.realpath(str(path))
    base = os.path.realpath(str(root)).rstrip(os.sep)
    if not os.path.normcase(full).startswith(os.path.normcase(base) + os.sep):
        return None
    return Path(full[len(base) + 1:]).as_posix()


def classify(entries, rel):
    for entry in entries:
        if matches(rel, entry["paths"]):
            return "sot", entry
    for entry in entries:
        if entry["derived"] and matches(rel, entry["derived"]):
            return "derived", entry
    return None, None


def run_check(root, command):
    try:
        result = subprocess.run(command, shell=True, cwd=str(root), capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=CHECK_TIMEOUT)
    except subprocess.TimeoutExpired:
        return False, "timed out after %ds" % CHECK_TIMEOUT
    tail = (result.stdout + result.stderr).strip().splitlines()[-5:]
    return result.returncode == 0, "\n".join(tail)


def head_text(root, rel):
    result = git(root, "show", "HEAD:" + rel)
    return result.stdout if result.returncode == 0 else None


def _rows(text):
    return list(csv.reader(io.StringIO(text))) if text else []


def changed_cells(old_text, new_text):
    old, new = _rows(old_text), _rows(new_text)
    header = (new or old or [[]])[0]
    changes = []
    for r in range(max(len(old), len(new))):
        a = old[r] if r < len(old) else None
        b = new[r] if r < len(new) else None
        label = "row %d" % (r + 1)
        if a is None:
            changes.append("%s added: %s" % (label, ",".join(b)))
            continue
        if b is None:
            changes.append("%s removed: %s" % (label, ",".join(a)))
            continue
        for c in range(max(len(a), len(b))):
            va = a[c] if c < len(a) else ""
            vb = b[c] if c < len(b) else ""
            if va != vb:
                column = header[c] if c < len(header) and header[c] else "col %d" % (c + 1)
                changes.append("%s %s: %r -> %r" % (label, column, va, vb))
    return changes


def changed_lines(old_text, new_text):
    old = (old_text or "").splitlines()
    new = (new_text or "").splitlines()
    return ["- " + line for line in old if line not in new] + ["+ " + line for line in new if line not in old]


def report_changes(root, rel, entry):
    if entry["report"] == "none":
        return []
    path = root / rel
    new_text = path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""
    old_text = head_text(root, rel)
    if entry["report"] == "cells":
        return changed_cells(old_text, new_text)
    return changed_lines(old_text, new_text)


def cmd_match(entries, rel):
    kind, entry = classify(entries, rel) if rel else (None, None)
    out = {"path": rel, "kind": kind, "entry": entry["name"] if entry else None,
           "checks": [c["run"] for c in entry["checks"]] if kind == "sot" else [],
           "fast_checks": [c["run"] for c in entry["checks"] if c["fast"]] if kind == "sot" else [],
           "regenerate": entry["regenerate"] if entry else []}
    print(json.dumps(out))
    return 0


def _print_failure_tail(tail):
    for line in tail.splitlines():
        print("    " + line)


def cmd_after_edit(root, entries, rel):
    kind, entry = classify(entries, rel)
    if kind is None:
        return 0
    if kind == "derived":
        how = "; ".join(entry["regenerate"]) or "its generator"
        print("SOT WARNING: %s is generated from '%s'; never edit it by hand. Revert it and run: %s. "
              "sot_guard.py check fails at commit time on a hand edit." % (rel, entry["name"], how))
        return 2
    failed = 0
    print("SoT edit: %s (entry '%s'). Report every changed value and these results to the owner." % (rel, entry["name"]))
    if not entry["checks"]:
        print("SOT WARNING: entry '%s' has no checks; nothing proves this edit." % entry["name"])
        failed += 1
    for check in (c for c in entry["checks"] if c["fast"]):
        ok, tail = run_check(root, check["run"])
        print("%s: %s" % ("PASS" if ok else "FAIL", check["run"]))
        if not ok:
            failed += 1
            _print_failure_tail(tail)
    slow = [c["run"] for c in entry["checks"] if not c["fast"]]
    if slow:
        print("At commit (sot_guard.py check): " + "; ".join(slow))
    if entry["regenerate"]:
        print("Regenerate derived files: " + "; ".join(entry["regenerate"]))
    if entry["report"] != "none":
        changes = report_changes(root, rel, entry)
        print("Changed vs HEAD (%d):" % len(changes))
        for line in changes[:REPORT_LIMIT]:
            print("  " + line)
        if len(changes) > REPORT_LIMIT:
            print("  ... %d more" % (len(changes) - REPORT_LIMIT))
    if failed:
        print("SOT CHECK FAILED: %d problem(s) in %s. Fix or revert before going on." % (failed, rel))
        return 2
    return 0


def default_base(root):
    head = git(root, "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD")
    if head.returncode == 0 and head.stdout.strip():
        return head.stdout.strip()
    for name in ["origin/" + t for t in TRUNKS] + list(TRUNKS):
        if git(root, "rev-parse", "-q", "--verify", name).returncode == 0:
            return name
    return None


def changed_files(root, base):
    names = set()
    commands = [("diff", "--name-only", "--cached"), ("diff", "--name-only"),
                ("ls-files", "--others", "--exclude-standard")]
    if base:
        mb = git(root, "merge-base", "HEAD", base)
        if mb.returncode == 0 and mb.stdout.strip():
            commands.append(("diff", "--name-only", mb.stdout.strip(), "HEAD"))
    for args in commands:
        result = git(root, *args)
        if result.returncode == 0:
            names.update(line.strip() for line in result.stdout.splitlines() if line.strip())
    return sorted(names)


def cmd_check(root, entries, base):
    files = changed_files(root, base or default_base(root))
    touched, derived_hits = {}, {}
    for rel in files:
        kind, entry = classify(entries, rel)
        if kind == "sot":
            touched.setdefault(entry["name"], (entry, []))[1].append(rel)
        elif kind == "derived":
            derived_hits.setdefault(entry["name"], (entry, []))[1].append(rel)
    failed = 0
    for name, (entry, rels) in derived_hits.items():
        if name not in touched:
            failed += 1
            print("FAIL: %s changed without a change to '%s' (generated files are never hand-edited; "
                  "regenerate with: %s)" % (", ".join(rels), name, "; ".join(entry["regenerate"]) or "its generator"))
    for name, (entry, rels) in touched.items():
        print("SoT '%s' changed: %s" % (name, ", ".join(rels)))
        if not entry["checks"]:
            failed += 1
            print("FAIL: entry '%s' has no checks; nothing proves this change" % name)
        for check in entry["checks"]:
            ok, tail = run_check(root, check["run"])
            print("%s: %s" % ("PASS" if ok else "FAIL", check["run"]))
            if not ok:
                failed += 1
                _print_failure_tail(tail)
    if failed:
        print("sot check: %d failure(s)" % failed)
        return 2
    if touched or derived_hits:
        print("sot check: ok")
    return 0


def tracked_files(root):
    result = git(root, "ls-files")
    return [line for line in result.stdout.splitlines() if line] if result.returncode == 0 else []


def _literal(glob):
    return not any(ch in glob for ch in "*?[") and not glob.strip().endswith(("/", "\\"))


def cmd_lint(root, entries):
    warnings = []
    files = tracked_files(root)
    all_sot = [g for e in entries for g in e["paths"]]
    for entry in entries:
        name = entry["name"]
        if not entry["checks"]:
            warnings.append("entry '%s' has no checks" % name)
        elif not any(c["fast"] for c in entry["checks"]):
            warnings.append("entry '%s' has no fast check; after-edit proves nothing until commit" % name)
        for glob in entry["paths"]:
            if not any(matches(f, [glob]) for f in files):
                warnings.append("entry '%s': path '%s' matches no tracked file" % (name, glob))
        for glob in entry["derived"]:
            overlap = [f for f in files if matches(f, [glob]) and matches(f, all_sot)]
            overlap += [g for g in all_sot if _literal(g) and matches(g, [glob])]
            overlap += [glob] if _literal(glob) and matches(glob, all_sot) else []
            if overlap:
                warnings.append("entry '%s': derived '%s' overlaps SoT paths (%s)"
                                % (name, glob, ", ".join(sorted(set(overlap)))))
        if entry["derived"] and not entry["regenerate"]:
            warnings.append("entry '%s' lists derived files but no regenerate command" % name)
    for w in warnings:
        print("WARN: " + w)
    print("sot registry: %d entr%s, %d warning(s)" % (len(entries), "y" if len(entries) == 1 else "ies", len(warnings)))
    return 0


def main(argv=None):
    configure_output()
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", default=None, help="repo root (default: the repo holding the path, else cwd)")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("match", "after-edit"):
        sub.add_parser(name).add_argument("path")
    sub.add_parser("check").add_argument("--base", default=None)
    sub.add_parser("lint-registry")
    args = parser.parse_args(argv)
    start = args.repo or getattr(args, "path", None) or "."
    root = repo_root(Path(start).resolve())
    if root is None:
        return cmd_match([], None) if args.command == "match" else 0
    try:
        entries = load_registry(root)
    except RegistryError as e:
        print("sot registry invalid: %s" % e, file=sys.stderr if args.command == "match" else sys.stdout)
        return 2
    if entries is None:
        if args.command in ("check", "lint-registry"):
            print("sot: no %s in %s" % (REGISTRY.as_posix(), root), file=sys.stderr)
        return cmd_match([], None) if args.command == "match" else 0
    if args.command == "match":
        return cmd_match(entries, relative(root, args.path))
    if args.command == "after-edit":
        rel = relative(root, args.path)
        return cmd_after_edit(root, entries, rel) if rel else 0
    if args.command == "check":
        return cmd_check(root, entries, args.base)
    return cmd_lint(root, entries)


if __name__ == "__main__":
    sys.exit(main())
