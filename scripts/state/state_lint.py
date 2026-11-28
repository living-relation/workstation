#!/usr/bin/env python3
"""Lint STATE files against STATE schema v1. Stdlib only.

Usage: state_lint.py FILE | --repo DIR
  FILE       lint one file
  --repo     lint STATE.md and STATE-*.md at the root of the repo (or worktree) DIR (archives/ is skipped)
Exit: 0 = OK (also when DIR is not a git repo or has no STATE.md yet: note on stderr), 2 = violation.
"""
import argparse
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import state_paths  # noqa: E402

MAX_LINES = 30
TITLE = "# STATE (max 30 lines, overwrite only)"
HEADER_KEYS = ("Repo:", "Branch:", "Last_Verified_SHA:", "Updated:")
SECTIONS = ("## Current Goal", "## Active Blocker", "## Next Single Step", "## Pointers")
SECTION_KEYS = {
    "## Current Goal": ("- Objective:", "- Spec_Ref:"),
    "## Active Blocker": ("- Status:", "- Detail:"),
    "## Pointers": ("- Branch_States:", "- Backlog:", "- Latest_ADR:"),
}
OPTIONAL_POINTER_KEYS = ("- Last_Cleanup:", "- Kept_Branches:", "- Question_Counter:")
POINTER_LINE = re.compile(r"^- [A-Za-z][A-Za-z0-9_]*:")
ALLOWED_TAG = "[NEXT]"
TAGS = ("[DONE]", "[NEXT]", "[TASK]", "[ADR]", "[RULE]", "[SOT]", "[BKLG]")
CARRIED = re.compile(r"\(carried\s+(\d+)\)", re.I)
STATUS = re.compile(r"^- Status:\s*(NONE|BLOCKED)\s*$")
UPDATED = re.compile(r"^Updated:\s*\d{4}-\d{2}-\d{2}\s+--\s+\S")
# Question IDs are one capital letter and one digit 1-9, never longer (D-2026-11-25-question-ids).
QUESTION_COUNTER = re.compile(r"^- Question_Counter:\s*[A-Z][1-9]\s*$")


def _sections(lines):
    found, current = {}, None
    for number, line in enumerate(lines, 1):
        if line.startswith("## "):
            current = line.strip()
            found.setdefault(current, [])
        elif current is not None:
            found[current].append((number, line))
    return found


def lint_text(text):
    problems = []
    lines = text.splitlines()
    if len(lines) > MAX_LINES:
        problems.append("has %d lines; the maximum is %d" % (len(lines), MAX_LINES))
    if not lines or lines[0].strip() != TITLE:
        problems.append("line 1 must be the title '%s'" % TITLE)
    head = [line.strip() for line in lines[1:]]
    for key in HEADER_KEYS:
        if not any(line.startswith(key) for line in head):
            problems.append("missing header '%s'" % key)
    if any(line.startswith("Updated:") for line in head) and not any(UPDATED.match(line) for line in head):
        problems.append("'Updated:' must read '<YYYY-MM-DD> -- <agent>'")
    sections = _sections(lines)
    for section in SECTIONS:
        if section not in sections:
            problems.append("missing section '%s'" % section)
    for section, keys in SECTION_KEYS.items():
        body = [line.strip() for _, line in sections.get(section, [])]
        for key in keys:
            if section in sections and not any(line.startswith(key) for line in body):
                problems.append("section '%s' is missing '%s'" % (section, key))
    allowed_pointers = SECTION_KEYS["## Pointers"] + OPTIONAL_POINTER_KEYS
    for number, line in sections.get("## Pointers", []):
        stripped = line.strip()
        if POINTER_LINE.match(stripped) and not stripped.startswith(allowed_pointers):
            problems.append("line %d: unknown Pointers line '%s' (allowed: %s)"
                            % (number, stripped.split(":")[0] + ":", ", ".join(k[2:] for k in allowed_pointers)))
        if stripped.startswith("- Question_Counter:") and not QUESTION_COUNTER.match(stripped):
            problems.append("line %d: '- Question_Counter:' must be one capital letter and one digit 1-9 "
                            "(A1 to A9, then B1 ...), never longer" % number)
    blocker = [line.strip() for _, line in sections.get("## Active Blocker", [])]
    status_lines = [line for line in blocker if line.startswith("- Status:")]
    if status_lines and not STATUS.match(status_lines[0]):
        problems.append("'- Status:' must be NONE or BLOCKED")
    if "## Next Single Step" in sections:
        steps = [line.strip() for _, line in sections["## Next Single Step"] if line.strip()]
        if not any(line.startswith("- " + ALLOWED_TAG) for line in steps):
            problems.append("'## Next Single Step' needs one '- [NEXT] ...' line")
    for number, line in enumerate(lines, 1):
        for tag in TAGS:
            if tag != ALLOWED_TAG and tag in line:
                problems.append("line %d: leftover tag %s (only %s is allowed in STATE)" % (number, tag, ALLOWED_TAG))
        for match in CARRIED.finditer(line):
            if int(match.group(1)) >= 2:
                problems.append("line %d: '(carried %s)': kept 2 runs, it must graduate or go to BACKLOG"
                                % (number, match.group(1)))
    return problems


def lint_file(path):
    try:
        text = Path(path).read_text(encoding="utf-8-sig", errors="replace")
    except OSError as error:
        return ["cannot read: %s" % error]
    return lint_text(text)


def project_files(folder):
    folder = Path(folder)
    return sorted(p for p in folder.glob("STATE*.md")
                  if p.is_file() and (p.name == state_paths.ROOT_STATE or p.name.startswith("STATE-")))


def _note(message):
    print("state_lint: NOTE: %s" % message, file=sys.stderr)


def main(argv=None):
    state_paths.configure_output()
    parser = argparse.ArgumentParser(description="Lint STATE files (schema v1).")
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("file", nargs="?")
    target.add_argument("--repo")
    args = parser.parse_args(argv)

    if args.file:
        files = [Path(args.file)]
    else:
        folder = state_paths.state_dir(args.repo)
        if folder is None:
            _note("not a git repo: %s; nothing linted" % args.repo)
            return 0
        if not state_paths.repo_migrated(folder):
            _note("no %s in %s (repo not migrated); nothing linted" % (state_paths.ROOT_STATE, folder))
            return 0
        files = project_files(folder)

    failed = 0
    for path in files:
        problems = lint_file(path)
        if problems:
            failed += 1
            for problem in problems:
                print("%s: %s" % (path, problem))
    if failed:
        print("state_lint: %d of %d file(s) violate STATE schema v1" % (failed, len(files)))
        return 2
    print("state_lint: OK (%d file(s))" % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
