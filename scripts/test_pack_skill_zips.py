#!/usr/bin/env python3
"""Tests for pack-skill-zips.py (stdlib unittest)."""
import importlib.util
import os
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("pack_skill_zips", HERE / "pack-skill-zips.py")
pack = importlib.util.module_from_spec(SPEC)
sys.modules["pack_skill_zips"] = pack
SPEC.loader.exec_module(pack)


def write_skill(root: Path, folder: str, name: str, description: str, extra=None):
    d = root / folder
    d.mkdir(parents=True, exist_ok=True)
    (d / "SKILL.md").write_text(
        f"---\nname: {name}\ndescription: {description}\n---\n\n# {name}\nbody\n",
        encoding="utf-8",
        newline="\n",
    )
    if extra:
        for rel, text in extra.items():
            p = d / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8", newline="\n")
    return d


def git_track(root: Path):
    if not (root / ".git").exists():
        subprocess.check_call(["git", "init", "-q"], cwd=root)
        subprocess.check_call(["git", "config", "user.email", "t@t"], cwd=root)
        subprocess.check_call(["git", "config", "user.name", "t"], cwd=root)
        subprocess.check_call(["git", "config", "core.hooksPath", "/dev/null"], cwd=root)
        subprocess.check_call(["git", "commit", "-qm", "init", "--allow-empty"], cwd=root)
    subprocess.check_call(["git", "add", "-A"], cwd=root)


class Discover(unittest.TestCase):
    def test_only_dirs_with_skill_md(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_skill(root, "good-skill", "good-skill", "A valid skill.")
            (root / "stray.zip").write_bytes(b"PK\x03\x04not-a-skill")
            (root / "empty-dir").mkdir()
            (root / "notes.md").write_text("nope\n", encoding="utf-8")
            names = [p.name for p in pack.skill_dirs(root)]
            self.assertEqual(names, ["good-skill"])


class Pack(unittest.TestCase):
    def test_zip_layout_and_supporting_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_skill(
                root,
                "demo-skill",
                "demo-skill",
                "Demo.",
                extra={"refs/a.md": "# a\n"},
            )
            git_track(root)
            report = pack.pack_all(root)
            zpath = root / "demo-skill.zip"
            self.assertTrue(zpath.is_file())
            self.assertIn("demo-skill", report.packed)
            with zipfile.ZipFile(zpath) as zf:
                names = zf.namelist()
            self.assertEqual(names, ["demo-skill/SKILL.md", "demo-skill/refs/a.md"])

    def test_deterministic_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_skill(root, "demo-skill", "demo-skill", "Demo.")
            git_track(root)
            pack.pack_all(root)
            first = (root / "demo-skill.zip").read_bytes()
            pack.pack_all(root)
            second = (root / "demo-skill.zip").read_bytes()
            self.assertEqual(first, second)
            self.assertTrue(first.startswith(b"PK"))

    def test_does_not_edit_skill_content(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            d = write_skill(
                root,
                "demo-skill",
                "demo-skill",
                "Has <project> in description on purpose.",
            )
            git_track(root)
            before = (d / "SKILL.md").read_bytes()
            pack.pack_all(root)
            self.assertEqual((d / "SKILL.md").read_bytes(), before)

    def test_removes_orphan_zip(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_skill(root, "keep-me", "keep-me", "Keep.")
            git_track(root)
            orphan = root / "gone-skill.zip"
            orphan.write_bytes(b"stale")
            report = pack.pack_all(root)
            self.assertFalse(orphan.exists())
            self.assertIn("gone-skill.zip", report.removed)
            self.assertTrue((root / "keep-me.zip").is_file())

    def test_ignores_zip_files_as_skills(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_skill(root, "real-skill", "real-skill", "Real.")
            git_track(root)
            (root / "real-skill.zip").write_bytes(b"old")
            pack.pack_all(root)
            with zipfile.ZipFile(root / "real-skill.zip") as zf:
                self.assertIn("real-skill/SKILL.md", zf.namelist())

    def test_unix_create_system_stored_and_file_type_bits(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_skill(root, "demo-skill", "demo-skill", "Demo.")
            git_track(root)
            pack.pack_all(root)
            with zipfile.ZipFile(root / "demo-skill.zip") as zf:
                for info in zf.infolist():
                    self.assertEqual(info.create_system, 3)
                    self.assertEqual(info.date_time, (1980, 1, 1, 0, 0, 0))
                    self.assertEqual(info.compress_type, zipfile.ZIP_STORED)
                    mode = (info.external_attr >> 16) & 0o777777
                    self.assertEqual(stat.S_IFMT(mode), stat.S_IFREG)
                    self.assertEqual(stat.S_IMODE(mode), 0o644)

    def test_excludes_tracked_env_dotfile(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            d = write_skill(root, "demo-skill", "demo-skill", "Demo.")
            (d / ".env").write_text("SECRET=1\n", encoding="utf-8")
            git_track(root)
            subprocess.check_call(["git", "add", "-f", "demo-skill/.env"], cwd=root)
            pack.pack_all(root)
            with zipfile.ZipFile(root / "demo-skill.zip") as zf:
                names = zf.namelist()
            self.assertEqual(names, ["demo-skill/SKILL.md"])
            self.assertNotIn("demo-skill/.env", names)


class Validate(unittest.TestCase):
    def test_name_and_description_rules(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_skill(root, "Good_Name", "Good_Name", "ok")
            write_skill(root, "claude-helper", "claude-helper", "reserved word in name")
            write_skill(
                root,
                "tag-skill",
                "tag-skill",
                "Uses <project> as a placeholder tag.",
            )
            write_skill(root, "ok-skill", "ok-skill", "A valid description.")
            write_skill(root, "mismatch", "other-name", "Folder does not match name.")
            long_desc = "x" * 1025
            write_skill(root, "long-skill", "long-skill", long_desc)
            git_track(root)
            report = pack.pack_all(root)
            joined = "\n".join(report.warnings)
            self.assertTrue(any("Good_Name" in w and "name" in w.lower() for w in report.warnings))
            self.assertTrue(any("claude-helper" in w and "claude" in w.lower() for w in report.warnings))
            self.assertTrue(any("tag-skill" in w and "<project>" in w for w in report.warnings))
            self.assertTrue(any("long-skill" in w and "1024" in w for w in report.warnings))
            self.assertTrue(any("mismatch" in w and "other-name" in w for w in report.warnings))
            self.assertFalse(any(w.startswith("ok-skill:") for w in report.warnings))
            self.assertTrue((root / "tag-skill.zip").is_file())
            self.assertIn("<project>", joined)

    def test_folded_description_parsed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            d = root / "fold-skill"
            d.mkdir()
            (d / "SKILL.md").write_text(
                "---\nname: fold-skill\ndescription: >-\n  First line of the description\n"
                "  continues here.\n---\n\nbody\n",
                encoding="utf-8",
                newline="\n",
            )
            meta = pack.parse_skill_md(d / "SKILL.md")
            self.assertEqual(meta["name"], "fold-skill")
            self.assertEqual(meta["description"], "First line of the description continues here.")

    def test_long_multiline_description_warns_not_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            d = root / "wordy-skill"
            d.mkdir()
            lines = "\n".join(f"  word{i:02d} extra padding for length" for i in range(12))
            (d / "SKILL.md").write_text(
                f"---\nname: wordy-skill\ndescription: >-\n{lines}\n---\n\nbody\n",
                encoding="utf-8",
                newline="\n",
            )
            git_track(root)
            meta = pack.parse_skill_md(d / "SKILL.md")
            self.assertGreater(len(meta["description"]), pack.DESC_SOFT)
            self.assertLess(len(meta["description"]), pack.DESC_MAX)
            report = pack.pack_all(root)
            self.assertTrue(any("wordy-skill" in w and str(pack.DESC_SOFT) in w for w in report.soft_warnings))
            self.assertFalse(any("wordy-skill" in w for w in report.warnings))
            rc = pack.main(["--skills-dir", str(root), "--strict"])
            self.assertEqual(rc, 0)

    def test_invalid_yaml_is_a_warning(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            d = root / "bad-yaml"
            d.mkdir()
            (d / "SKILL.md").write_text("---\nname: [unterminated\n---\n\nbody\n", encoding="utf-8")
            git_track(root)
            report = pack.pack_all(root)
            self.assertTrue(any("bad-yaml" in w and "YAML" in w for w in report.warnings))

    def test_untracked_skill_md_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_skill(root, "demo-skill", "demo-skill", "Demo.")
            subprocess.check_call(["git", "init", "-q"], cwd=root)
            subprocess.check_call(["git", "config", "user.email", "t@t"], cwd=root)
            subprocess.check_call(["git", "config", "user.name", "t"], cwd=root)
            subprocess.check_call(["git", "config", "core.hooksPath", "/dev/null"], cwd=root)
            subprocess.check_call(["git", "commit", "-qm", "init", "--allow-empty"], cwd=root)
            report = pack.pack_all(root)
            self.assertTrue(
                any("demo-skill" in e and "not git-tracked" in e for e in report.errors)
            )
            self.assertFalse((root / "demo-skill.zip").is_file())
            rc = pack.main(["--skills-dir", str(root)])
            self.assertEqual(rc, 1)
            rc_strict = pack.main(["--skills-dir", str(root), "--strict"])
            self.assertEqual(rc_strict, 1)


class CommitHelper(unittest.TestCase):
    def test_commits_only_skill_zips(self):
        script = HERE / "pack-skill-zips-commit.sh"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            skills = root / "skills"
            skills.mkdir()
            subprocess.check_call(["git", "init", "-q"], cwd=root)
            subprocess.check_call(["git", "config", "user.email", "t@t"], cwd=root)
            subprocess.check_call(["git", "config", "user.name", "t"], cwd=root)
            subprocess.check_call(["git", "config", "core.hooksPath", "/dev/null"], cwd=root)
            write_skill(skills, "demo-skill", "demo-skill", "Demo.")
            git_track(root)
            pack.pack_all(skills)
            subprocess.check_call(["git", "add", "skills/demo-skill"], cwd=root)
            subprocess.check_call(["git", "commit", "-qm", "skill"], cwd=root)
            subprocess.check_call(["git", "add", "--force", "skills/demo-skill.zip"], cwd=root)
            subprocess.check_call(["git", "commit", "-qm", "zip"], cwd=root)
            (skills / "demo-skill" / "SKILL.md").write_text(
                "---\nname: demo-skill\ndescription: Changed.\n---\n\n# demo-skill\n",
                encoding="utf-8",
                newline="\n",
            )
            pack.pack_all(skills)
            (root / "README").write_text("do not commit\n", encoding="utf-8")
            out = subprocess.check_output(["bash", str(script)], cwd=root, env=os.environ.copy(), text=True)
            self.assertIn("COMMITTED", out)
            names = subprocess.check_output(
                ["git", "diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD"],
                cwd=root,
                text=True,
            ).split()
            self.assertEqual(names, ["skills/demo-skill.zip"])
            self.assertTrue((root / "README").is_file())

    def test_commit_helper_runs_staged_guard(self):
        script = HERE / "pack-skill-zips-commit.sh"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            skills = root / "skills"
            skills.mkdir()
            subprocess.check_call(["git", "init", "-q"], cwd=root)
            subprocess.check_call(["git", "config", "user.email", "t@t"], cwd=root)
            subprocess.check_call(["git", "config", "user.name", "t"], cwd=root)
            subprocess.check_call(["git", "config", "core.hooksPath", "/dev/null"], cwd=root)
            write_skill(skills, "demo-skill", "demo-skill", "Demo.")
            git_track(root)
            pack.pack_all(skills)
            subprocess.check_call(["git", "add", "skills/demo-skill"], cwd=root)
            subprocess.check_call(["git", "commit", "-qm", "skill"], cwd=root)
            (skills / "huge.zip").write_bytes(b"0" * (1048576 + 1))
            proc = subprocess.run(
                ["bash", str(script)],
                cwd=root,
                env=os.environ.copy(),
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("guard:", proc.stdout + proc.stderr)




class Exclude(unittest.TestCase):
    def _repo(self, root: Path):
        write_skill(root, "keep-me", "keep-me", "Normal skill.")
        write_skill(root, "harness-design", "harness-design", "App owned.")
        d = root / "marked-skill"
        d.mkdir()
        (d / "SKILL.md").write_text(
            "---\nname: marked-skill\ndescription: Marked.\nsource: harness-design-app\n---\nbody\n",
            encoding="utf-8", newline="\n",
        )
        (root / "EXCLUDE.txt").write_text("# comment\nharness-design\nst185-pick-parts\n", encoding="utf-8")
        git_track(root)

    def test_load_excluded(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._repo(root)
            self.assertEqual(pack.load_excluded(root), {"harness-design", "st185-pick-parts"})
            self.assertTrue(pack.is_app_marked(root / "marked-skill"))
            self.assertFalse(pack.is_app_marked(root / "keep-me"))

    def test_excluded_and_marked_not_packed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._repo(root)
            report = pack.pack_all(root)
            self.assertEqual(report.packed, ["keep-me"])
            self.assertFalse((root / "harness-design.zip").exists())
            self.assertFalse((root / "marked-skill.zip").exists())
            self.assertTrue(any("skip excluded harness-design" in l for l in report.lines))

    def test_excluded_zip_never_removed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._repo(root)
            (root / "harness-design.zip").write_bytes(b"keep")
            (root / "st185-pick-parts.zip").write_bytes(b"keep")
            pack.pack_all(root)
            self.assertEqual((root / "harness-design.zip").read_bytes(), b"keep")
            self.assertEqual((root / "st185-pick-parts.zip").read_bytes(), b"keep")

    def test_repo_exclude_lists_harness_skills(self):
        names = pack.load_excluded(HERE.parent / "skills")
        for n in ("harness-design", "st185-build-harness-from-sot", "st185-pick-parts",
                  "st185-ship-change", "st185-change-sot", "st185-apply-route-markup"):
            self.assertIn(n, names)
        self.assertFalse((HERE.parent / "skills" / "harness-design").exists())

if __name__ == "__main__":
    unittest.main()
