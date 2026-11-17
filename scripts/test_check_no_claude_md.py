"""The CLAUDE-file check reads HEAD's tree, not a stale path or the diff."""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import check_no_claude_md as chk  # noqa: E402

GIT_ENV = {
    **os.environ,
    "GIT_AUTHOR_NAME": "test",
    "GIT_AUTHOR_EMAIL": "test@example.com",
    "GIT_COMMITTER_NAME": "test",
    "GIT_COMMITTER_EMAIL": "test@example.com",
}


def git(repo: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=repo, check=True, env=GIT_ENV, capture_output=True)


def commit_file(repo: Path, rel: str, text: str = "x\n") -> None:
    path = repo / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    git(repo, "add", "--", rel)
    git(repo, "commit", "-m", f"add {rel}")


class CheckNoClaudeMd(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        git(self.repo, "init", "-b", "main")
        commit_file(self.repo, "README.md", "hello\n")

    def tearDown(self):
        self.tmp.cleanup()

    def test_clean_tree_passes(self):
        self.assertEqual(chk.banned_tracked(self.repo), [])

    def test_root_claude_md_fails_with_dans_rule(self):
        commit_file(self.repo, "CLAUDE.md", "@AGENTS.md\n")
        hits = chk.banned_tracked(self.repo)
        self.assertEqual(hits, ["CLAUDE.md"])
        self.assertIn("fold the content into AGENTS.md", chk.RULE)
        self.assertIn("drop exact duplicates", chk.RULE)
        self.assertIn("in a PR", chk.RULE)

    def test_nested_names_fail(self):
        commit_file(self.repo, "docs/CLAUDE.local.md")
        commit_file(self.repo, ".claude/CLAUDE.md")
        commit_file(self.repo, "pkg/.claude/CLAUDE.md")
        self.assertEqual(
            chk.banned_tracked(self.repo),
            [".claude/CLAUDE.md", "docs/CLAUDE.local.md", "pkg/.claude/CLAUDE.md"],
        )

    def test_deleted_file_is_not_a_stale_hit(self):
        commit_file(self.repo, "CLAUDE.md", "@AGENTS.md\n")
        git(self.repo, "rm", "CLAUDE.md")
        git(self.repo, "commit", "-m", "delete CLAUDE.md")
        self.assertEqual(chk.banned_tracked(self.repo), [])
        (self.repo / "CLAUDE.md").write_text("@AGENTS.md\n", encoding="utf-8")
        self.assertEqual(chk.banned_tracked(self.repo), [])

    def test_other_names_pass(self):
        commit_file(self.repo, "memory/templates/working-memory-CLAUDE.md", "catalog\n")
        commit_file(self.repo, "AGENTS.md", "Read CLAUDE.md in prose only.\n")
        self.assertEqual(chk.banned_tracked(self.repo), [])


if __name__ == "__main__":
    unittest.main()
