"""hooks/run-ps.sh: powershell, else pwsh, else a silent exit 0 (Linux containers, WSL)."""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "hooks" / "run-ps.sh"


def _find_sh():
    found = shutil.which("sh")
    if found:
        return found
    for candidate in (
        r"C:\Program Files\Git\usr\bin\sh.exe",
        r"C:\Program Files\Git\bin\sh.exe",
    ):
        if Path(candidate).is_file():
            return candidate
    return None


SH = _find_sh()
needs_sh = pytest.mark.skipif(SH is None, reason="no sh on this machine")


def _fake_shell(folder: Path, name: str, exit_code: int):
    path = folder / name
    path.write_text(
        f'#!/bin/sh\necho "{name} $*"\nread -r line\necho "$line"\nexit {exit_code}\n',
        encoding="utf-8",
        newline="\n",
    )
    path.chmod(0o755)


def _run(path_dirs, stdin_text="{}"):
    env = {k: v for k, v in os.environ.items() if k.upper() != "PATH"}
    env["PATH"] = os.pathsep.join(str(d) for d in path_dirs)
    return subprocess.run(
        [SH, str(LAUNCHER), "hook.ps1"],
        input=stdin_text,
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )


@needs_sh
def test_no_powershell_on_path_exits_zero_silently(tmp_path):
    empty = tmp_path / "empty"
    empty.mkdir()
    result = _run([empty])
    assert result.returncode == 0
    assert result.stdout == ""
    assert result.stderr == ""


@needs_sh
def test_powershell_is_preferred_and_exit_code_passes_through(tmp_path):
    _fake_shell(tmp_path, "powershell", 2)
    _fake_shell(tmp_path, "pwsh", 0)
    result = _run([tmp_path], '{"x": 1}')
    assert result.returncode == 2
    assert result.stdout.startswith("powershell -NoProfile -ExecutionPolicy Bypass -File hook.ps1")
    assert '{"x": 1}' in result.stdout


@needs_sh
def test_pwsh_is_used_when_powershell_is_missing(tmp_path):
    _fake_shell(tmp_path, "pwsh", 0)
    result = _run([tmp_path])
    assert result.returncode == 0
    assert result.stdout.startswith("pwsh ")


def test_every_claude_hook_command_goes_through_the_launcher():
    data = json.loads((ROOT / "hooks" / "hooks.json").read_text(encoding="utf-8"))
    commands = [
        hook["command"]
        for entries in data["hooks"].values()
        for entry in entries
        for hook in entry["hooks"]
    ]
    assert commands
    for command in commands:
        assert command.startswith('sh "${CLAUDE_PLUGIN_ROOT}/hooks/run-ps.sh" '), command
        assert "powershell" not in command and "pwsh" not in command, command


def test_launcher_has_lf_line_endings():
    assert b"\r\n" not in LAUNCHER.read_bytes()
