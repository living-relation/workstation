# Install the workstation plugin

## Claude

Skip this if you don't use Claude.

1. Open https://claude.ai/customize/plugins and sign in.
2. Click Add, then Add marketplace, then Add from a repository.
3. Paste https://github.com/living-relation/workstation, turn Sync automatically on, and confirm.
4. Wait for it to load; it opens the workstation-core summary page.
5. Click Add (top right) on that page to install it. Adding the repo alone does not install it.
6. Fully quit Claude desktop from the tray icon and reopen it.

Updates arrive automatically after merges to main.

## Cursor

Skip this if you don't use Cursor.

Paste this into a Cursor agent chat opened in any folder:

```text
Install the workstation-core Cursor plugin from https://github.com/living-relation/workstation: if it is not cloned yet, clone it into my projects folder; then copy the repo (without .git and .venv) to ~/.cursor/plugins/local/workstation-core, replacing any old copy. Tell me when done so I can fully quit and reopen Cursor.
```

Manual fallback. `<projects-folder>` is the folder where you keep clones, for example `C:\Users\<you>\projects`.

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin.

1. `cd <projects-folder>`

```powershell
cd <projects-folder>
```

2. Clone if needed: `git clone https://github.com/living-relation/workstation`

```powershell
git clone https://github.com/living-relation/workstation
```

3. `cd <projects-folder>\workstation`

```powershell
cd <projects-folder>\workstation
```

4. Copy into ~/.cursor/plugins/local/workstation-core. This does not open claude.ai.

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.cursor\plugins\local\workstation-core" | Out-Null; Get-ChildItem -Force -LiteralPath . | Where-Object { $_.Name -ne '.git' -and $_.Name -ne '.venv' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path "$env:USERPROFILE\.cursor\plugins\local\workstation-core" $_.Name) -Recurse -Force }
```

5. Fully quit and reopen Cursor.

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

If you use Claude, do the Claude section at the top of this file. If you use Cursor, do the Cursor section. Skip the one you do not use.

## 2. Commands

One command per block. The first is for Claude. The second is the Cursor copy. It does not open claude.ai. Skip the one you do not use.

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** any folder.

```powershell
Start-Process "https://claude.ai/customize/plugins"
```

If you use Claude, do the Claude section at the top of this file.

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo.

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.cursor\plugins\local\workstation-core" | Out-Null; Get-ChildItem -Force -LiteralPath . | Where-Object { $_.Name -ne '.git' -and $_.Name -ne '.venv' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path "$env:USERPROFILE\.cursor\plugins\local\workstation-core" $_.Name) -Recurse -Force }
```

If you use Cursor, do the Cursor section at the top of this file. A shortcut that points outside `~\.cursor\plugins\local` is skipped (https://cursor.com/docs/plugins). `Start-Process` was not run on this Linux check. The copy command was run with a temp `USERPROFILE`. A Cursor window reload was not run.

## 3. Agent prompt

Paste this to an agent. It should run the installer, tell you the clicks, and then stop.

```text
Set up the workstation-core plugin on this PC. Do not edit the workstation repo. Do not create a scheduled task, Startup item, or Run key. In a normal Windows PowerShell 5.1 window (not admin), from this repo, run: powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugins.ps1. If I use Claude, follow the Claude section at the top of INSTALL.md. If I use Cursor, follow the Cursor section. Skip the one I do not use. Wait until I say those steps are done.
```

An agent was not asked to paste this prompt on a PC. The installer command inside it is the one in section 1.

## 4. Manual steps

If you use Claude, do the Claude section at the top of this file. If you use Cursor, do the Cursor section. Skip the one you do not use.

## What this does not do

- Does not turn the plugin on at claude.ai. A script cannot. It opens the page and prints the clicks only when you run it.
- Does not change how `install.ps1` skips an official plugin that is already enabled or already installed at user scope.
- Does not copy skills into `~\.claude\skills`.
- Does not upload skill zips.
- Does not add a scheduled task, a Startup item, or a Run key.
- Does not edit Claude memory files.
