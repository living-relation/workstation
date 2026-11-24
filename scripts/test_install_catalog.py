#!/usr/bin/env python3
"""install.ps1 runs the two catalog commands and can paste instructions.

The catalog script skips when the claude CLI is missing. It never removes a plugin.
"""
import os
import shutil
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "scripts" / "install-catalog-plugin.ps1"
PASTE = ROOT / "scripts" / "paste-instructions.ps1"
INSTALL = ROOT / "install.ps1"
PWSH = shutil.which("pwsh") or shutil.which("powershell")

ADD = "claude plugin marketplace add living-relation/workstation"
INSTALL_CMD = "claude plugin install workstation-core@workstation-plugins"


def run_ps(script, args, env=None, stdin=None):
    return subprocess.run(
        [PWSH, "-NoProfile", "-File", str(script), *args],
        capture_output=True,
        text=True,
        timeout=30,
        input=stdin,
        env=env,
        cwd=ROOT,
    )


@unittest.skipUnless(PWSH, "needs PowerShell")
class CatalogCommands(unittest.TestCase):
    def test_source_runs_only_the_two_commands(self):
        catalog = CATALOG.read_text(encoding="utf-8")
        install = INSTALL.read_text(encoding="utf-8")
        self.assertIn(ADD, catalog)
        self.assertIn(INSTALL_CMD, catalog)
        self.assertNotIn("plugin uninstall", catalog.lower())
        self.assertNotIn("plugin disable", catalog.lower())
        self.assertIn("install-catalog-plugin.ps1", install)
        self.assertIn("paste-instructions.ps1", install)
        cmd = (ROOT / "install.cmd").read_text(encoding="utf-8")
        self.assertIn("install.ps1", cmd)

    def test_whatif_does_not_call_claude(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "claude.log"
            env = os.environ.copy()
            env["PATH"] = tmp + os.pathsep + env.get("PATH", "")
            env["CLAUDE_LOG"] = str(log)
            fake = Path(tmp) / "claude"
            fake.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$CLAUDE_LOG\"\n", encoding="utf-8")
            fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
            proc = run_ps(CATALOG, ["-WhatIf"], env=env)
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertIn("WOULD " + ADD, proc.stdout)
            self.assertIn("WOULD " + INSTALL_CMD, proc.stdout)
            self.assertFalse(log.exists())

    def test_missing_cli_skips_cleanly(self):
        env = os.environ.copy()
        env["PATH"] = "/usr/bin:/bin"
        proc = run_ps(CATALOG, [], env=env)
        out = proc.stdout + proc.stderr
        self.assertEqual(proc.returncode, 0, out)
        self.assertIn("SKIP claude CLI is missing", out)
        self.assertIn(ADD, out)
        self.assertIn(INSTALL_CMD, out)

    def test_fake_claude_gets_the_two_commands_in_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "claude.log"
            env = os.environ.copy()
            env["PATH"] = tmp + os.pathsep + "/usr/bin:/bin"
            env["CLAUDE_LOG"] = str(log)
            fake = Path(tmp) / "claude"
            fake.write_text(
                textwrap.dedent(
                    """\
                    #!/bin/sh
                    printf '%s\\n' "$*" >> "$CLAUDE_LOG"
                    exit 0
                    """
                ),
                encoding="utf-8",
            )
            fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
            proc = run_ps(CATALOG, [], env=env)
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            lines = log.read_text(encoding="utf-8").splitlines()
            self.assertEqual(
                lines,
                [
                    "plugin marketplace add living-relation/workstation",
                    "plugin install workstation-core@workstation-plugins",
                ],
            )
            self.assertNotIn("uninstall", "\n".join(lines))
            self.assertNotIn("disable", "\n".join(lines))


@unittest.skipUnless(PWSH, "needs PowerShell")
class PasteHelper(unittest.TestCase):
    def test_quiet_skips(self):
        proc = run_ps(PASTE, ["-Quiet"])
        out = proc.stdout + proc.stderr
        self.assertEqual(proc.returncode, 0, out)
        self.assertIn("Paste helper skipped (-Quiet).", out)
        self.assertNotIn("Press Enter", out)

    def test_whatif_names_each_place_and_does_not_wait(self):
        proc = run_ps(PASTE, ["-WhatIf", "-PackageRoot", str(ROOT)])
        out = proc.stdout + proc.stderr
        self.assertEqual(proc.returncode, 0, out)
        self.assertIn("Claude Desktop > Settings > General > Instructions for Claude", out)
        self.assertIn("Cowork Global instructions", out)
        self.assertIn("Cursor Settings > Rules > User Rules", out)
        self.assertIn("Would ask whether the Cowork Global instructions box exists", out)
        self.assertNotIn("Press Enter", out)

    def test_real_run_skips_cowork_when_the_box_is_not_confirmed(self):
        # Enter, then "n" for Cowork, then Enter. No Sublime and no notepad on this host.
        proc = run_ps(PASTE, ["-PackageRoot", str(ROOT)], stdin="\nn\n\n")
        out = proc.stdout + proc.stderr
        self.assertEqual(proc.returncode, 0, out)
        self.assertIn("Claude Desktop > Settings > General > Instructions for Claude", out)
        self.assertIn("Skipped Cowork Global instructions", out)
        self.assertIn("Cursor Settings > Rules > User Rules", out)
        self.assertIn("Sublime Text and notepad were not found", out)


if __name__ == "__main__":
    unittest.main()
