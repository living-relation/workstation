#!/usr/bin/env python3
"""The plugin installer prints claude.ai clicks on -WhatIf and does not schedule.

The commands are the same single-line blocks as README.md and INSTALL.md.
Claude Code installs workstation-core from the workstation-plugins catalog with the
CLAUDE_CODE commands below (decision D-2026-11-23-claude-code-catalog).
install.ps1 runs the add and install commands (D-2026-11-24-install-runs-catalog).
install-plugins.ps1 still does not run them. Refresh and update stay manual.
"""
import json
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
    '$_.FullName -Destination '
    '"$env:USERPROFILE\\.cursor\\plugins\\local\\workstation-core" '
    "-Recurse -Force }"
)
INSTALLER = r"powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugins.ps1"
WHATIF = INSTALLER + " -WhatIf"
PASTE = "living-relation/workstation"
MISSING = (
    "workstation-core plugin not added on claude.ai yet: "
    "add catalog living-relation/workstation and turn on workstation-core"
)
PRESENT = "workstation-core synced from claude.ai is on this PC"
CLAUDE_CODE = (
    "claude plugin marketplace add living-relation/workstation",
    "claude plugin install workstation-core@workstation-plugins",
    "claude plugin marketplace update workstation-plugins",
    "claude plugin update workstation-core@workstation-plugins",
)
PRECEDENCE = (
    "That copy (`workstation-core@workstation-plugins`) takes precedence over the copy "
    "synced from claude.ai"
)
DESKTOP_STAYS = "Claude desktop and Cowork still get the plugin from claude.ai"
BANNED = (
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
        for doc in (install, readme):
            self.assertIn("Skip this if you don't use Claude Code.", doc)
            self.assertIn(PRECEDENCE, doc)
            self.assertIn(DESKTOP_STAYS, doc)
            fences = _fence_lines(doc)
            positions = []
            for cmd in CLAUDE_CODE:
                # Each command is its own one-line block, in add/install/refresh/update order.
                self.assertIn([cmd], fences, cmd)
                positions.append(doc.index("```powershell\n" + cmd + "\n```"))
            self.assertEqual(positions, sorted(positions))
            # The plugin id is exact: the catalog name is workstation-plugins, never the repo name.
            self.assertNotIn("workstation-core@workstation\n", doc)
            self.assertNotIn("workstation-core@synced", doc)
        self.assertLess(install.index("## Claude Code"), install.index("## Cursor"))
        catalog = json.loads((ROOT / ".claude-plugin" / "marketplace.json").read_text(encoding="utf-8"))
        name = catalog["name"]
        plugins = [p["name"] for p in catalog["plugins"]]
        self.assertEqual(name, "workstation-plugins")
        self.assertIn("workstation-core", plugins)
        self.assertIn(f"claude plugin install workstation-core@{name}", CLAUDE_CODE)
        self.assertIn(f"claude plugin marketplace update {name}", CLAUDE_CODE)
        self.assertIn("INSTALL.md (Claude Code section)", prompt)
        self.assertNotIn("Claude Code on that account", prompt)
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
        ran = "install.ps1` runs the add command and the install command below."
        self.assertIn(ran, install)
        self.assertIn(ran, readme)
        install_ps1 = (ROOT / "install.ps1").read_text(encoding="utf-8")
        self.assertNotIn("LinkSkills", install_ps1)
        self.assertNotIn("link-skills.ps1", install_ps1)
        self.assertIn("install-catalog-plugin.ps1", install_ps1)
        self.assertIn("paste-instructions.ps1", install_ps1)

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
        self.assertIn("Claude Code: install from the workstation-plugins catalog", out)
        self.assertIn("INSTALL.md (Claude Code section)", out)
        self.assertNotIn("Cowork, and Claude Code", out)
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


    def test_rerun_merges_and_does_not_nest_folders(self):
        """A second run updates files in place; it never copies hooks into hooks\\hooks."""
        if not PWSH:
            self.skipTest("powershell is not installed")
        with tempfile.TemporaryDirectory() as home:
            dest = Path(home) / ".cursor" / "plugins" / "local" / "workstation-core"
            for run in (1, 2):
                if run == 2:
                    # An older copy of a file must be replaced on the re-run.
                    (dest / "hooks" / "rules-inject.ps1").write_text("old\n", encoding="utf-8")
                proc = subprocess.run(
                    [PWSH, "-NoProfile", "-NonInteractive", "-File", str(PS1), "-UserHome", home],
                    capture_output=True,
                    text=True,
                    timeout=120,
                    cwd=ROOT,
                )
                out = proc.stdout + proc.stderr
                self.assertEqual(proc.returncode, 0, out)
            nested = sorted(
                d.name for d in dest.iterdir() if d.is_dir() and (d / d.name).exists()
            )
            self.assertEqual(nested, [], "nested folders after a re-run: " + ", ".join(nested))
            src = ROOT / "hooks" / "rules-inject.ps1"
            self.assertEqual((dest / "hooks" / "rules-inject.ps1").read_bytes(), src.read_bytes())
            self.assertTrue((dest / "skills").is_dir())
            self.assertFalse((dest / ".git").exists())

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

    def test_missing_present_turned_off_and_sync_off(self):
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
            # Turning the synced copy off in Claude Code (it uses the catalog copy) does not remove it
            # from claude.ai, so it still counts as present.
            self.assertIn(PRESENT, self._status(home))
            settings.write_text('{"syncClaudeAiPlugins":false}\n', encoding="utf-8")
            self.assertIn(MISSING, self._status(home))


if __name__ == "__main__":
    unittest.main()
