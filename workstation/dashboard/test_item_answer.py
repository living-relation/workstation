"""Feature 2: answer a Waiting row from the card -> branch + PR in that project's repo (never merged)."""

import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import actions  # noqa: E402
import collect  # noqa: E402
import server  # noqa: E402

TRACKER = """# Open items

## Needs Dan

| ID | Topic | Question | Options | Recommended |
|---|---|---|---|---|
| N1 | Drawings | Approve the drawing set? | A) yes; B) no | A |

## Needs approval

- Ok to order the crimp tool?
"""

PHONE = {"X-Forwarded-For": "100.64.0.9", "Host": "pc.example.ts.net", "Authorization": "Bearer secret"}


class RowEdits(unittest.TestCase):
    def test_table_row_answer_goes_in_last_cell(self) -> None:
        row = "| N1 | Drawings | Approve the drawing set? | A) yes; B) no | A |"
        out = actions.answer_row(row, "Dan", "2026-10-27", "Yes")
        self.assertEqual(out, "| N1 | Drawings | Approve the drawing set? | A) yes; B) no | A — **Dan 2026-10-27:** Yes |")
        self.assertEqual(out.count("|"), row.count("|"))  # table shape unchanged

    def test_empty_last_cell(self) -> None:
        self.assertEqual(actions.answer_row("| N2 | Q? | |", "Dan", "2026-10-27", "No"), "| N2 | Q? | **Dan 2026-10-27:** No |")

    def test_bullet_answer_appended(self) -> None:
        out = actions.answer_row("- Ok to order the crimp tool?", "Dan", "2026-10-27", "No, wait")
        self.assertEqual(out, "- Ok to order the crimp tool? — **Dan 2026-10-27:** No, wait")

    def test_answer_cleaned(self) -> None:
        self.assertEqual(actions.clean_answer("  a | b\n c  "), "a / b c")
        self.assertEqual(len(actions.clean_answer("x" * 2000)), actions.ANSWER_LIMIT)

    def test_find_row_by_fingerprint_after_lines_move(self) -> None:
        fp = collect.parse_tracker(TRACKER)["prompts"][0]["fp"]
        moved = "\n\nNew intro line\n" + TRACKER
        line = actions.find_row(moved, fp)
        self.assertIn("| N1 |", moved.split("\n")[line - 1])
        self.assertIsNone(actions.find_row(TRACKER.replace("Approve the drawing set?", "Approve it?"), fp))


class Settings(unittest.TestCase):
    def test_write_actions_off_unless_settings_say_true(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(collect, "state_dir", return_value=Path(tmp)):
            self.assertFalse(actions.can_write())
            (Path(tmp) / "settings.json").write_text('{"writeActions": "yes"}', encoding="utf-8")
            self.assertFalse(actions.can_write())  # only a real true counts
            (Path(tmp) / "settings.json").write_text('{"writeActions": true, "ownerName": "Dan<script>"}', encoding="utf-8")
            self.assertTrue(actions.can_write())
            self.assertEqual(actions.owner_name(), "Danscript")


class RecordAnswer(unittest.TestCase):
    """record_answer with git/gh faked: clone -> edit row -> branch -> commit -> push -> PR, then clone deleted."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.state = root / "state"
        self.state.mkdir()
        self.active = root / "active"
        self.project = self.active / "demo"
        (self.project / "docs").mkdir(parents=True)
        (self.project / "docs" / "OPEN-ITEMS.md").write_text(TRACKER, encoding="utf-8")
        self.fp = collect.parse_tracker(TRACKER)["prompts"][0]["fp"]
        self.calls: list[list[str]] = []
        self.patches = [
            mock.patch.object(collect, "state_dir", return_value=self.state),
            mock.patch.object(collect, "load_roots", return_value={"active": str(self.active)}),
            mock.patch.object(collect, "_github_slug", return_value="owner/demo"),
            mock.patch.object(collect, "_git", return_value=(1, "")),
            mock.patch.object(actions, "_run", side_effect=self.fake_run),
        ]
        for p in self.patches:
            p.start()
        (self.state / "settings.json").write_text('{"writeActions": true, "ownerName": "Dan"}', encoding="utf-8")

    def tearDown(self) -> None:
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def fake_run(self, args, cwd=None, timeout=180):
        self.calls.append(args)
        if args[:2] == ["git", "clone"]:
            dest = Path(args[-1])
            (dest / "docs").mkdir(parents=True)
            (dest / ".git" / "hooks").mkdir(parents=True)
            (dest / "docs" / "OPEN-ITEMS.md").write_text(TRACKER, encoding="utf-8")
        if args[:3] == ["git", "-C", args[2]] and "commit" in args:
            self.committed = (Path(args[2]) / "docs" / "OPEN-ITEMS.md").read_text(encoding="utf-8")
        if args[:2] == ["gh", "pr"]:
            return "https://github.com/owner/demo/pull/7"
        return ""

    def test_happy_path(self) -> None:
        result = actions.record_answer("demo", self.fp, "Yes", today="2026-10-27")
        self.assertEqual(result["prUrl"], "https://github.com/owner/demo/pull/7")
        verbs = [" ".join(a[:2]) if a[0] == "gh" else (a[3] if a[1] == "-C" else a[1]) for a in self.calls]
        self.assertEqual(verbs, ["clone", "checkout", "add", "commit", "push", "gh pr"])
        self.assertIn("https://github.com/owner/demo.git", self.calls[0])
        self.assertIn("| A — **Dan 2026-10-27:** Yes |", self.committed)
        self.assertFalse(any(a[:3] == ["gh", "pr", "merge"] or (a[0] == "git" and "merge" in a[:4]) for a in self.calls))
        self.assertTrue(result["branch"].startswith(f"dashboard/answer-{self.fp}-"))
        self.assertEqual(list((self.state / "work").iterdir()), [])  # clone deleted
        self.assertEqual(actions.load_answers()[f"demo|{self.fp}"]["prUrl"], result["prUrl"])
        # The live project checkout is untouched.
        self.assertEqual((self.project / "docs" / "OPEN-ITEMS.md").read_text(encoding="utf-8"), TRACKER)

    def test_stale_row_stops_before_any_commit(self) -> None:
        with self.assertRaises(actions.ActionError):
            actions.record_answer("demo", "0" * 12, "Yes")
        self.assertEqual([a[1] for a in self.calls], ["clone"])
        self.assertEqual(list((self.state / "work").iterdir()), [])

    def test_bad_input_refused_before_git(self) -> None:
        for project, fp, answer in (("demo", self.fp, "  "), ("demo", "not-a-fp", "Yes"), ("..", self.fp, "Yes"), ("nope", self.fp, "Yes")):
            with self.assertRaises(actions.ActionError):
                actions.record_answer(project, fp, answer)
        self.assertEqual(self.calls, [])

    def test_hooks_path_copied_into_clone(self) -> None:
        with mock.patch.object(collect, "_git", return_value=(0, ".githooks")):
            actions.record_answer("demo", self.fp, "Yes")
        self.assertIn(["git", "-C", self.calls[1][2], "config", "core.hooksPath", ".githooks"], self.calls)


class AnswerApi(unittest.TestCase):
    def setUp(self) -> None:
        self.got = []
        self._token = server.read_token
        server.read_token = lambda: "secret"
        self.patches = [
            mock.patch.object(actions, "can_write", return_value=True),
            mock.patch.object(actions, "record_answer", side_effect=self.fake_record),
        ]
        for p in self.patches:
            p.start()
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}/api/item-answer"

    def tearDown(self) -> None:
        self.httpd.shutdown()
        self.httpd.server_close()
        for p in self.patches:
            p.stop()
        server.read_token = self._token

    def fake_record(self, project, fp, answer):
        self.got.append((project, fp, answer))
        return {"prUrl": "https://github.com/owner/demo/pull/7", "branch": "b"}

    def post(self, headers, body=None):
        data = json.dumps(body or {"project": "demo", "fp": "a" * 12, "answer": "Yes"}).encode()
        req = urllib.request.Request(self.url, data=data, method="POST", headers={"Content-Type": "application/json", **headers})
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                return resp.status, json.loads(resp.read())
        except urllib.error.HTTPError as exc:
            return exc.code, json.loads(exc.read() or b"{}")

    def test_phone_with_token_and_header(self) -> None:
        code, data = self.post({**PHONE, "X-Workstation-Dashboard": "1", "Origin": "https://pc.example.ts.net"})
        self.assertEqual((code, data["prUrl"]), (200, "https://github.com/owner/demo/pull/7"))
        self.assertEqual(self.got, [("demo", "a" * 12, "Yes")])
        self.assertNotIn("secret", json.dumps(data))

    def test_no_token_refused(self) -> None:
        code, _ = self.post({k: v for k, v in PHONE.items() if k != "Authorization"} | {"X-Workstation-Dashboard": "1"})
        self.assertEqual(code, 401)
        self.assertEqual(self.got, [])

    def test_missing_header_refused(self) -> None:
        self.assertEqual(self.post(PHONE)[0], 403)
        self.assertEqual(self.got, [])

    def test_cross_origin_refused(self) -> None:
        self.assertEqual(self.post({**PHONE, "X-Workstation-Dashboard": "1", "Origin": "https://evil.example"})[0], 403)
        self.assertEqual(self.got, [])

    def test_write_actions_off_refused(self) -> None:
        with mock.patch.object(actions, "can_write", return_value=False):
            code, data = self.post({**PHONE, "X-Workstation-Dashboard": "1"})
        self.assertEqual(code, 403)
        self.assertIn("off", data["error"])
        self.assertEqual(self.got, [])

    def test_get_is_not_an_action(self) -> None:
        req = urllib.request.Request(self.url, headers=PHONE)
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req, timeout=5)
        self.assertIn(ctx.exception.code, (404, 405))
        self.assertEqual(self.got, [])


class SnapshotFlags(unittest.TestCase):
    def test_with_actions_marks_answered_rows_and_switch(self) -> None:
        data = {"projects": [{"name": "demo", "prompts": [{"fp": "f1"}, {"fp": "f2"}]}]}
        with mock.patch.object(actions, "load_answers", return_value={"demo|f1": {"prUrl": "u"}}), \
                mock.patch.object(actions, "can_write", return_value=False):
            out = server.with_actions(data)
        self.assertFalse(out["canWriteActions"])
        self.assertEqual(out["projects"][0]["prompts"][0]["answerPr"], "u")
        self.assertNotIn("answerPr", out["projects"][0]["prompts"][1])


if __name__ == "__main__":
    unittest.main()
