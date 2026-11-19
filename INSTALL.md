# Install the living-relation plugins

Skills get in only by installing these plugins. Updates later come from the Plugins menu. Leave marketplace auto-update off. This package does not link `~\.claude\skills`, upload a skill zip, or start anything at sign-in. It does not reinstall in the background.

The only catalog is `.claude-plugin/marketplace.json`.

| Field | Value |
| --- | --- |
| Marketplace name | `living-relation-plugins` |
| `workstation-core` | source `./` (this repo) |
| `handbuilt-cad` | source `{"source":"github","repo":"living-relation/handbuilt-cad"}` |

Cursor cannot list that GitHub repo inside `.cursor-plugin/marketplace.json`. See [Cursor](#cursor) below. Do not add another catalog file.

## 1. Installer

**Terminal:** Windows PowerShell 5.1, or double-click `install-plugins.cmd` in this repo. **Mode:** normal window, not admin. **Folder:** this repo.

The double-click runs the same script. It does not put a link in Startup.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugins.ps1
```

Dry run (prints the two commands, runs none):

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin. **Folder:** this repo.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugins.ps1 -WhatIf
```

A double-click of `install-plugins.cmd` was not run here (this check was on Linux). The script's `-WhatIf` and a real run with `-Marketplace` pointed at this working tree were run. See the PR for the exact commands.

## 2. Commands

Same two commands the installer runs. One command per block. The second command reuses the marketplace the first command added.

**Terminal:** Windows PowerShell 5.1, or Windows Terminal opened on PowerShell. **Mode:** normal window, not admin. **Folder:** any folder. `claude` is on PATH. Claude Code 2.1.292 or newer (that is when `claude plugin install --marketplace` adds the marketplace in the same command).

```powershell
claude plugin install workstation-core --marketplace living-relation/workstation --scope user
```

```powershell
claude plugin install handbuilt-cad --marketplace living-relation/workstation --scope user
```

**Terminal:** Claude Code session prompt. **Mode:** interactive session. `claude -p` cannot open `/plugin`.

```text
/plugin install workstation-core --marketplace living-relation/workstation
```

```text
/plugin install handbuilt-cad --marketplace living-relation/workstation
```

In a session, that opens the plugin's details so you can pick a scope. Pick user scope (for you, on this PC).

If the CLI is older than 2.1.292, add the marketplace first, then install by id:

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin.

```powershell
claude plugin marketplace add living-relation/workstation
```

```powershell
claude plugin install workstation-core@living-relation-plugins --scope user
```

```powershell
claude plugin install handbuilt-cad@living-relation-plugins --scope user
```

## 3. Agent prompt

Paste this to an agent. It should run the commands and then stop.

```text
Install the living-relation plugins on this PC. Do not link skills and do not upload skill zips. Do not edit the workstation repo. In a normal Windows PowerShell 5.1 window (not admin), from any folder, run these one at a time and stop if one fails: claude plugin install workstation-core --marketplace living-relation/workstation --scope user ; then claude plugin install handbuilt-cad --marketplace living-relation/workstation --scope user. Then open Claude Code, run /plugin, and confirm workstation-core@living-relation-plugins and handbuilt-cad@living-relation-plugins are on the Installed tab at user scope. Do not turn on marketplace auto-update. Do not create a scheduled task, Startup item, or Run key. Do not run install.ps1 -LinkSkills. Updates later come from the Plugins menu (Installed tab, Update now), not from a script.
```

An agent was not asked to paste this prompt on a PC. The commands inside it are the ones in section 2.

## 4. Manual steps

These clicks follow the Claude Code install docs (https://code.claude.com/docs/en/plugins/install) as read on 2026-11-19. A live click-through on a PC was not run.

1. Install Claude Code and sign in.
2. Open a local session in the desktop app's Code tab, or a terminal session.
3. Add the marketplace. In the session prompt, type `/plugin marketplace add living-relation/workstation` and confirm if it asks. The Plugins menu lists this catalog only after that add. A bare `owner/repo` is the GitHub form.
4. Open the Plugins menu. Click the + button next to the prompt. If it says **Add plugins**, choose that. If it says **Plugins**, choose **Plugins**, then **Browse plugins**. If **Browse plugins** is missing, choose **Manage plugins**.
5. Install **workstation-core**, then **handbuilt-cad**. Choose user scope (for you, every project on this PC).
6. Open the Installed tab and check both names are listed and enabled.
7. Updates later: on the Installed tab, open the plugin and choose **Update now**. Or open the Marketplaces tab, select **living-relation-plugins**, and choose **Update marketplace**. Leave auto-update off.

VS Code's Claude Code panel: type `/plugins`. If the list is empty, add the marketplace on the Marketplaces tab (step 3), then on the Plugins tab click Install and choose **Install for you**.

## Cursor

Checked on 2026-11-19 against https://cursor.com/docs/reference/plugins, https://cursor.com/docs/plugins, and the schema https://github.com/cursor/plugins/blob/main/schemas/marketplace.schema.json.

Cursor's marketplace `source` has to be a string. The schema text says that string is a path in the repo, or a remote URL. The published resolver still looks for `<source>/.cursor-plugin/plugin.json` on disk. Claude's object `{"source":"github","repo":"living-relation/handbuilt-cad"}` is not valid Cursor JSON. No Cursor doc shows a marketplace entry that clones a second GitHub repo. So this PR does not add handbuilt-cad to `.cursor-plugin/marketplace.json`, and it does not add another marketplace file.

What is already valid:

- `.cursor-plugin/marketplace.json` lists only `workstation-core` with `"source": "."`.
- `living-relation/handbuilt-cad` has its own `.cursor-plugin/plugin.json`. Import that repo on its own if you want those skills in Cursor.

To install workstation-core in Cursor (team marketplace): Dashboard, Plugins & MCPs, Add Marketplace, Import from Repo, paste this repo's URL, then install it from Customize. Leave **Auto Refresh** off. Update from Customize. A live Cursor import was not run.

Personal machines can also load a local copy from `~/.cursor/plugins/local` after a window reload (https://cursor.com/docs/plugins). A symlink that points outside that folder is skipped. That copy was not made here.

## What this does not do

- Does not change how `install.ps1` treats a Claude plugin that was already installed. That is a later change.
- Does not link skills (`install.ps1` without `-LinkSkills` still prints that skills are not linked).
- Does not upload skill zips.
- Does not add a scheduled task, a Startup item, or a Run key.
- Does not edit Claude memory files.
