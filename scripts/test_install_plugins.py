#!/usr/bin/env python3
"""The plugin installer prints its two commands on -WhatIf and does not link or schedule.

The commands are the same single-line blocks as README.md and INSTALL.md.
"""
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PS1 = ROOT / "install-plugins.ps1"
README = ROOT / "README.md"
INSTALL = ROOT / "INSTALL.md"
PWSH = shutil.which("pwsh") or shutil.which("powershell")

CORE = (
    "claude plugin install workstation-core "
    "--marketplace living-relation/workstation --scope user"
)
CAD = (
    "claude plugin install handbuilt-cad "
    "--marketplace living-relation/workstation --scope user"
)
SESSION_CORE = "/plugin install workstation-core --marketplace living-relation/workstation"
SESSION_CAD = "/plugin install handbuilt-cad --marketplace living-relation/workstation"
INSTALLER = r"powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugins.ps1"
WHATIF = INSTALLER + " -WhatIf"


def _fence_lines(text: str):
    lines = text.splitlines()
    blocks = []
    i = 0
    while i < len(lines):
        if lines[i].startswith("```"):
            body = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                body.append(lines[i])
                i += 1
            blocks.append(body)
        i += 1
    return blocks


class InstallPluginsDocs(unittest.TestCase):
    def test_four_methods_and_single_line_commands(self):
        install = INSTALL.read_text(encoding="utf-8")
        readme = README.read_text(encoding="utf-8")
        for heading in ("## 1. Installer", "## 2. Commands", "## 3. Agent prompt", "## 4. Manual steps"):
            self.assertIn(heading, install)
        self.assertIn("Plugins menu", install)
        self.assertIn("Leave marketplace auto-update off", install)
        self.assertIn("does not link", install.lower())
        for line in (CORE, CAD, SESSION_CORE, SESSION_CAD, INSTALLER, WHATIF):
            self.assertIn(line, install)
            self.assertIn([line], _fence_lines(install))
        for line in (CORE, CAD, SESSION_CORE, SESSION_CAD):
            self.assertIn([line], _fence_lines(readme))
        script = PS1.read_text(encoding="utf-8")
        self.assertIn("[string]$Marketplace = 'living-relation/workstation'", script)
        self.assertIn("'plugin', 'install', 'workstation-core'", script)
        self.assertIn("'plugin', 'install', 'handbuilt-cad'", script)
        for banned in ("Register-ScheduledTask", "schtasks", "link-skills.ps1", "Startup"):
            self.assertNotIn(banned, script)

    def test_whatif_prints_commands_and_does_not_run_them(self):
        if not PWSH:
            self.skipTest("powershell is not installed")
        proc = subprocess.run(
            [PWSH, "-NoProfile", "-NonInteractive", "-File", str(PS1), "-WhatIf"],
            capture_output=True,
            text=True,
            timeout=60,
            cwd=ROOT,
        )
        out = proc.stdout + proc.stderr
        self.assertEqual(proc.returncode, 0, out)
        self.assertIn(CORE, out)
        self.assertIn(CAD, out)
        self.assertIn("Skills were not linked", out)
        self.assertIn("Nothing was scheduled", out)
        self.assertNotIn("Successfully installed", out)


if __name__ == "__main__":
    unittest.main()
