import json
import tempfile
import unittest
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
    def test_counts_owners_and_limit(self):
        procs = [proc(1, 0, "claude.exe")] + [proc(10 + i, 1, "node.exe", "node mcp-server-x") for i in range(4)]
        result = toggles.analyze(procs, max_node=3, expected=[])
        self.assertEqual(result["node"]["count"], 4)
        self.assertEqual(result["node"]["byOwner"]["Claude"]["count"], 4)
        self.assertTrue(any("node processes" in p for p in result["problems"]))
        self.assertEqual(result["duplicates"][0]["count"], 4)

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
        self.assertEqual(conf["maxNode"], 3)
        self.assertEqual(conf["expected"][-1]["match"], "pnpm dev:")


if __name__ == "__main__":
    unittest.main()
