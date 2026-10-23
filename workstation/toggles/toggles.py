"""Dashboard toggles, their health checks and the process check.

Toggles come from two JSON files with the same shape:
  * toggles.json next to this file: package toggles, generic, committed.
  * %LOCALAPPDATA%\\Workstation\\toggles.json: this PC's own toggles (never committed).
A local entry with the same id replaces a package entry; "hidden": true hides it.

Each entry:
  {"id": "...", "name": "...", "start": "...", "stop": "...", "status": "...", "health": "..."}
Commands are PowerShell command lines. {toolkit} is replaced by the toolkit folder
(this repo's workstation\\ folder). "status" and "health" exit 0 for on / healthy.

CLI (used by shortcuts, toggle.ps1 and the watcher):
  python toggles.py list | on <id> | off <id> | status <id> | health <id> | process-check
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLKIT = HERE.parent
PACKAGE_FILE = HERE / "toggles.json"
CREATE_NO_WINDOW = 0x08000000
_BUSY: dict[str, str] = {}
_BUSY_LOCK = threading.Lock()
_STATUS_CACHE: dict[str, tuple[float, dict]] = {}


def state_root() -> Path:
    root = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    return Path(root) / "Workstation"


def local_file() -> Path:
    return state_root() / "toggles.json"


def _read(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def merge(package: dict, local: dict) -> list[dict]:
    """Package toggles first, local ones after; same id = local wins; hidden ones dropped."""
    order: list[str] = []
    rows: dict[str, dict] = {}
    for source, data in (("package", package), ("local", local)):
        for item in data.get("toggles") or []:
            if not isinstance(item, dict) or not str(item.get("id") or "").strip():
                continue
            tid = str(item["id"]).strip()
            if tid not in rows:
                order.append(tid)
            rows[tid] = {**item, "id": tid, "source": source}
    out = []
    for tid in order:
        row = rows[tid]
        if row.get("hidden"):
            continue
        row.setdefault("name", tid)
        out.append(row)
    return out


def load_toggles() -> list[dict]:
    return merge(_read(PACKAGE_FILE), _read(local_file()))


def settings() -> dict:
    data = _read(local_file()).get("processCheck") or {}
    expected = [e for e in data.get("expected") or [] if isinstance(e, dict) and e.get("match")]
    return {"expected": EXPECTED_ORPHANS + expected}


def find(tid: str) -> dict | None:
    for row in load_toggles():
        if row["id"] == tid:
            return row
    return None


def expand(command: str) -> str:
    return command.replace("{toolkit}", str(TOOLKIT))


def run_ps(command: str, timeout: int = 60, limit: int = 4000) -> tuple[int, str]:
    if not command.strip():
        return 1, "no command configured"
    args = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", expand(command)]
    try:
        done = subprocess.run(
            args,
            cwd=str(TOOLKIT),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            creationflags=CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
    except subprocess.TimeoutExpired:
        return 124, f"timed out after {timeout} s"
    except OSError as exc:
        return 1, str(exc)
    text = "\n".join(part for part in (done.stdout.strip(), done.stderr.strip()) if part)
    return done.returncode, text[-limit:] if limit else text


def status(row: dict) -> dict:
    tid = row["id"]
    hit = _STATUS_CACHE.get(tid)
    if hit and time.time() - hit[0] < 4:
        return hit[1]
    code, text = run_ps(str(row.get("status") or ""), timeout=25)
    result = {"on": code == 0, "detail": text.splitlines()[-1] if text else ""}
    _STATUS_CACHE[tid] = (time.time(), result)
    return result


def snapshot() -> list[dict]:
    rows = load_toggles()
    with ThreadPoolExecutor(max_workers=max(1, len(rows))) as pool:
        states = list(pool.map(status, rows))
    out = []
    for row, state in zip(rows, states):
        with _BUSY_LOCK:
            busy = _BUSY.get(row["id"], "")
        out.append(
            {
                "id": row["id"],
                "name": row["name"],
                "source": row["source"],
                "on": state["on"],
                "detail": state["detail"],
                "busy": busy,
                "hasHealth": bool(str(row.get("health") or "").strip()),
            }
        )
    return out


def switch(tid: str, turn_on: bool, wait: bool = False) -> dict:
    row = find(tid)
    if row is None:
        return {"ok": False, "error": "unknown toggle"}
    command = str(row.get("start" if turn_on else "stop") or "")
    if not command.strip():
        return {"ok": False, "error": "no command configured"}
    with _BUSY_LOCK:
        if _BUSY.get(tid):
            return {"ok": False, "error": f"already {_BUSY[tid]}"}
        _BUSY[tid] = "starting" if turn_on else "stopping"

    def work() -> dict:
        try:
            code, text = run_ps(command, timeout=180)
            _log(f"{tid} {'on' if turn_on else 'off'} exit {code}: {text[-600:]}")
            return {"ok": code == 0, "exit": code, "output": text}
        finally:
            _STATUS_CACHE.pop(tid, None)
            with _BUSY_LOCK:
                _BUSY.pop(tid, None)

    if wait:
        return work()
    threading.Thread(target=work, daemon=True).start()
    return {"ok": True, "started": True}


def health(tid: str) -> dict:
    row = find(tid)
    if row is None:
        return {"ok": False, "error": "unknown toggle"}
    code, text = run_ps(str(row.get("health") or ""), timeout=60)
    return {"ok": code == 0, "exit": code, "output": text}


def _log(line: str) -> None:
    try:
        path = state_root() / "dashboard" / "toggles.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as fh:
            fh.write(f"{datetime.now().isoformat(timespec='seconds')} {line}\n")
    except OSError:
        pass


# ---------------------------------------------------------------- process check

OWNER_APPS = {
    "claude.exe": "Claude",
    "cursor.exe": "Cursor",
    "code.exe": "VS Code",
    "windowsterminal.exe": "Terminal",
    "explorer.exe": "Explorer",
    "svchost.exe": "Task Scheduler",
}
WATCHED_NAMES = {"node.exe", "cmd.exe", "npx.exe", "uv.exe", "uvx.exe", "python.exe", "pythonw.exe"}
MCP_HINTS = ("mcp", "desktop-commander", "context7", "modelcontextprotocol", "server")
# Orphans that are normal when launched hidden (the launcher exits on purpose). "max" = copies allowed.
# Add your own in the local file: "processCheck": {"expected": [{"match": "pnpm dev:", "max": 2}]}.
EXPECTED_ORPHANS = [
    {"match": r"desktop-commander.*\bremote\b", "max": 1, "label": "Desktop Commander Remote"},
]


def list_processes() -> list[dict]:
    script = (
        "Get-CimInstance Win32_Process | ForEach-Object { [pscustomobject]@{"
        "pid=[int]$_.ProcessId; ppid=[int]$_.ParentProcessId; name=[string]$_.Name; "
        "cmd=[string]$_.CommandLine; mem=[int64]$_.WorkingSetSize; "
        "created=$(if ($_.CreationDate) { $_.CreationDate.ToUniversalTime().ToString('o') } else { '' }) } } "
        "| ConvertTo-Json -Compress -Depth 2"
    )
    code, text = run_ps(script, timeout=60, limit=0)
    if code != 0 or not text.strip():
        return []
    try:
        data = json.loads(text)
    except ValueError:
        return []
    return data if isinstance(data, list) else [data]


def _short(cmd: str, limit: int = 140) -> str:
    text = " ".join(cmd.split())
    return text if len(text) <= limit else text[: limit - 3] + "..."


def _mcp_key(cmd: str) -> str:
    low = cmd.lower().replace("\\", "/")
    if not any(hint in low for hint in MCP_HINTS):
        return ""
    for marker in ("node_modules/", "@"):
        pos = low.find(marker)
        if pos >= 0:
            return _short(low[pos:], 120)
    return _short(low, 120)


def analyze(procs: list[dict], expected: list[dict] | None = None) -> dict:
    """Pure function over a process list (pid, ppid, name, cmd, mem, created)."""
    by_pid = {int(p.get("pid") or 0): p for p in procs}

    def parent_alive(proc: dict) -> bool:
        parent = by_pid.get(int(proc.get("ppid") or 0))
        if parent is None:
            return False
        # A reused pid: the "parent" started after the child, so the real parent is gone.
        mine, theirs = str(proc.get("created") or ""), str(parent.get("created") or "")
        return not (mine and theirs and theirs > mine)

    def owner(proc: dict) -> str:
        seen = set()
        cur = proc
        while cur is not None and int(cur.get("pid") or 0) not in seen:
            seen.add(int(cur.get("pid") or 0))
            if not parent_alive(cur):
                return "orphan"
            cur = by_pid.get(int(cur.get("ppid") or 0))
            if cur is None:
                break
            app = OWNER_APPS.get(str(cur.get("name") or "").lower())
            if app:
                return app
        return "other"

    node = [p for p in procs if str(p.get("name") or "").lower() == "node.exe"]
    node_mb = sum(int(p.get("mem") or 0) for p in node) / 1_048_576
    by_owner: dict[str, dict] = {}
    for p in node:
        slot = by_owner.setdefault(owner(p), {"count": 0, "mb": 0.0})
        slot["count"] += 1
        slot["mb"] += int(p.get("mem") or 0) / 1_048_576

    orphans = []
    for p in procs:
        name = str(p.get("name") or "").lower()
        if name not in WATCHED_NAMES or parent_alive(p):
            continue
        cmd = str(p.get("cmd") or "")
        if name == "cmd.exe" and not cmd:
            continue
        # Only top-level orphans; their children are counted in the tree RAM.
        tree = [p]
        stack = [int(p.get("pid") or 0)]
        while stack:
            cur = stack.pop()
            for child in procs:
                if int(child.get("ppid") or 0) == cur and int(child.get("pid") or 0) != cur and parent_alive(child):
                    tree.append(child)
                    stack.append(int(child.get("pid") or 0))
        orphans.append(
            {
                "pid": int(p.get("pid") or 0),
                "name": p.get("name"),
                "cmd": _short(cmd),
                "processes": len(tree),
                "mb": round(sum(int(t.get("mem") or 0) for t in tree) / 1_048_576, 1),
            }
        )

    rules = EXPECTED_ORPHANS if expected is None else expected
    seen_rule: dict[int, list[dict]] = {}
    for o in orphans:
        o["expected"] = False
        for i, rule in enumerate(rules):
            try:
                hit = re.search(str(rule["match"]), o["cmd"], re.IGNORECASE)
            except re.error:
                hit = None
            if hit:
                o["expected"] = True
                o["label"] = rule.get("label") or rule["match"]
                seen_rule.setdefault(i, []).append(o)
                break
    for i, rows in seen_rule.items():
        allowed = int(rules[i].get("max", 1))
        if len(rows) > allowed:
            for o in rows:
                o["expected"] = False
                o["note"] = f"{len(rows)} copies running, expected at most {allowed}"
    bad = [o for o in orphans if not o["expected"]]

    groups: dict[str, list[dict]] = {}
    for p in node:
        key = _mcp_key(str(p.get("cmd") or ""))
        if key:
            groups.setdefault(key, []).append(p)
    duplicates = [
        {
            "server": key,
            "count": len(rows),
            "mb": round(sum(int(r.get("mem") or 0) for r in rows) / 1_048_576, 1),
            "pids": [int(r.get("pid") or 0) for r in rows],
        }
        for key, rows in sorted(groups.items(), key=lambda kv: -len(kv[1]))
        if len(rows) > 1
    ]

    problems = []
    if bad:
        problems.append(
            f"{len(bad)} orphaned process tree(s), {sum(o['mb'] for o in bad):.0f} MB: "
            + ", ".join(f"{o.get('label') or o['name']} {o['pid']}" for o in bad[:4])
        )
    return {
        "node": {
            "count": len(node),
            "mb": round(node_mb, 1),
            "byOwner": {k: {"count": v["count"], "mb": round(v["mb"], 1)} for k, v in sorted(by_owner.items())},
        },
        "orphans": orphans,
        "duplicates": duplicates,
        "problems": problems,
        "checkedAt": datetime.now().isoformat(timespec="seconds"),
    }


def process_check() -> dict:
    procs = list_processes()
    if not procs:
        return {"problems": ["could not read the process list"], "node": {}, "orphans": [], "duplicates": []}
    conf = settings()
    return analyze(procs, conf["expected"])


def main(argv: list[str]) -> int:
    if not argv or argv[0] in {"-h", "--help"}:
        print(__doc__)
        return 0
    cmd = argv[0]
    if cmd == "list":
        print(json.dumps(snapshot(), indent=2))
        return 0
    if cmd == "process-check":
        result = process_check()
        print(json.dumps(result, indent=2))
        return 1 if result["problems"] else 0
    if len(argv) < 2:
        print("needs a toggle id")
        return 2
    tid = argv[1]
    if cmd in {"on", "off"}:
        result = switch(tid, cmd == "on", wait=True)
    elif cmd == "health":
        result = health(tid)
    elif cmd == "status":
        row = find(tid)
        result = {"ok": False, "error": "unknown toggle"} if row is None else {"ok": status(row)["on"]}
    else:
        print(f"unknown command {cmd}")
        return 2
    print(result.get("output") or result.get("error") or ("on" if result.get("ok") else "off"))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
