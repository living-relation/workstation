# workstation (public)

Sets up a Windows + WSL workstation for agent-assisted work: installer and preflight, helper
scripts (workers, status), memory/handoff tooling, agent instruction templates, the shared
non-CAD agent skills, and a single pin file (`workstation.lock.yaml`) that says which repos and
upstream tools to fetch, at which versions. It holds **no CAD code and no models** - those come
from the repos listed in the pin file.

## Starting work

**Pick up existing work:** open a chat (Grok, Claude Code or Cursor) in the repo's folder and say `run session-start`. It reads AGENTS.md, DECISIONS, SPEC if the repo has one, and STATE, confirms in 3 lines, spots a cut-off last session, and asks before each follow-up.

**Start new work:** create the repo or pick the folder, say `run state-init`, and pick a profile. Full (milestones) gets AGENTS.md, SPEC, DECISIONS, rules, data, and the git hook pack only if you say yes. Toolkit (shared tools, no milestone) gets AGENTS.md, DECISIONS and rules, plus STATE, BACKLOG and archives in the store. Light (small repos) gets AGENTS.md only, and STATE in the store when work starts. A SoT registry entry is added for each data file the repo treats as a source of truth. It shows a plan before any overwrite, waits for yes, and opens a PR. A file already at its template home stays. An older agent doc that conflicts with the template is migrated into that layout. That conflict is not a blocker and not a reason to stop. Then use session-start each session.

**Bring an existing repo in line with the new agent docs:** 1) `run session-start` (folds any CLAUDE.md into AGENTS.md and deletes it in that PR on the task branch; reports drift), 2) `run state-init` (migrates an older agent doc that conflicts with the template into that layout, and adds only what's missing; a file already at its template home stays; the conflict is not a reason to stop), 3) `repo-cleanup` only if agent, decision, plan, handoff or state files have sprawled or duplicated (asks before deleting superseded docs; git history is the backup). One line: `run session-start, then state-init`.

**During and after a session:**

| Skill | When |
|---|---|
| state-closeout | At 80% context, a pivot, a blocker, a milestone, or a PR |
| agent-handoff-pack | The job moves to a new chat. It forwards to state-closeout handoff, which prints a paste block. The record is the store's STATE file |
| coordinator-kit | One chat coordinates a repo's agent work |
| safe-repo-preflight | Before a change, commit or push |
| pr-closeout | After a PR opens |
| debug-root-cause | A bug or a failing test, before a fix |
| review-feedback | Pull-request review comments, including GitHub Copilot's |

Note: ask for skills by name in plain words. Whether Claude lists them under / with a workstation-core: prefix is unverified. Progress goes only in the store's STATE file (`STATE.md` on main, `STATE-<slug>.md` on a branch), never in the repo and never in memory. Until this repo's state moves to the store, its root `STATE.md` is that file.

## Setup
```powershell
git clone <repo-url> <Projects>\active\workstation
powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1      # hooks, gitleaks, models folder, local.toml
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -ProjectsRoot <Projects> -WhatIf   # then without -WhatIf
```

## Plugins

**Claude**

Skip this if you don't use Claude.

1. Open https://claude.ai/customize/plugins and sign in.
2. Click Add, then Add marketplace, then Add from a repository.
3. Paste https://github.com/living-relation/workstation, turn Sync automatically on, and confirm.
4. Wait for it to load; it opens the workstation-core summary page.
5. Click Add (top right) on that page to install it. Adding the repo alone does not install it.
6. Fully quit Claude desktop from the tray icon and reopen it.

Updates arrive automatically after merges to main.

**Cursor**

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

The Workstation toolkit (`workstation\`: Health check, app locks, the manual Cursor worker, and the manual Desktop Commander shortcuts) runs
straight from this clone; install.ps1 copies nothing under the Projects root. Keep the clone on `main`.
Runtime files live in `%LOCALAPPDATA%\Workstation\`, never in the clone.
**Desktop Commander and the Cursor worker do not start on their own.** No Startup item, no Run key, and no scheduled task. Fusion add-in clones update only from the manual **Update Fusion add-ins** shortcut. See [workstation/fusion-addins/README.md](workstation/fusion-addins/README.md).

**Desktop Commander (manual, one phone remote per PC).** It serves every chat and project. The MCP plugin that
Claude starts is separate and is not changed here. `install.ps1` creates these manual links in `shortcuts\` (gitignored). Nothing starts at sign-in:

- **Health check** runs `workstation\health\workstation-status.ps1`.
- **Start Desktop Commander** runs `workstation\desktop-commander-remote\start-dc-remote.ps1 -Show`. It stops stale or duplicate phone-remote copies, then starts exactly one with `npx.cmd @wonderwhy-er/desktop-commander@latest remote`, or says the healthy copy is already online. It does not launch or remove the Desktop Commander desktop app. The MCP plugin is separate and starts with Claude.
- **Stop Desktop Commander** stops the phone remote.
- **DC remote status** lists each copy: PID, start time, whether its parent and console are alive, and an online / stale / duplicate verdict, plus the line `one copy serves all chats`.
- **Kill orphaned remote processes** lists leftovers and asks once per item.
- **Update Fusion add-ins** runs `workstation\fusion-addins\update-fusion-addins.ps1 -Pause` once (manual only).

On Windows one phone remote is a chain: cmd, then npx's node, then cmd, then the node remote. That chain is one copy. A healthy copy has a live parent and a live console. Leave that copy alone. Kill orphaned remote processes offers a copy whose terminal is gone, and extra copies when more than one remote is running (it keeps the newest and asks first). `-WhatIf` only lists. `-Force` stops the listed copies but never stops the newest remote unless you also pass `-IncludeActiveRemote`. Stopping uses taskkill /T on that copy's own chain, so a yes does not take down the healthy remote. The single healthy copy is never listed. Claude's Desktop Commander plugin is not listed. Health check says OK when zero or one remote is running, and warns only when extra copies or other leftovers are present. It also checks that the remote does not start at sign-in.

**Cursor worker (manual, one per folder you pick).** `install.ps1` adds **Start Cursor worker** and **Stop Cursor worker** in `shortcuts\`. Nothing starts at sign-in, reboot, or app launch. Start lists the folders in `<Projects>\active` on this PC (the root is detected, not hard-coded) and starts one worker for the folder you pick. Run Start again to add another folder. Stop lists the workers this tool started and stops one or all. The command is `agent worker --name <pc>-<folder> --worker-dir <folder> --data-dir <local instance dir> --management-addr 127.0.0.1:<port> --idle-release-timeout 0 --label workstation=manual start`. Details and the doc links are in `workstation\cursor-worker\README.md`. Health check can report running workers. It does not warn when none is running. It warns if a sign-in item, Run key, scheduled task, or app hook would start the worker. A folder with no git origin can still be started; Cursor may not match it to a repo.

## Fusion add-in updates

The updater fast-forwards the git clones behind the Fusion AddIns junctions. It is manual only: run the **Update Fusion add-ins** shortcut that `install.ps1` makes, or the command below. No scheduled task runs it. `install.ps1` removes the task `Workstation-UpdateFusionAddins` if an older install left it. It does not restart Fusion. The plugin catalog does not register a task.

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
powershell -NoProfile -ExecutionPolicy Bypass -File .\workstation\fusion-addins\update-fusion-addins.ps1
```

The four install methods (installer, commands, agent prompt, manual steps) are in [workstation/fusion-addins/README.md](workstation/fusion-addins/README.md).

`install.ps1` removes `shortcuts\rc` only when that folder is empty. A folder that still has files, or that is a link, is left alone.

Logs: `%LOCALAPPDATA%\Workstation\desktop-commander-remote\`. No token is stored in this repo.

On a PC that still has the old local setup, run `cleanup-legacy.ps1 -WhatIf`, then without `-WhatIf`. It backs up with SHA256 hashes first. A log the old server still has open is skipped instead of aborting the run. It says it would stop the old web server only when that process is actually running. It does not stop the phone remote and does not archive that state folder. Then run `install.ps1` so the manual links, including Health check, exist again.
WSL side (only if you want the Python helpers, e.g. the INVENTORY generator): `bash setup.sh`.

- `workstation.lock.yaml` - pins and pointers only. `INVENTORY.md` is generated from it (`.venv/bin/python scripts/gen-inventory.py`).
- No CAD code or models in this repo. `workstation.lock.yaml` does not pin any.
- `skills/` - this repo's skills; skills live only in their repo. They get in only when `workstation-core` is turned on from the `workstation-plugins` catalog on claude.ai (see [INSTALL.md](INSTALL.md)). No zip upload. `install.ps1` does not copy them into `~\.claude\skills`.
  `skills/EXCLUDE.txt` lists Claude-app-owned skills (harness-design, st185-*); those, and any SKILL.md with
  `source: harness-design-app`, are never zipped, and `link-skills.ps1` never moves or removes their folders.
  Each skill folder (`skills/<name>/` with a `SKILL.md`) has a matching generated `skills/<name>.zip` (CI builds it; nobody uploads it).

  **This repo is the source of truth for Dan's skills** (all 18 are his). `wizard` is his copy of
  [claude-wizard](https://github.com/vlad-ko/claude-wizard) `skill/` at base `43756e1` (`skills/wizard/UPSTREAM.md`).
  `workstation\check-upstream.ps1` is manual. For a skill with `metadata.upstream` it fetches upstream, shows
  `base..HEAD`, three-way merges into Dan's copy, bumps `upstream-base`, and opens a PR. No schedule and no
  sign-in item. The same check can be started by hand from Actions: workflow **check-upstream**
  (`workflow_dispatch` only, no cron).
  Zips update automatically: on a same-repo PR that touches skills (and whose head is not main), a GitHub Action
  rebuilds them and commits any changes back onto that PR branch. If main's zips are ever stale, the Action
  resets `chore/skill-zips` to `origin/main` and opens or updates that one PR (it never pushes to main).
  `GITHUB_TOKEN` commits do not start checks; the Action runs `gh workflow run` on the new commit. The owner
  must leave **Allow GitHub Actions to create and approve pull requests** on, and keep a ruleset on `main`
  that blocks direct pushes. The local packer is optional (`scripts\pack-skill-zips.ps1` or
  `bash scripts/pack-skill-zips.sh`; both call `python3 scripts/pack-skill-zips.py`). Zips are deterministic;
  the packer only treats directories that contain `SKILL.md` as skills and ignores `.zip` files. Limit
  violations are reported as warnings; skill files are never edited. Untracked `SKILL.md` fails the packer.
- Ownership notes: `install.ps1` runs `ownership-notes.ps1`, which adds a README.md/AGENTS.md ("owned by the workstation repo")
  to each folder it creates (`%LOCALAPPDATA%\Workstation` and its subfolders, `<Projects>\_claude`). In the shared
  skill folders it adds only `README-workstation.md`, which lists the links this repo owns. Existing files are never changed.
- `claude/` - Claude Code user-scope setup that `install.ps1` applies on each PC (merge; backup first; never
  removes or overwrites servers/plugins/hooks it did not add). `mcp-servers.json` is the connector list merged
  into `~/.claude.json` (kapture, github, githits, fetch, windows-mcp, context7). Required
  API keys are read from env or prompted; a server that still lacks a key is skipped with a message.
  `plugins.json` is the source of truth for plugins installed from Anthropic's
  official marketplace at user scope. `handoff/claude/pr-closeout-nudge.ps1` is copied into `~/.claude/hooks` and
  wired as a PostToolUse hook in `~/.claude/settings.json` next to context-guard and memory-link-guard.
  **Memory split:** Claude Code's shared store is `<Projects>\_claude\Claude Projects\Working Memory\memory\`
  (the `autoMemoryDirectory` junction plus `memory-link-guard.ps1`). Tiers: the repo (git) holds the router
  `AGENTS.md`, SPEC, DECISIONS, rules and data; the store's project folder holds live state (`STATE.md`,
  `STATE-<slug>.md`, `BACKLOG.md`, `archives\`) plus preference and fact notes in `INDEX.md`; `TASK.md` is
  git-ignored per worktree. At 80% context agents run `state-closeout`; a session that cannot reach the
  store works from committed docs only. Claude desktop online Memory is account-level facts about the user and is not synced.
  As of Store app 4.4212.0.0 ("Unified Claude", personal account, 2026-11-03; work account unverified),
  Cowork / Chat do not write local memory files. Install does not create or check `~\.claude\working-memory`;
  a leftover junction is harmless. Stranded local Cowork notes can be copied into the store or brought in
  with the app's Import memory button. See `MIGRATION.md`.
  Install does not change `autoMode` and does not write a remote-control startup flag. `cleanup-legacy.ps1` removes that flag and the one living-relation pull-request merge allow rule from a PC that already has them. Fusion work uses Autodesk's official, Autodesk-hosted MCP servers (nothing to install): Fusion Compute MCP `https://developer.api.autodesk.com/da/v3/mcp/fusion` (preferred, headless cloud Fusion, so local Fusion isn't interrupted); Fusion Data MCP `https://developer.api.autodesk.com/fusion/mcp`; Fusion Desktop MCP is built into Fusion (Preferences > General > API, local `http://127.0.0.1:27182/mcp`). Docs: https://help.autodesk.com/view/ADSKMCP/ENU/.
- `agents/projects-AGENTS.md` - the shared agent rules file for a projects root.
- `install.ps1`, `preflight.ps1`, `uninstall.ps1`, `toolkit.psd1` - imported as they were; they are rewritten to read the pin file in a later PR.
