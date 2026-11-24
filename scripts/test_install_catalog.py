#!/usr/bin/env python3
"""install.ps1 runs the two catalog commands and can paste instructions.

The catalog script skips when the claude CLI is missing. It never removes a plugin.
The paste helper is sealed in tests: it must not open an editor or write the clipboard.
"""
import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "scripts" / "install-catalog-plugin.ps1"
PASTE = ROOT / "scripts" / "paste-instructions.ps1"
INSTALL = ROOT / "install.ps1"
PWSH = shutil.which("pwsh") or shutil.which("powershell")

ADD = "claude plugin marketplace add living-relation/workstation"
INSTALL_CMD = "claude plugin install workstation-core@workstation-plugins"

INSTRUCTIONS_CLAUDE = ROOT / "instructions" / "instructions-for-claude.md"
INSTRUCTIONS_COWORK = ROOT / "instructions" / "cowork-global-instructions.md"
INSTRUCTIONS_CURSOR = ROOT / "instructions" / "cursor-user-rules.md"


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


def write_claude_shim(folder: Path) -> Path:
    """A PATH shim that logs arguments and never talks to a real claude CLI."""
    if os.name == "nt":
        shim = folder / "claude.cmd"
        shim.write_text(
            "@echo off\r\n>>\"%CLAUDE_LOG%\" echo %*\r\nexit /b 0\r\n",
            encoding="utf-8",
        )
    else:
        shim = folder / "claude"
        shim.write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$CLAUDE_LOG\"\nexit 0\n",
            encoding="utf-8",
        )
        shim.chmod(shim.stat().st_mode | stat.S_IEXEC)
    return shim


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
            write_claude_shim(Path(tmp))
            proc = run_ps(CATALOG, ["-WhatIf"], env=env)
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertIn("WOULD " + ADD, proc.stdout)
            self.assertIn("WOULD " + INSTALL_CMD, proc.stdout)
            self.assertFalse(log.exists())

    def test_missing_cli_skips_cleanly(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = os.environ.copy()
            env["PATH"] = tmp
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
            env["PATH"] = tmp + os.pathsep + env.get("PATH", "")
            env["CLAUDE_LOG"] = str(log)
            write_claude_shim(Path(tmp))
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
        self.assertNotIn("Copied to the clipboard.", out)
        self.assertNotIn("Opened in", out)

    def test_sealed_run_skips_cowork_and_records_copy_and_open(self):
        # Enter, then "n" for Cowork, then Enter. Hook dir seals clipboard and editor.
        with tempfile.TemporaryDirectory() as tmp:
            hook = Path(tmp) / "hook"
            hook.mkdir()
            side = Path(tmp) / "side-effects.log"
            env = os.environ.copy()
            env["WORKSTATION_PASTE_HOOK_DIR"] = str(hook)
            env["WORKSTATION_PASTE_SIDE_EFFECT_LOG"] = str(side)
            proc = run_ps(PASTE, ["-PackageRoot", str(ROOT)], env=env, stdin="\nn\n\n")
            out = proc.stdout + proc.stderr
            self.assertEqual(proc.returncode, 0, out)
            self.assertIn("Claude Desktop > Settings > General > Instructions for Claude", out)
            self.assertIn("Skipped Cowork Global instructions", out)
            self.assertIn("Cursor Settings > Rules > User Rules", out)
            self.assertIn("Copied to the clipboard.", out)
            self.assertIn("Clipboard write was sealed (no real clipboard).", out)
            self.assertIn("Opened in sealed editor:", out)
            self.assertNotIn("Opened in Sublime Text", out)
            self.assertNotIn("Opened in notepad", out)
            self.assertNotIn("Sublime Text and notepad were not found", out)
            self.assertFalse(side.exists(), side.read_text(encoding="utf-8") if side.exists() else "")

            editor = (hook / "editor.log").read_text(encoding="utf-8")
            self.assertIn("instructions-for-claude.md", editor)
            self.assertIn("cursor-user-rules.md", editor)
            self.assertNotIn("cowork-global-instructions.md", editor)
            self.assertEqual(len([line for line in editor.splitlines() if line.strip()]), 2)

            clip1 = (hook / "clipboard-1.txt").read_text(encoding="utf-8")
            clip2 = (hook / "clipboard-2.txt").read_text(encoding="utf-8")
            claude_text = INSTRUCTIONS_CLAUDE.read_text(encoding="utf-8")
            cursor_text = INSTRUCTIONS_CURSOR.read_text(encoding="utf-8")
            cowork_text = INSTRUCTIONS_COWORK.read_text(encoding="utf-8")
            copied = [clip1, clip2]
            self.assertIn(claude_text, copied)
            self.assertIn(cursor_text, copied)
            self.assertNotIn(cowork_text, copied)
            self.assertFalse((hook / "clipboard-3.txt").exists())

    def test_ci_without_hook_dir_refuses_side_effects(self):
        with tempfile.TemporaryDirectory() as tmp:
            side = Path(tmp) / "side-effects.log"
            env = os.environ.copy()
            env["CI"] = "true"
            env["WORKSTATION_PASTE_SIDE_EFFECT_LOG"] = str(side)
            env.pop("WORKSTATION_PASTE_HOOK_DIR", None)
            proc = run_ps(PASTE, ["-PackageRoot", str(ROOT)], env=env, stdin="\nn\n\n")
            out = proc.stdout + proc.stderr
            self.assertNotEqual(proc.returncode, 0, out)
            self.assertIn("Refusing to write the clipboard or open an editor", out)
            self.assertNotIn("Opened in Sublime Text", out)
            self.assertNotIn("Opened in notepad", out)
            self.assertFalse(side.exists(), side.read_text(encoding="utf-8") if side.exists() else "")

    def test_helper_source_checks_hook_dir_before_real_tools(self):
        text = PASTE.read_text(encoding="utf-8")
        hook_at = text.find("WORKSTATION_PASTE_HOOK_DIR")
        set_clip = text.find("Set-Clipboard")
        start_proc = text.find("Start-Process")
        self.assertGreater(hook_at, 0)
        self.assertGreater(set_clip, hook_at)
        self.assertGreater(start_proc, hook_at)
        self.assertIn("Write-SideEffectLog", text)
        self.assertIn("PYTEST_CURRENT_TEST", text)


if __name__ == "__main__":
    unittest.main()
