# Live task tracker

A window (about 450x670, resizable, dark, pinned on top by default) that shows a bot's current jobs: the
title, an "X of Y done" job count with "N of M subtasks done" under it, a progress bar, a small **Clear finished**
button, then one small card per job (rounded, gradient, light shadow, left accent strip in the bot's color).
Each card has a status dot in the bot's color (ring = pending, half = in progress, filled = done, orange = blocked),
the title, the note and, when the job has subtasks, a chevron and "done/total". Cards start collapsed: subtasks show
only after you click the chevron (expand state kept per job id in the registry). Finished jobs and finished
subtasks are dimmed and crossed off. The top level should hold only the main jobs the user gave; related or
follow-on work goes in that job's `subtasks`. The bot's own jobs are grouped by `group`; jobs with an `owner` come
under the **Delegated** header (blue line under it), by owner.

Controls: drag (title bar), pin toggle (always on top on/off), minimize, close (X), the chevrons, and **Clear
finished**. The window is a read-only status board: it never creates or writes any file. Clear finished only
hides the done jobs in this window; `tracker.json` is not changed. A hidden job comes back when it changes in the
list or the window restarts. After Clear finished, the "X of Y done" count covers only the jobs still shown (hidden done jobs are left out). Done subtasks under open jobs stay, crossed off. Pin state, window position and size,
and expanded jobs are kept in the registry (`HKCU\Software\Workstation\Tracker`; expanded job ids as a REG_MULTI_SZ `Expanded` value, an older comma-joined string is still read). Cards are not links; clicking one opens nothing. When every task is done it shows "All done" and
closes itself after a minute, unless a `-Show` asked for it while everything was done (it then stays open until you close it or the list has open jobs again).

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

`-Update` changes only the fields you pass (`-Status -Note -Title -Group -Owner`). `-Add`/`-AddSub` without
`-Id` pick the next free `tN`/`sN`. `-Set` without `-Path` and without piped JSON fails instead of waiting.

## Runtime files (`%LOCALAPPDATA%\Workstation\tracker\`, never in the clone)

| File | Purpose |
|---|---|
| `README.txt` | Names this repo as the owner of the folder |
| `tracker.json` | The task list (schema below) |
| `bots.json` | Optional owner name -> color map (starts as `{}`) |
| `settings.json` | Old versions only: if present and the registry key does not exist yet, the window reads it once to migrate pin/position/size/expanded into the registry; the file is never changed |
| (registry) `HKCU\Software\Workstation\Tracker` | Window state: `Pinned` (DWORD), `Left`, `Top`, `Width`, `Height`, `Expanded` (comma-separated job ids). A test data folder (`WORKSTATION_TRACKER_DIR`) uses a `test-<sha1>` subkey |
| (named event) `Local\WorkstationTrackerShow[-<sha1>]` | `-Show` sets it to bring an open window to the front and cancel any pending auto-close; if the window exits instead, `-Show` starts a new one. The `-<sha1>` suffix matches the window mutex for a test data folder. tracker.ps1's own writes hold the named mutex `Local\WorkstationTrackerWrite[-<sha1>]` |

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
    { "id": "d1", "title": "Review PRs", "owner": "Review Bot", "status": "blocked", "note": "waiting on #10" }
  ]
}
```

- `status`: `pending` | `in_progress` | `done` | `blocked` (jobs with `subtasks` derive it: all done = done, any
  blocked = blocked, any started = in_progress, else pending). Flat tasks without subtasks still work.
- `subtasks` (optional): `[{id, title, status, note}]`. A job with subtasks takes its status from them, except an explicit job `status: blocked`, which always wins.
- Top-level `owner` (optional): who owns the un-delegated jobs (default `Me`); used for their label and color.
- `group` (optional, default `General`): heading for the bot's own tasks.
- `owner` (optional): the bot a task is delegated to; such tasks appear under Delegated, by owner.

### bots.json

Optional colors per owner: `{ "Me": "#4C8DFF", "Helper": { "color": "#3FB950" } }`. Without a color an owner
gets a default (`Me` blue) or a stable color from a fallback palette.
