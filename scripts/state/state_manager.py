#!/usr/bin/env python3
"""Create, check and archive the live-state files in the repo. Stdlib only.

Live state lives in the repo (decision 2026-11-22): the worktree root holds STATE.md (trunk, the
coordinator's), STATE-<slug>.md (one per branch, committed on that branch), BACKLOG.md and archives/.

Usage: state_manager.py init|verify|branches|new-branch|archive-branch [--repo DIR] [--branch B]
                        [--no-fetch] [--show]
  init            create STATE.md, BACKLOG.md and archives/.gitkeep at the worktree root (never overwrites)
  verify          lint every STATE file, check an explicit Branch_States list and Last_Verified_SHA,
                  and on the trunk flag any top-level STATE-*.md left outside archives/
  branches        print the generated '- Branch_States:' line from every branch's STATE-<slug>.md:
                  pushed work through 'git fetch --prune' + 'git show origin/<branch>:STATE-<slug>.md',
                  unpushed work from each 'git worktree list' path. --no-fetch skips the fetch;
                  --show also prints each file (a new coordinator session reads its workers this way)
  new-branch      create STATE-<slug>.md at the worktree root (never writes the root STATE.md)
  archive-branch  archive the state file: 'git mv STATE-<slug>.md archives/STATE-<slug>-<YYYYMMDD>.md'
                  (never writes STATE.md). pr-closeout commits it as the PR's last commit before merge.
The root STATE.md has one writer, the coordinator. Its Branch_States line reads 'generated' (the
list comes from 'branches'), or the coordinator pastes the 'branches' output there.
Exit: 0 = OK (verify / branches / new-branch / archive-branch also exit 0 with a note when the repo
has no STATE.md yet), 1 = cannot act (not a git repo, trunk branch for a branch command),
2 = violation.
"""
import argparse
import datetime
import re
import subprocess
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


def _worktrees(repo):
    """(path, branch) for every worktree on a branch (porcelain output)."""
    out = state_paths._git(repo, "worktree", "list", "--porcelain")
    found, path = [], None
    for line in (out or "").splitlines():
        if line.startswith("worktree "):
            path = line[len("worktree "):].strip()
        elif line.startswith("branch refs/heads/") and path:
            found.append((Path(path), line[len("branch refs/heads/"):].strip()))
    return found


def _git_show(repo, spec):
    try:
        result = subprocess.run(["git", "-C", str(repo), "show", spec], capture_output=True)
    except OSError:
        return None
    if result.returncode != 0:
        return None
    return result.stdout.decode("utf-8", errors="replace")


def discover_branch_states(repo, fetch=True, remote="origin"):
    """Map STATE-<slug>.md -> (branch, source) for every non-trunk branch that has one.

    Pushed work: refs/remotes/<remote>/<branch>:STATE-<slug>.md (after 'git fetch --prune').
    Unpushed work: <worktree>/STATE-<slug>.md; a worktree copy wins over the pushed one.
    """
    if fetch and state_paths._git(repo, "remote") and state_paths._git(repo, "fetch", "--prune", "--quiet", remote) is None:
        _note("git fetch --prune %s failed; using the refs already here" % remote)
    trunk = default_branch(repo)
    found = {}
    refs = state_paths._git(repo, "for-each-ref", "--format=%(refname:short)", "refs/remotes/%s" % remote) or ""
    prefix = remote + "/"
    for ref in refs.splitlines():
        ref = ref.strip()
        if not ref.startswith(prefix) or ref == prefix + "HEAD":
            continue
        branch = ref[len(prefix):]
        if state_paths.is_trunk(branch) or branch == trunk:
            continue
        name = state_paths.branch_state_name(branch)
        spec = "%s:%s" % (ref, name)
        if state_paths._git(repo, "cat-file", "-e", spec) is not None:
            found[name] = (branch, spec)
    for path, branch in _worktrees(repo):
        if state_paths.is_trunk(branch) or branch == trunk:
            continue
        name = state_paths.branch_state_name(branch)
        candidate = path / name
        if candidate.is_file():
            found[name] = (branch, str(candidate))
    return found


def read_branch_state(repo, source):
    candidate = Path(source)
    if candidate.is_file():
        return candidate.read_text(encoding="utf-8-sig", errors="replace")
    return _git_show(repo, source)


def branches_line_from(names):
    return "- Branch_States: %s" % (", ".join(sorted(names)) or "none")


def _context(args):
    project = state_paths.project_name(args.repo)
    folder = state_paths.state_dir(args.repo)
    branch = args.branch or state_paths.current_branch(args.repo)
    return folder, project, branch


def _repo_label(args):
    root = state_paths.main_repo_root(args.repo)
    return root.name if root else "unknown"


def default_branch(repo):
    default = state_paths._git(repo, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
    if default and default.startswith("origin/") and len(default) > len("origin/"):
        return default[len("origin/"):]
    return None


def trunk_name(repo):
    return default_branch(repo) or state_paths.current_branch(repo) or "main"


def on_trunk(repo, branch):
    return state_paths.is_trunk(branch) or branch == default_branch(repo)


def _not_migrated(folder, what):
    _note("no %s in %s (repo not migrated; run init); %s" % (state_paths.ROOT_STATE, folder, what))
    return 0


def cmd_init(folder, project, branch, args):
    (folder / state_paths.ARCHIVES).mkdir(parents=True, exist_ok=True)
    keep = folder / state_paths.ARCHIVES / ".gitkeep"
    if not any((folder / state_paths.ARCHIVES).iterdir()):
        keep.write_text("", encoding="utf-8")
    _write_new(folder / state_paths.ROOT_STATE,
               render(_repo_label(args), trunk_name(args.repo), pointer=GENERATED_POINTER))
    _write_new(folder / state_paths.BACKLOG, BACKLOG_HEADER)
    return 0


def _sha_known(repo, sha):
    return state_paths._git(repo, "cat-file", "-e", sha + "^{commit}") is not None


def cmd_verify(folder, project, branch, args):
    if not state_paths.repo_migrated(folder):
        return _not_migrated(folder, "nothing verified")
    problems = []
    files = state_lint.project_files(folder)
    for path in files:
        problems += ["%s: %s" % (path.name, p) for p in state_lint.lint_file(path)]
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        for line in text.splitlines():
            match = SHA_LINE.match(line.strip())
            if match and match.group(1).lower() != "none" and not _sha_known(args.repo, match.group(1)):
                problems.append("%s: Last_Verified_SHA %s is not a commit in this repo" % (path.name, match.group(1)))
    if on_trunk(args.repo, branch):
        for name in branch_state_names(folder):
            problems.append("%s: a branch state file on the trunk; archive the state file "
                            "(state_manager.py archive-branch --branch <branch>) in a PR" % name)
    root = folder / state_paths.ROOT_STATE
    root_text = root.read_text(encoding="utf-8-sig", errors="replace") if root.is_file() else ""
    if root_text and not pointer_is_generated(root_text):
        listed = read_pointer(root_text) or []
        known = set(discover_branch_states(args.repo, fetch=False))
        hint = " (paste the output of 'state_manager.py branches', or write 'generated')"
        for name in listed:
            if name not in known:
                problems.append("STATE.md: Branch_States lists %s, which no branch has%s" % (name, hint))
        for name in sorted(known):
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


def cmd_new_branch(folder, project, branch, args):
    if _branch_guard(branch):
        return 1
    if not state_paths.repo_migrated(folder):
        return _not_migrated(folder, "no branch state made")
    name = state_paths.branch_state_name(branch)
    _write_new(folder / name, render(_repo_label(args), branch))
    return 0


def cmd_branches(folder, project, branch, args):
    found = discover_branch_states(args.repo, fetch=not args.no_fetch)
    print(branches_line_from(found))
    if args.show:
        for name in sorted(found):
            owner, source = found[name]
            text = read_branch_state(args.repo, source) or "(unreadable)\n"
            print("\n==> %s (branch %s, from %s)" % (name, owner, source))
            print(text.rstrip())
    return 0


def archive_name(folder, slug, today):
    base = folder / state_paths.ARCHIVES / ("STATE-%s-%s.md" % (slug, today))
    counter = 2
    candidate = base
    while candidate.exists():
        candidate = base.with_name("STATE-%s-%s-%d.md" % (slug, today, counter))
        counter += 1
    return candidate


def _tracked(folder, name):
    return state_paths._git(folder, "ls-files", "--error-unmatch", name) is not None


def cmd_archive_branch(folder, project, branch, args):
    if _branch_guard(branch):
        return 1
    if not state_paths.repo_migrated(folder):
        return _not_migrated(folder, "nothing archived")
    name = state_paths.branch_state_name(branch)
    source = folder / name
    if not source.is_file():
        _note("no %s to archive" % name)
        return 0
    (folder / state_paths.ARCHIVES).mkdir(exist_ok=True)
    today = datetime.date.today().strftime("%Y%m%d")
    target = archive_name(folder, state_paths.slugify(branch), today)
    rel = target.relative_to(folder).as_posix()
    if _tracked(folder, name):
        if state_paths._git(folder, "mv", name, rel) is None:
            print("state_manager: git mv %s %s failed" % (name, rel), file=sys.stderr)
            return 1
    else:
        source.replace(target)
        state_paths._git(folder, "add", rel)
    print("archived %s -> %s (staged; commit it as the PR's last commit before merge)" % (name, rel))
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
    parser = argparse.ArgumentParser(description="Manage the live-state files in the repo.")
    parser.add_argument("command", choices=sorted(COMMANDS))
    parser.add_argument("--repo", default=".")
    parser.add_argument("--branch")
    parser.add_argument("--no-fetch", action="store_true", help="branches: skip 'git fetch --prune'")
    parser.add_argument("--show", action="store_true", help="branches: also print each branch's STATE file")
    args = parser.parse_args(argv)
    folder, project, branch = _context(args)
    if not project or folder is None:
        print("state_manager: not a git repo: %s" % args.repo, file=sys.stderr)
        return 1
    return COMMANDS[args.command](folder, project, branch, args)


if __name__ == "__main__":
    sys.exit(main())
