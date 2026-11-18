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

    def lock_file(self):
        return json.loads((self.repo / "VERIFIED.lock").read_text(encoding="utf-8"))

    def locked(self):
        data = self.lock_file()
        data.pop("_history", None)
        return data

    def history(self):
        return self.lock_file().get("_history", [])

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

    def test_crlf_checkout_of_text_file_still_verifies(self):
        self.drawing.write_bytes(b"rev A\nline 2\n")
        self.lock_tool("lock", "out/drawing.txt")
        self.drawing.write_bytes(b"rev A\r\nline 2\r\n")
        self.assertEqual(self.lock_tool("verify").returncode, 0)

    def test_crlf_text_locked_then_lf_checkout_verifies(self):
        self.drawing.write_bytes(b"rev A\r\n")
        self.lock_tool("lock", "out/drawing.txt")
        self.drawing.write_bytes(b"rev A\n")
        self.assertEqual(self.lock_tool("verify").returncode, 0)

    def test_text_content_change_still_fails_after_normalising(self):
        self.drawing.write_bytes(b"rev A\r\n")
        self.lock_tool("lock", "out/drawing.txt")
        self.drawing.write_bytes(b"rev B\n")
        self.assertEqual(self.lock_tool("verify").returncode, 2)

    def test_binary_file_is_hashed_raw(self):
        binary = commit_file(self.repo, "out/model.bin", "x")
        binary.write_bytes(b"\x00\x01\r\n\x02")
        self.lock_tool("lock", "out/model.bin")
        binary.write_bytes(b"\x00\x01\n\x02")
        self.assertEqual(self.lock_tool("verify").returncode, 2)

    def test_deleted_locked_file_fails_verify(self):
        self.lock_tool("lock", "out/drawing.txt")
        self.drawing.unlink()
        self.assertEqual(self.lock_tool("verify").returncode, 2)

    def test_forged_lock_hash_fails_verify(self):
        self.lock_tool("lock", "out/drawing.txt")
        (self.repo / "VERIFIED.lock").write_text(json.dumps({"out/drawing.txt": "0" * 64}), encoding="utf-8")
        self.assertEqual(self.lock_tool("verify").returncode, 2)

    def test_lock_and_verify_never_print_the_hash(self):
        lock_result = self.lock_tool("lock", "out/drawing.txt")
        recorded = self.locked()["out/drawing.txt"]
        self.drawing.write_text("rev B\n", encoding="utf-8")
        verify_result = self.lock_tool("verify")
        for result in (lock_result, verify_result):
            self.assertNotIn(recorded[:8], result.stdout + result.stderr)

    def test_unlock_without_owner_phrase_is_refused(self):
        self.lock_tool("lock", "out/drawing.txt")
        result = self.lock_tool("unlock", "out/drawing.txt")
        self.assertEqual(result.returncode, 2)
        self.assertIn("REFUSED", result.stderr)
        self.assertIn("out/drawing.txt", self.locked())

    def test_unlock_with_blank_owner_phrase_is_refused(self):
        self.lock_tool("lock", "out/drawing.txt")
        self.assertEqual(self.lock_tool("unlock", "out/drawing.txt", "--owner-phrase", "   ").returncode, 2)
        self.assertIn("out/drawing.txt", self.locked())

    def test_old_confirm_token_flag_is_rejected(self):
        self.lock_tool("lock", "out/drawing.txt")
        token = self.locked()["out/drawing.txt"][:8]
        self.assertNotEqual(self.lock_tool("unlock", "out/drawing.txt", "--confirm", token).returncode, 0)
        self.assertIn("out/drawing.txt", self.locked())

    def test_unlock_with_owner_phrase_removes_entry_and_logs_it(self):
        self.lock_tool("lock", "out/drawing.txt")
        phrase = "yes, unlock the drawing for rev B"
        self.assertEqual(self.lock_tool("unlock", "out/drawing.txt", "--owner-phrase", phrase).returncode, 0)
        self.assertEqual(self.locked(), {})
        unlocks = [entry for entry in self.history() if entry["action"] == "unlock"]
        self.assertEqual(len(unlocks), 1)
        self.assertEqual(unlocks[0]["path"], "out/drawing.txt")
        self.assertEqual(unlocks[0]["owner_phrase"], phrase)
        self.assertRegex(unlocks[0]["date"], r"^\d{4}-\d{2}-\d{2}T")

    def test_history_survives_relock_and_verify(self):
        self.lock_tool("lock", "out/drawing.txt")
        self.lock_tool("unlock", "out/drawing.txt", "--owner-phrase", "ok")
        self.lock_tool("lock", "out/drawing.txt")
        self.assertEqual(self.lock_tool("verify").returncode, 0)
        self.assertGreater(len(self.history()), 2)

    def test_relock_of_changed_file_is_refused_and_keeps_old_hash(self):
        self.lock_tool("lock", "out/drawing.txt")
        recorded = self.locked()["out/drawing.txt"]
        self.drawing.write_text("rev B\n", encoding="utf-8")
        result = self.lock_tool("lock", "out/drawing.txt")
        self.assertEqual(result.returncode, 2)
        self.assertIn("REFUSED", result.stderr)
        self.assertEqual(self.locked()["out/drawing.txt"], recorded)
        self.assertEqual(self.lock_tool("verify").returncode, 2)

    def test_relock_after_owner_unlock_takes_new_hash(self):
        self.lock_tool("lock", "out/drawing.txt")
        recorded = self.locked()["out/drawing.txt"]
        self.drawing.write_text("rev B\n", encoding="utf-8")
        self.lock_tool("unlock", "out/drawing.txt", "--owner-phrase", "unlock the drawing")
        self.assertEqual(self.lock_tool("lock", "out/drawing.txt").returncode, 0)
        self.assertNotEqual(self.locked()["out/drawing.txt"], recorded)
        self.assertEqual(self.lock_tool("verify").returncode, 0)

    def test_relock_of_unchanged_file_is_ok(self):
        self.lock_tool("lock", "out/drawing.txt")
        self.assertEqual(self.lock_tool("lock", "out/drawing.txt").returncode, 0)

    def test_history_key_is_not_lockable(self):
        commit_file(self.repo, "_history", "x\n")
        self.assertEqual(self.lock_tool("lock", "_history").returncode, 1)

    def test_malformed_history_fails_safe(self):
        (self.repo / "VERIFIED.lock").write_text(json.dumps({"_history": "nope"}), encoding="utf-8")
        self.assertEqual(self.lock_tool("verify").returncode, 2)

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
