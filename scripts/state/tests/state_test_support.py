import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS))

VALID_STATE = """# STATE (max 30 lines, overwrite only)
Repo: sample-repo
Branch: main
Last_Verified_SHA: none
Updated: 2026-01-02 -- test-agent

## Current Goal
- Objective: Ship the sample feature
- Spec_Ref: none

## Active Blocker
- Status: NONE
- Detail: none

## Next Single Step
- [NEXT] Edit docs/sample.md

## Pointers
- Branch_States: none
- Backlog: BACKLOG.md
- Latest_ADR: none
"""


def run_tool(script, *args, cwd=None, env=None):
    full_env = dict(os.environ)
    full_env.update(env or {})
    return subprocess.run([sys.executable, str(TOOLS / script), *map(str, args)], cwd=cwd, env=full_env,
                          capture_output=True, text=True, encoding="utf-8", errors="replace")


def git(repo, *args):
    result = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError("git %s failed: %s" % (" ".join(args), result.stderr))
    return result.stdout.strip()


def make_repo(parent, name="Sample_Repo"):
    repo = Path(parent) / name
    repo.mkdir(parents=True)
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.name", "Test")
    git(repo, "config", "user.email", "test@example.invalid")
    git(repo, "config", "commit.gpgsign", "false")
    git(repo, "config", "core.hooksPath", str(Path(parent) / "no-hooks"))
    return repo


def commit_file(repo, rel, text, message="add"):
    path = Path(repo) / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    git(repo, "add", rel)
    git(repo, "commit", "-q", "-m", message)
    return path


class TempDirCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(ignore_cleanup_errors=True)
        self.tmp = Path(self._tmp.name).resolve()

    def tearDown(self):
        self._tmp.cleanup()
