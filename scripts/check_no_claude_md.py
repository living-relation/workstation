#!/usr/bin/env python3
"""Fail if this commit's tree tracks a Claude instruction file.

Looks at `git ls-tree HEAD` (the commit that is checked out). A path that
only appears in an older commit, in the diff, or as an untracked file is
not a failure. Dan's rule is the error text.
"""
import subprocess
import sys
from pathlib import Path

RULE = (
    "Dan's rule: fold the content into AGENTS.md (keep every rule, "
    "drop exact duplicates), then delete the CLAUDE file, in a PR."
)
BANNED_NAMES = {"CLAUDE.md", "CLAUDE.local.md"}


def is_banned(path: str) -> bool:
    norm = path.replace("\\", "/").strip()
    if norm.startswith("./"):
        norm = norm[2:]
    if not norm:
        return False
    name = norm.rsplit("/", 1)[-1]
    if name in BANNED_NAMES:
        return True
    return norm == ".claude/CLAUDE.md" or norm.endswith("/.claude/CLAUDE.md")


def tracked_paths(repo: Path) -> list[str]:
    """Names in HEAD's tree. Not the diff, and not a path left on disk."""
    r = subprocess.run(
        ["git", "ls-tree", "-r", "-z", "--name-only", "HEAD"],
        cwd=repo,
        check=True,
        capture_output=True,
    )
    return [p.decode("utf-8") for p in r.stdout.split(b"\0") if p]


def banned_tracked(repo: Path) -> list[str]:
    return [p for p in tracked_paths(repo) if is_banned(p)]


def main() -> int:
    hits = banned_tracked(Path.cwd())
    if not hits:
        return 0
    print("tracked Claude instruction file(s) are not allowed:", file=sys.stderr)
    for hit in hits:
        print(f"  {hit}", file=sys.stderr)
    print(RULE, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
