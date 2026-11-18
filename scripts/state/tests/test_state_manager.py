import re

from state_test_support import TempDirCase, commit_file, git, make_repo, run_tool

import state_lint
import state_manager


class StateManagerTests(TempDirCase):
    def setUp(self):
        super().setUp()
        self.repo = make_repo(self.tmp, "Managed_Repo")
        commit_file(self.repo, "README.md", "x\n")
        self.store = self.tmp / "store"
        self.store.mkdir()
        self.folder = self.store / "managed-repo"

    def run_manager(self, *args, cwd=None):
        return run_tool("state_manager.py", *args, "--store", self.store, cwd=cwd or self.repo)

    def test_init_creates_valid_files_and_never_overwrites(self):
        self.assertEqual(self.run_manager("init").returncode, 0)
        state = self.folder / "STATE.md"
        self.assertEqual(state_lint.lint_file(state), [])
        self.assertTrue((self.folder / "BACKLOG.md").is_file())
        self.assertTrue((self.folder / "archives").is_dir())
        state.write_text(state.read_text(encoding="utf-8").replace("none yet", "kept goal"), encoding="utf-8")
        self.assertEqual(self.run_manager("init").returncode, 0)
        self.assertIn("kept goal", state.read_text(encoding="utf-8"))

    def test_init_without_store_fails_and_creates_nothing(self):
        missing = self.tmp / "missing-store"
        result = run_tool("state_manager.py", "init", "--store", missing, cwd=self.repo)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(missing.exists())

    def root_bytes(self):
        return (self.folder / "STATE.md").read_bytes()

    def test_new_branch_creates_slug_file_and_never_writes_root(self):
        self.run_manager("init")
        before = self.root_bytes()
        result = self.run_manager("new-branch", "--branch", "feature/Big_Thing")
        self.assertEqual(result.returncode, 0, result.stderr)
        branch_file = self.folder / "STATE-feature-big-thing.md"
        self.assertEqual(state_lint.lint_file(branch_file), [])
        self.assertIn("Branch: feature/Big_Thing", branch_file.read_text(encoding="utf-8"))
        self.assertEqual(self.root_bytes(), before)
        self.assertEqual(self.run_manager("verify").returncode, 0)

    def test_init_root_pointer_is_generated(self):
        self.run_manager("init")
        root = (self.folder / "STATE.md").read_text(encoding="utf-8")
        self.assertTrue(state_manager.pointer_is_generated(root))

    def test_branches_prints_generated_line_from_files(self):
        self.run_manager("init")
        self.assertIn("- Branch_States: none", self.run_manager("branches").stdout)
        self.run_manager("new-branch", "--branch", "feature/b")
        self.run_manager("new-branch", "--branch", "feature/a")
        line = self.run_manager("branches").stdout.strip()
        self.assertEqual(line, "- Branch_States: STATE-feature-a.md, STATE-feature-b.md")

    def test_lint_and_verify_accept_pasted_branches_line(self):
        self.run_manager("init")
        self.run_manager("new-branch", "--branch", "feature/a")
        line = self.run_manager("branches").stdout.strip()
        root = self.folder / "STATE.md"
        text = root.read_text(encoding="utf-8")
        text = "\n".join(line if l.startswith("- Branch_States:") else l for l in text.splitlines()) + "\n"
        root.write_text(text, encoding="utf-8")
        self.assertEqual(state_lint.lint_file(root), [])
        self.assertEqual(self.run_manager("verify").returncode, 0)

    def test_verify_flags_stale_explicit_list_with_hint(self):
        self.run_manager("init")
        root = self.folder / "STATE.md"
        text = root.read_text(encoding="utf-8")
        root.write_text(text.replace(state_manager.GENERATED_POINTER, "none"), encoding="utf-8")
        self.run_manager("new-branch", "--branch", "feature/a")
        result = self.run_manager("verify")
        self.assertEqual(result.returncode, 2)
        self.assertIn("does not list STATE-feature-a.md", result.stdout)
        self.assertIn("branches", result.stdout)

    def test_branches_with_unreachable_store_exits_0(self):
        result = run_tool("state_manager.py", "branches", "--store", self.tmp / "nope", cwd=self.repo)
        self.assertEqual(result.returncode, 0)
        self.assertIn("unreachable", result.stderr)

    def test_new_branch_refuses_trunk(self):
        self.run_manager("init")
        self.assertEqual(self.run_manager("new-branch", "--branch", "main").returncode, 1)

    def test_archive_branch_moves_file_and_never_writes_root(self):
        self.run_manager("init")
        self.run_manager("new-branch", "--branch", "feature/a")
        self.run_manager("new-branch", "--branch", "feature/b")
        before = self.root_bytes()
        result = self.run_manager("archive-branch", "--branch", "feature/a")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.folder / "STATE-feature-a.md").exists())
        archived = list((self.folder / "archives").glob("STATE-feature-a-*.md"))
        self.assertEqual(len(archived), 1)
        self.assertRegex(archived[0].name, r"^STATE-feature-a-\d{8}\.md$")
        self.assertEqual(self.root_bytes(), before)
        self.assertIn("- Branch_States: STATE-feature-b.md", self.run_manager("branches").stdout)
        self.assertEqual(self.run_manager("verify").returncode, 0)

    def test_archive_twice_same_day_keeps_both(self):
        self.run_manager("init")
        for _ in range(2):
            self.run_manager("new-branch", "--branch", "feature/a")
            self.run_manager("archive-branch", "--branch", "feature/a")
        self.assertEqual(len(list((self.folder / "archives").glob("STATE-feature-a-*.md"))), 2)

    def test_verify_flags_dangling_pointer_and_unknown_sha(self):
        self.run_manager("init")
        root = self.folder / "STATE.md"
        text = root.read_text(encoding="utf-8")
        text = text.replace("- Branch_States: " + state_manager.GENERATED_POINTER, "- Branch_States: STATE-ghost.md")
        text = text.replace("Last_Verified_SHA: none", "Last_Verified_SHA: " + "ab" * 20)
        root.write_text(text, encoding="utf-8")
        result = self.run_manager("verify")
        self.assertEqual(result.returncode, 2)
        self.assertIn("STATE-ghost.md", result.stdout)
        self.assertIn("not a commit", result.stdout)

    def test_verify_accepts_real_sha(self):
        self.run_manager("init")
        root = self.folder / "STATE.md"
        sha = git(self.repo, "rev-parse", "HEAD")
        root.write_text(root.read_text(encoding="utf-8").replace("Last_Verified_SHA: none",
                                                                  "Last_Verified_SHA: " + sha), encoding="utf-8")
        self.assertEqual(self.run_manager("verify").returncode, 0)

    def test_verify_with_unreachable_store_exits_0(self):
        result = run_tool("state_manager.py", "verify", "--store", self.tmp / "nope", cwd=self.repo)
        self.assertEqual(result.returncode, 0)
        self.assertIn("unreachable", result.stderr)

    def test_worktree_uses_main_repo_folder_and_its_branch(self):
        self.run_manager("init")
        worktree = self.repo / ".claude" / "worktrees" / "w1"
        git(self.repo, "worktree", "add", "-q", "-b", "team/w1-docs", str(worktree))
        self.assertEqual(self.run_manager("new-branch", cwd=worktree).returncode, 0)
        self.assertTrue((self.folder / "STATE-team-w1-docs.md").is_file())
        self.assertFalse((self.store / "w1").exists())

    def test_pointer_helpers_round_trip(self):
        self.assertEqual(state_manager.read_pointer("- Branch_States: a.md, b.md\n"), ["a.md", "b.md"])
        self.assertEqual(state_manager.read_pointer("- Branch_States: none\n"), [])
        self.assertIsNone(state_manager.read_pointer("nothing\n"))
        self.assertEqual(state_manager.read_pointer("- Branch_States: generated (state_manager.py branches)\n"), [])
        self.assertTrue(state_manager.pointer_is_generated("- Branch_States: generated\n"))
        self.assertFalse(state_manager.pointer_is_generated("- Branch_States: none\n"))
        self.assertTrue(re.search(r"Updated: \d{4}-\d{2}-\d{2} -- ", state_manager.render("r", "main")))
