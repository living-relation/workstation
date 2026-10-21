# workstation (private)

Sets up a Windows + WSL workstation for agent-assisted work: installer and preflight, helper
scripts (workers, status, latch), memory/handoff tooling, agent instruction templates, the shared
non-CAD agent skills, and a single pin file (`workstation.lock.yaml`) that says which repos and
upstream tools to fetch, at which versions. It holds **no CAD code and no models** - those come
from the repos listed in the pin file.

## Setup
```powershell
git clone <repo-url> <Projects>\active\workstation
powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1      # hooks, gitleaks, models folder, local.toml
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -ProjectsRoot <Projects> -WhatIf   # then without -WhatIf
```
The Workstation toolkit (`workstation\`: Workers Start/Stop, Workstation Status, Cursor worker, Latch) runs
straight from this clone; install.ps1 copies nothing under the Projects root. Keep the clone on `main`, since the
shortcuts and the Latch task run whatever is checked out. Runtime files (the config install.ps1 writes, the Workers
Stop flag, worker logs and state) live in `%LOCALAPPDATA%\Workstation\`, never in the clone.
**Shortcuts and sign-in links** are generated, never committed (`*.lnk` is gitignored). Their definitions are
`Shortcuts` and `StartupLinks` in `toolkit.psd1`; `workstation\shortcuts\install-shortcuts.ps1` (run by install.ps1)
creates them pointing at this clone:
- `shortcuts\`: Workers Start, Workers Stop, Workstation Status, Dashboard, Desktop Commander Remote Start (`-Show`)
  and Desktop Commander Remote Stop.
- Startup folder: Desktop Commander Remote (hidden, via `run-hidden.vbs`) and Dashboard (`start-dashboard.ps1 -NoPause`).
  A Startup link of the same name is replaced only if it already runs the same script, after a backup to
  `%LOCALAPPDATA%\Workstation\backups\startup-links-<time>\`.
- Desktop Commander remote (`workstation\desktop-commander-remote\`) runs `npx @wonderwhy-er/desktop-commander@<pinned version>
  remote`; it keeps no token in the repo (the device login is held by Desktop Commander itself), and its logs go to
  `%LOCALAPPDATA%\Workstation\desktop-commander-remote\`.
WSL side (only if you want the Python helpers, e.g. the INVENTORY generator): `bash setup.sh`.

- `workstation.lock.yaml` - pins and pointers only. `INVENTORY.md` is generated from it (`.venv/bin/python scripts/gen-inventory.py`).
- No CAD here: this repo does not install, pin or link any CAD tool, CAD skill or CAD repo.
- `skills/` - this repo's skills. `install.ps1` links (junctions) each one into `~\.claude\skills` and `~\.cursor\skills` with
  `link-skills.ps1`, so a `git pull` updates them (by hand: `link-skills.ps1 [-WhatIf]`). `sync-skills.ps1 -From <this repo>\skills`
  installs copies instead. Other repos link their own skills from their own setup.
- `bots/` - optional Grok Bot bot profiles (`bots\profiles\*.profile.json`, format in `bots\PROFILE-FORMAT.md`). See "Optional bot
  profiles" below.
- Ownership notes: `install.ps1` runs `ownership-notes.ps1`, which adds a README.md/AGENTS.md ("owned by the workstation repo")
  to each folder it creates (`%LOCALAPPDATA%\Workstation` and its subfolders, `<Projects>\_claude`, `shortcuts\`). In the shared
  skill folders it adds only `README-workstation.md`, which lists the links this repo owns. Existing files are never changed.
- `agents/projects-AGENTS.md` - the shared agent rules file for a projects root.
- `install.ps1`, `preflight.ps1`, `uninstall.ps1`, `toolkit.psd1` - imported as they were; they are rewritten to read the pin file in a later PR.

## Optional bot profiles (Grok Bot only)

`install.ps1` checks whether Grok Bot is installed: an uninstall entry named "Grok Bot", a "Grok Bot" Start-menu shortcut, or
`%APPDATA%\Grok Bot`. If it isn't, the step is skipped without a message. If it is, the installer asks
**"Add the optional bot profiles? [y/N]"** (default No). `-Bots` says yes, `-NoBots` says no, and `-WhatIf` only reports. With `-Bots`, existing bots are found in `-BotsExistingDir` (else `$env:GROK_BOT_AGENTS_DIR`, else the Grok Bot agents folder when reachable); if none is found it asks for the folder, and a blank answer skips existing-bot checks.

"Add" runs `bots\merge-bot-profile.ps1` for each `bots\profiles\*.profile.json` and **only writes files** to
`%LOCALAPPDATA%\Workstation\bots\`: a ready-to-apply `<bot>.<new|update|merged>.json` and a `<bot>.md` paste sheet
(name, title, description, rules, and the steps). You then create or edit the bot in Grok Bot by hand from that sheet.
Grok Bot has no import API, and nothing here talks to it. Memory, chats and routines are never touched.

Existing bots are matched by name. The script reads a JSON copy you give it (`-Existing`/`-ExistingDir`), or, on the
Grok Bot box, the agent profile files (read-only). Otherwise it asks you. For a bot that exists, the choice per bot is
**merge** (default), **update** (replace the profile and rules) or **skip** (leave it). The old profile is backed up first.
Merge keeps the existing fields, adds the repo rules it doesn't already have (deduplicated by normalized text), and shows
both versions of any conflict and asks. Non-interactive runs (`-Bots`) keep the existing value and log the conflict in
`<bot>.conflicts.txt`. Claude and Cursor get no bot profiles.
