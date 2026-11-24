"""hooks/run-ps.sh: powershell, else pwsh, else the Python fallback or a once-per-session loud fail."""
import json
import os
import shutil
import sys
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


def _run(path_dirs, stdin_text="{}", script="hook.ps1", tmpdir=None, extra_env=None):
    env = {k: v for k, v in os.environ.items() if k.upper() not in ("PATH", "TMPDIR")}
    env["PATH"] = os.pathsep.join(str(d) for d in path_dirs)
    if tmpdir is not None:
        env["TMPDIR"] = str(tmpdir)
    env.pop("WORKSTATION_PROJECTS_ROOT", None)
    env.pop("WORKSTATION_INJECT_FAIL", None)
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        [SH, str(LAUNCHER), script],
        input=stdin_text,
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )


def _loud_fail(stdout):
    data = json.loads(stdout)
    line = data["systemMessage"]
    assert line.startswith("WORKSTATION RULES NOT LOADED:")
    assert "PowerShell is not on PATH" in line
    spec = data["hookSpecificOutput"]
    assert spec["additionalContext"] == f"Open your reply with this exact line: {line}"
    return data, spec


RULES = str(ROOT / "hooks" / "rules-inject.ps1")
STATE = str(ROOT / "hooks" / "state-inject.ps1")
SUBAGENT = str(ROOT / "hooks" / "subagent-rules.ps1")


def _empty(tmp_path):
    empty = tmp_path / "empty"
    empty.mkdir(exist_ok=True)
    return empty


def _python_only(tmp_path):
    """A PATH folder with python3 (a wrapper around this interpreter) and nothing else."""
    folder = tmp_path / "pyonly"
    folder.mkdir(exist_ok=True)
    wrapper = folder / "python3"
    wrapper.write_text(f'#!/bin/sh\nexec "{sys.executable}" "$@"\n', encoding="utf-8", newline="\n")
    wrapper.chmod(0o755)
    return folder


needs_posix = pytest.mark.skipif(os.name == "nt", reason="python3 wrapper needs a POSIX shell")


@needs_sh
def test_no_powershell_on_path_is_a_loud_fail(tmp_path):
    empty = _empty(tmp_path)
    result = _run([empty], '{"hook_event_name": "SessionStart"}', script=RULES, tmpdir=tmp_path)
    assert result.returncode == 0
    assert result.stderr == ""
    data, spec = _loud_fail(result.stdout)
    assert spec["hookEventName"] == "SessionStart"
    assert "additional_context" not in data


@needs_sh
def test_no_powershell_copies_the_hook_event_name(tmp_path):
    empty = tmp_path / "empty"
    empty.mkdir()
    result = _run([empty], '{"hook_event_name":"SubagentStart","agent_type":"Explore"}', script=SUBAGENT, tmpdir=tmp_path)
    assert result.returncode == 0
    _, spec = _loud_fail(result.stdout)
    assert spec["hookEventName"] == "SubagentStart"


@needs_sh
def test_no_powershell_defaults_the_event_when_stdin_has_none(tmp_path):
    empty = tmp_path / "empty"
    empty.mkdir()
    result = _run([empty], "{}", script=RULES, tmpdir=tmp_path)
    assert result.returncode == 0
    _, spec = _loud_fail(result.stdout)
    assert spec["hookEventName"] == "SessionStart"


def test_loud_fail_phrase_matches_the_powershell_helper():
    phrase = "WORKSTATION RULES NOT LOADED:"
    tell = "Open your reply with this exact line:"
    sh = LAUNCHER.read_text(encoding="utf-8")
    ps = (ROOT / "hooks" / "state-common.ps1").read_text(encoding="utf-8")
    assert phrase in sh and phrase in ps
    assert tell in sh and tell in ps


def test_subagent_rules_hook_is_claude_only():
    data = json.loads((ROOT / "hooks" / "hooks.json").read_text(encoding="utf-8"))
    commands = [
        hook["command"]
        for entry in data["hooks"]["SubagentStart"]
        for hook in entry["hooks"]
    ]
    assert len(commands) == 1
    assert commands[0].startswith('sh "${CLAUDE_PLUGIN_ROOT}/hooks/run-ps.sh" ')
    assert "subagent-rules.ps1" in commands[0]
    cursor = (ROOT / "hooks" / "cursor-hooks.json").read_text(encoding="utf-8")
    assert "subagentStart" not in cursor
    assert "subagent-rules.ps1" not in cursor
    paste = "If you don't see a 'rules-inject:' header at the start, say so first."
    for name in ("instructions-for-claude.md", "cowork-global-instructions.md"):
        text = (ROOT / "instructions" / name).read_text(encoding="utf-8")
        assert paste in text


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


STOP_LIKE = ["Stop", "SubagentStop", "PreToolUse", "PostToolUse", "PreCompact", "UserPromptSubmit", "Notification", "SessionEnd"]


@needs_sh
@pytest.mark.parametrize("event", STOP_LIKE)
def test_no_powershell_other_events_print_nothing(tmp_path, event):
    """Stop output is fed back after every reply; without PowerShell these events must stay silent."""
    empty = _empty(tmp_path)
    for script in (RULES, STATE, SUBAGENT, str(ROOT / "hooks" / "state-lint-stop.ps1"),
                   str(ROOT / "hooks" / "projects-root-report.ps1"), str(ROOT / "hooks" / "projects-root-guard.ps1")):
        payload = json.dumps({"session_id": "s-1", "hook_event_name": event})
        for _ in range(3):
            result = _run([empty], payload, script=script, tmpdir=tmp_path)
            assert result.returncode == 0
            assert result.stdout == ""
            assert result.stderr == ""
    assert not list(tmp_path.glob("workstation-rules-warned-*"))


@needs_sh
def test_repeated_stop_calls_never_block_or_add_context(tmp_path):
    empty = _empty(tmp_path)
    data = json.loads((ROOT / "hooks" / "hooks.json").read_text(encoding="utf-8"))
    scripts = [
        hook["command"].split('"${CLAUDE_PLUGIN_ROOT}/hooks/')[-1].rstrip('"')
        for entry in data["hooks"]["Stop"]
        for hook in entry["hooks"]
    ]
    assert scripts
    for _ in range(5):
        for name in scripts:
            result = _run([empty], '{"session_id":"loop","hook_event_name":"Stop","stop_hook_active":true}',
                          script=str(ROOT / "hooks" / name), tmpdir=tmp_path)
            assert result.returncode == 0
            assert result.stdout == ""


@needs_sh
def test_no_powershell_warning_prints_once_per_session(tmp_path):
    empty = _empty(tmp_path)
    payload = '{"session_id":"abc-123","hook_event_name":"SessionStart"}'
    first = _run([empty], payload, script=RULES, tmpdir=tmp_path)
    _loud_fail(first.stdout)
    assert (tmp_path / "workstation-rules-warned-abc-123-SessionStart").is_file()
    for script in (RULES, STATE):
        again = _run([empty], payload, script=script, tmpdir=tmp_path)
        assert again.returncode == 0
        assert again.stdout == ""
    other = _run([empty], '{"session_id":"other","hook_event_name":"SessionStart"}', script=RULES, tmpdir=tmp_path)
    _loud_fail(other.stdout)
    sub = _run([empty], '{"session_id":"abc-123","hook_event_name":"SubagentStart"}', script=SUBAGENT, tmpdir=tmp_path)
    _, spec = _loud_fail(sub.stdout)
    assert spec["hookEventName"] == "SubagentStart"
    sub2 = _run([empty], '{"session_id":"abc-123","hook_event_name":"SubagentStart"}', script=SUBAGENT, tmpdir=tmp_path)
    assert sub2.stdout == ""


@needs_sh
def test_unsafe_session_id_is_not_used_as_a_path(tmp_path):
    empty = _empty(tmp_path)
    payload = '{"session_id":"../../x","hook_event_name":"SessionStart"}'
    first = _run([empty], payload, script=RULES, tmpdir=tmp_path)
    _loud_fail(first.stdout)
    assert not list(tmp_path.glob("workstation-rules-warned-*"))


@needs_sh
def test_no_powershell_scripts_without_a_fallback_stay_silent(tmp_path):
    empty = _empty(tmp_path)
    for name in ("agents-md-only-warn.ps1", "hook.ps1"):
        result = _run([empty], '{"session_id":"q","hook_event_name":"SessionStart"}', script=name, tmpdir=tmp_path)
        assert result.returncode == 0
        assert result.stdout == ""


@needs_sh
@needs_posix
def test_python_fallback_loads_the_rules(tmp_path):
    folder = _python_only(tmp_path)
    home = tmp_path / "home"
    home.mkdir()
    payload = '{"session_id":"py-1","hook_event_name":"SessionStart"}'
    for _ in range(2):
        result = _run([folder], payload, script=RULES, tmpdir=tmp_path,
                      extra_env={"HOME": str(home), "USERPROFILE": str(home)})
        assert result.returncode == 0, result.stderr
        assert result.stdout.startswith("rules-inject: workstation-core rules")
        assert "<!-- shared-memory:v1 -->" in result.stdout
        assert "<!-- app-locks:v1 -->" in result.stdout
        assert "{{" not in result.stdout
        assert "<Projects>" in result.stdout
        assert "WORKSTATION RULES NOT LOADED" not in result.stdout
    assert not list(tmp_path.glob("workstation-rules-warned-*"))


@needs_sh
@needs_posix
def test_python_fallback_fills_the_projects_root_and_skips_blocks_already_loaded(tmp_path):
    folder = _python_only(tmp_path)
    home = tmp_path / "home"
    (home / ".claude").mkdir(parents=True)
    (home / ".claude" / "CLAUDE.md").write_text("<!-- app-locks:v1 -->\nold\n<!-- /app-locks:v1 -->\n", encoding="utf-8")
    result = _run([folder], '{"hook_event_name":"SessionStart"}', script=RULES, tmpdir=tmp_path,
                  extra_env={"HOME": str(home), "USERPROFILE": str(home), "WORKSTATION_PROJECTS_ROOT": "/p/Projects/"})
    assert result.returncode == 0, result.stderr
    assert "/p/Projects\\_claude" in result.stdout
    assert "<Projects>" not in result.stdout
    assert "<!-- app-locks:v1 -->" not in result.stdout


@needs_sh
@needs_posix
def test_python_fallback_subagent_rules_match_the_powershell_text(tmp_path):
    folder = _python_only(tmp_path)
    result = _run([folder], '{"session_id":"py-2","hook_event_name":"SubagentStart"}', script=SUBAGENT, tmpdir=tmp_path)
    assert result.returncode == 0, result.stderr
    spec = json.loads(result.stdout)["hookSpecificOutput"]
    assert spec["hookEventName"] == "SubagentStart"
    text = spec["additionalContext"]
    assert text.startswith("rules-inject: workstation-core rules for this subagent")
    assert "this branch's STATE-<slug>.md" in text
    assert "harness.design lock:" in text


@needs_sh
@needs_posix
def test_python_fallback_state_inject_prints_the_state_file(tmp_path):
    if shutil.which("git") is None:
        pytest.skip("no git")
    folder = _python_only(tmp_path)
    git_dir = Path(shutil.which("git")).parent
    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
    (repo / "STATE.md").write_text("# STATE\nRepo: repo\n", encoding="utf-8")
    payload = json.dumps({"session_id": "py-3", "hook_event_name": "SessionStart", "cwd": str(repo)})
    result = _run([folder, git_dir], payload, script=STATE, tmpdir=tmp_path)
    assert result.returncode == 0, result.stderr
    assert result.stdout.startswith("state-inject: live state from ")
    assert "Repo: repo" in result.stdout


@needs_sh
@needs_posix
def test_python_fallback_failure_falls_back_to_the_once_only_warning(tmp_path):
    folder = _python_only(tmp_path)
    payload = '{"session_id":"py-4","hook_event_name":"SessionStart"}'
    first = _run([folder], payload, script=RULES, tmpdir=tmp_path, extra_env={"WORKSTATION_INJECT_FAIL": "x"})
    data, _ = _loud_fail(first.stdout)
    assert "Python fallback failed" in data["systemMessage"]
    second = _run([folder], payload, script=RULES, tmpdir=tmp_path, extra_env={"WORKSTATION_INJECT_FAIL": "x"})
    assert second.stdout == ""


def test_cursor_hooks_never_use_the_launcher():
    """Cursor commands call powershell directly, so run-ps.sh cannot loop a Cursor stop hook."""
    data = json.loads((ROOT / "hooks" / "cursor-hooks.json").read_text(encoding="utf-8"))
    for entries in data["hooks"].values():
        for hook in entries:
            assert "run-ps.sh" not in hook["command"]
    for hook in data["hooks"]["stop"]:
        assert hook.get("loop_limit") == 1


def test_fallback_has_lf_line_endings():
    assert b"\r\n" not in (ROOT / "hooks" / "rules_fallback.py").read_bytes()
