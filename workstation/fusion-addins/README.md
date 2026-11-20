# Install the Fusion add-in updater

This is the install README for the Fusion add-in updater. The updater is manual only (owner decision 2026-11-20): it runs when you start it, from the **Update Fusion add-ins** shortcut or the command below. No scheduled task, Startup item, or Run key runs it.

Fusion loads add-in code only when that add-in starts again (restart Fusion, or Stop then Run in the Shift+S dialog). This updater does not start or stop Fusion. When a clone moves forward, a Windows toast asks you to restart Fusion yourself.

The script is `workstation\fusion-addins\update-fusion-addins.ps1`. It reads directory junctions in `%APPDATA%\Autodesk\Autodesk Fusion 360\API\AddIns`, resolves each target to its git repo root, and fast-forwards that repo only when the tracked tree is clean, the current branch is the remote default, and the branch has an upstream. Untracked files stay. A dirty tree, another branch, a missing upstream, or a history that is not a fast-forward is skipped and written to the log. Logs: `%LOCALAPPDATA%\Workstation\logs\fusion-addins-update.log` and `fusion-addins-last.json`. `-Pause` keeps the window open at the end (the shortcut passes it).

`install.ps1` creates the **Update Fusion add-ins** shortcut in `shortcuts\` with the other manual links. It registers no task. An older install registered the per-user task `Workstation-UpdateFusionAddins` (logon and hourly); `install.ps1` and `uninstall.ps1` now remove that task when it runs `update-fusion-addins.ps1`, and say so. The plugin catalog does not register a task. `install-plugins.ps1` does not either. Workstation Status warns if a task of that name exists, and reports any repo the last run skipped as dirty or left behind.

If the `cd` line errors, this clone is not in one of the usual `active` folders. Open the folder that contains `install.ps1` and continue from there.

## 1. Installer

**Terminal:** Windows PowerShell 5.1, or double-click `install.cmd` in this repo. **Mode:** normal window, not admin. **Folder:** any folder, then the `cd` line below.

`install.cmd` changes to this repo and runs `install.ps1`. A real run makes the shortcut and removes an old task. A dry run only reports.

```powershell
cd ((Get-ChildItem -Path @((Join-Path $env:USERPROFILE 'projects\active'),(Join-Path $env:USERPROFILE 'Projects\active'),(Join-Path $env:SystemDrive 'projects\active')) -Filter workstation -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'install.ps1') } | Select-Object -First 1).FullName)
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Dry run (says whether it would remove an old task, changes nothing):

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo, after the `cd` line.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -WhatIf
```

Uninstall removes the shortcut install made, and an old task if one is left.

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo, after the `cd` line.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

## 2. Commands

One command per block. Run the `cd` line first. The second command updates the clones once, now. The third is the full install (shortcut, old task removed).

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** any folder.

```powershell
cd ((Get-ChildItem -Path @((Join-Path $env:USERPROFILE 'projects\active'),(Join-Path $env:USERPROFILE 'Projects\active'),(Join-Path $env:SystemDrive 'projects\active')) -Filter workstation -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'install.ps1') } | Select-Object -First 1).FullName)
```

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\workstation\fusion-addins\update-fusion-addins.ps1
```

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

## 3. Agent prompt

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** any folder, then the workstation clone.

Paste this to an agent. It should run the installer, then stop. It should not restart Fusion.

```text
Set up the manual Fusion add-in updater on this PC. Do not edit the workstation repo. Do not restart Fusion and do not stop or start add-ins. Do not create a scheduled task: the updater is manual only. Use a normal Windows PowerShell 5.1 window, not admin. From any folder, run this cd line, then the installer: cd ((Get-ChildItem -Path @((Join-Path $env:USERPROFILE 'projects\active'),(Join-Path $env:USERPROFILE 'Projects\active'),(Join-Path $env:SystemDrive 'projects\active')) -Filter workstation -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'install.ps1') } | Select-Object -First 1).FullName) and then powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1. That makes the Update Fusion add-ins shortcut in shortcuts\ and removes an old per-user task Workstation-UpdateFusionAddins if one is left. The shortcut runs workstation\fusion-addins\update-fusion-addins.ps1 -Pause. It fast-forwards Fusion add-in clones found from AddIns junctions and skips a dirty tree, a non-default branch, or a branch with no upstream. It does not restart Fusion. A toast means I restart Fusion myself. To undo the install, from this repo run powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1.
```

An agent was not asked to paste this prompt on a PC. The installer command inside it is the one in section 1.

## 4. Manual steps

These steps run the updater without `install.ps1`, and remove an old task by hand. No admin. They do not restart Fusion.

1. Open Windows PowerShell 5.1. Do not choose Run as administrator.
2. Go to the workstation clone (the folder that contains `install.ps1`).

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** any folder.

```powershell
cd ((Get-ChildItem -Path @((Join-Path $env:USERPROFILE 'projects\active'),(Join-Path $env:USERPROFILE 'Projects\active'),(Join-Path $env:SystemDrive 'projects\active')) -Filter workstation -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'install.ps1') } | Select-Object -First 1).FullName)
```

3. Update the clones once, now:

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\workstation\fusion-addins\update-fusion-addins.ps1
```

4. When a toast says add-ins were updated, restart Fusion yourself (or Stop then Run each add-in in Shift+S).
5. If an older install left the task `Workstation-UpdateFusionAddins`, remove it (no admin). `install.ps1` does the same.

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** any folder.

```powershell
Unregister-ScheduledTask -TaskName 'Workstation-UpdateFusionAddins' -Confirm:$false
```

6. Confirm in Workstation Status (`workstation\health\workstation-status.ps1`) that the Fusion line says manual only. A repo with uncommitted tracked changes is reported as skipped (dirty). A repo that could not fast-forward is reported as left behind.

## What this does not do

- Does not run on a schedule, at sign-in, or in the background.
- Does not restart Fusion or reload add-ins.
- Does not register a task at clone time, from the plugin catalog, from `install-plugins.ps1`, or from `install.ps1`.
- Does not reset, stash, clean, force-push, or delete untracked files.
- Does not update a repo that is dirty, not on the default branch, or missing an upstream.
