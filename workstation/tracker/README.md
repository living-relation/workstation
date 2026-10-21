# Live task tracker

A read-only window (about 560x820, resizable, dark, large type, pinned on top by default) that shows a bot's current
jobs: the title, a big "X of Y done" job count with "N of M subtasks done" under it, a progress bar, then one
3D "bubble" card per job (rounded, gradient, drop shadow, top highlight, left accent strip in the bot's color).
Each card has a status dot in the bot's color (ring = pending, half = in progress, filled = done, orange = blocked),
the title and note, and when the job has subtasks a progress bar, "X of Y" and a collapsible **Subtasks** expander
(collapsed by default; expand state kept per job id in `settings.json` for the session). The bot's own jobs are
grouped by `group`; jobs with an `owner` come after a blue divider under **Delegated**, by owner.

The only controls are drag (title bar), pin toggle (always on top on/off), minimize, close (X) and the subtask expanders. (Minimize was kept although the spec only named drag/pin/close.) Pin state and
window position are remembered in `settings.json`. Clicking a task, or a bot's header under Delegated, opens that
bot's chat in the Grok Bot app (`grokbot://app/v1/agent?id=<agentId>`); if the `grokbot://` scheme is not
registered, or there is no valid agentId (must be a GUID; all-zero placeholders count as missing), it just focuses the
Grok Bot app (process name `Grok Bot`). When every task is done it shows "All done" and
closes itself after a minute.

There is no shortcut, Startup link or logon watcher. Bots open it on demand with `-Show`. Single instance (named
mutex): if it's already open, `-Show` refreshes it and brings it to the front without taking focus. While open it
live-refreshes whenever `tracker.json` changes, without moving, restoring or raising itself; only `-Show` brings it
to the front. Set `WORKSTATION_TRACKER_DIR` to use another data folder (for testing). PowerShell 5.1 + WPF only; no new dependencies.

## Commands for bots

`<ws>` is the workstation clone (normally `<Projects>\active\workstation`). Every write is atomic (temp file, then replace).

```powershell
$t = '<ws>\workstation\tracker\tracker.ps1'
# Replace the whole list and show the window (JSON from a file, or pipe it on stdin):
powershell -NoProfile -ExecutionPolicy Bypass -File $t -Set -Path plan.json -Show
Get-Content plan.json | powershell -NoProfile -ExecutionPolicy Bypass -File $t -Set -Show
# Add, update, remove one task:
powershell -NoProfile -ExecutionPolicy Bypass -File $t -Add -Id t4 -Title 'Fix the installer' -Group 'Repo' -Status pending
powershell -NoProfile -ExecutionPolicy Bypass -File $t -Add -Id d1 -Title 'Review PRs' -Owner 'Review Bot' -Status in_progress
powershell -NoProfile -ExecutionPolicy Bypass -File $t -Update -Id t4 -Status done -Note 'merged #12'
powershell -NoProfile -ExecutionPolicy Bypass -File $t -Remove -Id t4
# Subtasks (a job's status is derived from its subtasks when it has any):
powershell -NoProfile -ExecutionPolicy Bypass -File $t -AddSub -Job t4 -Id s1 -Title 'Write tests'
powershell -NoProfile -ExecutionPolicy Bypass -File $t -UpdateSub -Job t4 -Id s1 -Status done -Note '12 pass'
# Title only, show only, clear:
powershell -NoProfile -ExecutionPolicy Bypass -File $t -ListTitle 'Today'
powershell -NoProfile -ExecutionPolicy Bypass -File $t -Show
powershell -NoProfile -ExecutionPolicy Bypass -File $t -Clear
```

`-Update` changes only the fields you pass (`-Status -Note -Title -Group -Owner -AgentId`). `-Add`/`-AddSub` without
`-Id` pick the next free `tN`/`sN`. `-Set` without `-Path` and without piped JSON fails instead of waiting.

## Runtime files (`%LOCALAPPDATA%\Workstation\tracker\`, never in the clone)

| File | Purpose |
|---|---|
| `README.txt` | Names this repo as the owner of the folder |
| `tracker.json` | The task list (schema below) |
| `bots.json` | Bot name -> agentId map, used when a task has no `agentId` (starts as `{}`; `bots.example.json` only shows the format) |
| `settings.json` | `{pinned, left, top, width, height}` |
| `show.signal` | Written by `-Show` to bring an open window to the front; the window deletes it as an ack (and cancels any pending auto-close). If the window exits instead, `-Show` starts a new one |

### tracker.json schema

```json
{
  "title": "Today",
  "updated": "2026-10-21T16:20:00-04:00",
  "tasks": [
    { "id": "t1", "title": "Delete old copies", "group": "Cleanup", "status": "done", "note": "zip removed" },
    { "id": "t2", "title": "Fix installer", "group": "Repo", "note": "",
      "subtasks": [ { "id": "s1", "title": "Patch script", "status": "done", "note": "" },
                    { "id": "s2", "title": "Re-test", "status": "in_progress", "note": "" } ] },
    { "id": "d1", "title": "Review PRs", "owner": "Review Bot", "agentId": "<agent id>", "status": "blocked", "note": "waiting on #10" }
  ]
}
```

- `status`: `pending` | `in_progress` | `done` | `blocked` (jobs with `subtasks` derive it: all done = done, any
  blocked = blocked, any started = in_progress, else pending). Flat tasks without subtasks still work.
- `subtasks` (optional): `[{id, title, status, note}]`. A job with subtasks takes its status from them, except an explicit job `status: blocked`, which always wins.
- Top-level `owner` (optional): who owns the un-delegated jobs (default `Grok Bot`); used for their label, color and chat link.
- `group` (optional, default `General`): heading for the bot's own tasks.
- `owner` (optional): the bot a task is delegated to; such tasks appear under Delegated, by owner.
- `agentId` (optional): Grok Bot agent id whose chat opens on click. Without it, the window looks up the owner
  (or `Grok Bot` for own tasks) in `bots.json`.

### bots.json

Agent ids are account-specific, so the repo ships only `bots.example.json`; each machine keeps its real map in
runtime state. Each value is an agent id string or `{ "agentId": "<GUID>", "color": "#RRGGBB" }`:
`{ "Grok Bot": { "agentId": "<GUID>", "color": "#4C8DFF" }, "Helper Bot": "<GUID>" }`. Without a color a bot gets
a default (Grok Bot blue) or a stable color from a fallback palette.
