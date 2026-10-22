# Local project dashboard

A page on this PC that reads the projects under the workstation projects root
(`active\` from `%LOCALAPPDATA%\Workstation\workstation.json`) and the Claude and
Cursor processes that are already running. It does not start or stop
those workers. It does not start at sign-in: only the Dashboard shortcut starts it.

The Cursor worker health port is 8787. This page uses 8791.

## Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File workstation\dashboard\start-dashboard.ps1
```

Local: `http://127.0.0.1:8791/`

Away from home, the start script also listens on this PC's Tailscale address
and turns on Tailscale Serve when the tailnet allows it. Neither path is the
public internet. The script never turns on Tailscale Funnel and never binds
0.0.0.0. Localhost does not need the token. The tailnet address does.

A token for non-localhost requests is created in
`%LOCALAPPDATA%\Workstation\dashboard\`. Nothing in that folder is committed.

The board is one row per project: branch, clean or dirty, CI, open pull
requests, last completed item, and task and blocker counts. Task text stays
collapsed until the row is opened. Previews are a PDF first page, rendered
markdown, or a large png/jpg/webp. Icons and files that do not decode are
skipped. A thumbnail opens large and opens the file on this PC.
