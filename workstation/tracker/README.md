# Live task tracker

A small read-only window (about 320x400, dark, pinned on top by default) that shows a bot's current task list:
the title, an "X of Y done" count, a progress bar, and the tasks grouped by `group`, with tasks that have an
`owner` listed under **Delegated**, by owner. Icons: check = done, blue dot = in progress, warning = blocked,
empty box = pending. The note shows in small text under each task.

The only controls are drag (title bar), pin toggle (always on top on/off), minimize and close (X). Pin state and
window position are remembered in `settings.json`. Clicking a task, or a bot's header under Delegated, opens that
bot's chat in the Grok Bot app (`grokbot://app/v1/agent?id=<agentId>`); if the `grokbot://` scheme is not
registered or has no agentId, it just focuses the Grok Bot app. When every task is done it shows "All done" and
hides itself after a minute.

There is no shortcut, Startup link or logon watcher. Bots open it on demand with `-Show`. Single instance (named
mutex): if it's already open, `-Show` refreshes it and brings it to the front without taking focus. While open it
live-refreshes whenever `tracker.json` changes. PowerShell 5.1 + WPF only; no new dependencies.

## Commands for bots

`<ws>` is the workstation clone (normally `<Projects>\active\workstation`). Every write is atomic (temp file, then replace).

```powershell
$t = '<ws>\workstation\tracker\tracker.ps1'
# Replace the whole list and show the window (JSON from a file, or pipe it on stdin):
powershell -NoProfile -ExecutionPolicy Bypass -File $t -Set -Path plan.json -Show
Get-Content plan.json | powershell -NoProfile -ExecutionPolicy Bypass -File $t -Set -Show
# Add, update, remove one task:
powershell -NoProfile -ExecutionPolicy Bypass -File $t -Add -Id t4 -Title 'Fix the installer' -Group 'Repo' -Status pending
powershell -NoProfile -ExecutionPolicy Bypass -File $t -Add -Id d1 -Title 'Review PRs' -Owner 'Skill Expert' -Status in_progress
powershell -NoProfile -ExecutionPolicy Bypass -File $t -Update -Id t4 -Status done -Note 'merged #12'
powershell -NoProfile -ExecutionPolicy Bypass -File $t -Remove -Id t4
# Title only, show only, clear:
powershell -NoProfile -ExecutionPolicy Bypass -File $t -ListTitle 'Today'
powershell -NoProfile -ExecutionPolicy Bypass -File $t -Show
powershell -NoProfile -ExecutionPolicy Bypass -File $t -Clear
```

`-Update` changes only the fields you pass (`-Status -Note -Title -Group -Owner -AgentId`).

## Runtime files (`%LOCALAPPDATA%\Workstation\tracker\`, never in the clone)

| File | Purpose |
|---|---|
| `README.txt` | Names this repo as the owner of the folder |
| `tracker.json` | The task list (schema below) |
| `bots.json` | Bot name -> agentId map, used when a task has no `agentId` (seeded from `bots.example.json`) |
| `settings.json` | `{pinned, left, top, width, height}` |
| `show.signal` | Touched by `-Show` to bring an open window to the front |

### tracker.json schema

```json
{
  "title": "Today",
  "updated": "2026-10-21T16:20:00-04:00",
  "tasks": [
    { "id": "t1", "title": "Delete old copies", "group": "Cleanup", "status": "done", "note": "zip removed" },
    { "id": "t2", "title": "Fix installer", "group": "Repo", "status": "in_progress", "note": "" },
    { "id": "d1", "title": "Review PRs", "owner": "Skill Expert", "agentId": "<agent id>", "status": "blocked", "note": "waiting on #10" }
  ]
}
```

- `status`: `pending` | `in_progress` | `done` | `blocked`
- `group` (optional, default `General`): heading for the bot's own tasks.
- `owner` (optional): the bot a task is delegated to; such tasks appear under Delegated, by owner.
- `agentId` (optional): Grok Bot agent id whose chat opens on click. Without it, the window looks up the owner
  (or `Grok Bot` for own tasks) in `bots.json`.

### bots.json

Agent ids are account-specific, so the repo ships only `bots.example.json`; each machine keeps its real map in
runtime state: `{ "Grok Bot": "<agent id>", "Other Bot": "<agent id>" }`.
