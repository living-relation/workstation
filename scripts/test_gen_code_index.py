"""Tests for scripts/gen-code-index.py (descriptions per language, --check)."""
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "gen-code-index.py"
spec = importlib.util.spec_from_file_location("gen_code_index", SCRIPT)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


class Describe(unittest.TestCase):
    def one(self, name: str, text: str) -> str:
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / name
            p.write_text(text, encoding="utf-8")
            return gen.describe(p)

    def test_languages(self):
        self.assertEqual(self.one("a.ps1", "#Requires -Version 5.1\n# Does a thing.\n"), "Does a thing.")
        self.assertEqual(self.one("b.ps1", "<#\n.SYNOPSIS\n  Block help line.\n#>\n"), "Block help line.")
        self.assertEqual(self.one("c.py", '"""Doc line."""\n'), "Doc line.")
        self.assertEqual(self.one("d.py", '"""\nNext line doc.\n"""\n'), "Next line doc.")
        self.assertEqual(self.one("e.sh", "#!/bin/sh\n# Shell help.\n"), "Shell help.")
        self.assertEqual(self.one("f.cmd", "@echo off\nREM Cmd help.\n"), "Cmd help.")
        self.assertEqual(self.one("g.py", "import os\n"), "")

    def test_pipe_and_length(self):
        self.assertEqual(self.one("h.ps1", "# a | b\n"), "a / b")
        self.assertTrue(len(self.one("i.ps1", "# " + "x" * 400 + "\n")) <= gen.MAX)


class Check(unittest.TestCase):
    def test_repo_index_is_current(self):
        r = subprocess.run([sys.executable, str(SCRIPT), "--check"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_index_lists_itself_and_skips_tests(self):
        text = gen.render()
        self.assertIn("`scripts/gen-code-index.py`", text)
        self.assertNotIn("test_gen_code_index.py", text)
        self.assertNotIn("archives/", text.split("\n", 4)[-1].replace("archives/ are left out", ""))


if __name__ == "__main__":
    unittest.main()
