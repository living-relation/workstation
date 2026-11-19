# Workstation helpers

- `health/` - Health check (`workstation-status.ps1`). Read-only: memory, hooks, skills, app locks, and the Desktop Commander phone remote. `-Locks` checks only the locks. install also makes a manual Health check shortcut. No sign-in item.
- `desktop-commander-remote/` - manual Start, Stop, and status. One phone remote per PC. No sign-in item. Start does not launch the desktop app.
- `cursor-worker/` - manual Start and Stop for a Cursor self-hosted worker. Start lists folders in the detected `<Projects>\active` and starts the one you pick. Run it again for another folder. Stop lists workers this tool started. No sign-in item, no scheduled task, no hourly check.
- `kill-orphans.ps1` - lists leftover processes and asks before stopping each one.
- `skills-drift.ps1` - optional, manual. Compares older uploaded claude.ai copies with this repo. Skills get in only by installing the plugins (see `INSTALL.md`). This script does not install or link. No sign-in item.
- `check-upstream.ps1` - manual. Merges upstream into a skill that has `metadata.upstream` and opens a PR. No schedule.
- `fusion-lock/` - one Fusion lock and one harness.design lock per PC. `-Repo` is recorded and shown. It does not change who is blocked.
- `fusion-addins/` - fast-forward Fusion add-in clones found from AddIns junctions. `install.ps1` registers a per-user task (logon and every 60 minutes, hidden, no admin). It does not start Fusion. See `fusion-addins/README.md`.
- `repo-status.ps1`, `repo-branch.ps1` - read-only status of project repos.
- `paths.ps1` - shared paths. The Projects root comes from `%LOCALAPPDATA%\Workstation\workstation.json`, which install.ps1 writes.

These scripts run straight from the workstation repo clone. Keep the clone on `main`.

Pull and push one repo at a time (`git pull --ff-only`), by hand. The Fusion add-in updater is the one script that fast-forwards more than one clone, and only the clones the AddIns junctions point at, and only when each tree is clean, on the default branch, and has an upstream.
