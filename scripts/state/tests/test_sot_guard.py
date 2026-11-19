"""sot_guard.py: the .claude/sot.json registry, after-edit checks, CSV cell report, commit-time check, lint."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

from state_test_support import git, make_repo, run_tool

CHECKER = """import csv, sys
rows = list(csv.reader(open(sys.argv[1], encoding="utf-8")))
bad = [r for r in rows[1:] if "BAD" in r]
print("bad rows: %d" % len(bad))
sys.exit(1 if bad else 0)
"""
GOOD_CSV = "circuit,from,to\nC1,A1,B1\nC2,A2,B2\n"


def py_command(*args):
    return " ".join(['"%s"' % sys.executable] + list(args))


def registry(**overrides):
    entry = {
        "name": "wirelist",
        "paths": ["data/master.csv"],
        "checks": [{"run": py_command("tools/check_csv.py", "data/master.csv"), "fast": True}],
        "regenerate": [py_command("tools/build.py")],
        "derived": ["generated/**"],
        "report": "cells",
    }
    entry.update(overrides)
    return {"entries": [entry]}


class SotGuardTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = make_repo(self.tmp.name, "sot-repo")
        self.write("tools/check_csv.py", CHECKER)
        self.write("tools/build.py", "print('built')\n")
        self.write("data/master.csv", GOOD_CSV)
        self.write("generated/list.txt", "C1\nC2\n")
        self.write_registry(registry())
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "base")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text):
        path = self.repo / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")
        return path

    def write_registry(self, data):
        self.write(".claude/sot.json", json.dumps(data, indent=2))

    def sot(self, *args):
        return run_tool("sot_guard.py", "--repo", self.repo, *args, cwd=self.repo)

    def test_match_names_the_entry_and_its_fast_checks(self):
        r = self.sot("match", self.repo / "data" / "master.csv")
        out = json.loads(r.stdout)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(out["kind"], "sot")
        self.assertEqual(out["entry"], "wirelist")
        self.assertTrue(out["fast_checks"])

    def test_match_derived_and_unlisted(self):
        self.assertEqual(json.loads(self.sot("match", "generated/list.txt").stdout)["kind"], "derived")
        self.assertIsNone(json.loads(self.sot("match", "notes.md").stdout)["kind"])

    def test_after_edit_good_value_passes_and_lists_changed_cells(self):
        self.write("data/master.csv", "circuit,from,to\nC1,A1,B9\nC2,A2,B2\n")
        r = self.sot("after-edit", self.repo / "data" / "master.csv")
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("PASS", r.stdout)
        self.assertIn("row 2 to: 'B1' -> 'B9'", r.stdout)
        self.assertIn("Changed vs HEAD (1)", r.stdout)

    def test_after_edit_bad_value_fails_loudly(self):
        self.write("data/master.csv", "circuit,from,to\nC1,A1,BAD\nC2,A2,B2\n")
        r = self.sot("after-edit", self.repo / "data" / "master.csv")
        self.assertEqual(r.returncode, 2)
        self.assertIn("FAIL", r.stdout)
        self.assertIn("SOT CHECK FAILED", r.stdout)
        self.assertIn("'B1' -> 'BAD'", r.stdout)

    def test_after_edit_added_row_is_reported(self):
        self.write("data/master.csv", GOOD_CSV + "C3,A3,B3\n")
        r = self.sot("after-edit", "data/master.csv")
        self.assertIn("row 4 added: C3,A3,B3", r.stdout)

    def test_after_edit_of_derived_file_warns(self):
        self.write("generated/list.txt", "hand edit\n")
        r = self.sot("after-edit", "generated/list.txt")
        self.assertEqual(r.returncode, 2)
        self.assertIn("SOT WARNING", r.stdout)
        self.assertIn("build.py", r.stdout)

    def test_after_edit_unlisted_file_is_silent(self):
        self.write("notes.md", "x\n")
        r = self.sot("after-edit", "notes.md")
        self.assertEqual((r.returncode, r.stdout), (0, ""))

    def test_check_passes_on_good_change_and_fails_on_bad(self):
        self.write("data/master.csv", "circuit,from,to\nC1,A1,B7\nC2,A2,B2\n")
        self.assertEqual(self.sot("check", "--base", "HEAD").returncode, 0)
        self.write("data/master.csv", "circuit,from,to\nC1,A1,BAD\nC2,A2,B2\n")
        r = self.sot("check", "--base", "HEAD")
        self.assertEqual(r.returncode, 2)
        self.assertIn("sot check: 1 failure", r.stdout)

    def test_check_sees_committed_changes_since_the_merge_base(self):
        git(self.repo, "checkout", "-q", "-b", "feat/x")
        self.write("data/master.csv", "circuit,from,to\nC1,BAD,B1\nC2,A2,B2\n")
        git(self.repo, "commit", "-q", "-am", "bad value")
        self.assertEqual(self.sot("check", "--base", "main").returncode, 2)
        self.assertEqual(self.sot("check").returncode, 2)

    def test_check_fails_on_hand_edited_derived_file(self):
        self.write("generated/list.txt", "hand edit\n")
        r = self.sot("check", "--base", "HEAD")
        self.assertEqual(r.returncode, 2)
        self.assertIn("never hand-edited", r.stdout)

    def test_check_allows_derived_change_with_its_sot_change(self):
        self.write("data/master.csv", GOOD_CSV + "C3,A3,B3\n")
        self.write("generated/list.txt", "C1\nC2\nC3\n")
        self.assertEqual(self.sot("check", "--base", "HEAD").returncode, 0)

    def test_check_with_no_changes_is_quiet(self):
        r = self.sot("check", "--base", "HEAD")
        self.assertEqual((r.returncode, r.stdout), (0, ""))

    def test_entry_without_checks_fails_check(self):
        self.write_registry(registry(checks=[]))
        self.write("data/master.csv", GOOD_CSV + "C3,A3,B3\n")
        r = self.sot("check", "--base", "HEAD")
        self.assertEqual(r.returncode, 2)
        self.assertIn("no checks", r.stdout)

    def test_slow_checks_run_only_at_commit(self):
        slow = py_command("-c", '"import sys; sys.exit(1)"')
        fast = py_command("tools/check_csv.py", "data/master.csv")
        self.write_registry(registry(checks=[{"run": slow, "fast": False}, {"run": fast, "fast": True}]))
        self.write("data/master.csv", GOOD_CSV + "C3,A3,B3\n")
        after = self.sot("after-edit", "data/master.csv")
        self.assertEqual(after.returncode, 0, after.stdout)
        self.assertIn("At commit", after.stdout)
        self.assertEqual(self.sot("check", "--base", "HEAD").returncode, 2)

    def test_lint_warns_on_no_checks_and_overlap(self):
        self.write_registry(registry(checks=[], derived=["data/**"]))
        r = self.sot("lint-registry")
        self.assertEqual(r.returncode, 0)
        self.assertIn("has no checks", r.stdout)
        self.assertIn("overlaps SoT paths", r.stdout)

    def test_lint_clean_registry_has_no_warnings(self):
        r = self.sot("lint-registry")
        self.assertEqual(r.returncode, 0)
        self.assertIn("0 warning(s)", r.stdout)

    def test_lint_warns_on_path_matching_no_file(self):
        self.write_registry(registry(paths=["data/missing.csv"]))
        self.assertIn("matches no tracked file", self.sot("lint-registry").stdout)

    def test_invalid_registry_exits_2(self):
        self.write(".claude/sot.json", "{not json")
        self.assertEqual(self.sot("lint-registry").returncode, 2)
        self.write_registry({"entries": [{"paths": ["a"], "bogus": 1}]})
        r = self.sot("check")
        self.assertEqual(r.returncode, 2)
        self.assertIn("unknown keys bogus", r.stdout)
        self.write_registry({"entries": [{"paths": ["a"], "report": "pixels"}]})
        self.assertEqual(self.sot("lint-registry").returncode, 2)

    def test_no_registry_is_a_no_op(self):
        (self.repo / ".claude" / "sot.json").unlink()
        self.assertEqual(self.sot("check").returncode, 0)
        self.assertEqual(self.sot("after-edit", "data/master.csv").returncode, 0)
        self.assertIsNone(json.loads(self.sot("match", "data/master.csv").stdout)["kind"])

    def test_glob_rules(self):
        import sot_guard
        self.assertTrue(sot_guard.matches("sot/a/b.csv", ["sot/**"]))
        self.assertTrue(sot_guard.matches("sot/a/b.csv", ["sot/"]))
        self.assertFalse(sot_guard.matches("sot/a/b.csv", ["sot/*.csv"]))
        self.assertTrue(sot_guard.matches("Docs/X.CSV", ["docs/x.csv"]))
        self.assertTrue(sot_guard.matches("a/b/c.csv", ["**/c.csv"]))

    def test_path_outside_the_repo_is_not_matched(self):
        outside = Path(self.tmp.name) / "loose.csv"
        outside.write_text("x\n", encoding="utf-8")
        self.assertIsNone(json.loads(self.sot("match", outside).stdout)["kind"])


if __name__ == "__main__":
    unittest.main()
