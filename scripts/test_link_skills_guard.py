#!/usr/bin/env python3
"""Guard test: link-skills.ps1 never touches Claude-app-owned (excluded or marked) skills.
Runs PowerShell (pwsh or Windows powershell); skipped if neither is installed."""
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
import os
SCRIPT = os.environ.get("LINK_SKILLS_PS1") or str(HERE.parent / "link-skills.ps1")
PS = shutil.which("pwsh") or shutil.which("powershell")


def _skill(d: Path, name: str, extra: str = ""):
    d.mkdir(parents=True, exist_ok=True)
    (d / "SKILL.md").write_text(f"---\nname: {name}\ndescription: x\n{extra}---\nbody\n", encoding="utf-8")


@unittest.skipUnless(PS, "PowerShell not installed")
class LinkSkillsGuard(unittest.TestCase):
    script = SCRIPT

    def run_link(self, src: Path, tgt: Path, backup: Path, retire: str):
        cmd = (f"& '{self.script}' -From '{src}' -Targets '{tgt}' -Unlink '{tgt.parent / 'nounlink'}' "
               f"-BackupRoot '{backup}' -Retire {retire} | Format-Table -AutoSize | Out-String -Width 400")
        return subprocess.run([PS, "-NoProfile", "-NonInteractive", "-Command", cmd],
                              capture_output=True, text=True)

    def test_excluded_and_marked_folders_untouched(self):
        with tempfile.TemporaryDirectory() as tmp:
            t = Path(tmp)
            src, tgt, backup = t / "src", t / "tgt", t / "bak"
            _skill(src / "harness-design", "harness-design")
            _skill(src / "marked-skill", "marked-skill", "source: harness-design-app\n")
            (src / "EXCLUDE.txt").write_text("harness-design\nst185-pick-parts\n", encoding="utf-8")
            # Real app-owned folders in the target: must survive link, retire and prune.
            _skill(tgt / "harness-design", "harness-design")
            (tgt / "harness-design" / "today.md").write_text("app edit\n", encoding="utf-8")
            _skill(tgt / "st185-pick-parts", "st185-pick-parts")
            _skill(tgt / "app-only", "app-only", "source: harness-design-app\n")
            r = self.run_link(src, tgt, backup, "'harness-design','st185-pick-parts','app-only'")
            out = r.stdout + r.stderr
            self.assertEqual(r.returncode, 0, out)
            self.assertIn("SKIP harness app skill", out)
            for n in ("harness-design", "st185-pick-parts", "app-only"):
                self.assertTrue((tgt / n / "SKILL.md").is_file(), f"{n} touched\n{out}")
            self.assertEqual((tgt / "harness-design" / "today.md").read_text(encoding="utf-8"), "app edit\n")
            self.assertFalse((tgt / "marked-skill").exists(), out)
            self.assertFalse(backup.exists(), f"something was backed up aside\n{out}")

    @unittest.skipUnless(sys.platform == "win32", "junctions need Windows")
    def test_broken_junction_pruned_live_one_kept(self):
        with tempfile.TemporaryDirectory() as tmp:
            t = Path(tmp)
            src, tgt, backup = t / "src", t / "tgt", t / "bak"
            (src).mkdir()
            (src / "EXCLUDE.txt").write_text("harness-design\nst185-pick-parts\n", encoding="utf-8")
            gone = src / "harness-design"
            gone.mkdir()
            live = src / "st185-pick-parts"
            live.mkdir()
            (live / "notes.md").write_text("x\n", encoding="utf-8")
            tgt.mkdir()
            for name, target in (("harness-design", gone), ("st185-pick-parts", live)):
                subprocess.check_call(["cmd", "/c", "mklink", "/J", str(tgt / name), str(target)],
                                      stdout=subprocess.DEVNULL)
            gone.rmdir()  # broken junction now
            r = self.run_link(src, tgt, backup, "'none'")
            out = r.stdout + r.stderr
            self.assertEqual(r.returncode, 0, out)
            self.assertFalse(os.path.lexists(tgt / "harness-design"), f"broken link kept\n{out}")
            self.assertTrue((tgt / "st185-pick-parts" / "notes.md").is_file(), f"live link touched\n{out}")
            self.assertTrue((live / "notes.md").is_file())


if __name__ == "__main__":
    unittest.main()
