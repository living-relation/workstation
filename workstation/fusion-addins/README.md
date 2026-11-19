# Install the Fusion add-in updater

This is the install README for the Fusion add-in updater.

Fusion loads add-in code only when that add-in starts again (restart Fusion, or Stop then Run in the Shift+S dialog). This updater does not start or stop Fusion. When a clone moves forward, a Windows toast asks you to restart Fusion yourself.

The script is `workstation\fusion-addins\update-fusion-addins.ps1`. It reads directory junctions in `%APPDATA%\Autodesk\Autodesk Fusion 360\API\AddIns`, resolves each target to its git repo root, and fast-forwards that repo only when the tracked tree is clean, the current branch is the remote default, and the branch has an upstream. Untracked files stay. A dirty tree, another branch, a missing upstream, or a history that is not a fast-forward is skipped and written to the log. Logs: `%LOCALAPPDATA%\Workstation\logs\fusion-addins-update.log` and `fusion-addins-last.json`.

Nothing registers the task until you or an agent run the installer below, or the manual command in section 4. Cloning the repo does not register it. The plugin catalog does not register it. `install-plugins.ps1` does not register it.

The task name is `Workstation-UpdateFusionAddins`. It is per-user (no admin), the window is hidden, and it runs at logon and every 60 minutes. Workstation Status reports whether the task is present, the last run result, and any repo skipped as dirty or left behind.

If the `cd` line errors, this clone is not in one of the usual `active` folders. Open the folder that contains `install.ps1` and continue from there.

## 1. Installer

**Terminal:** Windows PowerShell 5.1, or double-click `install.cmd` in this repo. **Mode:** normal window, not admin. **Folder:** any folder, then the `cd` line below.

`install.cmd` changes to this repo and runs `install.ps1`. A real run registers the task. A dry run does not.

```powershell
cd ((Get-ChildItem -Path @((Join-Path $env:USERPROFILE 'projects\active'),(Join-Path $env:USERPROFILE 'Projects\active'),(Join-Path $env:SystemDrive 'projects\active')) -Filter workstation -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'install.ps1') } | Select-Object -First 1).FullName)
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Dry run (prints the task it would register, registers nothing):

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo, after the `cd` line.

```powershell
cd ((Get-ChildItem -Path @((Join-Path $env:USERPROFILE 'projects\active'),(Join-Path $env:USERPROFILE 'Projects\active'),(Join-Path $env:SystemDrive 'projects\active')) -Filter workstation -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'install.ps1') } | Select-Object -First 1).FullName)
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -WhatIf
```

To remove the task later, run uninstall from this repo. It removes the task only when the install manifest lists it.

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo, after the `cd` line.

```powershell
cd ((Get-ChildItem -Path @((Join-Path $env:USERPROFILE 'projects\active'),(Join-Path $env:USERPROFILE 'Projects\active'),(Join-Path $env:SystemDrive 'projects\active')) -Filter workstation -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'install.ps1') } | Select-Object -First 1).FullName)
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

## 2. Commands

One command per block. Run the `cd` line first. The first command registers the task (with the rest of workstation install). The second is a dry run. The third updates once now, with no schedule. The fourth removes what install recorded, including the task.

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** any folder.

```powershell
cd ((Get-ChildItem -Path @((Join-Path $env:USERPROFILE 'projects\active'),(Join-Path $env:USERPROFILE 'Projects\active'),(Join-Path $env:SystemDrive 'projects\active')) -Filter workstation -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'install.ps1') } | Select-Object -First 1).FullName)
```

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -WhatIf
```

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\workstation\fusion-addins\update-fusion-addins.ps1
```

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

## 3. Agent prompt

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** any folder, then the workstation clone.

Paste this to an agent. It should run the installer, then stop. It should not restart Fusion.

```text
Set up the Fusion add-in updater on this PC. Do not edit the workstation repo. Do not restart Fusion and do not stop or start add-ins. Use a normal Windows PowerShell 5.1 window, not admin. From any folder, run this cd line, then the installer: cd ((Get-ChildItem -Path @((Join-Path $env:USERPROFILE 'projects\active'),(Join-Path $env:USERPROFILE 'Projects\active'),(Join-Path $env:SystemDrive 'projects\active')) -Filter workstation -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'install.ps1') } | Select-Object -First 1).FullName) and then powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1. That registers the per-user task Workstation-UpdateFusionAddins (hidden window, at logon and every 60 minutes, no admin). The task runs workstation\fusion-addins\update-fusion-addins.ps1. It fast-forwards Fusion add-in clones found from AddIns junctions and skips a dirty tree, a non-default branch, or a branch with no upstream. It does not restart Fusion. A toast means I restart Fusion myself. To remove it, from this repo run powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1. Do not register the task from the plugin catalog or from install-plugins.ps1.
```

An agent was not asked to paste this prompt on a PC. The installer command inside it is the one in section 1.

## 4. Manual steps

These steps register the same per-user task without `install.ps1`. No admin. They do not restart Fusion. A Windows scheduled task was not created from the Linux check that wrote this file.

1. Open Windows PowerShell 5.1. Do not choose Run as administrator.
2. Go to the workstation clone (the folder that contains `install.ps1`).

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** any folder.

```powershell
cd ((Get-ChildItem -Path @((Join-Path $env:USERPROFILE 'projects\active'),(Join-Path $env:USERPROFILE 'Projects\active'),(Join-Path $env:SystemDrive 'projects\active')) -Filter workstation -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'install.ps1') } | Select-Object -First 1).FullName)
```

3. Register the task. Hidden window. At logon, and every 60 minutes. Run level Limited (no admin). The action is Windows PowerShell with `-WindowStyle Hidden`.

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo.

```powershell
$script = (Resolve-Path -LiteralPath '.\workstation\fusion-addins\update-fusion-addins.ps1').Path; $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'; $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name; $action = New-ScheduledTaskAction -Execute $ps -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $script + '"'); $logon = New-ScheduledTaskTrigger -AtLogOn -User $user; $hourly = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 60) -RepetitionDuration (New-TimeSpan -Days 9999); $settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 15); $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited; Register-ScheduledTask -TaskName 'Workstation-UpdateFusionAddins' -Action $action -Trigger $logon,$hourly -Settings $settings -Principal $principal -Force
```

4. To run one update now, without waiting for the task:

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\workstation\fusion-addins\update-fusion-addins.ps1
```

5. When a toast says add-ins were updated, restart Fusion yourself (or Stop then Run each add-in in Shift+S). The task will not do that.
6. Confirm in Workstation Status (`workstation\health\workstation-status.ps1`) that the task is present. A repo with uncommitted tracked changes is reported as skipped (dirty). A repo that could not fast-forward is reported as left behind.
7. Remove the task (no admin). This does not remove the rest of a workstation install. Use `uninstall.ps1` when the task was registered by `install.ps1`.

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** any folder.

```powershell
Unregister-ScheduledTask -TaskName 'Workstation-UpdateFusionAddins' -Confirm:$false
```

## What this does not do

- Does not restart Fusion or reload add-ins.
- Does not register a task at clone time, from the plugin catalog, or from `install-plugins.ps1`.
- Does not reset, stash, clean, force-push, or delete untracked files.
- Does not update a repo that is dirty, not on the default branch, or missing an upstream.
