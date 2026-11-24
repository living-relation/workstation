"""No-PowerShell fallback for the start-of-session hooks (Linux cloud sessions, containers, WSL).

hooks/run-ps.sh calls this with python3 (else python) only when powershell and pwsh are both missing,
and only on SessionStart or SubagentStart:

    python3 hooks/rules_fallback.py <rules-inject|state-inject|subagent-rules>  < hook payload JSON

It prints the same text as the PowerShell hook of that name, built from the same sources:
- rules-inject: the marked blocks in memory/templates (claude-global-memory-section.md, app-locks.md).
  A block is skipped when ~/.claude/CLAUDE.md already has it. Placeholders come from
  WORKSTATION_PROJECTS_ROOT or LOCALAPPDATA/Workstation/workstation.json; with neither (a cloud
  session), they stay as labels such as <Projects>, so the rules still load.
- state-inject: STATE.md or this branch's STATE-<slug>.md, found with scripts/state/state_paths.py.
- subagent-rules: the short rules text, read from hooks/subagent-rules.ps1 so it is never copied.
Output goes to stdout only when the whole text is built. Exit 0 is success (no output is a normal
skip). Any error prints nothing and exits 3, so run-ps.sh shows its once-per-session warning instead.
Never writes anything. Claude Code only: Cursor hooks call powershell directly.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOOKS = Path(__file__).resolve().parent
PLUGIN = HOOKS.parent
TEMPLATES = PLUGIN / "memory" / "templates"


def _read_payload():
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        data = json.loads(raw)
    except ValueError:
        return {}
    return data if isinstance(data, dict) else {}


def _projects_root():
    root = os.environ.get("WORKSTATION_PROJECTS_ROOT")
    if root:
        return root.rstrip("\\/")
    local = os.environ.get("LOCALAPPDATA")
    if local:
        cfg = Path(local) / "Workstation" / "workstation.json"
        if cfg.is_file():
            try:
                root = str(json.loads(cfg.read_text(encoding="utf-8-sig")).get("projectsRoot") or "")
            except (OSError, ValueError, AttributeError):
                root = ""
            if root:
                return root.rstrip("\\/")
    return None


def _user_home():
    home = os.environ.get("USERPROFILE") or os.environ.get("HOME") or str(Path.home())
    return home.rstrip("\\/")


def marked_block(text, name):
    start = f"<!-- {name}:v1 -->"
    end = f"<!-- /{name}:v1 -->"
    i = text.find(start)
    if i < 0:
        return None
    j = text.find(end, i)
    if j < 0:
        return text[i:].strip()
    return text[i:j + len(end)].strip()


def _file_has_marker(path, name):
    try:
        return f"<!-- {name}:v1 -->" in Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False


def rules_text(templates=TEMPLATES, projects_root=None, user_home=None):
    if user_home is None:
        user_home = _user_home()
    if projects_root:
        mapping = {
            "{{USERPROFILE_FWD}}": user_home.replace("\\", "/"),
            "{{USERPROFILE}}": user_home,
            "{{PROJECTS_ROOT_FWD}}": projects_root.replace("\\", "/"),
            "{{PROJECTS_ROOT}}": projects_root,
            "{{CLAUDE_PROJECT_KEY}}": re.sub(r"[^A-Za-z0-9]", "-", projects_root),
        }
    else:
        mapping = {
            "{{USERPROFILE_FWD}}": user_home.replace("\\", "/"),
            "{{USERPROFILE}}": user_home,
            "{{PROJECTS_ROOT_FWD}}": "<Projects>",
            "{{PROJECTS_ROOT}}": "<Projects>",
            "{{CLAUDE_PROJECT_KEY}}": "<project-key>",
        }
    own = Path(user_home) / ".claude" / "CLAUDE.md"
    parts = []
    for file_name, marker in (("claude-global-memory-section.md", "shared-memory"), ("app-locks.md", "app-locks")):
        if _file_has_marker(own, marker):
            continue
        path = Path(templates) / file_name
        if not path.is_file():
            continue
        block = marked_block(path.read_text(encoding="utf-8"), marker)
        if not block:
            continue
        for key, value in mapping.items():
            block = block.replace(key, value)
        parts.append(block.replace("\r\n", "\n"))
    if not parts:
        return None
    head = "rules-inject: workstation-core rules (memory store and app locks). They apply to this session."
    if not projects_root:
        head += " No projects root on this machine (cloud session): <Projects> stands for the owner's projects folder."
    return head + "\n" + "\n\n".join(parts)


def subagent_text(script=HOOKS / "subagent-rules.ps1"):
    source = Path(script).read_text(encoding="utf-8")
    body = re.search(r"\$lines = @\((.*?)\n\s*\)", source, re.S)
    if not body:
        raise ValueError("subagent-rules.ps1: $lines block not found")
    lines = [m.group(1).replace("''", "'") for m in re.finditer(r"^\s*'((?:[^']|'')*)'\s*$", body.group(1), re.M)]
    if not lines:
        raise ValueError("subagent-rules.ps1: no rule lines")
    return "\n".join(lines)


def _state_tools():
    candidates = []
    for env_name, sub in (("WORKSTATION_STATE_TOOLS", ""), ("CLAUDE_PLUGIN_ROOT", "scripts/state")):
        value = os.environ.get(env_name)
        if value:
            candidates.append(Path(value) / sub if sub else Path(value))
    candidates.append(PLUGIN / "scripts" / "state")
    for folder in candidates:
        if (folder / "state_paths.py").is_file():
            return folder
    return None


def state_text(payload):
    cwd = payload.get("cwd") or os.getcwd()
    if not cwd or not Path(cwd).is_dir():
        return None
    tools = _state_tools()
    if not tools:
        return None
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    try:
        result = subprocess.run(
            [sys.executable, str(tools / "state_paths.py"), "--repo", str(cwd), "--json"],
            capture_output=True, text=True, encoding="utf-8", env=env, timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0 or not result.stdout.strip():
        return None
    try:
        info = json.loads(result.stdout)
    except ValueError:
        return None
    if not info.get("project") or not info.get("state_dir") or not info.get("state_ready"):
        return None
    target = Path(str(info.get("state_file") or ""))
    note = None
    if not target.is_file():
        root = Path(info["state_dir"]) / "STATE.md"
        if str(target).lower() == str(root).lower() or not root.is_file():
            return None
        note = (f"No {target.name} for branch '{info.get('branch')}' yet; showing the root STATE.md. "
                "Create the branch file with: state_manager.py new-branch")
        target = root
    text = target.read_text(encoding="utf-8")
    if not text.strip():
        return None
    lines = [f"state-inject: live state from {target}"]
    if note:
        lines.append(note)
    lines += ["```", text.rstrip(), "```",
              "Before any other work, confirm in 3 lines: (1) the goal, (2) Last_Verified_SHA, (3) the next step, "
              "all from this STATE file. Ask only if it is missing or wrong."]
    return "\n".join(lines)


def main(argv):
    if len(argv) != 2:
        return 3
    name = argv[1]
    payload = _read_payload()
    if os.environ.get("WORKSTATION_INJECT_FAIL"):
        return 3
    if name == "rules-inject":
        out = rules_text(projects_root=_projects_root())
    elif name == "subagent-rules":
        out = json.dumps({"hookSpecificOutput": {"hookEventName": "SubagentStart",
                                                 "additionalContext": subagent_text()}})
    elif name == "state-inject":
        out = state_text(payload)
    else:
        return 3
    if out:
        sys.stdout.write(out + "\n")
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    try:
        if hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(encoding="utf-8")
        code = main(sys.argv)
    except Exception:  # any error: no output, run-ps.sh shows its warning once
        code = 3
    sys.exit(code)
