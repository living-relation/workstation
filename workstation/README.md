# Workstation helpers

- `health/` - Health check (`workstation-status.ps1`). Read-only: memory, hooks, skills, app locks, and the Desktop Commander phone remote. `-Locks` checks only the locks.
- `desktop-commander-remote/` - manual Start, Stop, and status. One phone remote per PC. No sign-in item. Start does not launch the desktop app.
- `kill-orphans.ps1` - lists leftover processes and asks before stopping each one.
- `skills-drift.ps1` - manual. Compares each claude.ai synced skill with this repo and lists zips to upload. No sign-in item.
- `check-upstream.ps1` - manual. Merges upstream into a skill that has `metadata.upstream` and opens a PR. No schedule.
- `fusion-lock/` - one Fusion lock and one harness.design lock per PC. `-Repo` is recorded and shown. It does not change who is blocked.
- `repo-status.ps1`, `repo-branch.ps1` - read-only status of project repos.
- `paths.ps1` - shared paths. The Projects root comes from `%LOCALAPPDATA%\Workstation\workstation.json`, which install.ps1 writes.

These scripts run straight from the workstation repo clone. Keep the clone on `main`.

Pull and push one repo at a time (`git pull --ff-only`), by hand.
