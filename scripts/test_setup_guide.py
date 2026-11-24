#!/usr/bin/env python3
"""The setup guide is printed by a script. SETUP-PROMPT.txt only points at it."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import setup_guide  # noqa: E402
import setup_phases  # noqa: E402
import setup_verify  # noqa: E402

PROMPT = ROOT / "SETUP-PROMPT.txt"


class SetupGuide(unittest.TestCase):
    def test_prints_every_phase_in_order(self):
        proc = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "setup_guide.py")],
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        positions = []
        for item in setup_phases.PHASES:
            marker = "Phase %s. %s" % (item["n"], item["title"])
            self.assertIn(marker, proc.stdout)
            positions.append(proc.stdout.index(marker))
        self.assertEqual(positions, sorted(positions))
        self.assertIn("claude plugin marketplace add living-relation/workstation", proc.stdout)
        self.assertIn("claude plugin install workstation-core@workstation-plugins", proc.stdout)
        self.assertIn("Claude Desktop > Settings > General > Instructions for Claude", proc.stdout)
        self.assertIn("Cowork Global instructions", proc.stdout)
        self.assertIn("Cursor Settings > Rules > User Rules", proc.stdout)
        self.assertIn(r"C:\Program Files\Sublime Text\subl.exe", proc.stdout)
        self.assertIn("-Quiet", proc.stdout)
        self.assertIn("Never force-push.", proc.stdout)
        self.assertNotIn("Check for updates in the catalog forces it sooner", proc.stdout)

    def test_prompt_is_only_a_pointer(self):
        text = PROMPT.read_text(encoding="utf-8")
        self.assertIn("scripts/setup_guide.py", text)
        self.assertIn("scripts/setup_verify.py", text)
        self.assertIn("INSTALL.md (Claude Code section)", text)
        self.assertNotIn("Claude Code on that account", text)
        self.assertNotIn("0. The package is the workstation repo clone", text)
        self.assertLess(len(text.splitlines()), 25)

    def test_verify_fails_until_every_phase_is_recorded(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "setup-phases.json"
            self.assertEqual(setup_verify.verify(log), 1)
            for number in setup_phases.phase_ids()[:-1]:
                self.assertEqual(setup_guide.complete(number, log), 0)
                self.assertEqual(setup_verify.verify(log), 1)
            last = setup_phases.phase_ids()[-1]
            self.assertEqual(setup_guide.complete(last, log), 0)
            self.assertEqual(setup_verify.verify(log), 0)
            # A second record does not drop a phase.
            self.assertEqual(setup_guide.complete(last, log), 0)
            self.assertEqual(setup_verify.verify(log), 0)

    def test_unknown_phase_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "setup-phases.json"
            self.assertEqual(setup_guide.complete("99", log), 2)
            self.assertFalse(log.exists())


if __name__ == "__main__":
    unittest.main()
