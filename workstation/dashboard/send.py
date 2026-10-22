"""Deliver a snippet through a real CLI resume. Never invents a send."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from collect import UUID_RE, _agent_rows, _run

SNIPPET_LIMIT = 4000


def _result_text(raw: str) -> str:
    raw = (raw or "").strip()
    if not raw:
        return ""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return raw[:4000]
    if isinstance(data, dict):
        for key in ("result", "text", "message"):
            value = data.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()[:4000]
        return json.dumps({key: data[key] for key in list(data)[:6] if key not in {"apiKey", "token"}})[:4000]
    return raw[:4000]


def _claude_running(session_id: str) -> str | None:
    short = session_id[:8]
    for agent in _agent_rows():
        full = str(agent.get("sessionId") or "")
        ident = str(agent.get("id") or "")
        if session_id not in {full, ident} and short != ident:
            continue
        state = str(agent.get("state") or "")
        if state in {"running", "working"}:
            return "Session is running. Resume would start a second copy, so nothing was sent."
        if state == "blocked":
            return "Session is waiting on a permission prompt. Nothing was sent."
    return None


def deliver(app: str, session: dict, text: str) -> dict:
    text = (text or "").strip()
    if not text:
        return {"ok": False, "sent": False, "error": "Empty snippet."}
    if len(text) > SNIPPET_LIMIT:
        return {"ok": False, "sent": False, "error": "Snippet is too long."}
    app = (app or "").lower()
    session_id = str(session.get("id") or "")
    if app in {"claude", "dispatch"}:
        return _deliver_claude(session_id, text)
    if app == "cursor":
        return _deliver_cursor(session, text)
    return {"ok": False, "sent": False, "error": "Unknown session type."}


def _deliver_claude(session_id: str, text: str) -> dict:
    if not UUID_RE.match(session_id):
        return {"ok": False, "sent": False, "error": "Not a Claude session id."}
    blocked = _claude_running(session_id)
    if blocked:
        return {"ok": False, "sent": False, "error": blocked}
    try:
        proc = subprocess.run(
            [
                "claude",
                "--resume",
                session_id,
                "-p",
                "--output-format",
                "json",
                text,
            ],
            capture_output=True,
            text=True,
            timeout=100,
            encoding="utf-8",
            errors="replace",
        )
    except subprocess.TimeoutExpired:
        return {
            "ok": False,
            "sent": False,
            "error": "claude --resume timed out. Check the session before trying again.",
        }
    except OSError as exc:
        return {"ok": False, "sent": False, "error": str(exc)}
    reply = _result_text(proc.stdout)
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "claude --resume failed").strip()
        return {"ok": False, "sent": False, "error": detail[:800], "reply": reply}
    return {"ok": True, "sent": True, "reply": reply or "(no reply text)"}


def _deliver_cursor(session: dict, text: str) -> dict:
    code, out, _err = _run(["agent", "status", "--format", "json"], timeout=15)
    authenticated = False
    if code == 0 and out.strip():
        try:
            status = json.loads(out)
            authenticated = bool(status.get("isAuthenticated"))
        except json.JSONDecodeError:
            authenticated = False
    if not authenticated:
        return {
            "ok": False,
            "sent": False,
            "error": "Cursor agent CLI is not logged in. Nothing was sent.",
        }
    session_id = str(session.get("id") or "")
    if not (UUID_RE.match(session_id) or session_id.startswith("bc-")):
        return {"ok": False, "sent": False, "error": "Not a Cursor chat id."}
    args = [
        "agent",
        "--resume",
        session_id,
        "-p",
        "--mode",
        "ask",
        "--output-format",
        "json",
        "--trust",
    ]
    cwd = session.get("cwd")
    if isinstance(cwd, str) and cwd and Path(cwd).is_dir():
        args.extend(["--workspace", cwd])
    args.append(text)
    try:
        proc = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=100,
            encoding="utf-8",
            errors="replace",
        )
    except subprocess.TimeoutExpired:
        return {
            "ok": False,
            "sent": False,
            "error": "agent --resume timed out. Nothing further was sent.",
        }
    except OSError as exc:
        return {"ok": False, "sent": False, "error": str(exc)}
    reply = _result_text(proc.stdout)
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "agent --resume failed").strip()
        return {"ok": False, "sent": False, "error": detail[:800], "reply": reply}
    return {"ok": True, "sent": True, "reply": reply or "(no reply text)"}


def open_session(app: str, session: dict) -> dict:
    app = (app or "").lower()
    session_id = str(session.get("id") or "")
    if app in {"claude", "dispatch"}:
        if not UUID_RE.match(session_id):
            return {"ok": False, "error": "Not a Claude session id."}
        try:
            subprocess.Popen(
                ["claude", "--desktop", "--resume", session_id],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError as exc:
            return {"ok": False, "error": str(exc)}
        return {"ok": True, "opened": "desktop"}
    if app == "cursor":
        cwd = session.get("cwd")
        if isinstance(cwd, str) and Path(cwd).is_dir():
            try:
                subprocess.Popen(
                    ["cursor", cwd],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except OSError as exc:
                return {"ok": False, "error": str(exc)}
            return {"ok": True, "opened": "desktop"}
        return {"ok": False, "error": "This Cursor chat has no folder to open."}
    return {"ok": False, "error": "Unknown session type."}
