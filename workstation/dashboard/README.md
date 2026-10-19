# Local project dashboard

A page on this PC that reads the projects under the workstation projects root
(`active\` from `%LOCALAPPDATA%\Workstation\workstation.json`) and the Claude,
Cursor, and Grok processes that are already running. It does not start or stop
those workers.

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

## Send

A reply is posted only by a real CLI resume:

- Claude and Claude Dispatch sessions: `claude --resume <session-id> -p`
- Cursor chats: `agent --resume <chat-id> -p --mode ask`, and only when
  `agent status` says the CLI is logged in
- Grok: no send. The button focuses the Grok Bot window

A session that is already running is not resumed, because that starts a second
copy. There is no allow/deny command, so permission prompts are shown and not
answered from the page.
