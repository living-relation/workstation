#!/usr/bin/env python3
"""Arm the state-closeout (closeout mode) run when chat context is at or above 80%.

Delivery: the workstation-core Cursor plugin runs this file through handoff/cursor/run-handoff-at-80.ps1
with --from-plugin (hooks/cursor-hooks.json preCompact and stop). Install no longer copies it into
~/.cursor/hooks or wires ~/.cursor/hooks.json (decision D-2026-11-26-hooks-in-plugin).
With --from-plugin:
- it does nothing when ~/.cursor/hooks.json still wires an older copy (that copy runs instead, so the
  handoff never fires twice);
- it is armed unless ~/.cursor/hooks/state/handoff-at-80/disarmed exists. Without --from-plugin (an older
  wired copy) it is armed only when ~/.cursor/hooks/state/handoff-at-80/armed exists, as before.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

THRESHOLD = 80
STATE_DIR = Path.home() / ".cursor" / "hooks" / "state" / "handoff-at-80"
ARMED_PATH = STATE_DIR / "armed"
DISARMED_PATH = STATE_DIR / "disarmed"
USER_HOOKS_JSON = Path.home() / ".cursor" / "hooks.json"
FOLLOWUP = (
    "CONTEXT PRESSURE: chat context is at or above 80%. "
    "Run the state-closeout skill in closeout mode immediately. "
    "Do not continue coding. Tag what this chat did, graduate each item to its home, "
    "queue the rest in BACKLOG.md, and rewrite this branch's STATE file in the repo "
    "(STATE.md on trunk, STATE-<branch-slug>.md on a branch, committed on that branch; "
    "30 lines max, one [NEXT] step). "
    "Commit finished repo work on the task branch first. "
    "Do not push to main. Do not start new project work."
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


def _armed(from_plugin: bool = False) -> bool:
    if from_plugin:
        return not DISARMED_PATH.exists()
    return ARMED_PATH.exists()


def _older_copy_wired() -> bool:
    """True when ~/.cursor/hooks.json still runs a copy of this script (an install before the plugin did)."""
    try:
        return "handoff-at-80.py" in USER_HOOKS_JSON.read_text(encoding="utf-8")
    except OSError:
        return False


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


def main(argv: list[str] | None = None) -> int:
    from_plugin = "--from-plugin" in (sys.argv[1:] if argv is None else argv)
    try:
        raw = sys.stdin.read().lstrip("\ufeff")  # Windows PowerShell pipes add a BOM
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        _emit({})
        return 0

    if from_plugin and _older_copy_wired():
        _emit({})
        return 0
    if not _armed(from_plugin):
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
