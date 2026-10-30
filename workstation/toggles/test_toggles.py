import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

import toggles


def proc(pid, ppid, name, cmd="", mb=10, created="2026-10-23T10:00:00"):
    return {"pid": pid, "ppid": ppid, "name": name, "cmd": cmd, "mem": mb * 1_048_576, "created": created}


class MergeTests(unittest.TestCase):
    def test_local_overrides_hides_and_adds(self):
        package = {"toggles": [{"id": "remote", "name": "Remote", "start": "a"}, {"id": "x", "name": "X"}]}
        local = {"toggles": [{"id": "remote", "name": "Mine", "start": "b"}, {"id": "x", "hidden": True}, {"id": "app"}]}
        rows = toggles.merge(package, local)
        self.assertEqual([r["id"] for r in rows], ["remote", "app"])
        self.assertEqual(rows[0]["start"], "b")
        self.assertEqual(rows[0]["source"], "local")
        self.assertEqual(rows[1]["name"], "app")

    def test_bad_entries_ignored(self):
        self.assertEqual(toggles.merge({"toggles": ["x", {"name": "no id"}]}, {}), [])

    def test_package_file_is_generic(self):
        data = json.loads(toggles.PACKAGE_FILE.read_text(encoding="utf-8"))
        text = json.dumps(data).lower()
        self.assertNotIn("resume", text)
        self.assertNotIn("c:\\\\", text)
        self.assertEqual([t["id"] for t in data["toggles"]], ["remote"])

    def test_expand(self):
        self.assertIn(str(toggles.TOOLKIT), toggles.expand("& '{toolkit}\\x.ps1'"))


class AnalyzeTests(unittest.TestCase):
    def test_counts_owners_without_node_limit(self):
        procs = [proc(1, 0, "claude.exe")] + [proc(10 + i, 1, "node.exe", "node mcp-server-x") for i in range(40)]
        result = toggles.analyze(procs, expected=[])
        self.assertEqual(result["node"]["count"], 40)
        self.assertNotIn("limit", result["node"])
        self.assertEqual(result["node"]["byOwner"]["Claude"]["count"], 40)
        self.assertEqual(result["problems"], [])
        self.assertEqual(result["duplicates"][0]["count"], 40)

    def test_orphan_tree_and_expected(self):
        dc = "cmd.exe /c npx.cmd --yes @wonderwhy-er/desktop-commander@0.3.0 remote"
        procs = [
            proc(100, 999, "cmd.exe", dc),
            proc(101, 100, "node.exe", "node npx-cli.js desktop-commander remote", mb=50),
        ]
        rules = [{"match": r"desktop-commander.*\bremote\b", "max": 1}]
        result = toggles.analyze(procs, expected=rules)
        self.assertEqual(len(result["orphans"]), 1)
        self.assertEqual(result["orphans"][0]["processes"], 2)
        self.assertTrue(result["orphans"][0]["expected"])
        self.assertEqual(result["problems"], [])
        procs.append(proc(200, 998, "node.exe", "node C:/x/desktop-commander/dist/index.js remote"))
        result = toggles.analyze(procs, expected=rules)
        self.assertEqual(len(result["problems"]), 1)
        self.assertIn("2 copies", result["orphans"][0]["note"])

    def test_reused_parent_pid_is_orphan(self):
        procs = [proc(5, 0, "explorer.exe", created="2026-10-23T12:00:00"), proc(6, 5, "node.exe", "node a.js", created="2026-10-23T09:00:00")]
        result = toggles.analyze(procs, expected=[])
        self.assertEqual([o["pid"] for o in result["orphans"]], [6])

    def test_live_parent_not_orphan(self):
        procs = [proc(5, 0, "cursor.exe"), proc(6, 5, "node.exe", "node a.js")]
        self.assertEqual(toggles.analyze(procs, expected=[])["orphans"], [])

    def test_explicit_expected_list_replaces_defaults(self):
        cmd = r"node C:\npm\node_modules\kapture-mcp\dist\index.js"
        result = toggles.analyze([proc(50, 999, "node.exe", cmd)], expected=[])
        self.assertFalse(result["orphans"][0]["expected"])
        self.assertTrue(result["problems"])

    def test_kapture_mcp_one_copy_expected(self):
        cmd = r"node C:\npm\node_modules\kapture-mcp\dist\index.js"
        result = toggles.analyze([proc(50, 999, "node.exe", cmd, mb=30)])
        self.assertEqual(len(result["orphans"]), 1)
        self.assertTrue(result["orphans"][0]["expected"])
        self.assertEqual(result["orphans"][0]["label"], "Kapture MCP")
        self.assertEqual(result["problems"], [])

    def test_kapture_mcp_two_copies_flagged(self):
        cmd = r"node C:\npm\node_modules\kapture-mcp\dist\index.js"
        procs = [proc(50, 999, "node.exe", cmd), proc(51, 998, "node.exe", cmd)]
        result = toggles.analyze(procs)
        self.assertEqual(len(result["problems"]), 1)
        self.assertFalse(result["orphans"][0]["expected"])
        self.assertIn("2 copies", result["orphans"][0]["note"])

    def test_claude_p_background_job_is_not_orphaned(self):
        now = datetime(2026, 10, 30, 12, 0, tzinfo=timezone.utc)
        created = "2026-10-30T11:00:00+00:00"
        procs = [
            proc(
                10,
                999,
                "node.exe",
                r"node C:\npm\node_modules\@anthropic-ai\claude-code\cli.js -p do the thing",
                created=created,
            ),
            proc(11, 10, "node.exe", "node mcp-server-x", created=created),
        ]
        result = toggles.analyze(procs, expected=[], now=now)
        self.assertEqual(len(result["orphans"]), 1)
        self.assertEqual(result["orphans"][0]["kind"], "background-job")
        self.assertEqual(result["orphans"][0]["label"], "background job running")
        self.assertTrue(result["orphans"][0]["expected"])
        self.assertEqual(result["problems"], [])

    def test_claude_p_cmd_launcher_tree_and_print_flag(self):
        now = datetime(2026, 10, 30, 12, 0, tzinfo=timezone.utc)
        created = "2026-10-30T11:30:00+00:00"
        procs = [
            proc(10, 999, "cmd.exe", "cmd.exe /c claude --print rewrite the docs", created=created),
            proc(11, 10, "node.exe", "node cli.js --print rewrite the docs", created=created),
        ]
        result = toggles.analyze(procs, expected=[], now=now)
        self.assertTrue(result["orphans"][0]["expected"])
        self.assertEqual(result["orphans"][0]["label"], "background job running")
        self.assertEqual(result["problems"], [])

    def test_claude_p_background_job_old_is_flagged(self):
        now = datetime(2026, 10, 30, 12, 0, tzinfo=timezone.utc)
        created = "2026-10-30T09:00:00+00:00"
        procs = [proc(10, 999, "node.exe", "claude.cmd -p rewrite the docs", created=created)]
        result = toggles.analyze(procs, expected=[], now=now, background_job_max_age_hours=2)
        self.assertEqual(result["orphans"][0]["kind"], "background-job")
        self.assertFalse(result["orphans"][0]["expected"])
        self.assertIn("running for 3.0 hours", result["orphans"][0]["note"])
        self.assertEqual(len(result["problems"]), 1)
        self.assertIn("background job", result["problems"][0])
        self.assertNotIn("orphaned", result["problems"][0])

    def test_claude_p_age_limit_is_configurable(self):
        now = datetime(2026, 10, 30, 12, 0, tzinfo=timezone.utc)
        created = "2026-10-30T09:00:00+00:00"
        procs = [proc(10, 999, "node.exe", "claude -p still going", created=created)]
        ok = toggles.analyze(procs, expected=[], now=now, background_job_max_age_hours=4)
        self.assertTrue(ok["orphans"][0]["expected"])
        self.assertEqual(ok["problems"], [])
        bad = toggles.analyze(procs, expected=[], now=now, background_job_max_age_hours=2)
        self.assertFalse(bad["orphans"][0]["expected"])

    def test_desktop_commander_per_claude_session_not_duplicate(self):
        dc = r"node C:\x\node_modules\@wonderwhy-er\desktop-commander\dist\index.js"
        procs = [
            proc(1, 0, "claude.exe", "claude.exe"),
            proc(2, 0, "claude.exe", "claude.exe"),
            proc(11, 1, "node.exe", dc),
            proc(12, 2, "node.exe", dc),
        ]
        result = toggles.analyze(procs, expected=[])
        self.assertEqual(result["duplicates"], [])
        self.assertEqual(result["problems"], [])

    def test_desktop_commander_same_claude_session_is_duplicate(self):
        dc = r"node C:\x\node_modules\@wonderwhy-er\desktop-commander\dist\index.js"
        procs = [
            proc(1, 0, "claude.exe", "claude.exe"),
            proc(11, 1, "node.exe", dc),
            proc(12, 1, "node.exe", dc),
        ]
        result = toggles.analyze(procs, expected=[])
        self.assertEqual(len(result["duplicates"]), 1)
        self.assertEqual(result["duplicates"][0]["count"], 2)
        self.assertEqual(result["duplicates"][0]["pids"], [11, 12])

    def test_other_mcp_still_duplicate_across_claude_windows(self):
        cmd = r"node C:\x\node_modules\@upstash\context7-mcp\dist\index.js"
        procs = [
            proc(1, 0, "claude.exe"),
            proc(2, 0, "claude.exe"),
            proc(11, 1, "node.exe", cmd),
            proc(12, 2, "node.exe", cmd),
        ]
        result = toggles.analyze(procs, expected=[])
        self.assertEqual(result["duplicates"][0]["count"], 2)


class SettingsTests(unittest.TestCase):
    def test_local_settings(self):
        with tempfile.TemporaryDirectory() as tmp:
            old = toggles.local_file
            path = Path(tmp) / "toggles.json"
            path.write_text(json.dumps({"processCheck": {"maxNode": 3, "expected": [{"match": "pnpm dev:"}]}}), encoding="utf-8")
            toggles.local_file = lambda: path
            try:
                conf = toggles.settings()
            finally:
                toggles.local_file = old
        self.assertNotIn("maxNode", conf)
        self.assertEqual(conf["expected"][-1]["match"], "pnpm dev:")
        self.assertTrue(any("kapture-mcp" in str(e.get("match")) for e in conf["expected"]))
        self.assertTrue(any("desktop-commander" in str(e.get("match")) for e in conf["expected"]))
        self.assertEqual(conf["backgroundJobMaxAgeHours"], 2)

    def test_local_background_job_age_override(self):
        with tempfile.TemporaryDirectory() as tmp:
            old = toggles.local_file
            path = Path(tmp) / "toggles.json"
            path.write_text(json.dumps({"processCheck": {"backgroundJobMaxAgeHours": 4, "expected": []}}), encoding="utf-8")
            toggles.local_file = lambda: path
            try:
                conf = toggles.settings()
            finally:
                toggles.local_file = old
        self.assertEqual(conf["backgroundJobMaxAgeHours"], 4)
        self.assertEqual(conf["expected"], toggles.EXPECTED_ORPHANS)


if __name__ == "__main__":
    unittest.main()


class RunPsTests(unittest.TestCase):
    """Toggle commands start background programs that inherit handles; run_ps must not wait on pipes."""

    def test_no_pipes_no_stdin_noninteractive(self):
        import subprocess
        from unittest import mock

        seen = {}

        def fake_run(args, **kw):
            seen["args"], seen["kw"] = args, kw
            kw["stdout"].write(b"started\n")
            return subprocess.CompletedProcess(args, 0)

        with mock.patch.object(toggles.subprocess, "run", side_effect=fake_run):
            code, text = toggles.run_ps("& 'x.ps1' -Action start")
        self.assertEqual((code, text), (0, "started"))
        self.assertIn("-NonInteractive", seen["args"])
        self.assertIs(seen["kw"]["stdin"], subprocess.DEVNULL)
        self.assertNotIn("capture_output", seen["kw"])
        self.assertNotEqual(seen["kw"]["stdout"], subprocess.PIPE)

    def test_toggle_scripts_never_prompt(self):
        text = (toggles.HERE / "remote.ps1").read_text(encoding="utf-8")
        for name in ("start-dc-remote.ps1", "stop-dc-remote.ps1", "workers-start.ps1", "workers-stop.ps1"):
            line = next(ln for ln in text.splitlines() if name in ln and ln.strip().startswith("&"))
            self.assertIn("-NoPause", line, name)
