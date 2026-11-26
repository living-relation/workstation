# workstation (public)

Sets up a Windows + WSL workstation for agent-assisted work: installer and preflight, helper
scripts (workers, status), memory/handoff tooling, agent instruction templates, the shared
non-CAD agent skills, and a single pin file (`workstation.lock.yaml`) that says which repos and
upstream tools to fetch, at which versions. It holds **no CAD code and no models** - those come
from the repos listed in the pin file.

## Starting work

**Pick up existing work:** open a chat (Grok, Claude Code or Cursor) in the repo's folder and say `run session-start`. It reads AGENTS.md, DECISIONS, SPEC if the repo has one, and STATE, confirms in 3 lines, spots a cut-off last session, and asks before each follow-up.

**Start new work:** create the repo or pick the folder, say `run state-init`, and pick a profile. Full (milestones) gets AGENTS.md, SPEC, DECISIONS, rules, data, and the git hook pack only if you say yes. Full and Toolkit also get STATE, BACKLOG and archives in the repo, plus the `state-files-gate` CI check. Toolkit (shared tools, no milestone) gets AGENTS.md, DECISIONS and rules. Light (small repos) gets AGENTS.md only, and STATE in the repo when work starts. A SoT registry entry is added for each data file the repo treats as a source of truth. It shows a plan before any overwrite, waits for yes, and opens a PR. A file already at its template home stays. An older agent doc that conflicts with the template is migrated into that layout. That conflict is not a blocker and not a reason to stop. Then use session-start each session.

**Bring an existing repo in line with the new agent docs:** 1) `run session-start` (folds any CLAUDE.md into AGENTS.md and deletes it in that PR on the task branch; reports drift), 2) `run state-init` (migrates an older agent doc that conflicts with the template into that layout, and adds only what's missing; a file already at its template home stays; the conflict is not a reason to stop), 3) `repo-cleanup` only if agent, decision, plan, handoff or state files have sprawled or duplicated (asks before deleting superseded docs; git history is the backup). One line: `run session-start, then state-init`.

**During and after a session:**

| Skill | When |
|---|---|
| state-closeout | At 80% context, a pivot, a blocker, a milestone, or a PR |
| agent-handoff-pack | The job moves to a new chat. It forwards to state-closeout handoff, which prints a paste block. The record is the branch's `STATE-<slug>.md` in the repo |
| coordinator-kit | One chat coordinates a repo's agent work |
| safe-repo-preflight | Before a change, commit or push |
| pr-closeout | After a PR opens |
| debug-root-cause | A bug or a failing test, before a fix |
| review-feedback | Pull-request review comments, including GitHub Copilot's |

Note: ask for skills by name in plain words. Whether Claude lists them under / with a workstation-core: prefix is unverified. Progress goes only in the repo's STATE file (`STATE.md` on main, `STATE-<slug>.md` committed on a branch and archived as the PR's last commit), never in memory (decision D-2026-11-22-state-in-repo in `DECISIONS.md`).

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

**Claude Code**

Skip this if you don't use Claude Code.

Claude Code installs workstation-core straight from this repo's catalog. That copy (`workstation-core@workstation-plugins`) takes precedence over the copy synced from claude.ai; `claude plugin list` then shows the synced one as not loaded. Claude desktop and Cowork still get the plugin from claude.ai (the Claude section above).

`install.ps1` runs the add command and the install command below. `install.cmd` runs `install.ps1`. If the `claude` CLI is missing, those two are skipped and the install continues. Nothing is uninstalled or disabled. Refresh and update stay manual.

**Terminal:** Windows PowerShell 5.1. **Mode:** normal window, not admin.

1. Add the catalog, once per PC. Skip this if `claude plugin marketplace list` already shows `workstation-plugins`.

```powershell
claude plugin marketplace add living-relation/workstation
```

2. Install the plugin.

```powershell
claude plugin install workstation-core@workstation-plugins
```

3. Later, after merges to main, refresh the catalog.

```powershell
claude plugin marketplace update workstation-plugins
```

4. Then update the installed plugin.

```powershell
claude plugin update workstation-core@workstation-plugins
```

5. Start a new Claude Code session. Open sessions keep the plugin they started with.

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
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.cursor\plugins\local\workstation-core" | Out-Null; Get-ChildItem -Force -LiteralPath . | Where-Object { $_.Name -ne '.git' -and $_.Name -ne '.venv' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination "$env:USERPROFILE\.cursor\plugins\local\workstation-core" -Recurse -Force }
```

5. Fully quit and reopen Cursor.

The Workstation toolkit (`workstation\`: Health check, app locks and the manual Cursor worker) runs
straight from this clone; install.ps1 copies nothing under the Projects root. Keep the clone on `main`.
Runtime files live in `%LOCALAPPDATA%\Workstation\`, never in the clone.
**The Cursor worker does not start on its own.** No Startup item, no Run key, and no scheduled task.

`install.ps1` creates these manual links in `shortcuts\` (gitignored). Nothing starts at sign-in:

- **Health check** runs `workstation\health\workstation-status.ps1`. Marks: `[ OK ]` checked and fine, `[ RUN ]` running, `[STOP]` off (normal for a manual tool), `[ -- ]` not checked or info only, `[WARN]` / `[FAIL]` needs a fix. The Plugins section compares the Claude Code workstation-core copy with this clone's `origin/main` (as of the last pull) and the Cursor copy with this clone's files.
- **Kill orphaned remote processes** lists leftovers and asks once per item.

Kill orphaned remote processes offers leftovers (the old local web server, the old watcher, a Claude remote-control session whose parent is gone) and asks first. `-WhatIf` only lists. `-Force` stops the listed items without asking. Health check warns when such leftovers are present.

**Cursor worker (manual, one per folder you pick).** `install.ps1` adds **Start Cursor worker** and **Stop Cursor worker** in `shortcuts\`. No Windows startup entry (sign-in or reboot) starts it; the Cursor app can restart its own worker when Cursor opens, and Health check warns about that. Start lists the folders in `<Projects>\active` on this PC (the root is detected, not hard-coded) and starts one worker for the folder you pick. Run Start again to add another folder. Stop lists the workers this tool started and stops one or all. The command is `agent worker --name <pc>-<folder> --worker-dir <folder> --data-dir <local instance dir> --management-addr 127.0.0.1:<port> --idle-release-timeout 0 --label workstation=manual start`. Details and the doc links are in `workstation\cursor-worker\README.md`. Start waits a few seconds and reports a failure (with the error and `agent login` advice) when the worker exits right away. Health check shows `[STOP]` when no worker is running (normal), `[ RUN ]` for each running worker, including one the Cursor app started by itself, and `[FAIL]` for a worker that Start recorded but that exited with an error since the last boot. It warns if a sign-in item, Run key, or scheduled task would start the worker, or if the Cursor app restarts its own worker at app launch. A folder with no git origin can still be started; Cursor may not match it to a repo.

`install.ps1` removes `shortcuts\rc` only when that folder is empty. A folder that still has files, or that is a link, is left alone.

No token is stored in this repo.

On a PC that still has the old local setup, run `cleanup-legacy.ps1 -WhatIf`, then without `-WhatIf`. It backs up with SHA256 hashes first. A log the old server still has open is skipped instead of aborting the run. It says it would stop the old web server only when that process is actually running. Then run `install.ps1` so the manual links, including Health check, exist again.
WSL side (only if you want the Python helpers, e.g. the INVENTORY generator): `bash setup.sh`.

- `workstation.lock.yaml` - pins and pointers only. `INVENTORY.md` is generated from it (`.venv/bin/python scripts/gen-inventory.py`).
- No CAD code or models in this repo. `workstation.lock.yaml` does not pin any.
- `skills/` - this repo's skills; skills live only in their repo. They get in from the `workstation-core` plugin: turned on from the `workstation-plugins` catalog on claude.ai for Claude desktop and Cowork, and installed from the same catalog with the `claude plugin` commands for Claude Code (see [INSTALL.md](INSTALL.md)). No zip upload. `install.ps1` does not copy them into `~\.claude\skills`.
  `skills/EXCLUDE.txt` lists Claude-app-owned skills (harness-design, st185-*); those, and any SKILL.md with
  `source: harness-design-app`, are left alone, and `link-skills.ps1` never moves or removes their folders.

  **This repo is the source of truth for Dan's skills** (all 18 are his). `wizard` is his copy of
  [claude-wizard](https://github.com/vlad-ko/claude-wizard) `skill/` at base `43756e1` (`skills/wizard/UPSTREAM.md`).
  `workstation\check-upstream.ps1` is manual. For a skill with `metadata.upstream` it fetches upstream, shows
  `base..HEAD`, three-way merges into Dan's copy, bumps `upstream-base`, and opens a PR. No schedule and no
  sign-in item. The same check can be started by hand from Actions: workflow **check-upstream**
  (`workflow_dispatch` only, no cron).
- Ownership notes: `install.ps1` runs `ownership-notes.ps1`, which adds a README.md/AGENTS.md ("owned by the workstation repo")
  to each folder it creates (`%LOCALAPPDATA%\Workstation` and its subfolders, `<Projects>\_claude`). In the shared
  skill folders it adds only `README-workstation.md`, which lists the links this repo owns. Existing files are never changed.
- Third-party installs: none (decision D-2026-11-26-no-third-party-installs). `install.ps1` installs only workstation-core
  items. It adds no MCP servers to `~/.claude.json`, installs no other Claude plugins, installs no Desktop Commander
  and does not set `pluginConfigs`; which plugins and MCP servers a PC has is the user's choice. memory-link-guard, context-guard and pr-closeout-nudge ship in the
  workstation-core plugin (`hooks/hooks.json`, `hooks/cursor-hooks.json`); install.ps1 copies no hook files and writes
  no hook entries or statusLine (decision D-2026-11-26-hooks-in-plugin).
  **Memory split:** Claude Code's shared store is `<Projects>\_claude\Claude Projects\Working Memory\memory\`
  (the `autoMemoryDirectory` junction plus `memory-link-guard.ps1`). Tiers (decision 2026-11-22): the repo (git) holds the router
  `AGENTS.md`, SPEC, DECISIONS, rules, data and live state (`STATE.md`, `STATE-<slug>.md`, `BACKLOG.md`,
  `archives/`); the store's project folder holds notes only (preferences, machine facts, gotchas in `INDEX.md`);
  `TASK.md` is git-ignored per worktree. At 80% context agents run `state-closeout`; a session that cannot
  reach the store still has live state in the repo and only misses notes. Claude desktop online Memory is account-level facts about the user and is not synced.
  As of Store app 4.4212.0.0 ("Unified Claude", personal account, 2026-11-03; work account unverified),
  Cowork / Chat do not write local memory files. Install does not create or check `~\.claude\working-memory`;
  a leftover junction is harmless. Stranded local Cowork notes can be copied into the store or brought in
  with the app's Import memory button. See `MIGRATION.md`.
  Install does not change `autoMode` and does not write a remote-control startup flag. `cleanup-legacy.ps1` removes that flag and the one living-relation pull-request merge allow rule from a PC that already has them.
- `instructions/projects-AGENTS.md` - the shared agent rules file for a projects root.
- `install.ps1`, `preflight.ps1`, `uninstall.ps1`, `toolkit.psd1` - imported as they were; they are rewritten to read the pin file in a later PR.
