#!/usr/bin/env python3
"""Arm the agent-handoff-pack quick-mode handoff when chat context is at or above 80%."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

THRESHOLD = 80
STATE_DIR = Path.home() / ".cursor" / "hooks" / "state" / "handoff-at-80"
ARMED_PATH = STATE_DIR / "armed"
FOLLOWUP = (
    "CONTEXT PRESSURE: chat context is at or above 80%. "
    "Run the agent-handoff-pack skill in quick mode immediately. "
    "Do not continue coding. Update living handoff docs, then output only the "
    "copyable next-chat paste block. Do not commit or push."
)


def _safe_id(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "_", value).strip("._")
    return cleaned[:120] or "unknown"


def _emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload) + "\n")


def _read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def _percent(payload: dict) -> float | None:
    raw = payload.get("context_usage_percent")
    if isinstance(raw, bool) or raw is None:
        return None
    try:
        return float(raw)
    except (TypeError, ValueError):
        return None


def _armed() -> bool:
    return ARMED_PATH.exists()


def handle_precompact(payload: dict) -> dict:
    percent = _percent(payload)
    if percent is None or percent < THRESHOLD:
        return {}
    conversation_id = str(payload.get("conversation_id") or "unknown")
    _write_json(
        STATE_DIR / "pending" / f"{_safe_id(conversation_id)}.json",
        {
            "conversation_id": conversation_id,
            "context_usage_percent": percent,
            "trigger": payload.get("trigger"),
        },
    )
    return {
        "user_message": (
            f"Context is at {percent:.0f}%. When this turn ends, a handoff will run "
            "so you can paste it into a new chat."
        )
    }


def handle_stop(payload: dict) -> dict:
    if payload.get("status") != "completed":
        return {}
    conversation_id = str(payload.get("conversation_id") or "unknown")
    safe = _safe_id(conversation_id)
    fired_path = STATE_DIR / "fired" / f"{safe}.json"
    pending_path = STATE_DIR / "pending" / f"{safe}.json"
    if fired_path.exists():
        return {}
    try:
        loop_count = int(payload.get("loop_count") or 0)
    except (TypeError, ValueError):
        loop_count = 0
    if loop_count > 0:
        return {}

    percent = _percent(payload)
    pending = _read_json(pending_path) if pending_path.exists() else {}
    pending_percent = _percent(pending)
    effective = percent if percent is not None else pending_percent
    if effective is None or effective < THRESHOLD:
        if not pending:
            return {}
        effective = pending_percent if pending_percent is not None else float(THRESHOLD)

    _write_json(
        fired_path,
        {
            "conversation_id": conversation_id,
            "context_usage_percent": effective,
        },
    )
    if pending_path.exists():
        pending_path.unlink()
    return {"followup_message": FOLLOWUP}


def main() -> int:
    try:
        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        _emit({})
        return 0

    if not _armed():
        _emit({})
        return 0

    event = str(payload.get("hook_event_name") or "")
    if event == "preCompact":
        _emit(handle_precompact(payload))
        return 0
    if event == "stop":
        _emit(handle_stop(payload))
        return 0
    _emit({})
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        _emit({})
        raise SystemExit(0)
