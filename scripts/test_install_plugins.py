#!/usr/bin/env python3
"""The plugin installer prints claude.ai clicks on -WhatIf and does not schedule.

The commands are the same single-line blocks as README.md and INSTALL.md.
"""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PS1 = ROOT / "install-plugins.ps1"
README = ROOT / "README.md"
INSTALL = ROOT / "INSTALL.md"
PROMPT = ROOT / "SETUP-PROMPT.txt"
PWSH = shutil.which("pwsh") or shutil.which("powershell")

OPEN = 'Start-Process "https://claude.ai/customize/plugins"'
CURSOR = (
    'New-Item -ItemType Directory -Force -Path '
    '"$env:USERPROFILE\\.cursor\\plugins\\local\\workstation-core" | Out-Null; '
    "Get-ChildItem -Force -LiteralPath . | Where-Object { $_.Name -ne '.git' "
    "-and $_.Name -ne '.venv' } | ForEach-Object { Copy-Item -LiteralPath "
    '$_.FullName -Destination (Join-Path '
    '"$env:USERPROFILE\\.cursor\\plugins\\local\\workstation-core" '
    "$_.Name) -Recurse -Force }"
)
INSTALLER = r"powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugins.ps1"
WHATIF = INSTALLER + " -WhatIf"
PASTE = "living-relation/workstation"
MISSING = (
    "workstation-core plugin not added on claude.ai yet: "
    "add catalog living-relation/workstation and turn on workstation-core"
)
PRESENT = "workstation-core plugin is present on claude.ai"
BANNED = (
    "claude plugin install",
    "claude plugin marketplace",
    "/plugin install",
    "/plugin marketplace",
    "-LinkSkills",
    "skills not linked",
    "skills: not linked",
    "linking",
    "sync automatically off",
    "leave it off",
    "leave marketplace auto-update off",
)


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
        prompt = PROMPT.read_text(encoding="utf-8")
        for heading in (
            "## 1. Installer",
            "## 2. Commands",
            "## 3. Agent prompt",
            "## 4. Manual steps",
        ):
            self.assertIn(heading, install)
        self.assertIn("turn Sync automatically on", install)
        self.assertIn("turn Sync automatically on", readme)
        self.assertNotIn("Sync automatically off", install)
        self.assertNotIn("Leave it off", install)
        self.assertNotIn("leave marketplace auto-update off", install.lower())
        self.assertNotIn("Check for updates in the catalog forces it sooner", install)
        self.assertNotIn("Check for updates in the catalog forces it sooner", readme)
        self.assertIn("does not copy skills", install.lower())
        self.assertIn(PASTE, install)
        self.assertIn("workstation-plugins", install)
        self.assertIn("https://claude.ai/customize/plugins", install)
        self.assertIn("https://claude.ai/customize/plugins", readme)
        self.assertIn("https://github.com/living-relation/workstation", install)
        self.assertIn("https://github.com/living-relation/workstation", readme)
        self.assertIn("Fully quit Claude desktop", install)
        self.assertIn("Fully quit Claude desktop", readme)
        add_on_page = (
            "Click Add (top right) on that page to install it. "
            "Adding the repo alone does not install it."
        )
        self.assertIn(add_on_page, install)
        self.assertIn(add_on_page, readme)
        self.assertNotIn("Find the `workstation-core` plugin in the plugin list", install)
        self.assertNotIn("Find the `workstation-core` plugin in the plugin list", readme)
        self.assertIn("Fully quit and reopen Cursor.", install)
        self.assertIn("Fully quit and reopen Cursor.", readme)
        self.assertIn("Skip this if you don't use Claude", install)
        self.assertIn("Skip this if you don't use Claude", readme)
        self.assertIn("Skip this if you don't use Cursor", install)
        self.assertIn("Skip this if you don't use Cursor", readme)
        self.assertNotIn("claude.ai", CURSOR)
        self.assertNotIn("Start-Process", CURSOR)
        agent = (
            "Install the workstation-core Cursor plugin from "
            "https://github.com/living-relation/workstation: if it is not cloned yet, "
            "clone it into my projects folder; then copy the repo (without .git and .venv) "
            "to ~/.cursor/plugins/local/workstation-core, replacing any old copy. "
            "Tell me when done so I can fully quit and reopen Cursor."
        )
        cd = "cd <projects-folder>"
        clone = "git clone https://github.com/living-relation/workstation"
        cd_repo = "cd <projects-folder>\\workstation"
        for line in (agent, cd, clone, cd_repo, CURSOR, OPEN, INSTALLER, WHATIF):
            self.assertIn(line, install)
            self.assertIn([line], _fence_lines(install))
        for line in (agent, cd, clone, cd_repo, CURSOR):
            self.assertIn([line], _fence_lines(readme))
        for blob in (install, readme, prompt):
            low = blob.lower()
            for banned in BANNED:
                self.assertNotIn(banned.lower(), low)
        script = PS1.read_text(encoding="utf-8")
        self.assertIn("[string]$Catalog = 'living-relation/workstation'", script)
        self.assertIn("https://claude.ai/customize/plugins", script)
        self.assertNotIn("plugin', 'install'", script)
        for banned in (
            "Register-ScheduledTask",
            "schtasks",
            "link-skills.ps1",
            "Startup",
            "claude plugin",
            "-LinkSkills",
        ):
            self.assertNotIn(banned, script)
        install_ps1 = (ROOT / "install.ps1").read_text(encoding="utf-8")
        self.assertNotIn("LinkSkills", install_ps1)
        self.assertNotIn("link-skills.ps1", install_ps1)

    def test_whatif_prints_clicks_and_does_not_open_or_copy(self):
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
        self.assertIn("Catalog to paste: " + PASTE, out)
        self.assertIn("Turn Sync automatically on", out)
        self.assertIn("after merges to main", out)
        self.assertNotIn("Sync automatically off", out)
        self.assertIn("Turn on workstation-core", out)
        self.assertIn("browser was not opened", out)
        self.assertIn("Nothing was copied", out)
        self.assertIn("Nothing was scheduled", out)
        self.assertNotIn("Opened ", out)
        self.assertNotIn("Copied workstation-core", out)

    def test_userhome_copies_plugin_and_does_not_open_a_browser(self):
        if not PWSH:
            self.skipTest("powershell is not installed")
        with tempfile.TemporaryDirectory() as home:
            proc = subprocess.run(
                [
                    PWSH,
                    "-NoProfile",
                    "-NonInteractive",
                    "-File",
                    str(PS1),
                    "-UserHome",
                    home,
                ],
                capture_output=True,
                text=True,
                timeout=120,
                cwd=ROOT,
            )
            out = proc.stdout + proc.stderr
            self.assertEqual(proc.returncode, 0, out)
            dest = (
                Path(home)
                / ".cursor"
                / "plugins"
                / "local"
                / "workstation-core"
                / ".cursor-plugin"
                / "plugin.json"
            )
            self.assertTrue(dest.is_file(), out)
            self.assertFalse((Path(home) / ".cursor" / "plugins" / "local" / "workstation-core" / ".git").exists())
            self.assertIn("Copied workstation-core", out)
            self.assertIn("browser was not opened", out)
            self.assertNotIn("Opened ", out)
            self.assertIn("Nothing was scheduled", out)


class PluginPresence(unittest.TestCase):
    def _status(self, home: Path) -> str:
        env = os.environ.copy()
        env.pop("CLAUDE_CODE_PLUGIN_CACHE_DIR", None)
        script = (
            f". '{ROOT / 'workstation' / 'health' / 'claude-ai-plugin.ps1'}'; "
            f"if (Test-WorkstationCoreOnClaudeAi -UserRoot '{home}') "
            f"{{ Write-Output '{PRESENT}' }} else {{ Write-Output '{MISSING}' }}"
        )
        proc = subprocess.run(
            [PWSH, "-NoProfile", "-NonInteractive", "-Command", script],
            capture_output=True,
            text=True,
            timeout=60,
            env=env,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        return proc.stdout

    def test_missing_and_present_and_turned_off(self):
        if not PWSH:
            self.skipTest("powershell is not installed")
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            self.assertIn(MISSING, self._status(home))
            plugin = home / ".claude" / "plugins" / "synced" / "workstation-core" / ".claude-plugin"
            plugin.mkdir(parents=True)
            (plugin / "plugin.json").write_text('{"name":"workstation-core"}\n', encoding="utf-8")
            self.assertIn(PRESENT, self._status(home))
            settings = home / ".claude" / "settings.json"
            settings.write_text(
                '{"enabledPlugins":{"workstation-core@synced":false}}\n',
                encoding="utf-8",
            )
            self.assertIn(MISSING, self._status(home))
            settings.write_text('{"syncClaudeAiPlugins":false}\n', encoding="utf-8")
            self.assertIn(MISSING, self._status(home))


if __name__ == "__main__":
    unittest.main()
