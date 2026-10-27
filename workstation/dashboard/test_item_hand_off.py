"""Feature 3: the launcher. Hand a tracker row to a new background Claude session in that project's
folder; the dashboard itself never edits the repo."""

import json
import subprocess
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

## Needs approval

- Ok to order the crimp tool?

## Open

| # | Item | Status |
|---|---|---|
| 7 | Pick the connector for the fan relay | Open |
"""

PHONE = {"X-Forwarded-For": "100.64.0.9", "Host": "pc.example.ts.net", "Authorization": "Bearer secret"}


class FakeProc:
    def __init__(self, code=0, hang=False):
        self.code, self.hang = code, hang

    def wait(self, timeout=None):
        if self.hang:
            raise subprocess.TimeoutExpired("claude", timeout)
        return self.code


class Sandbox(unittest.TestCase):
    """A fake projects root with one project, local state in a temp folder, and Popen recorded."""

    proc = FakeProc()

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.state = root / "state"
        self.state.mkdir()
        self.active = root / "active"
        self.project = self.active / "demo"
        (self.project / "docs").mkdir(parents=True)
        (self.project / "docs" / "OPEN-ITEMS.md").write_text(TRACKER, encoding="utf-8")
        parsed = collect.parse_tracker(TRACKER)
        self.prompt_fp = parsed["prompts"][0]["fp"]
        self.task_fp = parsed["tasks"][0]["fp"]
        self.popen = []
        self.patches = [
            mock.patch.object(collect, "state_dir", return_value=self.state),
            mock.patch.object(collect, "load_roots", return_value={"active": str(self.active)}),
            mock.patch.object(actions.shutil, "which", return_value="C:/fake/claude.exe"),
            mock.patch.object(actions.subprocess, "Popen", side_effect=self.fake_popen),
        ]
        for p in self.patches:
            p.start()
        (self.state / "settings.json").write_text('{"writeActions": true, "ownerName": "Dan"}', encoding="utf-8")

    def tearDown(self) -> None:
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def fake_popen(self, args, **kw):
        self.popen.append((args, kw))
        kw["stdout"].write("backgrounded · 3d581936 · dashboard-x\n".encode("utf-8"))  # what `claude --bg` prints
        return self.proc


class Launcher(Sandbox):
    def test_starts_bg_session_in_project_folder(self) -> None:
        result = actions.launch("hand-off", "demo", self.task_fp, "use the Deutsch one", today="2026-10-27")
        (args, kw), = self.popen
        self.assertEqual(args[:2], ["C:/fake/claude.exe", "--bg"])
        self.assertNotIn("--session-id", args)  # --bg ignores it and picks its own id
        self.assertEqual(result["sessionId"], "3d581936")
        self.assertEqual(args[args.index("--name") + 1], "dashboard-hand-off-demo")
        self.assertEqual(Path(kw["cwd"]), self.project)
        self.assertIs(kw["stdin"], subprocess.DEVNULL)
        # Output goes to files, never pipes (PR #40).
        self.assertNotIn(kw["stdout"], (subprocess.PIPE, None))
        self.assertNotIn(kw["stderr"], (subprocess.PIPE, None))
        self.assertEqual(len(list((self.state / "launch").glob("*.out.txt"))), 1)
        prompt = args[-1]
        self.assertIn("7: Pick the connector for the fan relay", prompt)
        self.assertIn("use the Deutsch one", prompt)
        self.assertIn("AGENTS.md", prompt)
        self.assertIn("Never merge", prompt)
        self.assertIn(f"Dashboard item: {self.task_fp}", prompt)
        saved = actions.load_sessions()[f"demo|{self.task_fp}"]
        self.assertEqual((saved["kind"], saved["sessionId"]), ("hand-off", result["sessionId"]))

    def test_item_text_comes_from_disk_not_the_page(self) -> None:
        actions.launch("hand-off", "demo", self.task_fp)
        self.assertNotIn("note:", self.popen[0][0][-1])  # no note given -> no note block
        self.assertIn("Pick the connector", self.popen[0][0][-1])

    def test_repo_is_never_touched(self) -> None:
        before = sorted(p.name for p in self.project.rglob("*"))
        actions.launch("hand-off", "demo", self.task_fp)
        self.assertEqual(sorted(p.name for p in self.project.rglob("*")), before)

    def test_refuses_bad_input_before_launching(self) -> None:
        for kind, project, fp in (("rm", "demo", self.task_fp), ("hand-off", "demo", "nope"),
                                  ("hand-off", "..", self.task_fp), ("hand-off", "missing", self.task_fp),
                                  ("hand-off", "demo", "0" * 12)):
            with self.assertRaises(actions.ActionError):
                actions.launch(kind, project, fp)
        self.assertEqual(self.popen, [])

    def test_no_claude_on_path(self) -> None:
        with mock.patch.object(actions.shutil, "which", return_value=None):
            with self.assertRaises(actions.ActionError):
                actions.launch("hand-off", "demo", self.task_fp)
        self.assertEqual(self.popen, [])


class LauncherSlowOrFailed(Sandbox):
    def test_still_starting_after_wait_is_ok(self) -> None:
        self.proc = FakeProc(hang=True)
        result = actions.launch("hand-off", "demo", self.task_fp)
        self.assertIn(f"demo|{self.task_fp}", actions.load_sessions())
        self.assertTrue(result["sessionId"])

    def test_nonzero_exit_is_an_error_and_not_saved(self) -> None:
        self.proc = FakeProc(code=2)
        with self.assertRaises(actions.ActionError):
            actions.launch("hand-off", "demo", self.task_fp)
        self.assertEqual(actions.load_sessions(), {})


class Settings(unittest.TestCase):
    def test_actions_off_unless_settings_say_true(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(collect, "state_dir", return_value=Path(tmp)):
            self.assertFalse(actions.can_write())
            (Path(tmp) / "settings.json").write_text('{"writeActions": "yes"}', encoding="utf-8")
            self.assertFalse(actions.can_write())  # only a real true counts
            (Path(tmp) / "settings.json").write_text('{"writeActions": true, "ownerName": "Dan<script>"}', encoding="utf-8")
            self.assertTrue(actions.can_write())
            self.assertEqual(actions.owner_name(), "Danscript")


class ActionApi(unittest.TestCase):
    def setUp(self) -> None:
        self.got = []
        self._token = server.read_token
        server.read_token = lambda: "secret"
        self.patches = [
            mock.patch.object(actions, "can_write", return_value=True),
            mock.patch.object(actions, "launch", side_effect=self.fake_launch),
        ]
        for p in self.patches:
            p.start()
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.httpd.server_address[1]}"

    def tearDown(self) -> None:
        self.httpd.shutdown()
        self.httpd.server_close()
        for p in self.patches:
            p.stop()
        server.read_token = self._token

    def fake_launch(self, kind, project, fp, text=""):
        self.got.append((kind, project, fp, text))
        return {"sessionId": "sid", "name": "dashboard-x"}

    def post(self, path, headers, body):
        data = json.dumps(body).encode()
        req = urllib.request.Request(self.base + path, data=data, method="POST",
                                     headers={"Content-Type": "application/json", **headers})
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                return resp.status, json.loads(resp.read())
        except urllib.error.HTTPError as exc:
            return exc.code, json.loads(exc.read() or b"{}")

    def test_hand_off_and_answer_routes(self) -> None:
        ok = {**PHONE, "X-Workstation-Dashboard": "1", "Origin": "https://pc.example.ts.net"}
        self.assertEqual(self.post("/api/item-hand-off", ok, {"project": "demo", "fp": "a" * 12, "note": "n"})[0], 200)
        code, data = self.post("/api/item-answer", ok, {"project": "demo", "fp": "b" * 12, "answer": "Yes"})
        self.assertEqual((code, data["sessionId"]), (200, "sid"))
        self.assertEqual(self.got, [("hand-off", "demo", "a" * 12, "n"), ("answer", "demo", "b" * 12, "Yes")])
        self.assertNotIn("secret", json.dumps(data))

    def test_refusals(self) -> None:
        body = {"project": "demo", "fp": "a" * 12}
        no_token = {k: v for k, v in PHONE.items() if k != "Authorization"} | {"X-Workstation-Dashboard": "1"}
        self.assertEqual(self.post("/api/item-hand-off", no_token, body)[0], 401)
        self.assertEqual(self.post("/api/item-hand-off", PHONE, body)[0], 403)  # no CSRF header
        self.assertEqual(self.post("/api/item-hand-off", {**PHONE, "X-Workstation-Dashboard": "1",
                                                          "Origin": "https://evil.example"}, body)[0], 403)
        with mock.patch.object(actions, "can_write", return_value=False):
            code, data = self.post("/api/item-hand-off", {**PHONE, "X-Workstation-Dashboard": "1"}, body)
        self.assertEqual(code, 403)
        self.assertIn("off", data["error"])
        self.assertEqual(self.got, [])

    def test_launch_error_is_409(self) -> None:
        with mock.patch.object(actions, "launch", side_effect=actions.ActionError("that row changed")):
            code, data = self.post("/api/item-hand-off", {**PHONE, "X-Workstation-Dashboard": "1"}, {"project": "demo", "fp": "a" * 12})
        self.assertEqual((code, data["error"]), (409, "that row changed"))

    def test_get_is_not_an_action(self) -> None:
        req = urllib.request.Request(self.base + "/api/item-hand-off", headers=PHONE)
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req, timeout=5)
        self.assertIn(ctx.exception.code, (404, 405))
        self.assertEqual(self.got, [])


class SnapshotFlags(unittest.TestCase):
    def test_session_and_pr_attached_to_items(self) -> None:
        data = {"projects": [{"name": "demo",
                              "prs": [{"url": "https://github.com/o/demo/pull/9", "items": ["f1"]}],
                              "tasks": [{"fp": "f1"}, {"fp": "f2"}, {"fp": "f3"}]}]}
        sessions = {"demo|f1": {"kind": "hand-off", "name": "n", "startedAt": "t", "sessionId": "hidden"},
                    "demo|f2": {"kind": "answer", "name": "n2", "startedAt": "t2", "sessionId": "x"}}
        with mock.patch.object(actions, "load_sessions", return_value=sessions), \
                mock.patch.object(actions, "can_write", return_value=False):
            out = server.with_actions(data)
        t1, t2, t3 = out["projects"][0]["tasks"]
        self.assertFalse(out["canWriteActions"])
        self.assertEqual(t1["sessionPr"], "https://github.com/o/demo/pull/9")
        self.assertEqual(t1["session"], {"kind": "hand-off", "name": "n", "startedAt": "t"})
        self.assertNotIn("sessionPr", t2)
        self.assertEqual(t2["session"]["kind"], "answer")
        self.assertNotIn("session", t3)

    def test_session_id_parsed(self) -> None:
        self.assertEqual(actions.session_id("backgrounded · 3d581936 · dashboard-x\n  claude agents"), "3d581936")
        self.assertIsNone(actions.session_id(""))

    def test_pr_body_mark(self) -> None:
        self.assertEqual(collect.dashboard_items("x\nDashboard item: `0123456789ab`\nDashboard item: fedcba987654"),
                         ["0123456789ab", "fedcba987654"])
        self.assertEqual(collect.dashboard_items("Dashboard item: short"), [])


if __name__ == "__main__":
    unittest.main()
