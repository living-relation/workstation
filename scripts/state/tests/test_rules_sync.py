from state_test_support import TempDirCase, make_repo, run_tool

import rules_sync

SCOPED_RULE = """---
description: Wiring rules
paths:
  - "docs/wiring/**"
  - src/*.py
---
# Wiring

Edit the master list only.
"""

GLOBAL_RULE = """# State protocol

Read STATE first.
"""


class RenderTests(TempDirCase):
    def test_scoped_rule_maps_paths_to_globs(self):
        out = rules_sync.render(".claude/rules/wiring.md", SCOPED_RULE)
        self.assertTrue(out.startswith("---\ndescription: Wiring rules\nglobs: docs/wiring/**,src/*.py\n"
                                       "alwaysApply: false\n---\n"))
        self.assertIn("do not edit", out)
        self.assertIn("Edit the master list only.", out)

    def test_rule_without_paths_is_always_on(self):
        out = rules_sync.render(".claude/rules/state.md", GLOBAL_RULE)
        self.assertIn("alwaysApply: true", out)
        self.assertIn("# State protocol", out)

    def test_inline_list_paths(self):
        meta, _ = rules_sync.split_front_matter("---\npaths: [a/**, \"b/*.md\"]\n---\nbody\n")
        self.assertEqual(meta["paths"], ["a/**", "b/*.md"])


class SyncCliTests(TempDirCase):
    def setUp(self):
        super().setUp()
        self.repo = make_repo(self.tmp, "Rules_Repo")
        rules = self.repo / ".claude" / "rules"
        rules.mkdir(parents=True)
        (rules / "wiring.md").write_text(SCOPED_RULE, encoding="utf-8")
        (rules / "00-state.md").write_text(GLOBAL_RULE, encoding="utf-8")
        self.cursor = self.repo / ".cursor" / "rules"

    def sync(self, *args):
        return run_tool("rules_sync.py", "--repo", self.repo, *args)

    def snapshot(self):
        return {p.name: p.read_bytes() for p in sorted(self.cursor.glob("*.mdc"))}

    def test_running_twice_gives_identical_output(self):
        self.assertEqual(self.sync().returncode, 0)
        first = self.snapshot()
        self.assertEqual(self.sync().returncode, 0)
        self.assertEqual(self.snapshot(), first)
        self.assertEqual(sorted(first), ["00-state.mdc", "wiring.mdc"])
        self.assertEqual(self.sync("--check").returncode, 0)

    def test_check_before_sync_reports_missing(self):
        result = self.sync("--check")
        self.assertEqual(result.returncode, 2)
        self.assertIn("MISSING", result.stdout)
        self.assertFalse(self.cursor.exists())

    def test_hand_edited_mdc_fails_check(self):
        self.sync()
        target = self.cursor / "wiring.mdc"
        target.write_text(target.read_text(encoding="utf-8") + "extra hand edit\n", encoding="utf-8")
        result = self.sync("--check")
        self.assertEqual(result.returncode, 2)
        self.assertIn("DRIFT .cursor/rules/wiring.mdc", result.stdout)

    def test_crlf_checkout_is_not_drift(self):
        self.sync()
        target = self.cursor / "wiring.mdc"
        target.write_bytes(target.read_bytes().replace(b"\n", b"\r\n"))
        self.assertEqual(self.sync("--check").returncode, 0)

    def test_orphan_generated_rule_is_flagged_and_removed(self):
        self.sync()
        (self.repo / ".claude" / "rules" / "wiring.md").unlink()
        self.assertEqual(self.sync("--check").returncode, 2)
        self.sync()
        self.assertFalse((self.cursor / "wiring.mdc").exists())

    def test_hand_made_mdc_without_source_is_left_alone(self):
        self.cursor.mkdir(parents=True)
        (self.cursor / "own.mdc").write_text("---\nalwaysApply: true\n---\nmine\n", encoding="utf-8")
        self.sync()
        self.assertTrue((self.cursor / "own.mdc").exists())
        self.assertEqual(self.sync("--check").returncode, 0)

    def test_no_rules_folder_and_no_generated_rules_exits_0_with_note(self):
        empty = make_repo(self.tmp, "Empty_Repo")
        for args in ((), ("--check",)):
            result = run_tool("rules_sync.py", "--repo", empty, *args)
            self.assertEqual(result.returncode, 0)
            self.assertIn("NOTE", result.stderr)

    def test_no_rules_folder_but_generated_rules_left_is_drift(self):
        self.sync()
        for source in (self.repo / ".claude" / "rules").glob("*.md"):
            source.unlink()
        (self.repo / ".claude" / "rules").rmdir()
        result = self.sync("--check")
        self.assertEqual(result.returncode, 2)
        self.assertIn("ORPHAN", result.stdout)

    def test_hand_made_mdc_with_a_source_name_is_a_conflict_and_kept(self):
        self.cursor.mkdir(parents=True)
        own = self.cursor / "wiring.mdc"
        own.write_text("---\nalwaysApply: true\n---\nmy own wiring rule\n", encoding="utf-8")
        before = own.read_bytes()
        result = self.sync()
        self.assertEqual(result.returncode, 2)
        self.assertIn("CONFLICT .cursor/rules/wiring.mdc", result.stdout)
        self.assertEqual(own.read_bytes(), before)
        self.assertTrue((self.cursor / "00-state.mdc").exists())
        check = self.sync("--check")
        self.assertEqual(check.returncode, 2)
        self.assertIn("CONFLICT", check.stdout)
