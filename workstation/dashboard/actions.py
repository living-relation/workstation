"""Write actions for tracker items: record an owner's answer on a branch and open a PR.

Never merges and never touches the project checkout under active\\. Each action clones the
project's GitHub main into a throwaway folder under the dashboard state dir, edits the one
tracker row, commits (with the same hooks the project checkout uses), pushes a new branch,
opens a PR and deletes the clone. Children get stdin closed and write to temp files, not
pipes (the PR #40 hang).
"""

from __future__ import annotations

import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
from datetime import datetime
from pathlib import Path

import collect

_LOCK = threading.Lock()  # one write action at a time
ANSWER_LIMIT = 500


class ActionError(Exception):
    """A write action stopped; the message is safe to show on the page."""


def settings() -> dict:
    """Local, never-committed settings: %LOCALAPPDATA%\\Workstation\\dashboard\\settings.json.

    {"writeActions": true, "ownerName": "<name>"} turns write actions on for this PC only.
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
    return re.sub(r"[^\w .-]", "", name)[:40] or "Owner"


def work_dir() -> Path:
    path = collect.state_dir() / "work"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _answers_path() -> Path:
    return collect.state_dir() / "answers.json"


def load_answers() -> dict:
    """{"<project>|<fp>": {"prUrl": ..., "at": ...}} for rows answered from this page."""
    try:
        data = json.loads(_answers_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def _save_answer(project: str, fp: str, pr_url: str) -> None:
    data = load_answers()
    data[f"{project}|{fp}"] = {"prUrl": pr_url, "at": collect._now()}
    _answers_path().write_text(json.dumps(data, indent=2), encoding="utf-8")


def clean_answer(text: str) -> str:
    """One line, no table-breaking pipes, capped."""
    text = re.sub(r"\s+", " ", str(text or "")).strip().replace("|", "/")
    return text[:ANSWER_LIMIT]


def answer_row(line: str, owner: str, day: str, answer: str) -> str:
    """Append "**<owner> <day>:** <answer>" to a tracker line: into the last cell of a table row,
    or at the end of a bullet."""
    note = f"**{owner} {day}:** {answer}"
    stripped = line.rstrip()
    if stripped.lstrip().startswith("|"):
        body = stripped[:-1].rstrip() if stripped.endswith("|") else stripped
        cell = body[body.rfind("|") + 1 :].strip()
        sep = " " if not cell else " — "
        return f"{body}{sep}{note} |"
    return f"{stripped} — {note}"


def find_row(text: str, fp: str) -> int | None:
    """1-based line of the item with this fingerprint in a tracker's text, or None."""
    parsed = collect.parse_tracker(text)
    for bucket in parsed.values():
        for item in bucket:
            if item.get("fp") == fp:
                return item["line"]
    return None


def _run(args: list[str], cwd: Path | None = None, timeout: float = 180) -> str:
    """Run a command with stdin closed and output in temp files; raise ActionError on failure."""
    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0", "GH_PROMPT_DISABLED": "1"}
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        try:
            proc = subprocess.run(
                args, cwd=str(cwd) if cwd else None, stdin=subprocess.DEVNULL, stdout=out, stderr=err,
                timeout=timeout, env=env, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ActionError(f"{args[0]} {args[1] if len(args) > 1 else ''} did not finish: {exc}") from exc
        out.seek(0)
        err.seek(0)
        stdout = out.read().decode("utf-8", "replace").strip()
        stderr = err.read().decode("utf-8", "replace").strip()
    if proc.returncode != 0:
        tail = (stderr or stdout).splitlines()[-3:]
        raise ActionError(f"{' '.join(args[:3])} failed: {' / '.join(tail)}")
    return stdout


def _rmtree(path: Path) -> None:
    def force(func, target, _exc):  # git pack files are read-only on Windows
        os.chmod(target, stat.S_IWRITE)
        func(target)

    if sys.version_info >= (3, 12):
        shutil.rmtree(path, onexc=force)
    else:
        shutil.rmtree(path, onerror=force)


def _copy_hooks(project: Path, clone: Path) -> None:
    """Give the clone the same commit hooks the project checkout uses (never fewer)."""
    code, hooks_path = collect._git(project, "config", "--get", "core.hooksPath")
    if code == 0 and hooks_path:
        _run(["git", "-C", str(clone), "config", "core.hooksPath", hooks_path])
        return
    src = project / ".git" / "hooks"
    if src.is_dir():
        for hook in src.iterdir():
            if hook.is_file() and not hook.name.endswith(".sample"):
                shutil.copy2(hook, clone / ".git" / "hooks" / hook.name)


def record_answer(project_name: str, fp: str, answer: str, today: str | None = None) -> dict:
    """Record an answer on a new branch of the project's GitHub main and open a PR. Returns {"prUrl"}."""
    answer = clean_answer(answer)
    if not answer:
        raise ActionError("answer is empty")
    if not re.fullmatch(r"[0-9a-f]{12}", fp or ""):
        raise ActionError("bad row id")
    project = collect.project_dir(project_name)
    if project is None:
        raise ActionError("project not found")
    tracker_rel, _ = collect._tracker_for(project)
    slug = collect._github_slug(project)
    if not tracker_rel or not slug:
        raise ActionError("project has no open-items file or no GitHub remote")
    day = today or datetime.now().strftime("%Y-%m-%d")
    owner = owner_name()
    if not _LOCK.acquire(blocking=False):
        raise ActionError("another action is still running; try again in a minute")
    clone = None
    try:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        branch = f"dashboard/answer-{fp}-{stamp}"
        clone = work_dir() / f"{project.name}-{stamp}"
        _run(["git", "clone", "--quiet", "--depth", "20", "--branch", "main", "--single-branch",
              f"https://github.com/{slug}.git", str(clone)])
        _copy_hooks(project, clone)
        file = clone / tracker_rel
        text = file.read_text(encoding="utf-8")
        line_no = find_row(text, fp)
        if line_no is None:
            raise ActionError("that row changed or is gone on GitHub main; refresh the page")
        newline = "\r\n" if "\r\n" in text else "\n"
        lines = text.split(newline)
        lines[line_no - 1] = answer_row(lines[line_no - 1], owner, day, answer)
        file.write_text(newline.join(lines), encoding="utf-8", newline="")
        _run(["git", "-C", str(clone), "checkout", "-q", "-b", branch])
        _run(["git", "-C", str(clone), "add", "--", tracker_rel])
        _run(["git", "-C", str(clone), "commit", "-q", "-m",
              f"{tracker_rel}: record {owner}'s answer (row line {line_no})\n\nFrom the workstation dashboard, {day}."])
        _run(["git", "-C", str(clone), "push", "-q", "-u", "origin", branch])
        body = (
            f"**{owner}'s answer ({day}), sent from the workstation dashboard:**\n\n> {answer}\n\n"
            f"Row: `{tracker_rel}` line {line_no}\n\n> {_quote(lines[line_no - 1])}\n\n"
            "The answer is written on that row only. Following this repo's own rules, its agent moves "
            "it into the decisions file (if it has one) and updates or removes the row. Not merged: "
            "the owner reviews and merges."
        )
        url = _run(["gh", "pr", "create", "--repo", slug, "--base", "main", "--head", branch,
                    "--title", f"Answer from {owner}: {_title(lines[line_no - 1])}", "--body", body],
                   cwd=clone).splitlines()[-1].strip()
        _save_answer(project.name, fp, url)
        return {"prUrl": url, "branch": branch}
    finally:
        _LOCK.release()
        if clone is not None and clone.exists():
            try:
                _rmtree(clone)
            except OSError:
                pass  # left under the dashboard's work folder; safe to delete by hand


def _quote(row: str) -> str:
    return collect._clip(row, 600)


def _title(row: str) -> str:
    cells = [c.strip() for c in row.strip().strip("|").split("|") if c.strip()]
    text = " ".join(cells[:3]) if row.lstrip().startswith("|") else re.sub(r"^\s*[-*]\s+(\[[ xX]\]\s+)?", "", row)
    return collect._clip(re.sub(r"\*\*[^*]+:\*\*.*$", "", text), 70)
