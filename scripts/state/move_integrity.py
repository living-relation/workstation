#!/usr/bin/env python3
"""Check that a move or split of documents lost no line. Stdlib only.

Every content line of --before (a file, a folder, or a backup folder) must be accounted for:
  - found in the --after files or folders (exact line, or contained in a longer line), or
  - listed in --proposal with a tag; a [DONE] line must also exist in the git history of
    --git-history REPO (when given), because [DONE] means "kept in git history only".
A --before line that itself carries [DONE] is treated the same way as a [DONE] proposal row.
Lines with no letters or digits (blank, rules, table separators) are skipped.
Usage: move_integrity.py --before PATH [--after PATH...] [--git-history REPO] [--proposal FILE]
Exit: 0 = nothing lost, 2 = lost lines (each named as file:line), 1 = usage error.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import state_paths  # noqa: E402

TEXT_SUFFIXES = {".md", ".mdc", ".txt", ".csv", ".tsv", ".json", ".yml", ".yaml", ".toml"}
SKIPPED_NAMES = {"MANIFEST.sha256"}
TAGS = ("[DONE]", "[NEXT]", "[TASK]", "[ADR]", "[RULE]", "[SOT]", "[BKLG]")
DONE = "[DONE]"
LIST_MARKER = re.compile(r"^(?:[-*+>]\s+|\d+[.)]\s+|\[[ xX]\]\s+)+")
MIN_CONTAINED = 12
LEADING_TAG = re.compile(r"^(?:[-*+>]\s+|\d+[.)]\s+|\[[ xX]\]\s+)*(?:\[(?:DONE|NEXT|TASK|ADR|RULE|SOT|BKLG)\]\s*)+")


def normalize(line):
    text = line.strip().strip("|").strip()
    text = LIST_MARKER.sub("", text)
    for tag in TAGS:
        text = text.replace(tag, " ")
    return re.sub(r"\s+", " ", text).strip()


def has_content(text):
    return any(ch.isalnum() for ch in text)


def text_files(path):
    path = Path(path)
    if path.is_file():
        return [path]
    return sorted(p for p in path.rglob("*")
                  if p.is_file() and p.suffix.lower() in TEXT_SUFFIXES and p.name not in SKIPPED_NAMES
                  and ".git" not in p.parts)


def read_lines(path):
    return Path(path).read_text(encoding="utf-8-sig", errors="replace").splitlines()


def after_corpus(paths):
    lines = set()
    for root in paths:
        for path in text_files(root):
            for line in read_lines(path):
                norm = normalize(line)
                if has_content(norm):
                    lines.add(norm)
    return lines, "\n".join(sorted(lines))


def load_proposal(path):
    entries = {}
    if not path:
        return entries
    for line in read_lines(path):
        tags = [tag for tag in TAGS if tag in line]
        if not tags:
            continue
        cells = [normalize(line)]
        if "|" in line:
            cells += [normalize(cell) for cell in line.strip().strip("|").split("|")]
        for cell in cells:
            if has_content(cell):
                entries.setdefault(cell, set()).update(tags)
    return entries


def proposal_tags(norm, entries):
    if norm in entries:
        return entries[norm]
    if len(norm) >= MIN_CONTAINED:
        for text, tags in entries.items():
            if norm in text:
                return tags
    return set()


def history_needle(raw):
    return LEADING_TAG.sub("", raw.strip(), count=1).strip()


def in_git_history(repo, raw):
    needle = history_needle(raw)
    if not has_content(needle):
        return False
    try:
        result = subprocess.run(["git", "-C", str(repo), "log", "--all", "-F", "-S", needle, "--format=%H", "-1"],
                                capture_output=True, text=True, encoding="utf-8", errors="replace")
    except OSError:
        return False
    return result.returncode == 0 and bool(result.stdout.strip())


def check(before, after, proposal=None, git_history=None):
    after_lines, after_text = after_corpus(after or [])
    entries = load_proposal(proposal)
    lost, counts = [], {"total": 0, "moved": 0, "proposed": 0, "done": 0}
    for path in text_files(before):
        for number, raw in enumerate(read_lines(path), 1):
            norm = normalize(raw)
            if not has_content(norm):
                continue
            counts["total"] += 1
            if norm in after_lines or (len(norm) >= MIN_CONTAINED and norm in after_text):
                counts["moved"] += 1
                continue
            tags = proposal_tags(norm, entries)
            if DONE in raw:
                tags = tags | {DONE}
            if not tags:
                lost.append((path, number, raw.strip(), "no new home and no proposal tag"))
            elif tags == {DONE}:
                if git_history and not in_git_history(git_history, raw):
                    lost.append((path, number, raw.strip(), "[DONE] but not found in git history"))
                else:
                    counts["done"] += 1
            else:
                counts["proposed"] += 1
    return lost, counts


def main(argv=None):
    state_paths.configure_output()
    parser = argparse.ArgumentParser(description="Report lines lost in a document move.")
    parser.add_argument("--before", required=True)
    parser.add_argument("--after", nargs="*", default=[])
    parser.add_argument("--git-history", dest="git_history")
    parser.add_argument("--proposal")
    args = parser.parse_args(argv)
    for path in [args.before, *args.after] + ([args.proposal] if args.proposal else []):
        if not Path(path).exists():
            print("move_integrity: no such path: %s" % path, file=sys.stderr)
            return 1
    if not args.after and not args.proposal:
        print("move_integrity: give --after and/or --proposal", file=sys.stderr)
        return 1
    lost, counts = check(args.before, args.after, args.proposal, args.git_history)
    for path, number, text, reason in lost:
        print("LOST %s:%d: %s  (%s)" % (path, number, text, reason))
    print("move_integrity: %(total)d line(s): %(moved)d moved, %(proposed)d tagged in the proposal, "
          "%(done)d [DONE]" % counts + ", %d lost" % len(lost))
    return 2 if lost else 0


if __name__ == "__main__":
    sys.exit(main())
