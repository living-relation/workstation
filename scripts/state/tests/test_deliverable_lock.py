import json

from state_test_support import TempDirCase, commit_file, make_repo, run_tool

import deliverable_lock


class DeliverableLockTests(TempDirCase):
    def setUp(self):
        super().setUp()
        self.repo = make_repo(self.tmp, "Lock_Repo")
        self.drawing = commit_file(self.repo, "out/drawing.txt", "rev A\n")

    def lock_tool(self, *args):
        return run_tool("deliverable_lock.py", "--repo", self.repo, *args, cwd=self.repo)

    def locked(self):
        return json.loads((self.repo / "VERIFIED.lock").read_text(encoding="utf-8"))

    def test_lock_records_relative_path_and_sha256(self):
        self.assertEqual(self.lock_tool("lock", "out/drawing.txt").returncode, 0)
        data = self.locked()
        self.assertEqual(list(data), ["out/drawing.txt"])
        self.assertEqual(data["out/drawing.txt"], deliverable_lock.sha256_of(self.drawing))

    def test_verify_passes_untouched(self):
        self.lock_tool("lock", "out/drawing.txt")
        self.assertEqual(self.lock_tool("verify").returncode, 0)

    def test_tamper_fails_verify(self):
        self.lock_tool("lock", "out/drawing.txt")
        self.drawing.write_text("rev B\n", encoding="utf-8")
        result = self.lock_tool("verify")
        self.assertEqual(result.returncode, 2)
        self.assertIn("CHANGED out/drawing.txt", result.stdout)

    def test_deleted_locked_file_fails_verify(self):
        self.lock_tool("lock", "out/drawing.txt")
        self.drawing.unlink()
        self.assertEqual(self.lock_tool("verify").returncode, 2)

    def test_forged_lock_hash_fails_verify(self):
        self.lock_tool("lock", "out/drawing.txt")
        (self.repo / "VERIFIED.lock").write_text(json.dumps({"out/drawing.txt": "0" * 64}), encoding="utf-8")
        self.assertEqual(self.lock_tool("verify").returncode, 2)

    def test_unlock_without_token_is_refused(self):
        self.lock_tool("lock", "out/drawing.txt")
        result = self.lock_tool("unlock", "out/drawing.txt")
        self.assertEqual(result.returncode, 2)
        self.assertIn("REFUSED", result.stderr)
        self.assertIn("out/drawing.txt", self.locked())

    def test_unlock_with_wrong_token_is_refused(self):
        self.lock_tool("lock", "out/drawing.txt")
        self.assertEqual(self.lock_tool("unlock", "out/drawing.txt", "--confirm", "deadbeef").returncode, 2)
        self.assertIn("out/drawing.txt", self.locked())

    def test_unlock_with_owner_token_removes_entry(self):
        self.lock_tool("lock", "out/drawing.txt")
        token = deliverable_lock.token_for(self.locked()["out/drawing.txt"])
        self.assertEqual(self.lock_tool("unlock", "out/drawing.txt", "--confirm", token).returncode, 0)
        self.assertEqual(self.locked(), {})

    def test_path_outside_repo_is_rejected(self):
        outside = self.tmp / "outside.txt"
        outside.write_text("x", encoding="utf-8")
        self.assertEqual(self.lock_tool("lock", outside).returncode, 1)
        self.assertFalse((self.repo / "VERIFIED.lock").exists())

    def test_traversal_path_is_rejected(self):
        (self.tmp / "secret.txt").write_text("x", encoding="utf-8")
        self.assertEqual(self.lock_tool("lock", "../secret.txt").returncode, 1)

    def test_malformed_lock_file_fails_safe(self):
        (self.repo / "VERIFIED.lock").write_text("[1, 2]", encoding="utf-8")
        self.assertEqual(self.lock_tool("verify").returncode, 2)

    def test_no_lock_file_verifies_ok(self):
        self.assertEqual(self.lock_tool("verify").returncode, 0)
