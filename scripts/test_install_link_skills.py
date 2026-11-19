#!/usr/bin/env python3
"""install.ps1 has no -LinkSkills switch and does not copy skills into ~/.claude/skills.

Dry runs (-WhatIf) in a temp -UserHome. Needs PowerShell. install.ps1 targets Windows;
on other systems the dry run is still attempted when pwsh is installed.
"""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

INSTALL = Path(__file__).resolve().parent.parent / "install.ps1"
PS = shutil.which("powershell") or shutil.which("pwsh")
MISSING = (
    "workstation-core plugin not added on claude.ai yet: "
    "add catalog living-relation/workstation and turn on workstation-core"
)


@unittest.skipUnless(PS, "install.ps1 needs PowerShell")
class InstallNoSkillCopy(unittest.TestCase):
    def dry_run(self, *flags: str) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as home:
            return subprocess.run(
                [PS, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(INSTALL),
                 "-WhatIf", "-UserHome", home, "-NoPopup", *flags],
                capture_output=True, text=True, timeout=300)

    def test_source_has_no_link_switch(self):
        text = INSTALL.read_text(encoding="utf-8")
        self.assertNotIn("LinkSkills", text)
        self.assertNotIn("link-skills.ps1", text)
        self.assertNotIn("skills: not linked", text)
        self.assertNotIn("skills not linked", text)

    def test_default_warns_when_plugin_is_absent(self):
        r = self.dry_run()
        out = r.stdout + r.stderr
        self.assertEqual(r.returncode, 0, out)
        self.assertIn(MISSING, out)
        self.assertNotIn("skills: not linked", out)
        self.assertNotIn("skills not linked", out)
        self.assertNotIn("would-link", out)
        low = out.lower()
        self.assertNotIn("skill zip", low)
        self.assertNotIn("upload", low)

    def test_link_switch_is_rejected(self):
        r = self.dry_run("-LinkSkills")
        out = r.stdout + r.stderr
        self.assertNotEqual(r.returncode, 0, out)
        self.assertIn("LinkSkills", out)


if __name__ == "__main__":
    unittest.main()
