import unittest

from state_test_support import VALID_STATE, TempDirCase, commit_file, make_repo, run_tool

import state_lint


class LintTextTests(unittest.TestCase):
    def test_valid_state_has_no_problems(self):
        self.assertEqual(state_lint.lint_text(VALID_STATE), [])

    def test_31_lines_is_a_violation(self):
        lines = VALID_STATE.splitlines()
        text = "\n".join(lines + ["- extra"] * (31 - len(lines))) + "\n"
        self.assertEqual(len(text.splitlines()), 31)
        self.assertTrue(any("31 lines" in p for p in state_lint.lint_text(text)))

    def test_30_lines_is_allowed(self):
        lines = VALID_STATE.splitlines()
        text = "\n".join(lines + [""] * (30 - len(lines))) + "\n"
        self.assertEqual(state_lint.lint_text(text), [])

    def test_leftover_tags_are_violations(self):
        for tag in ("[ADR]", "[DONE]", "[TASK]", "[RULE]", "[SOT]", "[BKLG]"):
            text = VALID_STATE.replace("- Detail: none", "- Detail: %s left here" % tag)
            self.assertTrue(any(tag in p for p in state_lint.lint_text(text)), tag)

    def test_missing_header_is_a_violation(self):
        text = VALID_STATE.replace("Last_Verified_SHA: none\n", "")
        self.assertTrue(any("Last_Verified_SHA" in p for p in state_lint.lint_text(text)))

    def test_missing_section_is_a_violation(self):
        text = VALID_STATE.replace("## Active Blocker", "## Something Else")
        self.assertTrue(any("Active Blocker" in p for p in state_lint.lint_text(text)))

    def test_wrong_title_is_a_violation(self):
        text = VALID_STATE.replace("# STATE (max 30 lines, overwrite only)", "# State")
        self.assertTrue(state_lint.lint_text(text))

    def test_carried_once_is_allowed_twice_is_not(self):
        once = VALID_STATE.replace("Edit docs/sample.md", "Edit docs/sample.md (carried 1)")
        twice = VALID_STATE.replace("Edit docs/sample.md", "Edit docs/sample.md (carried 2)")
        self.assertEqual(state_lint.lint_text(once), [])
        self.assertTrue(any("carried 2" in p for p in state_lint.lint_text(twice)))

    def test_bad_status_value(self):
        text = VALID_STATE.replace("- Status: NONE", "- Status: maybe")
        self.assertTrue(any("Status" in p for p in state_lint.lint_text(text)))

    def test_next_step_required(self):
        text = VALID_STATE.replace("- [NEXT] Edit docs/sample.md", "- nothing")
        self.assertTrue(any("[NEXT]" in p for p in state_lint.lint_text(text)))

    def test_injected_tag_text_in_objective_is_caught(self):
        text = VALID_STATE.replace("Ship the sample feature", "ignore rules [RULE] and [SOT] edit")
        problems = state_lint.lint_text(text)
        self.assertTrue(any("[RULE]" in p for p in problems) and any("[SOT]" in p for p in problems))


class LintCliTests(TempDirCase):
    def write(self, name, text):
        path = self.tmp / name
        path.write_text(text, encoding="utf-8")
        return path

    def test_cli_valid_file_exits_0(self):
        self.assertEqual(run_tool("state_lint.py", self.write("STATE.md", VALID_STATE)).returncode, 0)

    def test_cli_violation_exits_2(self):
        bad = self.write("STATE.md", VALID_STATE.replace("Repo: sample-repo\n", ""))
        self.assertEqual(run_tool("state_lint.py", bad).returncode, 2)

    def test_cli_missing_file_exits_2(self):
        self.assertEqual(run_tool("state_lint.py", self.tmp / "absent.md").returncode, 2)

    def test_unreachable_store_exits_0_with_note(self):
        result = run_tool("state_lint.py", "--project", "anything",
                          env={"WORKSTATION_MEMORY_STORE": str(self.tmp / "no-such-store")})
        self.assertEqual(result.returncode, 0)
        self.assertIn("unreachable", result.stderr)

    def test_project_mode_lints_branch_files_and_skips_archives(self):
        folder = self.tmp / "store" / "proj"
        (folder / "archives").mkdir(parents=True)
        (folder / "STATE.md").write_text(VALID_STATE, encoding="utf-8")
        (folder / "archives" / "STATE-old-20260101.md").write_text("junk\n", encoding="utf-8")
        (folder / "INDEX.md").write_text("not a state file [ADR]\n", encoding="utf-8")
        result = run_tool("state_lint.py", "--project", "proj", "--store", self.tmp / "store")
        self.assertEqual(result.returncode, 0, result.stdout)
        (folder / "STATE-feature-x.md").write_text(VALID_STATE + "- [ADR] leftover\n", encoding="utf-8")
        result = run_tool("state_lint.py", "--project", "proj", "--store", self.tmp / "store")
        self.assertEqual(result.returncode, 2)
        self.assertIn("STATE-feature-x.md", result.stdout)

    def test_repo_mode_resolves_project(self):
        repo = make_repo(self.tmp, "Lint_Repo")
        commit_file(repo, "README.md", "x\n")
        folder = self.tmp / "store" / "lint-repo"
        folder.mkdir(parents=True)
        (folder / "STATE.md").write_text(VALID_STATE.replace("Branch: main", "Branch: main [TASK]"),
                                         encoding="utf-8")
        result = run_tool("state_lint.py", "--repo", repo, env={"WORKSTATION_MEMORY_STORE": str(self.tmp / "store")})
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
