# Install the workstation plugin

## Claude

1. Open claude.ai Plugins: https://claude.ai/customize/plugins (signed in to the account you want the skills on).
2. Click Add, then Add marketplace, then Add from a repository.
3. Paste `https://github.com/living-relation/workstation`, turn Sync automatically on, and confirm.
4. Find the `workstation-core` plugin in the plugin list and turn it on.
5. Fully quit Claude desktop (from the tray icon, not just closing the window), then reopen it.

Updates arrive automatically after merges to main.

## Cursor

1. Open a normal (not admin) Windows PowerShell 5.1 window.
2. cd to the repo clone (`cd <Projects>\active\workstation`). If no clone exists, clone first with the full URL https://github.com/living-relation/workstation.

```powershell
cd <Projects>\active\workstation
```

```powershell
git clone https://github.com/living-relation/workstation <Projects>\active\workstation
```

3. Run the existing one copy command into ~/.cursor/plugins/local/workstation-core.

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.cursor\plugins\local\workstation-core" | Out-Null; Get-ChildItem -Force -LiteralPath . | Where-Object { $_.Name -ne '.git' -and $_.Name -ne '.venv' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path "$env:USERPROFILE\.cursor\plugins\local\workstation-core" $_.Name) -Recurse -Force }
```

4. Fully quit and reopen Cursor.
5. Check that the plugin's skills show up.

The only catalog is `.claude-plugin/marketplace.json`.

| Field | Value |
| --- | --- |
| Catalog to paste | `https://github.com/living-relation/workstation` |
| Catalog name | `workstation-plugins` |
| Plugin to turn on | `workstation-core` (source `./`, this repo) |

`.cursor-plugin/marketplace.json` lists the same plugin with source `.`. Do not add another catalog file.

## 1. Installer

**Terminal:** Windows PowerShell 5.1, or double-click `install-plugins.cmd` in this repo. **Mode:** normal window, not admin. **Folder:** this repo.

The double-click runs the same script. It does not put a shortcut in Startup. A real run opens the Plugins page and copies the plugin for Cursor. A dry run does neither.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugins.ps1
```

Dry run (prints the clicks, opens nothing, copies nothing):

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugins.ps1 -WhatIf
```

A double-click of `install-plugins.cmd` was not run here (this check was on Linux). `-WhatIf` and a real run with `-UserHome` pointed at a temp folder were run. `Start-Process` opening the browser was not run. A signed-in click-through on claude.ai was not run. The page URL `https://claude.ai/customize/plugins` was taken from the Customize > Plugins docs on 2026-11-19 and was not opened in a signed-in browser.

After the script prints the clicks, do the Claude list and the Cursor list at the top of this file.

## 2. Commands

One command per block. The first opens the page. The second is the copy command in the Cursor list.

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** any folder.

```powershell
Start-Process "https://claude.ai/customize/plugins"
```

Then do the Claude list at the top of this file.

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo.

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.cursor\plugins\local\workstation-core" | Out-Null; Get-ChildItem -Force -LiteralPath . | Where-Object { $_.Name -ne '.git' -and $_.Name -ne '.venv' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path "$env:USERPROFILE\.cursor\plugins\local\workstation-core" $_.Name) -Recurse -Force }
```

Then do the Cursor list at the top of this file. A shortcut that points outside `~\.cursor\plugins\local` is skipped (https://cursor.com/docs/plugins). `Start-Process` was not run on this Linux check. The copy command was run with a temp `USERPROFILE`. A Cursor window reload was not run.

## 3. Agent prompt

Paste this to an agent. It should run the installer, tell you the clicks, and then stop.

```text
Set up the workstation-core plugin on this PC. Do not edit the workstation repo. Do not create a scheduled task, Startup item, or Run key. In a normal Windows PowerShell 5.1 window (not admin), from this repo, run: powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugins.ps1. Then follow the Claude list and the Cursor list at the top of INSTALL.md. Wait until I say those steps are done.
```

An agent was not asked to paste this prompt on a PC. The installer command inside it is the one in section 1.

## 4. Manual steps

Do the Claude list and the Cursor list at the top of this file.

## What this does not do

- Does not turn the plugin on at claude.ai. A script cannot. It opens the page and prints the clicks only when you run it.
- Does not change how `install.ps1` skips an official plugin that is already enabled or already installed at user scope.
- Does not copy skills into `~\.claude\skills`.
- Does not upload skill zips.
- Does not add a scheduled task, a Startup item, or a Run key.
- Does not edit Claude memory files.
