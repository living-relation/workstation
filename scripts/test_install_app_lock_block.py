#!/usr/bin/env python3
"""install.ps1 adds the Fusion Desktop lock lines to an older app-locks block in <Projects>\\AGENTS.md.

Dry run (-WhatIf) in a temp -UserHome, so nothing is written. Needs PowerShell.
"""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INSTALL = ROOT / "install.ps1"
TEMPLATE = ROOT / "memory" / "templates" / "app-locks.md"
PS = shutil.which("pwsh") or shutil.which("powershell")

OLD_BLOCK = (
    "<!-- app-locks:v1 -->\n"
    "## App locks (one agent at a time on this PC)\n"
    "The harness.design desktop app (section 5b) has one lock on this PC.\n"
    "- Acquire: app-lock.ps1 acquire -Name harness-design\n"
    "- Check in: app-lock.ps1 checkin -Name harness-design\n"
    "- Release: app-lock.ps1 release -Name harness-design\n"
    "<!-- /app-locks:v1 -->\n"
)


class TemplateHasFusionDesktopLock(unittest.TestCase):
    def test_template_lines(self):
        text = TEMPLATE.read_text(encoding="utf-8")
        for verb in ("acquire", "checkin", "release"):
            self.assertIn(f"{verb} -Name fusion-desktop", text)
        self.assertIn("Fusion Compute and Fusion Data MCP need no lock", text)
        self.assertLess(text.index("Local Fusion Desktop"), text.index("<!-- /app-locks:v1 -->"))


@unittest.skipUnless(PS, "install.ps1 needs PowerShell")
class InstallAddsFusionDesktopLines(unittest.TestCase):
    def dry_run(self, agents_text: str) -> tuple[str, str]:
        with tempfile.TemporaryDirectory() as home:
            projects = Path(home) / "Projects"
            projects.mkdir()
            agents = projects / "AGENTS.md"
            agents.write_text(agents_text, encoding="utf-8")
            r = subprocess.run(
                [PS, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(INSTALL),
                 "-WhatIf", "-UserHome", home, "-NoPopup"],
                capture_output=True, text=True, timeout=300)
            after = agents.read_text(encoding="utf-8")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(after, agents_text, "a dry run must not write")
        return r.stdout + r.stderr, after

    def test_old_block_gets_fusion_lines(self):
        out, _ = self.dry_run("# Projects\n\n" + OLD_BLOCK)
        self.assertIn("add the Fusion Desktop lock lines", out)

    def test_current_block_left_alone(self):
        block = TEMPLATE.read_text(encoding="utf-8")
        out, _ = self.dry_run("# Projects\n\n" + block)
        self.assertNotIn("add the Fusion Desktop lock lines", out)


if __name__ == "__main__":
    unittest.main()
