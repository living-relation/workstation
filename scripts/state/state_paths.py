#!/usr/bin/env python3
"""Resolve the memory store, the project folder and the per-branch STATE file. Stdlib only.

Store root, first match wins:
  1. env WORKSTATION_MEMORY_STORE
  2. storePath in ~/.claude/hooks/memory-link-guard.config.json
  3. the target of the autoMemoryDirectory junction/link named in ~/.claude/settings.json
  4. ~/Projects/_claude/Claude Projects/Working Memory/memory
Project = the main repo's folder name, slugged (a worktree uses its main repo).
Branch file = STATE.md on a trunk branch (or detached), else STATE-<branch slug>.md.

Usage: state_paths.py [--repo DIR] [--branch B] [--json]
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ENV_STORE = "WORKSTATION_MEMORY_STORE"
TRUNK_BRANCHES = ("main", "master", "trunk")
DEFAULT_STORE_PARTS = ("Projects", "_claude", "Claude Projects", "Working Memory", "memory")
ROOT_STATE = "STATE.md"
BACKLOG = "BACKLOG.md"
ARCHIVES = "archives"


def configure_output():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")
        except (AttributeError, ValueError):
            pass


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", (text or "").lower()).strip("-")


def _read_json(path):
    try:
        with open(path, encoding="utf-8-sig") as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _expand(raw, home):
    text = os.path.expandvars(str(raw).strip())
    if text.startswith("~"):
        text = str(home) + text[1:]
    if text.startswith("\\\\?\\"):
        text = text[4:]
    return Path(text)


def _link_target(link):
    try:
        if not (link.is_symlink() or getattr(os.path, "isjunction", lambda _p: False)(link)):
            return None
        target = os.readlink(link)
        if target.startswith("\\\\?\\"):
            target = target[4:]
        target_path = Path(target)
        if not target_path.is_absolute():
            target_path = link.parent / target_path
        return target_path
    except OSError:
        return None


def find_store(env=None, home=None):
    env = os.environ if env is None else env
    home = Path(home) if home else Path.home()
    override = env.get(ENV_STORE, "").strip()
    if override:
        return _expand(override, home)
    config = _read_json(home / ".claude" / "hooks" / "memory-link-guard.config.json")
    if str(config.get("storePath") or "").strip():
        return _expand(config["storePath"], home)
    settings = _read_json(home / ".claude" / "settings.json")
    if str(settings.get("autoMemoryDirectory") or "").strip():
        target = _link_target(_expand(settings["autoMemoryDirectory"], home))
        if target is not None:
            return target
    return home.joinpath(*DEFAULT_STORE_PARTS)


def _git(repo, *args):
    try:
        result = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)
    except OSError:
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def _main_root_from_dotgit(repo):
    dotgit = Path(repo) / ".git"
    if dotgit.is_dir():
        return Path(repo)
    if dotgit.is_file():
        first = dotgit.read_text(encoding="utf-8", errors="replace").splitlines()[:1]
        gitdir = first[0].split(":", 1)[1].strip() if first and ":" in first[0] else ""
        parts = Path(gitdir.replace("\\", "/")).parts
        lowered = [p.lower() for p in parts]
        for index in range(len(lowered) - 1):
            if lowered[index] == ".git" and lowered[index + 1] == "worktrees":
                return Path(*parts[:index])
    return None


def main_repo_root(repo):
    repo = Path(repo).resolve()
    common = _git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if common:
        common_path = Path(common)
        if common_path.name.lower() == ".git":
            return common_path.parent
        return common_path.with_name(re.sub(r"\.git$", "", common_path.name, flags=re.I))
    return _main_root_from_dotgit(repo)


def project_name(repo):
    root = main_repo_root(repo)
    return slugify(root.name) if root else None


def current_branch(repo):
    branch = _git(repo, "rev-parse", "--abbrev-ref", "HEAD")
    return None if not branch or branch == "HEAD" else branch


def is_trunk(branch):
    return not branch or branch in TRUNK_BRANCHES


def branch_state_name(branch):
    if is_trunk(branch):
        return ROOT_STATE
    return "STATE-%s.md" % slugify(branch)


def project_dir(store, project):
    return Path(store) / project


def store_reachable(store):
    return Path(store).is_dir()


def resolve(repo=".", branch=None, env=None, home=None):
    store = find_store(env=env, home=home)
    project = project_name(repo)
    branch = branch or current_branch(repo)
    folder = project_dir(store, project) if project else None
    return {
        "store": str(store),
        "store_reachable": store_reachable(store),
        "repo_root": str(main_repo_root(repo) or ""),
        "project": project,
        "project_dir": str(folder) if folder else None,
        "branch": branch,
        "slug": slugify(branch) if branch else None,
        "state_file": str(folder / branch_state_name(branch)) if folder else None,
    }


def main(argv=None):
    configure_output()
    parser = argparse.ArgumentParser(description="Resolve store, project and STATE file paths.")
    parser.add_argument("--repo", default=".")
    parser.add_argument("--branch")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    info = resolve(args.repo, args.branch)
    if args.json:
        print(json.dumps(info, indent=2))
    else:
        for key, value in info.items():
            print("%s: %s" % (key, value))
    return 0 if info["project"] else 1


if __name__ == "__main__":
    sys.exit(main())
