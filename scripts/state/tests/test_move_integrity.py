from state_test_support import TempDirCase, commit_file, git, make_repo, run_tool

import move_integrity

OLD_DOC = """# Open items

| Row | Item |
|---|---|
| 12 | Route the fuel pump relay wire |
| 13 | Order the spare terminals |

- Decided: one bus only for the sensors
- History: the old bracket was replaced last month
"""


class NormalizeTests(TempDirCase):
    def test_markers_and_tags_are_ignored(self):
        self.assertEqual(move_integrity.normalize("  - [NEXT]  Do   the thing "), "Do the thing")
        self.assertEqual(move_integrity.normalize("| a | b |"), "a | b")

    def test_lines_without_content_are_skipped(self):
        self.assertFalse(move_integrity.has_content("|---|---|"))


class IntegrityCliTests(TempDirCase):
    def setUp(self):
        super().setUp()
        self.before = self.tmp / "before"
        self.before.mkdir()
        (self.before / "OPEN.md").write_text(OLD_DOC, encoding="utf-8")
        self.after = self.tmp / "after"
        self.after.mkdir()

    def write_after(self, lines):
        (self.after / "NEW.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    def all_lines(self):
        return [line for line in OLD_DOC.splitlines() if move_integrity.has_content(line)]

    def test_full_move_passes(self):
        self.write_after(["## Moved"] + self.all_lines())
        result = run_tool("move_integrity.py", "--before", self.before, "--after", self.after)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("0 lost", result.stdout)

    def test_deleting_one_line_fails_and_names_it(self):
        lines = [l for l in self.all_lines() if "spare terminals" not in l]
        self.write_after(lines)
        result = run_tool("move_integrity.py", "--before", self.before, "--after", self.after)
        self.assertEqual(result.returncode, 2)
        self.assertIn("LOST", result.stdout)
        self.assertIn("Order the spare terminals", result.stdout)
        self.assertIn("OPEN.md:6", result.stdout)
        self.assertEqual(result.stdout.count("LOST "), 1)

    def test_line_folded_into_longer_line_counts_as_moved(self):
        lines = [l for l in self.all_lines() if "one bus" not in l]
        self.write_after(lines + ["- B17 Decided: one bus only for the sensors (see rule file)"])
        result = run_tool("move_integrity.py", "--before", self.before, "--after", self.after)
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_proposal_tag_covers_line(self):
        self.write_after([l for l in self.all_lines() if "spare terminals" not in l])
        proposal = self.tmp / "proposal.md"
        proposal.write_text("| 13 | Order the spare terminals | [BKLG] | BACKLOG |\n", encoding="utf-8")
        result = run_tool("move_integrity.py", "--before", self.before, "--after", self.after,
                          "--proposal", proposal)
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_done_line_found_in_git_history_passes(self):
        repo = make_repo(self.tmp, "History_Repo")
        commit_file(repo, "docs/OPEN.md", OLD_DOC)
        git(repo, "rm", "-q", "docs/OPEN.md")
        git(repo, "commit", "-q", "-m", "drop")
        self.write_after([l for l in self.all_lines() if "old bracket" not in l])
        proposal = self.tmp / "proposal.md"
        proposal.write_text("[DONE] History: the old bracket was replaced last month\n", encoding="utf-8")
        result = run_tool("move_integrity.py", "--before", self.before, "--after", self.after,
                          "--proposal", proposal, "--git-history", repo)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("1 [DONE]", result.stdout)

    def test_done_line_missing_from_git_history_fails(self):
        repo = make_repo(self.tmp, "Empty_History")
        commit_file(repo, "README.md", "unrelated\n")
        self.write_after([l for l in self.all_lines() if "old bracket" not in l])
        proposal = self.tmp / "proposal.md"
        proposal.write_text("[DONE] History: the old bracket was replaced last month\n", encoding="utf-8")
        result = run_tool("move_integrity.py", "--before", self.before, "--after", self.after,
                          "--proposal", proposal, "--git-history", repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("not found in git history", result.stdout)

    def test_tagged_before_line_is_searched_without_its_tag(self):
        repo = make_repo(self.tmp, "Tagged_History")
        commit_file(repo, "docs/OPEN.md", OLD_DOC)
        git(repo, "rm", "-q", "docs/OPEN.md")
        git(repo, "commit", "-q", "-m", "drop")
        tagged = OLD_DOC.replace("- History: the old", "- [DONE] History: the old")
        (self.before / "OPEN.md").write_text(tagged, encoding="utf-8")
        self.write_after([l for l in self.all_lines() if "old bracket" not in l])
        result = run_tool("move_integrity.py", "--before", self.before, "--after", self.after,
                          "--git-history", repo)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("1 [DONE]", result.stdout)

    def test_history_needle_strips_marker_and_leading_tag_only(self):
        self.assertEqual(move_integrity.history_needle("  - [DONE] Ship the [NEXT] part"), "Ship the [NEXT] part")
        self.assertEqual(move_integrity.history_needle("[DONE][BKLG] x y"), "x y")
        self.assertEqual(move_integrity.history_needle("- plain line"), "- plain line")

    def test_backup_manifest_is_skipped(self):
        (self.before / "MANIFEST.sha256").write_text("abc123  OPEN.md\n", encoding="utf-8")
        self.write_after(self.all_lines())
        result = run_tool("move_integrity.py", "--before", self.before, "--after", self.after)
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_missing_path_is_usage_error(self):
        result = run_tool("move_integrity.py", "--before", self.tmp / "nope", "--after", self.after)
        self.assertEqual(result.returncode, 1)
