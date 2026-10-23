---
name: deploy-project-watcher
description: Add a project to the owner's shared session watcher (phone alerts when a Claude session needs him, stalls, or a PR finishes). Use when the owner says "add a watcher to <project>", "watch this project", "deploy the watcher", or "update all watchers". Creates the project's untracked _watch folder, registers it with the shared engine in <projects>\_tools, makes the two shortcuts, and gives the ntfy topic with setup steps.
---

# Deploy the project watcher

The engine is shared and already installed in `<projects>\_tools\` (`watcher.py`, `watch_gui.py`, `watch-*.ps1`, `watch-VERSION`, `watch-README.md`, registry `watch-projects.json`). One process serves every registered project; one ntfy topic serves all. This skill only adds a project to it. Never copy engine code into a project or into a repo.

Follow `<projects>\AGENTS.md`: no new root folders, never commit watcher data.

`<projects>` is this PC's projects root (the folder that holds `active\`), for example `C:\projects`.

## Deploy a project

1. **Ask the owner (plain words, one message):** which project (folder under `<projects>\active\`), and where the shortcuts go (default `<projects>\_tools`). If he already named them, do not ask again. Use the project's folder name as the display name unless he gives one (short, e.g. `ST185`).
2. **Check first:** the project folder exists; the name is not already in `python <projects>\_tools\watcher.py --projects` (if it is, this is a repair, not a new deploy); `python` and `pythonw` are on PATH.
3. **Create the data folder:** `<project>\_watch\`. Put in it a `README.txt` ("Session watcher data. Local only: never commit or push. Do NOT run `git clean -x` or `git clean -fdx` in this repo: it deletes this folder.") and a `VERSION` file holding the contents of `<projects>\_tools\watch-VERSION`. A `config.json` of `{}` is enough: defaults come from the engine, including the shared ntfy topic. Do not write a topic into it. Leave `stray_check` off (it is on for one project only; check the registry).
4. **Exclude it from git, locally only** (skip if the project is not a git repo):
   - append `_watch/` to `<project>\.git\info\exclude` (never `.gitignore`), with a comment line saying never to run `git clean -x`;
   - verify: `git -C <project> check-ignore -v _watch/state.json` must print the exclude rule, and `git -C <project> status --short` must not list `_watch`. If either fails, stop and fix before continuing.
   - For a git worktree, the exclude lives in the main repo's `.git\info\exclude`.
5. **Register with the engine:** `python <projects>\_tools\watcher.py --register --name <Name> --path <project>` (this also creates `_watch` if missing).
6. **Make the shortcuts:** `powershell -File <projects>\_tools\watch-make-shortcuts.ps1 -ProjectName <Name> -Dir <shortcut folder>` creates `<Name> Watch.lnk` (window) and `<Name> Watch Status.lnk` (read-only popup). Shortcuts live only in the chosen folder, never on the Desktop.
7. **Check the logon task exists:** `Get-ScheduledTask ClaudeSessionWatcher`. If missing, run `<projects>\_tools\watch-register-logon-task.ps1`.
8. **Add the first task if the owner has one:** `watch-add.ps1 -ProjectName <Name> -Id <task> -Repo <path> [-Worktree ..] [-Card ..] [-Branch ..]`. This also starts the engine. With no task the engine stays off until one is added.
9. **Verify:** `watch-status.ps1 -ProjectName <Name>` prints a state line (`READY` with no tasks, `RUNNING` with one). If it prints ERROR, read `<projects>\_tools\watch-engine.log`.
10. **Save a memory note** for the project (project `INDEX.md` line, signed) saying the watcher is deployed and under which name. Memory is never committed.

## What to tell the owner at the end

Give the ntfy topic in a code block, then exactly three setup steps:

```
<the shared ntfy topic: read it from the engine's defaults in <projects>\_tools\watch-README.md; never write it into a repo>
```

1. Install the **ntfy** app on your phone (skip if already done for another project).
2. In ntfy, subscribe to the topic above on server `ntfy.sh`. It is the same topic for every project; alerts start with the project name.
3. Open `<shortcut folder>\<Name> Watch.lnk`, pick the project at the top, and press **Test alert**. A push should reach the phone.

Also list in the report: the paths created, the exclude check result, and anything not verified.

## Update all watchers

The engine code is shared, so updating it updates every project at once. Offer this when `<projects>\_tools\watch-VERSION` differs from a project's `_watch\VERSION`:

1. List each registered project (`watcher.py --projects`) with its `_watch\VERSION` next to the master version, and ask which to update (default: all).
2. Per project: confirm the exclude still works (step 4 check), write the master version into `_watch\VERSION`, and re-run `watch-make-shortcuts.ps1` so the shortcuts point at the current files.
3. Run `python <projects>\_tools\watcher_test.py` once. Then restart the engine once: `python <projects>\_tools\watcher.py --stop` followed by `watch-start.ps1 -Force`.
4. Verify with `watch-status.ps1 -ProjectName <Name>` for each project; report any that are not RUNNING or READY.
5. Do not touch a project's `config.json`, `watch.json` or `state.json` during an update. If a new version needs a config key, the engine defaults cover it.

## Rules

- Never commit, push or stage anything in `_watch\`. Never run `git clean -x` or `-fdx`.
- Never create a second ntfy topic or a second engine.
- Remove a project: `watcher.py --unregister <Name>`, delete its two shortcuts, and only delete `<project>\_watch\` if the owner asks.
