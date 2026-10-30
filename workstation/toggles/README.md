# Dashboard toggles, health checks and the watcher

The top row of the dashboard is a row of switches. Each switch turns something on or off,
has a **Health** button that works only while it is on, and the row ends with a
**Process check** button. The same commands run from shortcuts (`toggle.ps1`) when the
dashboard is not open, and from the background watcher.

## Where toggles come from

| File | What | Committed |
|---|---|---|
| `toggles.json` (this folder) | package toggles: **Remote** (Desktop Commander Remote + Claude remote control + Cursor workers) | yes |
| `%LOCALAPPDATA%\Workstation\toggles.json` | this PC's own toggles and process-check settings | never |

A local entry with the same `id` replaces a package one; `"hidden": true` hides it.
Project-specific toggles (for example a web app you host) go only in the local file.

## Add a toggle

Add an entry to `%LOCALAPPDATA%\Workstation\toggles.json` and reload the dashboard. No restart needed.

```json
{
  "toggles": [
    {
      "id": "my-app",
      "name": "My app",
      "start": "Start-ScheduledTask -TaskName 'My app autostart'",
      "stop": "& '{toolkit}\\toggles\\stop-port.ps1' -Port 5173,8080",
      "status": "& '{toolkit}\\toggles\\check-http.ps1' -Port 5173 -ListenOnly",
      "health": "& '{toolkit}\\toggles\\check-http.ps1' -Port 5173 -Tailscale"
    }
  ]
}
```

- Every command is a PowerShell command line. `{toolkit}` is this repo's `workstation\` folder.
- `status` and `health` exit 0 for on / healthy. Lines starting `FAIL` are shown in the warning toast.
- Helpers: `check-http.ps1` (port listening, HTTP 200 on localhost and optionally the Tailscale IP),
  `stop-port.ps1` (stops the console tree that owns a port, nothing else).
- Remove a toggle: delete its entry (or set `"hidden": true` for a package one).
- Full example: `toggles.local.example.json`.

## Process check

Shows `node.exe` processes and RAM by owning app (Claude, Cursor, ...) for information, lists orphaned
process trees (their parent process is gone) and duplicate MCP/server processes. A problem (and a watcher
warning) is an orphan that is not expected; the node count alone never warns. Orphans that are normal
because a hidden launcher exits on purpose are listed under `expected`, with how many copies are fine:

```json
{ "processCheck": { "expected": [ { "match": "launch-my-app\\.bat", "max": 1 } ] } }
```

Built-in expected orphans (max 1 copy each; a second copy is flagged):
- Desktop Commander Remote
- Kapture MCP (`kapture-mcp` … `dist/index.js`; the bridge starts this detached so sessions share it)

A `claude -p` (or `claude --print`) job whose cmd/PowerShell launcher has already exited is reported as
**background job running**, not as an orphan. It is only a problem if it has been running longer than
`backgroundJobMaxAgeHours` (default 2; set it in the local file next to `expected`).

Desktop Commander MCP copies are duplicates only when two of them sit under the same Claude window.
One copy per Claude window is fine. Other MCP servers are still counted across the whole PC.

## Shortcuts and CLI

`toggle.ps1 -Id <id> -Action on|off|status|health`, `toggle.ps1 -Action process-check`.
The installer adds **Remote On**, **Remote Off**, **Process Check**, **Watcher On** and **Watcher Off** shortcuts; the existing
Workers and Desktop Commander shortcuts keep working and run the same scripts.

## Watcher

Off by default and manual only (no scheduled task). The **Watcher On** shortcut (`watcher.ps1 -Action on`)
starts `watcher.py --loop 15` hidden: every 15 minutes it health-checks the toggles that are on,
runs the process check and shows a Windows toast when something is wrong. The same problems are not
repeated for 4 hours. Last result: `%LOCALAPPDATA%\Workstation\dashboard\watcher.json`.
Stop it with the **Watcher Off** shortcut (`watcher.ps1 -Action off`); sign-out stops it too. Watcher Off also removes the old Workstation-Watcher task an older install may have left.

## Access

Toggles always run on the PC that runs the dashboard: the server runs the command, so flipping one from
the phone over Tailscale does exactly what flipping it at the PC does. Toggles use the dashboard's existing auth: localhost needs no token, the tailnet address needs the
dashboard token. Toggles only run commands from the two config files, never from the request.
