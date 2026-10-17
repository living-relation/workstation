# workstation (private)

Sets up a Windows + WSL workstation for agent-assisted work: installer and preflight, helper
scripts (workers, status, latch), memory/handoff tooling, agent instruction templates, the shared
non-CAD agent skills, and a single pin file (`workstation.lock.yaml`) that says which repos and
upstream tools to fetch, at which versions. It holds **no CAD code and no models** - those come
from the repos listed in the pin file.

## Setup
```powershell
git clone <repo-url> C:\projects\_workstation-repo
powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1      # hooks, gitleaks, models folder, local.toml
```
WSL side (only if you want the Python helpers, e.g. the INVENTORY generator): `bash setup.sh`.

- `workstation.lock.yaml` - pins and pointers only. `INVENTORY.md` is generated from it (`.venv/bin/python scripts/gen-inventory.py`).
- `skills/` - non-CAD skills (CAD skills live in the CAD repo's `skills/`). Install both with `sync-skills.ps1 -From <cad-repo>\skills -From <this repo>\skills`.
- `agents/projects-AGENTS.md` - the shared agent rules file for a projects root.
- `install.ps1`, `preflight.ps1`, `uninstall.ps1`, `toolkit.psd1` - imported as they were; they are rewritten to read the pin file in a later PR.
