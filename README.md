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
WSL side (only if you want the Python helpers, e.g. the INVENTORY generator): `bash setup.sh`.

- `workstation.lock.yaml` - pins and pointers only. `INVENTORY.md` is generated from it (`.venv/bin/python scripts/gen-inventory.py`).
  - **handbuilt-cad follows main** (`commit: follow`). It is not pinned to a sha, because a sha pin went stale on every
    handbuilt-cad PR. A merged handbuilt-cad PR needs no change here: the bot that merged it pulls the clones fast-forward
    only. `last_checked` is information only (the main commit last checked with this workstation). If an install ever has to be
    frozen, set `ref` and `commit` to that sha and write why beside it.
- `skills/` - non-CAD skills (CAD skills live in the CAD repo's `skills/`). Install both with `sync-skills.ps1 -From <cad-repo>\skills -From <this repo>\skills`.
- `agents/projects-AGENTS.md` - the shared agent rules file for a projects root.
- `install.ps1`, `preflight.ps1`, `uninstall.ps1`, `toolkit.psd1` - imported as they were; they are rewritten to read the pin file in a later PR.
