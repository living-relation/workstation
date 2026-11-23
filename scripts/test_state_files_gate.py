"""Tests for the branch state gate (.github/state-files-gate.sh and its git-checker template)."""
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GATE = ROOT / ".github" / "state-files-gate.sh"
TEMPLATE = ROOT / "skills" / "git-checker" / "hooks" / "state-files-gate.sh"


def git(repo, *args):
    subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@example.invalid",
                    "-c", "commit.gpgsign=false", *args], check=True, capture_output=True)


class GateTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name) / "r"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "core.hooksPath", str(Path(self._tmp.name) / "no-hooks"))

    def tearDown(self):
        self._tmp.cleanup()

    def commit(self, rel, text="x\n"):
        path = self.repo / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        git(self.repo, "add", rel)
        git(self.repo, "commit", "-q", "-m", rel)

    def run_gate(self):
        return subprocess.run(["bash", str(GATE), "HEAD"], cwd=self.repo, capture_output=True, text=True)

    def test_template_and_copy_match(self):
        self.assertEqual(GATE.read_bytes(), TEMPLATE.read_bytes())

    def test_root_state_and_archives_pass(self):
        self.commit("STATE.md")
        self.commit("BACKLOG.md")
        self.commit("archives/STATE-feat-a-20261122.md")
        self.commit("docs/STATE-notes.md")
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_top_level_branch_state_fails(self):
        self.commit("STATE.md")
        self.commit("STATE-feat-a.md")
        result = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertIn("STATE-feat-a.md", result.stdout)
        self.assertIn("archive-branch", result.stdout)


if __name__ == "__main__":
    unittest.main()
