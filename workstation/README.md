# Workstation helpers

- `shortcuts/` - scripts for the Workstation shortcuts: Health check, the Phone access parts (`claude-root-start.ps1` / `claude-root-stop.ps1`, projects-root Claude remote), `retire-cursor-worker.ps1` (Install runs it to stop the removed Cursor worker), and the per-project remote-control pair (`rc-generate.ps1`, `rc-open.ps1`, `rc-close.ps1`). `install-shortcuts.ps1` creates the links in the workstation repo's own `shortcuts\` folder (gitignored), not on the Desktop. No batch pull/push shortcuts.
- `repo-status.ps1`, `repo-branch.ps1` - read-only status of project repos.
- `paths.ps1` - shared paths: the Projects root (from `%LOCALAPPDATA%\Workstation\workstation.json`, which install.ps1 writes) and the runtime folder `%LOCALAPPDATA%\Workstation\`.
- No Cursor worker any more (removed 2026-10-31): Cursor's built-in Remote Control handles Cursor. Old logs may remain in `%LOCALAPPDATA%\Workstation\cursor-worker\`.

These scripts run straight from the workstation repo clone (no installed copy under the Projects root), so keep the
clone on `main`.

Pull and push one repo at a time (`git pull --ff-only`), by hand or through the agent that owns it.
