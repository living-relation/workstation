# Install the workstation plugin

Skills get in only by turning on the `workstation-core` plugin on claude.ai. That one plugin covers chat, Cowork, and Claude Code signed in to the same account. Cursor on an individual account uses a folder copy. This package cannot change claude.ai from a script. It does not copy skills into `~\.claude\skills`, upload a skill zip, or start anything at sign-in. It does not reinstall in the background. Leave Sync automatically off.

The only catalog is `.claude-plugin/marketplace.json`.

| Field | Value |
| --- | --- |
| Catalog to paste | `living-relation/workstation` |
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

After the script prints the clicks, do them:

1. Sign in to the claude.ai account you use for chat, Cowork, and Claude Code.
2. Open Customize in the left sidebar.
3. Open Plugins.
4. Click Add, then Add marketplace.
5. Choose Add from a repository.
6. Paste `living-relation/workstation`.
7. Turn Sync automatically off. Leave it off.
8. Confirm the add.
9. Turn on workstation-core.

Catalog name: `workstation-plugins`. Updates later: open this catalog and choose Check for updates. Leave Sync automatically off.

The same run copies this repo to `%USERPROFILE%\.cursor\plugins\local\workstation-core` (a real copy, not a shortcut that points outside that folder). Reload the Cursor window. Run the script again when you want a newer copy, then reload again.

## 2. Commands

One command per block. The first opens the page. The clicks under it finish the claude.ai part. The second copies the plugin for Cursor.

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** any folder.

```powershell
Start-Process "https://claude.ai/customize/plugins"
```

Then, in the browser:

1. Sign in to the claude.ai account you use for chat, Cowork, and Claude Code.
2. Open Customize in the left sidebar.
3. Open Plugins.
4. Click Add, then Add marketplace.
5. Choose Add from a repository.
6. Paste `living-relation/workstation`.
7. Turn Sync automatically off. Leave it off.
8. Confirm the add.
9. Turn on workstation-core.

Catalog name: `workstation-plugins`. That covers chat, Cowork, and Claude Code signed in to this account. Updates later: open this catalog and choose Check for updates. Leave Sync automatically off.

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo.

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.cursor\plugins\local\workstation-core" | Out-Null; Get-ChildItem -Force -LiteralPath . | Where-Object { $_.Name -ne '.git' -and $_.Name -ne '.venv' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path "$env:USERPROFILE\.cursor\plugins\local\workstation-core" $_.Name) -Recurse -Force }
```

Reload the Cursor window after the copy. A shortcut that points outside `~\.cursor\plugins\local` is skipped (https://cursor.com/docs/plugins). `Start-Process` was not run on this Linux check. The copy command was run with a temp `USERPROFILE`. A Cursor window reload was not run.

## 3. Agent prompt

Paste this to an agent. It should run the installer, tell you the clicks, and then stop.

```text
Set up the workstation-core plugin on this PC. Do not edit the workstation repo. Do not copy skills into ~\.claude\skills. Do not upload a skill zip. Do not create a scheduled task, Startup item, or Run key. In a normal Windows PowerShell 5.1 window (not admin), from this repo, run: powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugins.ps1. That opens https://claude.ai/customize/plugins and prints the clicks, and it copies this repo to %USERPROFILE%\.cursor\plugins\local\workstation-core. Tell me to do these clicks and wait until I say done: sign in to the claude.ai account used for chat, Cowork, and Claude Code; open Customize, then Plugins; click Add, then Add marketplace; choose Add from a repository; paste living-relation/workstation (catalog name workstation-plugins); turn Sync automatically off; turn on workstation-core. That one plugin covers chat, Cowork, and Claude Code signed in to that account. Then reload the Cursor window. Updates later: on claude.ai open the catalog and choose Check for updates, and leave Sync automatically off. For Cursor, run the installer again and reload the window.
```

An agent was not asked to paste this prompt on a PC. The installer command inside it is the one in section 1.

## 4. Manual steps

These clicks follow Customize > Plugins as described at https://claude.com/docs/plugins/overview and https://support.claude.com/en/articles/13837440-use-plugins-in-claude on 2026-11-19. A live click-through on a signed-in account was not run. The Sync automatically control is described for a marketplace you add yourself; its exact place on the personal Add marketplace dialog was not clicked here.

1. Open https://claude.ai/customize/plugins and sign in to the account you use for chat, Cowork, and Claude Code.
2. If you are not already there, open Customize in the left sidebar, then Plugins.
3. Click Add, then Add marketplace.
4. Choose Add from a repository.
5. Paste `living-relation/workstation`.
6. Turn Sync automatically off. Leave it off.
7. Confirm the add. The catalog name is `workstation-plugins`.
8. Turn on workstation-core.
9. That covers chat, Cowork, and Claude Code signed in to this account. Start Claude Code again, signed in to this account, so the account copy downloads. Health check looks for that download under `~\.claude\plugins\synced`. Until it is there, health check warns that the plugin is not added yet.
10. Updates later: open this catalog and choose Check for updates. Leave Sync automatically off.

Cursor, on this PC:

1. Copy this repo's files into `%USERPROFILE%\.cursor\plugins\local\workstation-core`. Use a real copy. A shortcut that points outside that folder is skipped.
2. Reload the Cursor window (Command Palette, Developer: Reload Window).

## What this does not do

- Does not turn the plugin on at claude.ai. A script cannot. It opens the page and prints the clicks only when you run it.
- Does not change how `install.ps1` skips an official plugin that is already enabled or already installed at user scope.
- Does not copy skills into `~\.claude\skills`.
- Does not upload skill zips.
- Does not add a scheduled task, a Startup item, or a Run key.
- Does not edit Claude memory files.
