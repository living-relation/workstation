#!/usr/bin/env python3
"""install.ps1 links skills only with -LinkSkills; -NoLinkSkills is a no-op; no zip-upload reminder.
Dry runs (-WhatIf) in a temp -UserHome. Windows only (install.ps1 targets Windows)."""
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

INSTALL = Path(__file__).resolve().parent.parent / "install.ps1"
PS = shutil.which("powershell") or shutil.which("pwsh")
LINK_WHATIF = 'Performing the operation "link ->'


@unittest.skipUnless(sys.platform == "win32" and PS, "install.ps1 needs Windows PowerShell")
class InstallLinkSkills(unittest.TestCase):
    def dry_run(self, *flags: str) -> str:
        with tempfile.TemporaryDirectory() as home:
            r = subprocess.run(
                [PS, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(INSTALL),
                 "-WhatIf", "-UserHome", home, "-NoPopup", *flags],
                capture_output=True, text=True, timeout=300)
            return r.stdout + r.stderr

    def test_default_does_not_link(self):
        out = self.dry_run()
        self.assertIn("skills: not linked", out)
        self.assertNotIn(LINK_WHATIF, out)

    def test_no_link_skills_is_a_no_op(self):
        out = self.dry_run("-NoLinkSkills")
        self.assertIn("skills: not linked", out)
        self.assertNotIn(LINK_WHATIF, out)

    def test_link_skills_opts_in(self):
        out = self.dry_run("-LinkSkills")
        self.assertNotIn("skills: not linked", out)
        self.assertIn(LINK_WHATIF, out)

    def test_no_zip_upload_reminder(self):
        out = self.dry_run().lower()
        self.assertNotIn("skill zip", out)
        self.assertNotIn("upload", out)


if __name__ == "__main__":
    unittest.main()
