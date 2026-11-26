"""The three workstation hooks ship in the workstation-core plugin, not in install.ps1.

Decision D-2026-11-26-hooks-in-plugin: memory-link-guard, context-guard and pr-closeout-nudge run from
hooks/hooks.json (Claude Code) and hooks/cursor-hooks.json (Cursor, plus handoff-at-80.py). install.ps1
copies no hook files and writes no hook entries, statusLine, or ~/.cursor/hooks.json.
"""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _commands(groups) -> list[str]:
    out = []
    for g in groups or []:
        if "hooks" in g:
            out.extend(h.get("command", "") for h in g["hooks"])
        else:
            out.append(g.get("command", ""))
    return out


class Check(unittest.TestCase):
    def setUp(self):
        self.claude = json.loads((ROOT / "hooks" / "hooks.json").read_text(encoding="utf-8"))["hooks"]
        self.cursor = json.loads((ROOT / "hooks" / "cursor-hooks.json").read_text(encoding="utf-8"))["hooks"]

    def _has(self, hooks, event, script, *bits):
        cmds = [c for c in _commands(hooks.get(event)) if script in c]
        self.assertEqual(len(cmds), 1, f"{event} should run {script} once: {cmds}")
        for b in bits:
            self.assertIn(b, cmds[0])
        return cmds[0]

    def test_claude_plugin_hooks(self):
        for event in ("SessionStart", "PreToolUse"):
            self._has(self.claude, event, "memory/hooks/memory-link-guard.ps1", "-FromPlugin", "${CLAUDE_PLUGIN_ROOT}", "run-ps.sh")
        self._has(self.claude, "Stop", "handoff/claude/context-guard.ps1", "-Mode stop", "-FromPlugin")
        self._has(self.claude, "PreCompact", "handoff/claude/context-guard.ps1", "-Mode precompact", "-FromPlugin")
        self._has(self.claude, "PostToolUse", "handoff/claude/pr-closeout-nudge.ps1", "-FromPlugin")
        guard_group = [g for g in self.claude["PreToolUse"] if any("memory-link-guard" in h["command"] for h in g["hooks"])]
        self.assertEqual(guard_group[0]["matcher"], "Write|Edit")

    def test_cursor_plugin_hooks(self):
        for event in ("sessionStart", "preToolUse"):
            self._has(self.cursor, event, "memory/hooks/memory-link-guard.ps1", "-FromPlugin", "${CURSOR_PLUGIN_ROOT}")
        self._has(self.cursor, "postToolUse", "handoff/claude/pr-closeout-nudge.ps1", "-FromPlugin")
        for event in ("preCompact", "stop"):
            self._has(self.cursor, event, "handoff/cursor/run-handoff-at-80.ps1", "${CURSOR_PLUGIN_ROOT}")
        self.assertNotIn("context-guard", json.dumps(self.cursor), "context-guard ignores Cursor payloads")

    def test_scripts_exist(self):
        for rel in ("memory/hooks/memory-link-guard.ps1", "handoff/claude/context-guard.ps1",
                    "handoff/claude/pr-closeout-nudge.ps1", "handoff/cursor/handoff-at-80.py",
                    "handoff/cursor/run-handoff-at-80.ps1"):
            self.assertTrue((ROOT / rel).is_file(), rel)

    def test_install_writes_no_hooks(self):
        text = (ROOT / "install.ps1").read_text(encoding="utf-8")
        for gone in ("Copy-HomeFile", "Merge-HookCommand", "$GuardDest", "$CtxDest", "$NudgeDest",
                     "$CursorHooksJson", "$ArmedPath", "statusLine = ", "hooks.SessionStart +="):
            self.assertNotIn(gone, text, gone)


if __name__ == "__main__":
    unittest.main()
