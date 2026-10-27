# Local project dashboard

A page on this PC that reads the projects under the workstation projects root
(`active\` from `%LOCALAPPDATA%\Workstation\workstation.json`) and the Claude and
Cursor processes that are already running. It starts or stops things only
when you flip a toggle (see Toggles below). It does not start at sign-in: only the Dashboard shortcut starts it.

The Cursor worker health port is 8787. This page uses 8791.

## Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File workstation\dashboard\start-dashboard.ps1
```

Local: `http://127.0.0.1:8791/`

Away from home, the start script also listens on this PC's Tailscale address
and turns on Tailscale Serve when the tailnet allows it. Neither path is the
public internet. The script never turns on Tailscale Funnel and never binds
0.0.0.0. Localhost does not need the token.

**Phone (tailnet):** use the HTTPS MagicDNS link only
(`https://<pc>.ts.net/?token=...`). Opening that link sets an HttpOnly `dash`
cookie (`Secure; SameSite=Lax` on HTTPS) and redirects to `/` without the token, so
static files and API calls keep working. Plain `http://100.x:8791` is not the
supported phone bookmark (a `Secure` cookie would not stick on HTTP; the cookie
omits `Secure` only if somehow opened over plain HTTP). The start script writes
`%LOCALAPPDATA%\Workstation\dashboard\phone.url` as a Windows Internet
Shortcut, `phone-link.txt`, and (if `segno` or `qrcode` is installed) `phone-qr.png`.

A token for non-localhost requests is created in
`%LOCALAPPDATA%\Workstation\dashboard\`. Nothing in that folder is committed.

The page uses a light card layout: a dark top bar with a Refresh button and one jump link per
project, summary tiles, a Workstation card (toggles, Health, Process check, shortcuts), then one
card per project. Each project card shows branch, clean or dirty, CI, open pull
requests, last completed item, and task and blocker counts. Task text stays
collapsed until Show details is pressed. Inside, tap a task, blocker, warning or waiting row to
expand it: it shows the row's full text (the list shows the first 300 characters) and an
**Open on GitHub** link to the project's open-items file on `main`. The link jumps to the row's
line only when that project's checkout is on `main` with nothing unpushed; otherwise the local
line may not match `main`, so it opens the file's top. An expanded row stays open through the
15-second refresh.

**Hand a row to Claude, or answer a waiting question.** The dashboard never edits a repo itself.
An expanded row has **Hand to Claude** (with an optional note); a Waiting row has **Yes**, **No** and
a text box instead. After you confirm, the page starts a new background Claude Code session
(`claude --bg --name dashboard-<action>-<project> "<task>"`) in that project's folder under
`active\`. The task holds the row's full text (re-read from the file, not taken from the page),
your note or answer, and these orders: read the repo's agent guide and rules first and follow them,
work on a branch, run the checks, open one PR, never merge, and put `Dashboard item: <id>` in the
PR body. The card then shows "Claude started ..." and, once that PR is open, its link. The session
does the real work (for an answer: record it where that repo's rules say and update what it
affects). Output of the launch goes to `launch\` files in the dashboard's local folder (stdin
closed, no pipes), and the sessions started are listed in `sessions.json` there. Find a session
with `claude agents`; open it with `claude attach <id>`. Sessions start with your Claude Code
defaults, including its permission mode.

Actions are **off** unless this PC has `%LOCALAPPDATA%\Workstation\dashboard\settings.json`
with `{"writeActions": true, "ownerName": "<your name>"}`. That file is local only and never
committed; a PC without it shows "Actions are off on this PC." Every action request needs the
login (localhost, or the phone cookie/token), the `X-Workstation-Dashboard: 1` header the page
sends, and, when the browser sends an Origin, the same host. The older buttons (toggles, Health,
send) don't check that header yet; that's a later change.

Previews are a PDF first page, rendered
markdown, or a large png/jpg/webp. Icons and files that do not decode are
skipped. A thumbnail opens large and opens the file on this PC.

## Toggles

The top row has on/off switches (Remote, plus any from your local
`%LOCALAPPDATA%\Workstation\toggles.json`), a Health button per switch and a
Process check button. See `workstation\toggles\README.md` to add or remove one.
The Dashboard shortcut first pulls the workstation clone (fast-forward only; skipped with a warning when it
is not on main or has local changes) and restarts the server, so the page always runs the latest code. It opens the page and closes by itself; it stays open only when
there is a warning to read (for example, the tailnet firewall rule needs admin).

Test a branch without touching the running dashboard: set `DASHBOARD_PORT=8799`
and run `server.py` from that checkout.
