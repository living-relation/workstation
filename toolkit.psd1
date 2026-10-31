# Workstation toolkit names: the ONE place to change when the toolkit or its scripts are renamed.
# Read by install.ps1, install-admin.ps1, uninstall.ps1 and preflight.ps1. Script paths are relative to the toolkit.
@{
  # The toolkit runs straight from this package (the workstation repo clone, normally <Projects>\active\workstation):
  # PackageFolder is the folder inside the package that holds the scripts. Nothing is copied under <Projects>.
  PackageFolder      = 'workstation'
  # Folders under <Projects> that held an installed COPY of the toolkit in older setups: '_bridge' (until 2026-10-08)
  # and '_workstation' (until the toolkit ran from the repo clone). Preflight and Health check WARN while one
  # still exists; install never moves or deletes it (stop its workers, then archive it by hand).
  LegacyFolders      = @('_bridge', '_workstation')

  # Per-user runtime folder under %LOCALAPPDATA% (never inside the clone): the config file install.ps1 writes
  # (ConfigFile: projectsRoot), the stop flag that Stop Cursor workers writes and the Cursor worker's logs, state and sqlite cache.
  StateFolder        = 'Workstation'
  ConfigFile         = 'workstation.json'

  # Scripts inside the toolkit.
  ShortcutsInstaller = 'shortcuts\install-shortcuts.ps1'
  CommonScript       = 'shortcuts\workstation-common.ps1'
  PullScript         = 'shortcuts\pull.ps1'  # this clone only; never recreate batch pull-all
  StatusScript       = 'repo-status.ps1'
  WorkerFolder       = 'cursor-worker'

  # Shortcuts that ShortcutsInstaller creates (link name -> script). ShortcutFolder is a folder INSIDE this package
  # (the workstation repo clone), relative to the package root, so no personal path is stored; the generated .lnk
  # files are gitignored. install.ps1 passes the resolved folder to ShortcutsInstaller as -LinkDir.
  ShortcutFolder     = 'shortcuts'
  # Icon = index in shell32.dll; Args = extra arguments after -File <script>.
  Shortcuts          = @(
    @{ Name = 'Start Cursor workers';      Script = 'shortcuts\workers-start.ps1';      Icon = 137 }
    @{ Name = 'Stop Cursor workers';       Script = 'shortcuts\workers-stop.ps1';       Icon = 131 }
    @{ Name = 'Health check'; Script = 'shortcuts\workstation-status.ps1'; Icon = 23 }
    @{ Name = 'Dashboard';          Script = 'shortcuts\dashboard.ps1';          Icon = 13 }
    @{ Name = 'Update from GitHub'; Script = 'shortcuts\pull.ps1';               Icon = 238 }
    @{ Name = 'Install';            Script = 'shortcuts\install.ps1';            Icon = 21 }
    @{ Name = 'Start Desktop Commander'; Script = 'desktop-commander-remote\start-dc-remote.ps1'; Args = '-Show'; Icon = 137 }
    @{ Name = 'Stop Desktop Commander';  Script = 'desktop-commander-remote\stop-dc-remote.ps1';  Icon = 131 }
    # Same commands as the dashboard's Phone access toggle and Check for stray processes button (toggles\toggles.json).
    @{ Name = 'Start phone access';      Script = 'toggles\toggle.ps1'; Args = '-Id remote -Action on';  Icon = 137 }
    @{ Name = 'Stop phone access';     Script = 'toggles\toggle.ps1'; Args = '-Id remote -Action off'; Icon = 131 }
    @{ Name = 'Check for stray processes';  Script = 'toggles\toggle.ps1'; Args = '-Action process-check';  Icon = 23 }
    # Watcher: off by default, manual only (no scheduled task).
    @{ Name = 'Start phone alerts watcher';     Script = 'toggles\watcher.ps1'; Args = '-Action on';  Icon = 137 }
    @{ Name = 'Stop phone alerts watcher';    Script = 'toggles\watcher.ps1'; Args = '-Action off'; Icon = 131 }
    # One link per project folder under active\ (git repo or plain folder). Output is shortcuts\rc\, gitignored.
    @{ Name = 'Make Claude remote shortcuts'; Script = 'shortcuts\rc-generate.ps1'; Icon = 47 }
    # Same command as the dashboard's 'Stop and start all Claude remotes' button: stops the per-project
    # Claude remotes that are running, then starts fresh sessions for exactly those folders. Click only.
    @{ Name = 'Stop and start all Claude remotes'; Script = 'shortcuts\rc-restart-all.ps1'; Icon = 238 }
  )

  # Old names of the Shortcuts above (renamed 2026-10-31). The shortcuts installer deletes an old-named link in
  # ShortcutFolder only when it still runs Script (with Args when given), so only links this toolkit made go.
  # uninstall.ps1 does the same. Per-project links in shortcuts\rc\ have their own rename in rc-lib.ps1.
  RenamedShortcuts   = @(
    @{ Old = 'Workers Start';      Script = 'workers-start.ps1' }
    @{ Old = 'Workers Stop';       Script = 'workers-stop.ps1' }
    @{ Old = 'Workstation Status'; Script = 'workstation-status.ps1' }
    @{ Old = 'Pull';               Script = 'pull.ps1' }
    @{ Old = 'Desktop Commander Remote Start'; Script = 'start-dc-remote.ps1' }
    @{ Old = 'Desktop Commander Remote Stop';  Script = 'stop-dc-remote.ps1' }
    @{ Old = 'Remote On';      Script = 'toggle.ps1';  Args = '-Id remote -Action on' }
    @{ Old = 'Remote Off';     Script = 'toggle.ps1';  Args = '-Id remote -Action off' }
    @{ Old = 'Process Check';  Script = 'toggle.ps1';  Args = '-Action process-check' }
    @{ Old = 'Watcher On';     Script = 'watcher.ps1'; Args = '-Action on' }
    @{ Old = 'Watcher Off';    Script = 'watcher.ps1'; Args = '-Action off' }
    @{ Old = 'Generate RC shortcuts'; Script = 'rc-generate.ps1' }
  )

  # Sign-in links that ShortcutsInstaller puts in the user's Startup folder (install.ps1 passes -StartupDir).
  # Hidden = start through desktop-commander-remote\run-hidden.vbs (wscript, no window). A link of the same name
  # is only replaced when it already runs the same script file name (from any folder: older copies under
  # %LOCALAPPDATA% or a worktree); it is backed up first. Anything else is left alone with a warning.
  # Desktop Commander Remote no longer starts at sign-in: it runs only while the dashboard's Phone access toggle is on
  # (or from the manual Start phone access / Start Desktop Commander shortcuts).
  StartupLinks       = @()
  # Sign-in links older installs created. ShortcutsInstaller removes them (backup first) when they run Script.
  RetiredStartupLinks = @(
    @{ Name = 'Desktop Commander Remote'; Script = 'start-dc-remote.ps1' }
  )

  # Old Desktop shortcut folders: 'Bridge' (before the rename) and 'Workstation' (Desktop location before the links
  # moved into the package). Preflight reports them as legacy (WARN); the shortcuts installer removes only links in
  # them that run the toolkit scripts, then the folder once it is empty.
  LegacyShortcutFolders = @('Bridge', 'Workstation')
  LegacyShortcutNames   = @('Bridge Start', 'Bridge Stop', 'Bridge Status', 'Pull All', 'Push All')
  # Old script file names: shortcuts\bridge-start/stop/status/common, pull-all, push-all; root sync-pull, sync-status, git-branch.
  LegacyScripts         = @('bridge-start.ps1', 'bridge-stop.ps1', 'bridge-status.ps1', 'bridge-common.ps1', 'pull-all.ps1', 'push-all.ps1', 'sync-pull.ps1', 'sync-status.ps1', 'git-branch.ps1')
}
