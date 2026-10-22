# Workstation helpers

- `shortcuts/` - scripts for the Workstation shortcuts: Workers Start, Workers Stop, Workstation Status. `install-shortcuts.ps1` creates the links in the workstation repo's own `shortcuts\` folder (gitignored), not on the Desktop. No batch pull/push shortcuts.
- `repo-status.ps1`, `repo-branch.ps1` - read-only status of project repos.
- `paths.ps1` - shared paths: the Projects root (from `%LOCALAPPDATA%\Workstation\workstation.json`, which install.ps1 writes) and the runtime folder `%LOCALAPPDATA%\Workstation\`.
- `cursor-worker/` - Cursor agent worker supervisor (logs, state and sqlite cache go to `%LOCALAPPDATA%\Workstation\cursor-worker\`, never into the clone).

These scripts run straight from the workstation repo clone (no installed copy under the Projects root), so keep the
clone on `main`.

Pull and push one repo at a time (`git pull --ff-only`), by hand or through the agent that owns it.
