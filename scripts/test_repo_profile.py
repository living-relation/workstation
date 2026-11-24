#!/usr/bin/env python3
"""repo_profile.py proposes stores and keeps a saved profile on rerun."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "repo_profile.py"


def run(*args):
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        timeout=30,
    )


class RepoProfile(unittest.TestCase):
    def test_clear_code_and_docs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "app.py").write_text("print(1)\n", encoding="utf-8")
            (root / "README.md").write_text("# hi\n", encoding="utf-8")
            proc = run("scan", "--repo", str(root))
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertIn("code: yes", proc.stdout)
            self.assertIn("docs: yes", proc.stdout)
            self.assertIn("cad: no", proc.stdout)
            self.assertIn("harness: no", proc.stdout)
            self.assertIn("unclear: none", proc.stdout)
            saved = run("save", "--repo", str(root), "--stores", "docs,code")
            self.assertEqual(saved.returncode, 0, saved.stderr)
            data = json.loads((root / "repo-profile.json").read_text(encoding="utf-8"))
            self.assertEqual(data["stores"], ["code", "docs"])
            again = run("scan", "--repo", str(root))
            self.assertEqual(again.returncode, 0, again.stderr)
            self.assertIn("rerun uses the saved profile", again.stdout)
            self.assertEqual((root / "repo-profile.json").read_text(encoding="utf-8"), json.dumps(
                {"version": 1, "stores": ["code", "docs"]}, indent=2
            ) + "\n")

    def test_cad_and_harness_files_are_clear(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "bracket.f3d").write_bytes(b"x")
            (root / "main.harness.json").write_text("{}\n", encoding="utf-8")
            proc = run("scan", "--repo", str(root))
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertIn("cad: yes", proc.stdout)
            self.assertIn("harness: yes", proc.stdout)
            self.assertIn("unclear: none", proc.stdout)

    def test_named_folder_without_files_of_that_kind_is_unclear(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cad = root / "cad"
            cad.mkdir()
            (cad / "notes.txt").write_text("later\n", encoding="utf-8")
            harness = root / "harnesses"
            harness.mkdir()
            (harness / "readme.txt").write_text("later\n", encoding="utf-8")
            (root / "app.py").write_text("print(1)\n", encoding="utf-8")
            proc = run("scan", "--repo", str(root))
            self.assertEqual(proc.returncode, 2, proc.stdout + proc.stderr)
            self.assertIn("unclear: cad, harness", proc.stdout)
            self.assertFalse((root / "repo-profile.json").exists())

    def test_save_does_not_replace_a_profile_unless_asked(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "app.py").write_text("print(1)\n", encoding="utf-8")
            first = run("save", "--repo", str(root), "--stores", "code")
            self.assertEqual(first.returncode, 0, first.stderr)
            blocked = run("save", "--repo", str(root), "--stores", "code,docs")
            self.assertEqual(blocked.returncode, 3, blocked.stdout + blocked.stderr)
            data = json.loads((root / "repo-profile.json").read_text(encoding="utf-8"))
            self.assertEqual(data["stores"], ["code"])
            replaced = run("save", "--repo", str(root), "--stores", "code,docs", "--replace")
            self.assertEqual(replaced.returncode, 0, replaced.stderr)
            data = json.loads((root / "repo-profile.json").read_text(encoding="utf-8"))
            self.assertEqual(data["stores"], ["code", "docs"])

    def test_this_repo_scan_matches_its_saved_profile(self):
        proc = run("scan", "--repo", str(ROOT))
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("unclear: none", proc.stdout)
        saved = json.loads((ROOT / "repo-profile.json").read_text(encoding="utf-8"))
        self.assertEqual(saved["version"], 1)
        self.assertEqual(saved["stores"], ["code", "docs"])


if __name__ == "__main__":
    unittest.main()
