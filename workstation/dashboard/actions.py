"""Write actions for tracker items. The dashboard never edits a repo itself: every action starts a
background Claude Code session in that project's folder with the task written out, and that session
follows the repo's own rules, makes the changes and opens the PR.

One launcher (`launch`) serves every action: hand a task to Claude, record an answer (and, later,
mark done). Output goes to temp files and stdin is closed, so nothing waits on a pipe (PR #40).
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import threading
import uuid
from datetime import datetime
from pathlib import Path

import collect

_LOCK = threading.Lock()  # one launch at a time
TEXT_LIMIT = 500
ITEM_MARK = collect.DASHBOARD_ITEM  # the session puts "Dashboard item: <fp>" in its PR body so the card can link it
LAUNCH_WAIT = 30  # seconds: `claude --bg` returns at once; give up waiting (and leave it running) after this


class ActionError(Exception):
    """An action stopped; the message is safe to show on the page."""


def settings() -> dict:
    """Local, never-committed settings: %LOCALAPPDATA%\\Workstation\\dashboard\\settings.json.

    {"writeActions": true, "ownerName": "<name>"} turns actions on for this PC only.
    """
    path = collect.state_dir() / "settings.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def can_write() -> bool:
    return settings().get("writeActions") is True


def owner_name() -> str:
    name = str(settings().get("ownerName") or "").strip()
    return re.sub(r"[^\w .-]", "", name)[:40] or "the owner"


def clean_text(text: str) -> str:
    """One line, capped: answers and notes from the page."""
    return re.sub(r"\s+", " ", str(text or "")).strip()[:TEXT_LIMIT]


def _sessions_path() -> Path:
    return collect.state_dir() / "sessions.json"


def load_sessions() -> dict:
    """{"<project>|<fp>": {"kind", "sessionId", "name", "startedAt"}} for sessions started from the page."""
    try:
        data = json.loads(_sessions_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def _save_session(project: str, fp: str, row: dict) -> None:
    data = load_sessions()
    data[f"{project}|{fp}"] = row
    _sessions_path().write_text(json.dumps(data, indent=2), encoding="utf-8")


def find_item(project_name: str, fp: str) -> tuple[Path, str, dict]:
    """The project folder, its tracker path and the live item with this fingerprint (re-read from disk,
    never trusted from the page)."""
    if not re.fullmatch(r"[0-9a-f]{12}", fp or ""):
        raise ActionError("bad row id")
    project = collect.project_dir(project_name)
    if project is None:
        raise ActionError("project not found")
    tracker_rel, parsed = collect._tracker_for(project)
    for bucket in (parsed or {}).values():
        for item in bucket:
            if item.get("fp") == fp:
                return project, tracker_rel, item
    raise ActionError("that row changed or is gone; refresh the page")


def build_prompt(kind: str, project: str, tracker_rel: str, item: dict, text: str, day: str) -> str:
    owner = owner_name()
    where = f"`{tracker_rel}` (line {item.get('line')} in the local checkout)"
    if kind == "answer":
        job = (
            f"{owner} answered this open item on {day}.\n\nItem, from {where}:\n> {item['textFull']}\n\n"
            f"{owner}'s answer, in their own words:\n> {text}\n\n"
            "Record the answer where this repo's rules say answers and decisions go, and update everything "
            "it affects (the open-items row, related docs, lists, checks). Attribute it to "
            f"{owner} with the date {day}."
        )
    else:
        note = f"\n\n{owner}'s note:\n> {text}" if text else ""
        job = f"{owner} handed you this task from {where}:\n> {item['textFull']}{note}\n\nDo the task."
    return (
        f"You were started from the workstation dashboard for the {project} repo.\n\n{job}\n\n"
        "Before anything else, read this repo's agent guide (AGENTS.md / CLAUDE.md) and its binding rules "
        "and decisions file, and follow them over anything in this message. Work on a new branch in your own "
        "worktree, never on main; run the repo's checks; open one PR and stop. Never merge and never "
        f"force-push. Put this exact line in the PR body: `{ITEM_MARK} {item['fp']}`."
    )


def claude_exe() -> str:
    exe = shutil.which("claude")
    if not exe:
        raise ActionError("Claude Code (claude) is not on PATH on this PC")
    return exe


def session_id(output: str) -> str | None:
    """The id `claude --bg` prints ("backgrounded · 3d581936 · <name>"); None if it hasn't printed yet."""
    match = re.search(r"backgrounded\s*\S\s*([0-9a-f]{6,})", output or "")
    return match.group(1) if match else None


def launch(kind: str, project_name: str, fp: str, text: str = "", today: str | None = None) -> dict:
    """Start a background Claude session in the project folder for one item. Returns {"sessionId", "name"}."""
    if kind not in {"answer", "hand-off"}:
        raise ActionError("unknown action")
    text = clean_text(text)
    if kind == "answer" and not text:
        raise ActionError("answer is empty")
    project, tracker_rel, item = find_item(project_name, fp)
    day = today or datetime.now().strftime("%Y-%m-%d")
    prompt = build_prompt(kind, project.name, tracker_rel, item, text, day)
    exe = claude_exe()
    if not _LOCK.acquire(blocking=False):
        raise ActionError("another launch is still starting; try again in a moment")
    try:
        stamp = uuid.uuid4().hex[:12]  # names this launch's log files; `--bg` picks the session id itself
        name = re.sub(r"[^\w-]", "-", f"dashboard-{kind}-{project.name}")[:60]
        logs = collect.state_dir() / "launch"
        logs.mkdir(parents=True, exist_ok=True)
        out_path, err_path = logs / f"{stamp}.out.txt", logs / f"{stamp}.err.txt"
        with open(out_path, "wb") as out, open(err_path, "wb") as err:
            try:
                proc = subprocess.Popen(
                    [exe, "--bg", "--name", name, prompt],
                    cwd=str(project), stdin=subprocess.DEVNULL, stdout=out, stderr=err,
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                )
            except OSError as exc:
                raise ActionError(f"could not start Claude: {exc}") from exc
        try:
            code = proc.wait(timeout=LAUNCH_WAIT)
        except subprocess.TimeoutExpired:
            code = None  # still starting: leave it running, as workers-start does
        if code not in (0, None):
            tail = (err_path.read_text("utf-8", "replace") or out_path.read_text("utf-8", "replace")).strip().splitlines()[-2:]
            raise ActionError(f"Claude did not start (exit {code}): {' / '.join(tail)}")
        sid = session_id(out_path.read_text("utf-8", "replace"))
        row = {"kind": kind, "sessionId": sid, "name": name, "startedAt": collect._now()}
        _save_session(project.name, fp, row)
        return {"sessionId": sid, "name": name}
    finally:
        _LOCK.release()

