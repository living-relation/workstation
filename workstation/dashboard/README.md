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

**Answer a waiting question on the card.** An expanded Waiting row has Yes, No and a text box.
After you confirm, the dashboard opens a PR in that project's repo and shows its link on the card;
it never merges. It clones the project's GitHub `main` into a throwaway folder under
`%LOCALAPPDATA%\Workstation\dashboard\work\` (never your checkout under `active\`), gives the clone
the same commit hooks your checkout uses, appends `**<name> <date>:** <answer>` to that one row of
the open-items file (the last table cell, or the end of a bullet), commits, pushes a
`dashboard/answer-*` branch, opens the PR and deletes the clone. The row is found on `main` by its
text, so moved lines are fine; if the row's words changed, nothing is written and the page says to
refresh. Moving the answer into a decisions file is left to that repo's own agent and rules.
Answers sent from the page are listed in `answers.json` in the same local folder.

Write actions are **off** unless this PC has `%LOCALAPPDATA%\Workstation\dashboard\settings.json`
with `{"writeActions": true, "ownerName": "<your name>"}`. That file is local only and never
committed; a PC without it shows "Answering is off on this PC." Every write request needs the
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
