# Workstation helpers

- `shortcuts/` - Desktop "Workstation" shortcuts: Workers Start, Workers Stop, Workstation Status (`install-shortcuts.ps1` creates them). No batch pull/push shortcuts.
- `repo-status.ps1`, `repo-branch.ps1` - read-only status of project repos.
- `cursor-worker/` - Cursor agent worker supervisor (logs/state are created at run time and ignored by git).
- `latch/` - keeps the Grok Bot desktop app running (scheduled task).

Pull and push one repo at a time (`git pull --ff-only`), by hand or through the agent that owns it.
