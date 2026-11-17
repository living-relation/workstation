# workstation (public)

Sets up a Windows + WSL workstation for agent-assisted work: installer and preflight, helper
scripts (workers, status), memory/handoff tooling, agent instruction templates, the shared
non-CAD agent skills, and a single pin file (`workstation.lock.yaml`) that says which repos and
upstream tools to fetch, at which versions. It holds **no CAD code and no models** - those come
from the repos listed in the pin file.

## Setup
```powershell
git clone <repo-url> <Projects>\active\workstation
powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1      # hooks, gitleaks, models folder, local.toml
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -ProjectsRoot <Projects> -WhatIf   # then without -WhatIf
```
The Workstation toolkit (`workstation\`: Health check, app locks, the manual Cursor worker, and the manual Desktop Commander shortcuts) runs
straight from this clone; install.ps1 copies nothing under the Projects root. Keep the clone on `main`.
Runtime files live in `%LOCALAPPDATA%\Workstation\`, never in the clone.
**Nothing starts on its own.** No sign-in links, no scheduled tasks, no Run key.

**Desktop Commander (manual, one phone remote per PC).** It serves every chat and project. The MCP plugin that
Claude starts is separate and is not changed here. `install.ps1` creates these manual links in `shortcuts\` (gitignored). Nothing starts at sign-in:

- **Health check** runs `workstation\health\workstation-status.ps1`.
- **Start Desktop Commander** runs `workstation\desktop-commander-remote\start-dc-remote.ps1 -Show`. It stops stale or duplicate phone-remote copies, then starts exactly one with `npx.cmd @wonderwhy-er/desktop-commander@latest remote`, or says the healthy copy is already online. It does not launch or remove the Desktop Commander desktop app. The MCP plugin is separate and starts with Claude.
- **Stop Desktop Commander** stops the phone remote.
- **DC remote status** lists each copy: PID, start time, whether its parent and console are alive, and an online / stale / duplicate verdict, plus the line `one copy serves all chats`.
- **Kill orphaned remote processes** lists leftovers and asks once per item.

On Windows one phone remote is a chain: cmd, then npx's node, then cmd, then the node remote. That chain is one copy. A healthy copy has a live parent and a live console. Leave that copy alone. Kill orphaned remote processes offers a copy whose terminal is gone, and extra copies when more than one remote is running (it keeps the newest and asks first). `-WhatIf` only lists. `-Force` stops the listed copies but never stops the newest remote unless you also pass `-IncludeActiveRemote`. Stopping uses taskkill /T on that copy's own chain, so a yes does not take down the healthy remote. The single healthy copy is never listed. Claude's Desktop Commander plugin is not listed. Health check says OK when zero or one remote is running, and warns only when extra copies or other leftovers are present. It also checks that the remote does not start at sign-in.

**Cursor worker (manual, one per folder you pick).** `install.ps1` adds **Start Cursor worker** and **Stop Cursor worker** in `shortcuts\`. Nothing starts at sign-in, reboot, or app launch. Start lists the folders in `<Projects>\active` on this PC (the root is detected, not hard-coded) and starts one worker for the folder you pick. Run Start again to add another folder. Stop lists the workers this tool started and stops one or all. The command is `agent worker --name <pc>-<folder> --worker-dir <folder> --data-dir <local instance dir> --management-addr 127.0.0.1:<port> --idle-release-timeout 0 --label workstation=manual start`. Details and the doc links are in `workstation\cursor-worker\README.md`. Health check can report running workers. It does not warn when none is running. It warns if a sign-in item, Run key, scheduled task, or app hook would start the worker. A folder with no git origin can still be started; Cursor may not match it to a repo.

`install.ps1` removes `shortcuts\rc` only when that folder is empty. A folder that still has files, or that is a link, is left alone.

Logs: `%LOCALAPPDATA%\Workstation\desktop-commander-remote\`. No token is stored in this repo.

On a PC that still has the old local setup, run `cleanup-legacy.ps1 -WhatIf`, then without `-WhatIf`. It backs up with SHA256 hashes first. A log the old server still has open is skipped instead of aborting the run. It says it would stop the old web server only when that process is actually running. It does not stop the phone remote and does not archive that state folder. Then run `install.ps1` so the manual links, including Health check, exist again.
WSL side (only if you want the Python helpers, e.g. the INVENTORY generator): `bash setup.sh`.

- `workstation.lock.yaml` - pins and pointers only. `INVENTORY.md` is generated from it (`.venv/bin/python scripts/gen-inventory.py`).
- No CAD here: this repo does not install, pin or link any CAD tool, CAD skill or CAD repo.
- `skills/` - this repo's (non-CAD) skills; skills live only in their repo. `install.ps1` links
  (junctions) each one into `~\.claude\skills` only (Cursor reads it too; old `~\.cursor\skills` links are removed) with `link-skills.ps1`, so a `git pull` updates them
  (by hand: `link-skills.ps1 [-WhatIf]`). Opt out with `install.ps1 -NoLinkSkills`. `-LinkSkills` is still accepted and ignored.
  Re-running it removes only its own links whose skill was renamed or removed (the
  link only). CAD skills live in the CAD repo, which links them from its own setup.
  `skills/EXCLUDE.txt` lists Claude-app-owned skills (harness-design, st185-*); those, and any SKILL.md with
  `source: harness-design-app`, are never linked or zipped, and `link-skills.ps1` never moves or removes their folders.
  Each skill folder (`skills/<name>/` with a `SKILL.md`) has a matching `skills/<name>.zip` for upload to Claude.

  **This repo is the source of truth for Dan's skills** (all 12 are his). `wizard` is his copy of
  [claude-wizard](https://github.com/vlad-ko/claude-wizard) `skill/` at base `43756e1` (`skills/wizard/UPSTREAM.md`).
  claude.ai does not read this repo. After a skill change merges:

  1. Upload the new `skills/<name>.zip` at claude.ai: **Customize > Skills > Upload**, on each of Dan's two accounts.
  2. Run `workstation\skills-drift.ps1` (or the **Skills drift** shortcut). It compares each account's synced copy
     (`~\.claude\skills\synced\<bucket>\<name>`, the skill body only, because claude.ai rewrites the frontmatter)
     with the repo and lists zips that still need that upload.

  `link-skills.ps1` does not add a junction for a skill that is already in a synced bucket, so Claude Code does not
  load it twice. It removes an old junction only (never the folder it points at, and never anything under `synced`).
  Skills that are not on claude.ai still get a junction.

  `workstation\check-upstream.ps1` is manual. For a skill with `metadata.upstream` it fetches upstream, shows
  `base..HEAD`, three-way merges into Dan's copy, bumps `upstream-base`, and opens a PR. No schedule and no
  sign-in item. The same check can be started by hand from Actions: workflow **check-upstream**
  (`workflow_dispatch` only, no cron).
  `install.ps1` ends with a Windows popup reminding you to upload new or changed zips in Claude desktop
  (Settings > Capabilities > Skills); click OK to open `skills\` in Explorer. The popup is skipped for
  `-NoPopup` (alias `-Quiet`), `-WhatIf`, `-UserHome`, and CI. Changed zip names are tracked in
  `%LOCALAPPDATA%\Workstation\skill-zips.json`.
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
  into `~/.claude.json` (kapture, github, autodesk-fusion-mcp, githits, fetch, windows-mcp, context7). Required
  API keys are read from env or prompted; a server that still lacks a key is skipped with a message.
  `plugins.json` is the source of truth for plugins installed from Anthropic's
  official marketplace at user scope. `handoff/claude/pr-closeout-nudge.ps1` is copied into `~/.claude/hooks` and
  wired as a PostToolUse hook in `~/.claude/settings.json` next to context-guard and memory-link-guard.
  **Memory split:** Claude Code's shared store is `<Projects>\_claude\Claude Projects\Working Memory\memory\`
  (the `autoMemoryDirectory` junction plus `memory-link-guard.ps1`). It holds preferences, rules and
  cross-project facts, each fact once. Project progress stays in the repo state file named by `AGENTS.md`
  (here, `STATE.md`). Claude desktop online Memory is account-level facts about the user and is not synced.
  As of Store app 4.4212.0.0 ("Unified Claude", personal account, 2026-11-03; work account unverified),
  Cowork / Chat do not write local memory files. Install does not create or check `~\.claude\working-memory`;
  a leftover junction is harmless. Stranded local Cowork notes can be copied into the store or brought in
  with the app's Import memory button. See `MIGRATION.md`.
  Install does not change `autoMode` and does not write a remote-control startup flag. `cleanup-legacy.ps1` removes that flag and the one living-relation pull-request merge allow rule from a PC that already has them. The Fusion MCP url in `claude\mcp-servers.json` is `http://127.0.0.1:8765/mcp` (the add-in's port).
- `agents/projects-AGENTS.md` - the shared agent rules file for a projects root.
- `install.ps1`, `preflight.ps1`, `uninstall.ps1`, `toolkit.psd1` - imported as they were; they are rewritten to read the pin file in a later PR.
