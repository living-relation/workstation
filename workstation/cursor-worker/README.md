# Cursor worker (manual)

Start and Stop shortcuts only. Nothing starts at sign-in, reboot, or app launch.

Start lists the folders in `<Projects>\active` on this PC and starts one worker for the folder you pick. Run Start again to add another folder. Stop lists the workers this tool started and lets you stop one or all. The Cursor app and a worker you started by hand are left alone.

The projects root is the one `install.ps1` saved in `%LOCALAPPDATA%\Workstation\workstation.json`. If that file is missing, the root is taken from this clone's location (`<Projects>\active\workstation`). It is not hard-coded, so each PC can use its own profile path.

## Command

Start runs this (options before `start`, as the CLI reference requires):

```text
agent worker --name <this-PC>-<folder> --worker-dir <picked folder> --data-dir %LOCALAPPDATA%\Workstation\cursor-worker\instances\<folder-id> --management-addr 127.0.0.1:<port> --idle-release-timeout 0 --label workstation=manual start
```

If the CLI on this PC is `agent.ps1`, the process is `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <agent.ps1>` plus those arguments. `agent.cmd` and `agent.exe` are launched directly.

Checked 2026-11-17:

- [My Machines](https://cursor.com/docs/cloud-agent/self-hosted/my-machines) - `agent worker start`, `--name`, `--worker-dir` (repeatable; git remote is how Cursor matches a repo).
- [CLI parameters](https://cursor.com/docs/cli/reference/parameters) - `agent worker [options] start`, including `--data-dir`, `--management-addr`, `--label`, `--idle-release-timeout`.
- [Team pools](https://cursor.com/docs/cloud-agent/self-hosted/pool) - put worker options before `start`.
- [CLI changelog](https://cursor.com/docs/cli/changelog) - a data-directory lock blocks a second daemon on the same data dir, so each folder gets its own `--data-dir`. `--idle-release-timeout 0` keeps the worker up. The parameters page says the default is already `0`; the changelog says the default is one hour. The script passes `0` either way.

`--pool` is not used. This is a personal My Machines worker. Sign in with `agent login`. This repo does not store a token.

A folder with no git `origin` can still be started. Cursor may not offer it for a repo request, because routing uses the remote.

Logs: `%LOCALAPPDATA%\Workstation\cursor-worker\`.
