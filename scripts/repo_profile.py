#!/usr/bin/env python3
"""Scan a repo and save what it stores: code, CAD, docs, harness.

A clear scan is a proposal. Unclear items are questions; this script does not guess them.
Answers go in repo-profile.json. A later scan does not overwrite that file, so a rerun matches.

  python3 scripts/repo_profile.py scan --repo <dir>
  python3 scripts/repo_profile.py save --repo <dir> --stores code,docs
"""
import argparse
import json
import sys
from pathlib import Path

STORES = ("code", "cad", "docs", "harness")
SKIP_DIRS = {
    ".git",
    ".venv",
    "node_modules",
    "__pycache__",
    ".tools",
}
CODE_EXT = {
    ".py", ".ps1", ".psm1", ".psd1", ".js", ".ts", ".tsx", ".jsx", ".go", ".rs",
    ".c", ".h", ".cpp", ".cs", ".java", ".sh", ".rb", ".php", ".swift", ".kt", ".cmd",
}
DOC_EXT = {".md", ".rst", ".adoc"}
CAD_EXT = {
    ".f3d", ".f3z", ".step", ".stp", ".iges", ".igs", ".sldprt", ".sldasm", ".slddrw",
    ".fcstd", ".ipt", ".iam", ".catpart", ".catproduct",
}
CAD_DIR_NAMES = {"cad", "drawings"}
HARNESS_DIR_NAMES = {"harness", "harnesses"}
PROFILE_NAME = "repo-profile.json"


def _is_harness_file(name):
    low = name.lower()
    return low.endswith(".harness.json") or low == "harness.json" or low.endswith(".harn")


def scan_tree(root):
    """Return counts, unclear store names, and a short reason for each unclear store."""
    root = Path(root).resolve()
    counts = {name: 0 for name in STORES}
    weak = {"cad": [], "harness": []}
    for dirpath, dirnames, filenames in os_walk(root):
        dirnames[:] = [name for name in dirnames if name not in SKIP_DIRS]
        folder = Path(dirpath).name.lower()
        cad_here = False
        harness_here = False
        real_files = []
        for filename in filenames:
            if filename.startswith("."):
                continue
            real_files.append(filename)
            suffix = Path(filename).suffix.lower()
            if suffix in CODE_EXT:
                counts["code"] += 1
            if suffix in DOC_EXT:
                counts["docs"] += 1
            if suffix in CAD_EXT:
                counts["cad"] += 1
                cad_here = True
            if _is_harness_file(filename):
                counts["harness"] += 1
                harness_here = True
        rel = str(Path(dirpath).resolve().relative_to(root))
        if rel == ".":
            rel = "."
        if folder in CAD_DIR_NAMES and real_files and not cad_here:
            weak["cad"].append(rel)
        if folder in HARNESS_DIR_NAMES and real_files and not harness_here:
            weak["harness"].append(rel)
    unclear = []
    reasons = {}
    if counts["cad"] == 0 and weak["cad"]:
        unclear.append("cad")
        reasons["cad"] = "folder named cad or drawings has files and no CAD model: %s" % ", ".join(weak["cad"])
    if counts["harness"] == 0 and weak["harness"]:
        unclear.append("harness")
        reasons["harness"] = (
            "folder named harness or harnesses has files and no harness file: %s" % ", ".join(weak["harness"])
        )
    proposed = [name for name in STORES if counts[name]]
    if not proposed and not unclear:
        unclear = list(STORES)
        reasons = {name: "nothing in the repo matched this store" for name in STORES}
    return {"counts": counts, "proposed": proposed, "unclear": unclear, "reasons": reasons}


def os_walk(root):
    import os
    return os.walk(root)


def profile_path(root):
    return Path(root).resolve() / PROFILE_NAME


def read_profile(root):
    path = profile_path(root)
    if not path.is_file():
        return None
    data = json.loads(path.read_text(encoding="utf-8"))
    stores = data.get("stores") if isinstance(data, dict) else None
    if not isinstance(stores, list):
        return None
    return [str(item) for item in stores]


def write_profile(root, stores):
    path = profile_path(root)
    payload = {"version": 1, "stores": list(stores)}
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return path


def parse_stores(text):
    items = [part.strip().lower() for part in text.split(",") if part.strip()]
    bad = [item for item in items if item not in STORES]
    if bad:
        raise ValueError("unknown store %s (use %s)" % (", ".join(bad), ", ".join(STORES)))
    # One copy, in the fixed order, so two saves of the same answers match byte for byte.
    return [name for name in STORES if name in set(items)]


def cmd_scan(root):
    found = scan_tree(root)
    saved = read_profile(root)
    print("repo: %s" % Path(root).resolve())
    print("proposal:")
    for name in STORES:
        mark = "yes" if name in found["proposed"] else "no"
        print("  %s: %s (%d)" % (name, mark, found["counts"][name]))
    if found["unclear"]:
        print("unclear: %s" % ", ".join(found["unclear"]))
        for name in found["unclear"]:
            print("  ask: %s — %s" % (name, found["reasons"].get(name, "unclear")))
    else:
        print("unclear: none")
    if saved is not None:
        print("saved: %s stores %s" % (PROFILE_NAME, ", ".join(saved) or "(none)"))
        print("rerun uses the saved profile; scan does not overwrite it")
        return 0
    if found["unclear"]:
        print("no profile saved; ask only the unclear items, then save")
        return 2
    print("clear proposal: %s" % ", ".join(found["proposed"]))
    print("save it with: python3 scripts/repo_profile.py save --stores %s" % ",".join(found["proposed"]))
    return 0


def cmd_save(root, stores, replace):
    chosen = parse_stores(stores)
    saved = read_profile(root)
    if saved is not None and saved != chosen and not replace:
        print(
            "saved profile stays (%s); pass --replace to change it" % ", ".join(saved),
            file=sys.stderr,
        )
        return 3
    if saved == chosen:
        print("saved profile already matches")
        return 0
    path = write_profile(root, chosen)
    print("wrote %s stores %s" % (path.name, ", ".join(chosen) or "(none)"))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="Propose and save what a repo stores.")
    parser.add_argument("command", choices=("scan", "save"))
    parser.add_argument("--repo", default=".", help="repo root (default: the current directory)")
    parser.add_argument("--stores", help="comma list: code,cad,docs,harness")
    parser.add_argument("--replace", action="store_true", help="overwrite a saved profile")
    args = parser.parse_args(argv)
    root = Path(args.repo)
    if not root.is_dir():
        print("not a directory: %s" % root, file=sys.stderr)
        return 2
    if args.command == "scan":
        return cmd_scan(root)
    if not args.stores and args.stores != "":
        print("save needs --stores", file=sys.stderr)
        return 2
    try:
        return cmd_save(root, args.stores or "", args.replace)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
