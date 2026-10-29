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
The Workstation toolkit (`workstation\`: Workers Start/Stop, Workstation Status, Cursor worker) runs
straight from this clone; install.ps1 copies nothing under the Projects root. Keep the clone on `main`, since the
shortcuts run whatever is checked out. Runtime files (the config install.ps1 writes, the Workers
Stop flag, worker logs and state) live in `%LOCALAPPDATA%\Workstation\`, never in the clone.
**Shortcuts and sign-in links** are generated, never committed (`*.lnk` is gitignored). Their definitions are
`Shortcuts` and `StartupLinks` in `toolkit.psd1`; `workstation\shortcuts\install-shortcuts.ps1` (run by install.ps1)
creates them pointing at this clone:
- `shortcuts\rc\`: one **RC** `<folder>` link and one **Close RC** `<folder>` link per directory in `active\` (a git repo or a plain folder; names starting with a dot are skipped). Generate RC shortcuts rewrites this folder and does not start a session.
- `shortcuts\`: Workers Start, Workers Stop, Workstation Status, Dashboard, Pull (`git pull --ff-only` of this clone only; or double-click root `pull.cmd`), Install (runs this clone's `install.ps1` with any arguments passed through; or double-click root `install.cmd`), Desktop Commander Remote Start (`-Show`)
  and Desktop Commander Remote Stop, and Generate RC shortcuts.
- Startup folder: nothing. Desktop Commander Remote runs only while the dashboard's Remote toggle is on (or from the Remote On / Desktop Commander Remote Start shortcuts); install removes the old `Desktop Commander Remote.lnk` sign-in link (backup first). The Dashboard does not start at sign-in;
  only the Dashboard shortcut starts it.
  A Startup link of the same name is replaced only if it already runs the same script, after a backup to
  `%LOCALAPPDATA%\Workstation\backups\startup-links-<time>\`.
- Desktop Commander remote (`workstation\desktop-commander-remote\`) runs `npx @wonderwhy-er/desktop-commander@<pinned version>
  remote`; it keeps no token in the repo (the device login is held by Desktop Commander itself), and its logs go to
  `%LOCALAPPDATA%\Workstation\desktop-commander-remote\`.
WSL side (only if you want the Python helpers, e.g. the INVENTORY generator): `bash setup.sh`.

- `workstation.lock.yaml` - pins and pointers only. `INVENTORY.md` is generated from it (`.venv/bin/python scripts/gen-inventory.py`).
- No CAD here: this repo does not install, pin or link any CAD tool, CAD skill or CAD repo.
- `skills/` - this repo's (non-CAD) skills; skills live only in their repo. Linking is opt-in: `install.ps1 -LinkSkills` links
  (junctions) each one into `~\.claude\skills` only (Cursor reads it too; old `~\.cursor\skills` links are removed) with `link-skills.ps1`, so a `git pull` updates them
  (by hand: `link-skills.ps1 [-WhatIf]`). Re-running it removes only its own links whose skill was renamed or removed (the
  link only). CAD skills live in the CAD repo, which links them from its own setup.
  `skills/EXCLUDE.txt` lists Claude-app-owned skills (harness-design, st185-*); those, and any SKILL.md with
  `source: harness-design-app`, are never linked or zipped, and `link-skills.ps1` never moves or removes their folders.
  Each skill folder (`skills/<name>/` with a `SKILL.md`) has a matching `skills/<name>.zip` for upload to Claude.
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
  to each folder it creates (`%LOCALAPPDATA%\Workstation` and its subfolders, `<Projects>\_claude`, `shortcuts\`). In the shared
  skill folders it adds only `README-workstation.md`, which lists the links this repo owns. Existing files are never changed.
- `agents/projects-AGENTS.md` - the shared agent rules file for a projects root.
- `install.ps1`, `preflight.ps1`, `uninstall.ps1`, `toolkit.psd1` - imported as they were; they are rewritten to read the pin file in a later PR.
