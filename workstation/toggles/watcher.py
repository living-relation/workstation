"""Background watcher: health checks for the toggles that are on, plus the process check.

Off by default. The Watcher On shortcut (watcher.ps1 -Action on) starts it hidden with --loop 15,
so it checks every 15 minutes until Watcher Off (or sign-out) stops it. No scheduled task.
Shows a Windows toast when something is wrong. The same problem set is not repeated within
REPEAT_HOURS, so it does not nag. Results go to %LOCALAPPDATA%\\Workstation\\dashboard\\watcher.json.
"""

from __future__ import annotations

import hashlib
import json
import sys
import time
from datetime import datetime

import toggles

REPEAT_HOURS = 4


def check() -> dict:
    problems: list[str] = []
    checked = []
    for row in toggles.snapshot():
        if not row["on"] or not row["hasHealth"]:
            continue
        result = toggles.health(row["id"])
        checked.append({"id": row["id"], "ok": result["ok"], "output": result.get("output", "")})
        if not result["ok"]:
            fails = [ln.strip() for ln in str(result.get("output") or "").splitlines() if ln.strip().startswith("FAIL")]
            problems.append(f"{row['name']}: " + ("; ".join(fails[:2]) if fails else "health check failed"))
    proc = toggles.process_check()
    problems.extend(proc.get("problems") or [])
    return {"checkedAt": datetime.now().isoformat(timespec="seconds"), "toggles": checked, "processes": proc, "problems": problems}


def toast(title: str, body: str) -> None:
    def q(text: str) -> str:
        return text.replace("'", "''").replace("&", "and").replace("<", "(").replace(">", ")")

    script = (
        "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null;"
        "$t = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02);"
        f"$n = $t.GetElementsByTagName('text'); $n.Item(0).AppendChild($t.CreateTextNode('{q(title)}')) | Out-Null;"
        f"$n.Item(1).AppendChild($t.CreateTextNode('{q(body)}')) | Out-Null;"
        "$id = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe';"
        "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($id).Show([Windows.UI.Notifications.ToastNotification]::new($t))"
    )
    toggles.run_ps(script, timeout=30)


def main(argv: list[str]) -> int:
    result = check()
    state_file = toggles.state_root() / "dashboard" / "watcher.json"
    state_file.parent.mkdir(parents=True, exist_ok=True)
    try:
        last = json.loads(state_file.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        last = {}
    sig = hashlib.sha1("\n".join(sorted(p.split(",")[0] for p in result["problems"])).encode()).hexdigest()
    due = sig != last.get("signature") or time.time() - float(last.get("notifiedAt") or 0) > REPEAT_HOURS * 3600
    result["signature"] = sig
    result["notifiedAt"] = last.get("notifiedAt") or 0
    if result["problems"] and (due or "--notify" in argv):
        toast("Workstation needs a look", " | ".join(result["problems"])[:240])
        result["notifiedAt"] = time.time()
    state_file.write_text(json.dumps(result, indent=2), encoding="utf-8")
    if "--print" in argv:
        print(json.dumps(result, indent=2))
    return 1 if result["problems"] else 0


def loop(argv: list[str]) -> int:
    i = argv.index("--loop")
    minutes = float(argv[i + 1]) if i + 1 < len(argv) else 15.0
    rest = argv[:i] + argv[i + 2:]
    while True:
        try:
            main(rest)
        except Exception:  # keep watching; the next round retries
            pass
        time.sleep(max(60.0, minutes * 60))


if __name__ == "__main__":
    if "--loop" in sys.argv[1:]:
        sys.exit(loop(sys.argv[1:]))
    sys.exit(main(sys.argv[1:]))
