import json
import os
import subprocess
import unittest
from pathlib import Path
from unittest import mock

from state_test_support import TempDirCase, git, make_repo, commit_file, run_tool

import state_paths


class SlugTests(unittest.TestCase):
    def test_branch_slug_replaces_non_alnum_and_lowercases(self):
        self.assertEqual(state_paths.slugify("Feature/Some_Thing.v2"), "feature-some-thing-v2")

    def test_slug_trims_dashes(self):
        self.assertEqual(state_paths.slugify("--a//b--"), "a-b")

    def test_trunk_uses_root_state(self):
        for branch in ("main", "master", None):
            self.assertEqual(state_paths.branch_state_name(branch), "STATE.md")

    def test_branch_uses_slug_state(self):
        self.assertEqual(state_paths.branch_state_name("team/w1-x"), "STATE-team-w1-x.md")


class LinkTargetFallbackTests(TempDirCase):
    def without_isjunction(self):
        return mock.patch.object(os.path, "isjunction", None, create=True)

    def test_plain_folder_is_not_a_link_without_isjunction(self):
        folder = self.tmp / "plain"
        folder.mkdir()
        with self.without_isjunction():
            self.assertIsNone(state_paths._link_target(folder))

    def test_plain_file_and_missing_path_are_not_links(self):
        target = self.tmp / "file.txt"
        target.write_text("x", encoding="utf-8")
        with self.without_isjunction():
            self.assertIsNone(state_paths._link_target(target))
            self.assertIsNone(state_paths._link_target(self.tmp / "missing"))

    @unittest.skipUnless(os.name == "nt", "directory junctions are Windows only")
    def test_junction_resolves_without_isjunction(self):
        real = self.tmp / "real-store"
        real.mkdir()
        link = self.tmp / "junction"
        done = subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(real)], capture_output=True)
        if done.returncode != 0:
            self.skipTest("mklink /J failed")
        with self.without_isjunction():
            target = state_paths._link_target(link)
        self.assertIsNotNone(target)
        self.assertEqual(Path(os.path.normcase(str(target))).resolve(), Path(os.path.normcase(str(real))).resolve())

    def test_symlink_resolves_without_isjunction(self):
        real = self.tmp / "real"
        real.mkdir()
        link = self.tmp / "sym"
        try:
            os.symlink(str(real), str(link), target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("symlinks not permitted here")
        with self.without_isjunction():
            self.assertEqual(Path(state_paths._link_target(link)).resolve(), real.resolve())


class StoreResolutionTests(TempDirCase):
    def test_env_overrides_everything(self):
        home = self.tmp / "home"
        (home / ".claude" / "hooks").mkdir(parents=True)
        (home / ".claude" / "hooks" / "memory-link-guard.config.json").write_text(
            json.dumps({"storePath": str(self.tmp / "config-store")}), encoding="utf-8")
        store = state_paths.find_store(env={"WORKSTATION_MEMORY_STORE": str(self.tmp / "env-store")}, home=home)
        self.assertEqual(store, self.tmp / "env-store")

    def test_config_store_path_beats_default(self):
        home = self.tmp / "home"
        (home / ".claude" / "hooks").mkdir(parents=True)
        (home / ".claude" / "hooks" / "memory-link-guard.config.json").write_text(
            json.dumps({"storePath": "~/custom-store"}), encoding="utf-8")
        self.assertEqual(state_paths.find_store(env={}, home=home), home / "custom-store")

    def test_auto_memory_link_target_is_used(self):
        home = self.tmp / "home"
        target = self.tmp / "real-store"
        target.mkdir()
        (home / ".claude").mkdir(parents=True)
        link = home / "memory-link"
        try:
            os.symlink(target, link, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("symlinks not permitted here")
        (home / ".claude" / "settings.json").write_text(json.dumps({"autoMemoryDirectory": str(link)}),
                                                        encoding="utf-8")
        self.assertEqual(Path(os.path.realpath(state_paths.find_store(env={}, home=home))),
                         Path(os.path.realpath(target)))

    def test_default_store_under_home(self):
        home = self.tmp / "home"
        home.mkdir()
        store = state_paths.find_store(env={}, home=home)
        self.assertEqual(store, home.joinpath(*state_paths.DEFAULT_STORE_PARTS))

    def test_bad_config_json_falls_through(self):
        home = self.tmp / "home"
        (home / ".claude" / "hooks").mkdir(parents=True)
        (home / ".claude" / "hooks" / "memory-link-guard.config.json").write_text("{not json", encoding="utf-8")
        self.assertEqual(state_paths.find_store(env={}, home=home), home.joinpath(*state_paths.DEFAULT_STORE_PARTS))


class WorktreeTests(TempDirCase):
    def test_worktree_resolves_main_repo_project(self):
        repo = make_repo(self.tmp, "My_Main.Repo")
        commit_file(repo, "README.md", "x\n")
        worktree = repo / ".claude" / "worktrees" / "w9"
        git(repo, "worktree", "add", "-q", "-b", "team/w9-tools", str(worktree))
        self.assertEqual(state_paths.project_name(worktree), "my-main-repo")
        self.assertEqual(state_paths.current_branch(worktree), "team/w9-tools")
        info = state_paths.resolve(worktree, env={"WORKSTATION_MEMORY_STORE": str(self.tmp / "store")})
        self.assertEqual(Path(info["state_file"]), worktree.resolve() / "STATE-team-w9-tools.md")
        self.assertEqual(Path(info["notes_dir"]), self.tmp / "store" / "my-main-repo")
        self.assertFalse(info["state_ready"])

    def test_state_ready_when_worktree_root_has_state(self):
        repo = make_repo(self.tmp, "Ready_Repo")
        commit_file(repo, "STATE.md", "x\n")
        (repo / "sub").mkdir()
        info = state_paths.resolve(repo / "sub", env={"WORKSTATION_MEMORY_STORE": str(self.tmp / "store")})
        self.assertTrue(info["state_ready"])
        self.assertEqual(Path(info["state_dir"]), repo.resolve())
        self.assertEqual(Path(info["state_file"]), repo.resolve() / "STATE.md")

    def test_dotgit_file_fallback_without_git(self):
        main = self.tmp / "Other-Repo"
        (main / ".git" / "worktrees" / "x").mkdir(parents=True)
        worktree = self.tmp / "wt"
        worktree.mkdir()
        (worktree / ".git").write_text("gitdir: %s\n" % (main / ".git" / "worktrees" / "x"), encoding="utf-8")
        self.assertEqual(state_paths._main_root_from_dotgit(worktree).name, "Other-Repo")

    def test_cli_from_worktree_prints_main_project(self):
        repo = make_repo(self.tmp, "Cli_Repo")
        commit_file(repo, "README.md", "x\n")
        worktree = repo / ".claude" / "worktrees" / "a"
        git(repo, "worktree", "add", "-q", "-b", "feature/a", str(worktree))
        result = run_tool("state_paths.py", "--json", cwd=worktree,
                          env={"WORKSTATION_MEMORY_STORE": str(self.tmp / "store")})
        self.assertEqual(result.returncode, 0, result.stderr)
        info = json.loads(result.stdout)
        self.assertEqual(info["project"], "cli-repo")
        self.assertEqual(info["slug"], "feature-a")

    def test_non_repo_has_no_project(self):
        plain = self.tmp / "plain"
        plain.mkdir()
        self.assertIsNone(state_paths.project_name(plain))


if __name__ == "__main__":
    unittest.main()
