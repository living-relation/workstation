#!/usr/bin/env python3
"""Create, check and archive live-state files in the memory store. Stdlib only.

Usage: state_manager.py init|verify|branches|new-branch|archive-branch [--repo DIR] [--branch B] [--store DIR]
  init            create <store>/<project>/ with STATE.md, BACKLOG.md and archives/ (never overwrites)
  verify          lint every STATE file, check an explicit Branch_States list and Last_Verified_SHA
  branches        print the generated '- Branch_States:' line from the STATE-*.md files
  new-branch      create STATE-<slug>.md for the branch (never writes the root STATE.md)
  archive-branch  move STATE-<slug>.md to archives/STATE-<slug>-<YYYYMMDD>.md (never writes STATE.md)
The root STATE.md has one writer, the coordinator. Its Branch_States line reads 'generated' (the
list comes from 'branches'), or the coordinator pastes the 'branches' output there.
Exit: 0 = OK (verify / branches / new-branch / archive-branch also exit 0 with a note when the
store is unreachable), 1 = cannot act (init with no store, trunk branch for a branch command),
2 = violation.
"""
import argparse
import datetime
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import state_lint  # noqa: E402
import state_paths  # noqa: E402

AGENT = "state_manager"
POINTER = re.compile(r"^(- Branch_States:)(.*)$")
SHA_LINE = re.compile(r"^Last_Verified_SHA:\s*(\S+)")
BACKLOG_HEADER = "# BACKLOG (append-only queue; newest at the bottom)\n"
GENERATED_POINTER = "generated (state_manager.py branches)"

TEMPLATE = """# STATE (max 30 lines, overwrite only)
Repo: {repo}
Branch: {branch}
Last_Verified_SHA: none
Updated: {today} -- {agent}

## Current Goal
- Objective: none yet
- Spec_Ref: none

## Active Blocker
- Status: NONE
- Detail: none

## Next Single Step
- [NEXT] Set the goal and first step in this file

## Pointers
- Branch_States: {pointer}
- Backlog: BACKLOG.md
- Latest_ADR: none
"""


def _note(message):
    print("state_manager: NOTE: %s" % message, file=sys.stderr)


def render(repo, branch, today=None, pointer="none"):
    today = today or datetime.date.today().isoformat()
    return TEMPLATE.format(repo=repo, branch=branch, today=today, agent=AGENT, pointer=pointer)


def _write_new(path, text):
    if path.exists():
        print("kept %s (already exists)" % path)
        return False
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print("created %s" % path)
    return True


def _pointer_value(state_text):
    for line in state_text.splitlines():
        match = POINTER.match(line.strip())
        if match:
            return match.group(2).strip()
    return None


def pointer_is_generated(state_text):
    value = _pointer_value(state_text)
    return value is not None and value.lower().startswith("generated")


def read_pointer(state_text):
    value = _pointer_value(state_text)
    if value is None:
        return None
    if not value or value.lower() == "none" or value.lower().startswith("generated"):
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


def branch_state_names(folder):
    return sorted(p.name for p in state_lint.project_files(folder) if p.name != state_paths.ROOT_STATE)


def branches_line(folder):
    return "- Branch_States: %s" % (", ".join(branch_state_names(folder)) or "none")


def _context(args):
    store = Path(args.store) if args.store else state_paths.find_store()
    project = state_paths.project_name(args.repo)
    branch = args.branch or state_paths.current_branch(args.repo)
    return store, project, branch


def _repo_label(args):
    root = state_paths.main_repo_root(args.repo)
    return root.name if root else "unknown"


def trunk_name(repo):
    default = state_paths._git(repo, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
    if default and default.startswith("origin/") and len(default) > len("origin/"):
        return default[len("origin/"):]
    return state_paths.current_branch(repo) or "main"


def cmd_init(store, project, branch, args):
    if not state_paths.store_reachable(store):
        print("state_manager: store unreachable: %s" % store, file=sys.stderr)
        return 1
    folder = state_paths.project_dir(store, project)
    (folder / state_paths.ARCHIVES).mkdir(parents=True, exist_ok=True)
    _write_new(folder / state_paths.ROOT_STATE,
               render(_repo_label(args), trunk_name(args.repo), pointer=GENERATED_POINTER))
    _write_new(folder / state_paths.BACKLOG, BACKLOG_HEADER)
    return 0


def _sha_known(repo, sha):
    return state_paths._git(repo, "cat-file", "-e", sha + "^{commit}") is not None


def cmd_verify(store, project, branch, args):
    folder = state_paths.project_dir(store, project)
    if not state_paths.store_reachable(store) or not folder.is_dir():
        _note("store or project folder unreachable (%s); nothing verified" % folder)
        return 0
    problems = []
    files = state_lint.project_files(folder)
    for path in files:
        problems += ["%s: %s" % (path.name, p) for p in state_lint.lint_file(path)]
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        for line in text.splitlines():
            match = SHA_LINE.match(line.strip())
            if match and match.group(1).lower() != "none" and not _sha_known(args.repo, match.group(1)):
                problems.append("%s: Last_Verified_SHA %s is not a commit in this repo" % (path.name, match.group(1)))
    root = folder / state_paths.ROOT_STATE
    root_text = root.read_text(encoding="utf-8-sig", errors="replace") if root.is_file() else ""
    if root_text and not pointer_is_generated(root_text):
        listed = read_pointer(root_text) or []
        hint = " (paste the output of 'state_manager.py branches', or write 'generated')"
        for name in listed:
            if not (folder / name).is_file():
                problems.append("STATE.md: Branch_States lists %s, which does not exist%s" % (name, hint))
        for name in branch_state_names(folder):
            if name not in listed:
                problems.append("STATE.md: Branch_States does not list %s%s" % (name, hint))
    if not (folder / state_paths.BACKLOG).is_file():
        problems.append("missing %s" % state_paths.BACKLOG)
    for problem in problems:
        print(problem)
    if problems:
        return 2
    print("state_manager: verify OK (%d STATE file(s))" % len(files))
    return 0


def _branch_guard(branch):
    if state_paths.is_trunk(branch):
        print("state_manager: '%s' is a trunk branch; it uses STATE.md (run init)" % branch, file=sys.stderr)
        return 1
    return 0


def cmd_new_branch(store, project, branch, args):
    if _branch_guard(branch):
        return 1
    folder = state_paths.project_dir(store, project)
    if not state_paths.store_reachable(store) or not folder.is_dir():
        _note("store or project folder unreachable (%s); no branch state made" % folder)
        return 0
    name = state_paths.branch_state_name(branch)
    _write_new(folder / name, render(_repo_label(args), branch))
    return 0


def cmd_branches(store, project, branch, args):
    folder = state_paths.project_dir(store, project)
    if not state_paths.store_reachable(store) or not folder.is_dir():
        _note("store or project folder unreachable (%s); no branch list" % folder)
        return 0
    print(branches_line(folder))
    return 0


def archive_name(folder, slug, today):
    base = folder / state_paths.ARCHIVES / ("STATE-%s-%s.md" % (slug, today))
    counter = 2
    candidate = base
    while candidate.exists():
        candidate = base.with_name("STATE-%s-%s-%d.md" % (slug, today, counter))
        counter += 1
    return candidate


def cmd_archive_branch(store, project, branch, args):
    if _branch_guard(branch):
        return 1
    folder = state_paths.project_dir(store, project)
    if not state_paths.store_reachable(store) or not folder.is_dir():
        _note("store or project folder unreachable (%s); nothing archived" % folder)
        return 0
    name = state_paths.branch_state_name(branch)
    source = folder / name
    if not source.is_file():
        _note("no %s to archive" % name)
    else:
        (folder / state_paths.ARCHIVES).mkdir(exist_ok=True)
        today = datetime.date.today().strftime("%Y%m%d")
        target = archive_name(folder, state_paths.slugify(branch), today)
        source.replace(target)
        print("archived %s -> %s" % (name, target))
    return 0


COMMANDS = {
    "init": cmd_init,
    "verify": cmd_verify,
    "branches": cmd_branches,
    "new-branch": cmd_new_branch,
    "archive-branch": cmd_archive_branch,
}


def main(argv=None):
    state_paths.configure_output()
    parser = argparse.ArgumentParser(description="Manage live-state files in the memory store.")
    parser.add_argument("command", choices=sorted(COMMANDS))
    parser.add_argument("--repo", default=".")
    parser.add_argument("--branch")
    parser.add_argument("--store", help="store root (overrides the normal resolution)")
    args = parser.parse_args(argv)
    store, project, branch = _context(args)
    if not project:
        print("state_manager: not a git repo: %s" % args.repo, file=sys.stderr)
        return 1
    return COMMANDS[args.command](store, project, branch, args)


if __name__ == "__main__":
    sys.exit(main())
