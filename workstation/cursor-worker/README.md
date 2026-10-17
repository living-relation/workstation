# Cursor "this PC" worker

Keeps `agent worker` running so Cursor surfaces (cursor.com/agents, desktop, mobile) can start agent sessions on this PC.
Pick this PC under My Machines; it is listed under the PC's host name (`$WorkerName` in `config.ps1`).

## How projects are found
- Cursor matches a request to a folder by its **git remote**. `Projects` itself has no remote and is not a repo (by design).
- So the worker registers every `active\<project>` folder that is a git repo **with an `origin` remote** (plus `Projects` as the root).
- Projects without a git remote cannot be targeted; plain folders stay local-only, which is fine. If a project later gets an `origin` remote (the user's decision), click **Workers Stop** and **Workers Start** so the worker registers it (this ends any running session).
- New projects follow the same rule. Only `active\` is scanned.

## Files
- `config.ps1` - name, folder, health port (8787), project discovery, paths
- `run-worker.ps1` - supervisor; restarts the worker whenever it exits
- `health-check.ps1` - manual only (its scheduled task was removed 2026-10-07); exits at once if the stop flag exists, otherwise: checks `/healthz`; revives the supervisor; restarts after 2 failed checks; restarts (when idle) if the project list changed
- `repair-sqlite.ps1` - fixes the Cursor CLI Windows bug (`better-sqlite3` built for the wrong Node). Runs before every worker start, so it self-heals after `agent update`
- `install.ps1` - retired 2026-10-07 (it created the logon start and scheduled tasks); not shipped
- `%LOCALAPPDATA%\Workstation\cursor-worker\logs\` - `worker.log`, `supervisor.log`, `health.log` (plus `state\` and `sqlite-cache\` there; nothing is written into the repo clone)

## Start and stop (manual)
- No logon start and no scheduled tasks anymore: the Run entry `CursorWorker` and the tasks `Cursor-Worker` / `Cursor-Worker-Health` were removed 2026-10-07.
- **Workers Start** (in the workstation repo's `shortcuts\` folder) starts the supervisor hidden; **Workers Stop** stops the supervisor and `agent worker`; **Workstation Status** shows both and `/healthz`.
- Stop flag: while `%LOCALAPPDATA%\Workstation\workers-stopped.flag` exists (written by the **Workers Stop** shortcut, removed by **Workers Start**), `health-check.ps1` exits at once and revives nothing.

## Status
```powershell
Invoke-WebRequest http://127.0.0.1:8787/readyz -UseBasicParsing | Select-Object -ExpandProperty Content
Get-Content $env:LOCALAPPDATA\Workstation\cursor-worker\logs\health.log -Tail 10
```
`/readyz` returns 503 with `"claimed":true` while a session is running. That is normal.

## Gotchas
- Runs only while the Windows user who owns `<Projects>` and the Cursor login is logged in (Cursor login lives in that profile). After a reboot, log in and click **Workers Start**.
- A supervisor started by **Workers Start** can be stopped with **Workers Stop**. (The old task-launched copies hid their command line and could only be stopped through their task or an elevated shell.)
- `repair-sqlite.ps1` edits files inside `%LOCALAPPDATA%\cursor-agent\versions\...`; the original is saved as `better_sqlite3.node.orig`.
- Cloud sessions assume Linux paths (`/home/ubuntu/...`); Cursor logs a harmless-looking read error on Windows. Watch for real failures in `worker.log`.

## Decisions (user, 2026-10-05)
- `Projects` stays a plain folder, not a git repo.
- Projects root is the global root; every project under `active\` should be reachable.
