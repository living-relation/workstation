import re

from state_test_support import TempDirCase, commit_file, git, make_repo, run_tool

import state_lint
import state_manager


class StateManagerTests(TempDirCase):
    def setUp(self):
        super().setUp()
        self.repo = make_repo(self.tmp, "Managed_Repo")
        commit_file(self.repo, "README.md", "x\n")
        self.folder = self.repo

    def run_manager(self, *args, cwd=None):
        return run_tool("state_manager.py", *args, cwd=cwd or self.repo)

    def init_and_commit(self):
        self.assertEqual(self.run_manager("init").returncode, 0)
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "state")

    def test_init_creates_valid_files_in_repo_and_never_overwrites(self):
        self.assertEqual(self.run_manager("init").returncode, 0)
        state = self.folder / "STATE.md"
        self.assertEqual(state_lint.lint_file(state), [])
        self.assertTrue((self.folder / "BACKLOG.md").is_file())
        self.assertTrue((self.folder / "archives" / ".gitkeep").is_file())
        state.write_text(state.read_text(encoding="utf-8").replace("none yet", "kept goal"), encoding="utf-8")
        self.assertEqual(self.run_manager("init").returncode, 0)
        self.assertIn("kept goal", state.read_text(encoding="utf-8"))

    def test_not_a_repo_fails(self):
        plain = self.tmp / "plain"
        plain.mkdir()
        self.assertEqual(run_tool("state_manager.py", "init", cwd=plain).returncode, 1)

    def root_bytes(self):
        return (self.folder / "STATE.md").read_bytes()

    def test_new_branch_creates_slug_file_and_never_writes_root(self):
        self.init_and_commit()
        git(self.repo, "checkout", "-q", "-b", "feature/Big_Thing")
        before = self.root_bytes()
        result = self.run_manager("new-branch")
        self.assertEqual(result.returncode, 0, result.stderr)
        branch_file = self.folder / "STATE-feature-big-thing.md"
        self.assertEqual(state_lint.lint_file(branch_file), [])
        self.assertIn("Branch: feature/Big_Thing", branch_file.read_text(encoding="utf-8"))
        self.assertEqual(self.root_bytes(), before)
        self.assertEqual(self.run_manager("verify").returncode, 0)

    def test_new_branch_in_unmigrated_repo_makes_nothing(self):
        git(self.repo, "checkout", "-q", "-b", "feature/x")
        result = self.run_manager("new-branch")
        self.assertEqual(result.returncode, 0)
        self.assertIn("not migrated", result.stderr)
        self.assertFalse((self.folder / "STATE-feature-x.md").exists())

    def test_init_uses_origin_head_default_branch(self):
        git(self.repo, "update-ref", "refs/remotes/origin/prod", "HEAD")
        git(self.repo, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/prod")
        self.run_manager("init")
        root = (self.folder / "STATE.md").read_text(encoding="utf-8")
        self.assertIn("Branch: prod\n", root)

    def test_init_without_origin_uses_current_branch(self):
        git(self.repo, "checkout", "-q", "-b", "develop")
        self.run_manager("init")
        self.assertIn("Branch: develop\n", (self.folder / "STATE.md").read_text(encoding="utf-8"))

    def test_init_root_pointer_is_generated(self):
        self.run_manager("init")
        self.assertTrue(state_manager.pointer_is_generated((self.folder / "STATE.md").read_text(encoding="utf-8")))

    def add_worktree(self, branch, name):
        path = self.tmp / "wt" / name
        git(self.repo, "worktree", "add", "-q", "-b", branch, str(path))
        self.assertEqual(self.run_manager("new-branch", cwd=path).returncode, 0)
        return path

    def test_branches_reads_unpushed_worktrees(self):
        self.init_and_commit()
        self.assertIn("- Branch_States: none", self.run_manager("branches", "--no-fetch").stdout)
        self.add_worktree("feature/b", "b")
        self.add_worktree("feature/a", "a")
        line = self.run_manager("branches", "--no-fetch").stdout.splitlines()[0]
        self.assertEqual(line, "- Branch_States: STATE-feature-a.md, STATE-feature-b.md")

    def test_branches_reads_pushed_refs_after_fetch_and_show_prints_files(self):
        self.init_and_commit()
        remote = self.tmp / "remote.git"
        git(self.tmp, "init", "-q", "--bare", "-b", "main", str(remote))
        git(self.repo, "remote", "add", "origin", str(remote))
        git(self.repo, "push", "-q", "origin", "main")
        other = self.tmp / "other"
        git(self.tmp, "clone", "-q", str(remote), str(other))
        for key, value in (("user.name", "T"), ("user.email", "t@example.invalid"), ("commit.gpgsign", "false"),
                           ("core.hooksPath", str(self.tmp / "no-hooks"))):
            git(other, "config", key, value)
        git(other, "checkout", "-q", "-b", "team/w1-docs")
        self.assertEqual(run_tool("state_manager.py", "new-branch", cwd=other).returncode, 0)
        git(other, "add", "STATE-team-w1-docs.md")
        git(other, "commit", "-q", "-m", "worker state")
        git(other, "push", "-q", "origin", "team/w1-docs")
        result = self.run_manager("branches", "--show")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("- Branch_States: STATE-team-w1-docs.md", result.stdout)
        self.assertIn("Branch: team/w1-docs", result.stdout)
        self.assertIn("origin/team/w1-docs:STATE-team-w1-docs.md", result.stdout)

    def test_lint_and_verify_accept_pasted_branches_line(self):
        self.init_and_commit()
        self.add_worktree("feature/a", "a")
        line = self.run_manager("branches", "--no-fetch").stdout.splitlines()[0]
        root = self.folder / "STATE.md"
        text = root.read_text(encoding="utf-8")
        text = "\n".join(line if l.startswith("- Branch_States:") else l for l in text.splitlines()) + "\n"
        root.write_text(text, encoding="utf-8")
        self.assertEqual(state_lint.lint_file(root), [])
        self.assertEqual(self.run_manager("verify").returncode, 0)

    def test_verify_flags_stale_explicit_list_with_hint(self):
        self.init_and_commit()
        root = self.folder / "STATE.md"
        root.write_text(root.read_text(encoding="utf-8").replace(state_manager.GENERATED_POINTER, "none"),
                        encoding="utf-8")
        self.add_worktree("feature/a", "a")
        result = self.run_manager("verify")
        self.assertEqual(result.returncode, 2)
        self.assertIn("does not list STATE-feature-a.md", result.stdout)
        self.assertIn("branches", result.stdout)

    def test_verify_in_unmigrated_repo_exits_0(self):
        result = self.run_manager("verify")
        self.assertEqual(result.returncode, 0)
        self.assertIn("not migrated", result.stderr)

    def test_verify_flags_branch_state_left_on_trunk(self):
        self.init_and_commit()
        commit_file(self.repo, "STATE-feature-old.md", state_manager.render("r", "feature/old"))
        result = self.run_manager("verify")
        self.assertEqual(result.returncode, 2)
        self.assertIn("STATE-feature-old.md: a branch state file on the trunk", result.stdout)

    def test_new_branch_refuses_trunk(self):
        self.init_and_commit()
        self.assertEqual(self.run_manager("new-branch", "--branch", "main").returncode, 1)

    def test_archive_branch_git_mvs_file_and_never_writes_root(self):
        self.init_and_commit()
        git(self.repo, "checkout", "-q", "-b", "feature/a")
        self.run_manager("new-branch")
        git(self.repo, "add", "STATE-feature-a.md")
        git(self.repo, "commit", "-q", "-m", "branch state")
        before = self.root_bytes()
        result = self.run_manager("archive-branch")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.folder / "STATE-feature-a.md").exists())
        archived = list((self.folder / "archives").glob("STATE-feature-a-*.md"))
        self.assertEqual(len(archived), 1)
        self.assertRegex(archived[0].name, r"^STATE-feature-a-\d{8}\.md$")
        self.assertEqual(self.root_bytes(), before)
        staged = git(self.repo, "diff", "--cached", "--name-status", "-M")
        self.assertRegex(staged, r"R\d*\tSTATE-feature-a.md\tarchives/STATE-feature-a-\d{8}\.md")

    def test_archive_untracked_file_moves_and_stages(self):
        self.init_and_commit()
        git(self.repo, "checkout", "-q", "-b", "feature/a")
        self.run_manager("new-branch")
        self.assertEqual(self.run_manager("archive-branch").returncode, 0)
        self.assertIn("archives/STATE-feature-a-", git(self.repo, "diff", "--cached", "--name-only"))

    def test_archive_twice_same_day_keeps_both(self):
        self.init_and_commit()
        git(self.repo, "checkout", "-q", "-b", "feature/a")
        for _ in range(2):
            self.run_manager("new-branch")
            self.run_manager("archive-branch")
        self.assertEqual(len(list((self.folder / "archives").glob("STATE-feature-a-*.md"))), 2)

    def test_verify_flags_dangling_pointer_and_unknown_sha(self):
        self.init_and_commit()
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
        self.init_and_commit()
        root = self.folder / "STATE.md"
        sha = git(self.repo, "rev-parse", "HEAD")
        root.write_text(root.read_text(encoding="utf-8").replace("Last_Verified_SHA: none",
                                                                  "Last_Verified_SHA: " + sha), encoding="utf-8")
        self.assertEqual(self.run_manager("verify").returncode, 0)

    def test_worktree_writes_its_own_root(self):
        self.init_and_commit()
        worktree = self.repo / ".claude" / "worktrees" / "w1"
        git(self.repo, "worktree", "add", "-q", "-b", "team/w1-docs", str(worktree))
        self.assertEqual(self.run_manager("new-branch", cwd=worktree).returncode, 0)
        self.assertTrue((worktree / "STATE-team-w1-docs.md").is_file())
        self.assertFalse((self.repo / "STATE-team-w1-docs.md").exists())

    def test_pointer_helpers_round_trip(self):
        self.assertEqual(state_manager.read_pointer("- Branch_States: a.md, b.md\n"), ["a.md", "b.md"])
        self.assertEqual(state_manager.read_pointer("- Branch_States: none\n"), [])
        self.assertIsNone(state_manager.read_pointer("nothing\n"))
        self.assertEqual(state_manager.read_pointer("- Branch_States: generated (state_manager.py branches)\n"), [])
        self.assertTrue(state_manager.pointer_is_generated("- Branch_States: generated\n"))
        self.assertFalse(state_manager.pointer_is_generated("- Branch_States: none\n"))
        self.assertTrue(re.search(r"Updated: \d{4}-\d{2}-\d{2} -- ", state_manager.render("r", "main")))


if __name__ == "__main__":
    import unittest
    unittest.main()
