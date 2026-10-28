#!/usr/bin/env python3
"""Tests for pack-skill-zips.py (stdlib unittest)."""
import importlib.util
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
    d.mkdir(parents=True)
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
            report = pack.pack_all(root)
            zpath = root / "demo-skill.zip"
            self.assertTrue(zpath.is_file())
            self.assertIn("demo-skill", report.packed)
            with zipfile.ZipFile(zpath) as zf:
                names = zf.namelist()
            self.assertEqual(names, ["demo-skill/SKILL.md", "demo-skill/refs/a.md"])
            self.assertTrue(all(n.startswith("demo-skill/") for n in names))
            self.assertIn("demo-skill/SKILL.md", names)

    def test_deterministic_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_skill(root, "demo-skill", "demo-skill", "Demo.")
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
            before = (d / "SKILL.md").read_bytes()
            pack.pack_all(root)
            self.assertEqual((d / "SKILL.md").read_bytes(), before)

    def test_removes_orphan_zip(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_skill(root, "keep-me", "keep-me", "Keep.")
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
            (root / "real-skill.zip").write_bytes(b"old")
            pack.pack_all(root)
            with zipfile.ZipFile(root / "real-skill.zip") as zf:
                self.assertIn("real-skill/SKILL.md", zf.namelist())

    def test_unix_create_system_for_cross_os_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_skill(root, "demo-skill", "demo-skill", "Demo.")
            pack.pack_all(root)
            with zipfile.ZipFile(root / "demo-skill.zip") as zf:
                for info in zf.infolist():
                    self.assertEqual(info.create_system, 3)
                    self.assertEqual(info.date_time, (1980, 1, 1, 0, 0, 0))


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
            report = pack.pack_all(root)
            joined = "\n".join(report.warnings)
            self.assertTrue(any("Good_Name" in w and "name" in w.lower() for w in report.warnings))
            self.assertTrue(any("claude-helper" in w and "claude" in w.lower() for w in report.warnings))
            self.assertTrue(any("tag-skill" in w and "<project>" in w for w in report.warnings))
            self.assertTrue(any("long-skill" in w and "1024" in w for w in report.warnings))
            self.assertTrue(any("mismatch" in w and "other-name" in w for w in report.warnings))
            self.assertFalse(any(w.startswith("ok-skill:") for w in report.warnings))
            # Still packed; validation does not block writing.
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


if __name__ == "__main__":
    unittest.main()
